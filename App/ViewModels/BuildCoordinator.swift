import Foundation
import Combine

/// Orchestrator for the whole flow (the wizard's and the build's "state machine").
///
/// Key safety guarantees that live here:
///   - S-3: JIT re-validation of the disk (id + size) JUST before formatting.
///   - S-5: any failure or cancellation detaches the ISO and leaves no half-done formats.
///
/// Not `@MainActor`: the heavy work runs on a background thread and the
/// publications to SwiftUI are marshalled to main via `onMain`.
public final class BuildCoordinator: ObservableObject {

    public enum Step: Equatable { case selectISO, selectDisk, confirm, build }

    // Navigation
    @Published public var step: Step = .selectISO

    // ISO
    @Published public var isoURL: URL?
    @Published public private(set) var isoInfo: ISOInfo?
    @Published public private(set) var isInspectingISO = false
    @Published public private(set) var isoError: String?

    // Hash verification (optional)
    @Published public var expectedHash: String = ""
    @Published public private(set) var computedHash: String?
    @Published public private(set) var hashMatches: Bool?
    @Published public private(set) var isHashing = false
    @Published public private(set) var hashProgress: Double = 0

    // Disk / label / confirmation
    @Published public var selectedDisk: Disk?
    @Published public var label: String = "WIN11"
    @Published public var confirmedDestructive = false

    // Build
    @Published public private(set) var progress = BuildProgress(phase: .idle, phaseFraction: 0, detail: "")
    @Published public private(set) var isBuilding = false
    @Published public private(set) var finished = false
    /// Instant when the CURRENT phase started (for the "heartbeat"/elapsed time
    /// of phases without sub-progress, e.g. Formatting).
    @Published public private(set) var phaseStartedAt: Date?
    private var lastProgressPhase: BuildPhase?

    // Per-phase speed meters (smoothed bytes/sec).
    private let copyMeter = RateMeter()
    private let splitMeter = RateMeter()
    private let rawMeter = RateMeter()

    public let diskService: DiskService
    private let iso: ISOService
    private let copier: CopyService
    private let wim: WimService
    private let helper: HelperClient

    private let cancelToken = CancellationToken()
    private let isoLock = NSLock()
    private var _mountedISO: MountedISO?
    private var mountedISO: MountedISO? {
        get { isoLock.lock(); defer { isoLock.unlock() }; return _mountedISO }
        set { isoLock.lock(); defer { isoLock.unlock() }; _mountedISO = newValue }
    }

    public init(diskService: DiskService = DiskService(),
                iso: ISOService = ISOService(),
                copier: CopyService = CopyService(),
                wim: WimService = WimService(),
                helper: HelperClient = HelperClient()) {
        self.diskService = diskService
        self.iso = iso
        self.copier = copier
        self.wim = wim
        self.helper = helper
    }

    // MARK: - Step 1: ISO

    public func selectISO(_ url: URL) {
        isoURL = url
        isoInfo = nil
        isoError = nil
        computedHash = nil
        hashMatches = nil
        isInspectingISO = true

        background { [weak self] in
            guard let self else { return }
            self.detachISOIfNeeded()

            // Mounting is OPTIONAL: only the Windows flow needs to inspect
            // files (setup.exe, install.wim). Many isohybrid Linux ISOs do NOT
            // mount on macOS ("attach failed") — that is NOT an error: the boot
            // type and the size are obtained by reading the file, and the raw flow
            // writes the .iso directly. If it doesn't mount, we carry on unmounted.
            let mounted = try? self.iso.attach(url)
            self.mountedISO = mounted

            let info: ISOInfo
            if let mounted {
                info = self.iso.inspect(mounted, isoURL: url)
            } else {
                let bootType = ISOBootDetector.detect(isoAt: url, isWindows: false)
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.uint64Value ?? 0
                info = ISOInfo(url: url, sizeBytes: size, volumeName: nil,
                               isWindowsInstaller: false, installWIMSizeBytes: nil,
                               usesESD: false, newestBootFileDate: nil, bootType: bootType)
            }
            self.onMain {
                self.isoInfo = info
                self.isInspectingISO = false
                if !FAT32Label.isValid(self.label) { self.label = "WIN11" }
            }
        }
    }

    public var canProceedFromISO: Bool { isoInfo?.bootIsSupported == true }

    /// `true` if the ISO is written raw (Linux/isohybrid) instead of copied to FAT32.
    public var isRawFlow: Bool { isoInfo?.bootType == .hybridRaw }

    /// Phases to show on the progress screen, depending on the ISO type.
    public var activePhases: [BuildPhase] {
        BuildPhase.sequence(for: isoInfo?.bootType ?? .windows)
    }

    public func verifyHash() {
        guard let url = isoURL, !expectedHash.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isHashing = true
        hashProgress = 0
        computedHash = nil
        hashMatches = nil
        let expected = expectedHash

        background { [weak self] in
            guard let self else { return }
            do {
                let hash = try self.iso.sha256(of: url, progress: { f in
                    self.onMain { self.hashProgress = f }
                })
                self.onMain {
                    self.computedHash = hash
                    self.hashMatches = ISOService.hashesMatch(hash, expected)
                    self.isHashing = false
                }
            } catch {
                self.onMain { self.isHashing = false }
            }
        }
    }

    // MARK: - Step 2: Disk

    public func goToDiskSelection() {
        diskService.start()
        step = .selectDisk
    }

    /// Backward navigation from the step bar: only to already-visited steps
    /// and never during a build in progress (a destructive operation is not interrupted).
    public func goTo(step target: Step) {
        guard !isBuilding else { return }
        let order: [Step] = [.selectISO, .selectDisk, .confirm, .build]
        guard let from = order.firstIndex(of: step),
              let to = order.firstIndex(of: target),
              to < from else { return }
        if target == .selectDisk { diskService.start() }
        step = target
    }

    // MARK: - Step 3: Confirmation

    public func goToConfirm() {
        guard selectedDisk != nil else { return }
        if !FAT32Label.isValid(label) { label = FAT32Label.sanitize(label) }
        confirmedDestructive = false
        step = .confirm
    }

    public var canStartBuild: Bool {
        guard let disk = selectedDisk, confirmedDestructive else { return false }
        if isRawFlow {
            // The raw flow (Linux) doesn't use a FAT32 label, but the USB MUST fit the
            // whole ISO (A2): otherwise we don't let the write start.
            guard let info = isoInfo, disk.fitsRawImage(ofBytes: info.sizeBytes) else { return false }
            return true
        }
        return FAT32Label.isValid(label)
    }

    /// `true` if the flow is raw and the chosen USB does NOT fit the image (blocking, A2).
    /// The UI uses this to explain why the button is disabled.
    public var rawDiskTooSmall: Bool {
        guard isRawFlow, let disk = selectedDisk, let info = isoInfo else { return false }
        return !disk.fitsRawImage(ofBytes: info.sizeBytes)
    }

    /// Message with sizes for the "USB too small" banner in Confirm (A2), or `nil` when
    /// it doesn't apply. Reuses the same i18n key as the `BuildError`.
    public var rawDiskTooSmallMessage: String? {
        guard rawDiskTooSmall, let disk = selectedDisk, let info = isoInfo else { return nil }
        let have = ByteCountFormatter.string(fromByteCount: Int64(disk.sizeBytes), countStyle: .file)
        let need = ByteCountFormatter.string(fromByteCount: Int64(info.sizeBytes), countStyle: .file)
        return loc("error.build.usbTooSmall \(have) \(need)")
    }

    // MARK: - Step 4: Build

    public func startBuild() {
        // The mount (mountedISO) is only needed by the Windows flow; the raw flow
        // writes the file directly. That's why it's not required here.
        guard let disk = selectedDisk, let info = isoInfo else { return }
        let mounted = mountedISO
        let safeLabel = FAT32Label.sanitize(label)
        cancelToken.reset()
        isBuilding = true
        finished = false
        step = .build
        setProgress(.formatting, 0, loc("build.detail.preparing"))

        background { [weak self] in
            guard let self else { return }
            do {
                try self.runBuild(disk: disk, mounted: mounted, info: info, label: safeLabel)
                self.onMain {
                    self.progress = BuildProgress(phase: .done, phaseFraction: 1,
                                                  detail: loc("build.detail.ready"))
                    self.isBuilding = false
                    self.finished = true
                }
            } catch is CancellationSignal {
                self.cleanupAfterExit()
                self.onMain {
                    self.progress = BuildProgress(phase: .cancelled, phaseFraction: 0,
                                                  detail: loc("build.detail.cancelled"))
                    self.isBuilding = false
                }
            } catch {
                self.cleanupAfterExit()
                self.onMain {
                    self.progress = BuildProgress(phase: .failed(error.localizedDescription),
                                                  phaseFraction: 0, detail: error.localizedDescription)
                    self.isBuilding = false
                }
            }
        }
    }

    public func cancel() { cancelToken.cancel() }

    /// Resets the wizard to create another USB.
    public func reset() {
        cancelToken.reset()
        detachISOIfNeeded()
        isoURL = nil; isoInfo = nil; isoError = nil
        computedHash = nil; hashMatches = nil; expectedHash = ""
        selectedDisk = nil; confirmedDestructive = false; label = "WIN11"
        progress = BuildProgress(phase: .idle, phaseFraction: 0, detail: "")
        phaseStartedAt = nil; lastProgressPhase = nil
        isBuilding = false; finished = false
        step = .selectISO
    }

    // MARK: - Orchestration (background thread)

    /// Dispatches to the correct flow based on the ISO's boot type.
    private func runBuild(disk: Disk, mounted: MountedISO?, info: ISOInfo, label: String) throws {
        switch info.bootType {
        case .windows:
            // The Windows flow needs the ISO mounted to copy its files.
            guard let mounted else { throw BuildError.usbVolumeNotFound }
            try runWindowsBuild(disk: disk, mounted: mounted, info: info, label: label)
        case .hybridRaw:
            try runRawBuild(disk: disk, info: info)
        case .elToritoOnly, .notBootable:
            // Shouldn't get here (the wizard filters earlier), but just to be safe.
            throw BuildError.unsupportedISO
        }
    }

    /// Windows flow: format FAT32 → copy → split install.wim → finalize.
    private func runWindowsBuild(disk: Disk, mounted: MountedISO, info: ISOInfo, label: String) throws {
        let cancelled: () -> Bool = { [cancelToken] in cancelToken.isCancelled }
        func checkpoint() throws { if cancelled() { throw CancellationSignal() } }

        // ---- Phase 1: Format ----
        setProgress(.formatting, 0.1, loc("build.detail.revalidating"))
        // S-3: the identifier may have changed owner after a reconnection.
        guard DiskRevalidation.isStillValid(selected: disk, in: diskService.snapshot()) else {
            throw BuildError.diskChanged
        }
        try checkpoint()

        setProgress(.formatting, 0.3, loc("build.detail.requestingAuth"))
        try helper.registerIfNeeded()
        try checkpoint()

        // Close the "old volume with the same label" gap: if there's already a
        // /Volumes/<label> mounted (from a previous attempt or another disk), unmount
        // it before formatting, so the only one that appears is the FRESHLY formatted
        // one and the verification-by-effect doesn't get confused.
        let labelMount = "/Volumes/\(label)"
        if FileManager.default.fileExists(atPath: labelMount) {
            _ = Subprocess.run("/usr/sbin/diskutil", ["unmount", "force", labelMount])
        }

        setProgress(.formatting, 0.5, loc("build.detail.formatting \(disk.displayName) \(disk.sizeDescription)"))
        // Kick off the format (XPC) and move on AS SOON AS the formatted volume
        // appears, without waiting for the reply (which the helper may lose on exit).
        // Instant verification-by-effect (policy: EraseDecision).
        let usbVolume: URL
        switch formatAndAwaitVolume(bsdName: disk.id, label: label, timeout: 180) {
        case .success(let url):
            usbVolume = url
        case .failure(let error):
            if error is CancellationSignal { throw CancellationSignal() }
            throw error
        }
        setProgress(.formatting, 1.0, loc("build.detail.formatted"))
        try checkpoint()

        // ---- Phase 2: Copy (everything except install.wim) ----
        copyMeter.reset()
        setProgress(.copying, 0, loc("build.detail.copyingISO"))
        try copier.copy(from: mounted.mountPoint, to: usbVolume,
                        excluding: ["sources/install.wim"],
                        progress: { p in
                            let bps = self.copyMeter.sample(bytes: p.bytesCopied, at: Date())
                            self.setProgress(.copying, p.fraction, loc("build.detail.copyingFile \(p.currentFile)"),
                                             bytesDone: p.bytesCopied, bytesTotal: p.totalBytes,
                                             bytesPerSecond: bps)
                        },
                        isCancelled: cancelled)
        try checkpoint()

        // ---- Phase 3: install.wim (split if > 4 GiB, otherwise copy whole) ----
        let sourcesDir = usbVolume.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        let wimURL = mounted.mountPoint.appendingPathComponent("sources/install.wim")

        if info.requiresWIMSplit {
            splitMeter.reset()
            // WIM size to translate wimlib's fraction into real bytes.
            let wimSize = (try? FileManager.default.attributesOfItem(atPath: wimURL.path)[.size] as? NSNumber)??.uint64Value ?? 0
            setProgress(.splitting, 0, loc("build.detail.splitting"),
                        bytesDone: 0, bytesTotal: wimSize, bytesPerSecond: nil)
            try wim.split(wim: wimURL, intoSourcesDir: sourcesDir,
                          partSizeMiB: WimConstants.partSizeMiB,
                          progress: { f in
                              let done = wimSize > 0 ? UInt64(Double(wimSize) * f) : 0
                              let bps = wimSize > 0 ? self.splitMeter.sample(bytes: done, at: Date()) : nil
                              self.setProgress(.splitting, f, loc("build.detail.splitting"),
                                               bytesDone: done, bytesTotal: wimSize, bytesPerSecond: bps)
                          },
                          isCancelled: cancelled)
        } else if FileManager.default.fileExists(atPath: wimURL.path) {
            setProgress(.splitting, 0, loc("build.detail.copyingWim"))
            let dest = sourcesDir.appendingPathComponent("install.wim")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: wimURL, to: dest)
            setProgress(.splitting, 1.0, loc("build.detail.wimCopied"))
        }
        try checkpoint()

        // ---- Phase 4: Finalize (detach ISO + eject USB) ----
        setProgress(.finalizing, 0.3, loc("build.detail.unmountingISO"))
        detachISOIfNeeded()
        setProgress(.finalizing, 0.7, loc("build.detail.ejecting"))
        _ = Subprocess.run("/usr/sbin/diskutil", ["eject", "/dev/\(disk.id)"])
        setProgress(.finalizing, 1.0, loc("build.detail.finalized"))
    }

    /// Raw flow (Linux/isohybrid): write the RAW ISO to the disk with the root
    /// helper (no format/label/split). The helper unmounts, writes `/dev/rdiskN`
    /// and ejects; here we only orchestrate and report progress via callback.
    private func runRawBuild(disk: Disk, info: ISOInfo) throws {
        // A2: `dd` writes the whole ISO; if the USB can't fit the image the write
        // fails halfway and leaves the USB broken. Guard BEFORE touching the disk.
        guard disk.fitsRawImage(ofBytes: info.sizeBytes) else {
            throw BuildError.usbTooSmallForImage(needBytes: info.sizeBytes, haveBytes: disk.sizeBytes)
        }

        // S-3: JIT revalidation just before the destructive operation.
        setProgress(.writingImage, 0, loc("build.detail.revalidating"))
        guard DiskRevalidation.isStillValid(selected: disk, in: diskService.snapshot()) else {
            throw BuildError.diskChanged
        }
        if cancelToken.isCancelled { throw CancellationSignal() }

        setProgress(.writingImage, 0, loc("build.detail.requestingAuth"))
        try helper.registerIfNeeded()
        if cancelToken.isCancelled { throw CancellationSignal() }

        rawMeter.reset()
        setProgress(.writingImage, 0, loc("build.detail.writingImage"),
                    bytesDone: 0, bytesTotal: info.sizeBytes, bytesPerSecond: nil)

        // The helper writes the .iso FILE (info.url), not the mount. async→sync
        // bridge: we launch the write and wait for its resolution. NOTE: the helper's
        // `dd` is not interruptible, so during this phase cancellation does not
        // abort midway (the USB would be left reformattable). The UI disables Cancel.
        let lock = NSLock()
        var done = false
        var writeError: Error?
        Task {
            var err: Error?
            do {
                try await self.helper.writeImage(isoPath: info.url.path, bsdName: disk.id) { written, total in
                    let frac = total > 0 ? Double(written) / Double(total) : 0
                    let bps = self.rawMeter.sample(bytes: UInt64(max(0, written)), at: Date())
                    self.setProgress(.writingImage, frac, loc("build.detail.writingImage"),
                                     bytesDone: UInt64(max(0, written)), bytesTotal: UInt64(max(0, total)),
                                     bytesPerSecond: bps)
                }
            } catch { err = error }
            lock.lock(); done = true; writeError = err; lock.unlock()
        }
        while true {
            lock.lock(); let d = done; let e = writeError; lock.unlock()
            if d { if let e { throw e }; break }
            usleep(200_000)
        }

        // The helper already ejected the disk; only the ISO is left to release.
        setProgress(.finalizing, 0.6, loc("build.detail.unmountingISO"))
        detachISOIfNeeded()
        setProgress(.finalizing, 1.0, loc("build.detail.finalized"))
    }

    /// Requests the format over XPC and returns the formatted volume AS SOON AS it
    /// appears mounted, without hanging waiting for the reply (which the helper may
    /// lose on exit). Ends on the first condition that occurs:
    ///   - the volume `/Volumes/<label>` appears → success (verification-by-effect),
    ///   - the reply arrives with an error → failure,
    ///   - cancellation → CancellationSignal,
    ///   - `timeout` elapses → one last attempt to see the volume, or `.eraseTimedOut`.
    private func formatAndAwaitVolume(bsdName: String, label: String,
                                      timeout: TimeInterval) -> Result<URL, Error> {
        let lock = NSLock()
        var replyDone = false
        var replyError: Error?
        Task {
            var err: Error?
            do { try await self.helper.eraseDisk(bsdName: bsdName, label: label) }
            catch { err = error }
            lock.lock(); replyDone = true; replyError = err; lock.unlock()
        }

        let volumeURL = URL(fileURLWithPath: "/Volumes/\(label)")
        // eraseDisk MS-DOS GPT creates EFI (s1) + data FAT32 (s2). The root daemon
        // does NOT auto-mount the volume, so we detect it by effect on the partition
        // and mount it ourselves.
        let dataPartition = "\(bsdName)s2"
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if cancelToken.isCancelled { return .failure(CancellationSignal()) }
            if FileManager.default.fileExists(atPath: volumeURL.path) {
                return .success(volumeURL)          // format confirmed by effect
            }
            // Is the data partition already FAT32 with our label? → mount it.
            if Self.isFormatted(partition: dataPartition, label: label) {
                _ = Subprocess.run("/usr/sbin/diskutil", ["mount", dataPartition])
                if FileManager.default.fileExists(atPath: volumeURL.path) {
                    return .success(volumeURL)
                }
            }
            lock.lock(); let done = replyDone; let err = replyError; lock.unlock()
            if done, let err { return .failure(err) } // the helper reported a real failure
            usleep(500_000)
        }
        if FileManager.default.fileExists(atPath: volumeURL.path) { return .success(volumeURL) }
        return .failure(replyError ?? BuildError.eraseTimedOut)
    }

    /// `true` if the partition is already FAT32 with the expected label (verification
    /// by effect of the format, independent of the XPC reply and auto-mounting).
    private static func isFormatted(partition: String, label: String) -> Bool {
        let r = Subprocess.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/\(partition)"])
        guard r.succeeded,
              let plist = (try? PropertyListSerialization.propertyList(from: r.stdout, options: [], format: nil)) as? [String: Any]
        else { return false }
        // diskutil reports FilesystemType="msdos" (doesn't contain "fat"), which is
        // why we accept msdos/fat; the label match is the strong signal.
        let volumeName = plist["VolumeName"] as? String
        let fsType = ((plist["FilesystemType"] as? String)
            ?? (plist["FilesystemName"] as? String) ?? "").lowercased()
        return volumeName == label && (fsType.contains("fat") || fsType.contains("msdos"))
    }

    /// Waits for the freshly formatted volume to mount at /Volumes/<label>.
    private func waitForVolume(label: String, timeout: TimeInterval) -> URL? {
        let path = "/Volumes/\(label)"
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if cancelToken.isCancelled { return nil }
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
            usleep(300_000)
        }
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    // MARK: - Cleanup / utilities

    private func detachISOIfNeeded() {
        if let m = mountedISO {
            try? iso.detach(m)
            mountedISO = nil
        }
    }

    /// S-5: on failure or cancellation, leave everything clean (ISO detached).
    private func cleanupAfterExit() {
        detachISOIfNeeded()
    }

    private func setProgress(_ phase: BuildPhase, _ fraction: Double, _ detail: String,
                             bytesDone: UInt64? = nil, bytesTotal: UInt64? = nil,
                             bytesPerSecond: Double? = nil) {
        onMain {
            if self.lastProgressPhase != phase {
                self.lastProgressPhase = phase
                self.phaseStartedAt = Date()
            }
            self.progress = BuildProgress(phase: phase, phaseFraction: fraction, detail: detail,
                                          bytesDone: bytesDone, bytesTotal: bytesTotal,
                                          bytesPerSecond: bytesPerSecond)
        }
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    /// Runs blocking work on a dedicated thread (not on the cooperative pool
    /// nor on main). Safe to combine with the XPC sync→async bridge.
    private func background(_ body: @escaping () -> Void) {
        Thread.detachNewThread(body)
    }
}

/// Internal cancellation signal (not a user error).
private struct CancellationSignal: Error {}

/// Orchestration errors.
enum BuildError: LocalizedError {
    case diskChanged
    case usbVolumeNotFound
    case eraseTimedOut
    case unsupportedISO
    /// The USB is smaller than the ISO to be written raw (A2). Carries both sizes so
    /// the user can see how much is needed vs. how much they have.
    case usbTooSmallForImage(needBytes: UInt64, haveBytes: UInt64)

    var errorDescription: String? {
        switch self {
        case .diskChanged:
            return loc("error.build.diskChanged")
        case .usbVolumeNotFound:
            return loc("error.build.usbVolumeNotFound")
        case .eraseTimedOut:
            return loc("error.build.eraseTimedOut")
        case .unsupportedISO:
            return loc("error.build.unsupportedISO")
        case let .usbTooSmallForImage(needBytes, haveBytes):
            let need = ByteCountFormatter.string(fromByteCount: Int64(needBytes), countStyle: .file)
            let have = ByteCountFormatter.string(fromByteCount: Int64(haveBytes), countStyle: .file)
            return loc("error.build.usbTooSmall \(have) \(need)")
        }
    }
}

/// "Verification by effect" policy for the format: the format is considered good
/// if there was a clean reply from the helper, OR if the freshly formatted volume
/// appeared mounted (even if the XPC reply was lost). Avoids hanging the app over a
/// lost reply when the format did happen.
enum EraseDecision {
    static func succeeded(replyFailed: Bool, volumeAppeared: Bool) -> Bool {
        !replyFailed || volumeAppeared
    }
}

/// Thread-safe cancellation flag.
final class CancellationToken {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func reset() { lock.lock(); cancelled = false; lock.unlock() }
}
