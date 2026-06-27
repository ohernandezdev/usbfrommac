import Foundation
import Combine

/// Orquestador del flujo completo (la "máquina de estados" del wizard y del build).
///
/// Garantías de seguridad clave que viven aquí:
///   - S-3: re-validación JIT del disco (id + tamaño) JUSTO antes de formatear.
///   - S-5: cualquier fallo o cancelación desmonta el ISO y no deja formateos a medias.
///
/// No es `@MainActor`: el trabajo pesado corre en un hilo de fondo y las
/// publicaciones a SwiftUI se marshalizan a main vía `onMain`.
public final class BuildCoordinator: ObservableObject {

    public enum Step: Equatable { case selectISO, selectDisk, confirm, build }

    // Navegación
    @Published public var step: Step = .selectISO

    // ISO
    @Published public var isoURL: URL?
    @Published public private(set) var isoInfo: ISOInfo?
    @Published public private(set) var isInspectingISO = false
    @Published public private(set) var isoError: String?

    // Verificación de hash (opcional)
    @Published public var expectedHash: String = ""
    @Published public private(set) var computedHash: String?
    @Published public private(set) var hashMatches: Bool?
    @Published public private(set) var isHashing = false
    @Published public private(set) var hashProgress: Double = 0

    // Disco / etiqueta / confirmación
    @Published public var selectedDisk: Disk?
    @Published public var label: String = "WIN11"
    @Published public var confirmedDestructive = false

    // Build
    @Published public private(set) var progress = BuildProgress(phase: .idle, phaseFraction: 0, detail: "")
    @Published public private(set) var isBuilding = false
    @Published public private(set) var finished = false
    /// Instante en que empezó la fase ACTUAL (para el "heartbeat"/tiempo transcurrido
    /// de fases sin sub-progreso, p. ej. Formatear).
    @Published public private(set) var phaseStartedAt: Date?
    private var lastProgressPhase: BuildPhase?

    // Medidores de velocidad por fase (bytes/seg suavizados).
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

    // MARK: - Paso 1: ISO

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
            do {
                let mounted = try self.iso.attach(url)
                self.mountedISO = mounted
                let info = self.iso.inspect(mounted, isoURL: url)
                self.onMain {
                    self.isoInfo = info
                    self.isInspectingISO = false
                    if !FAT32Label.isValid(self.label) { self.label = "WIN11" }
                }
            } catch {
                self.onMain {
                    self.isInspectingISO = false
                    self.isoError = error.localizedDescription
                }
            }
        }
    }

    public var canProceedFromISO: Bool { isoInfo?.bootIsSupported == true }

    /// `true` si el ISO se escribe crudo (Linux/isohíbrido) en vez de copiar a FAT32.
    public var isRawFlow: Bool { isoInfo?.bootType == .hybridRaw }

    /// Fases a mostrar en la pantalla de progreso, según el tipo de ISO.
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

    // MARK: - Paso 2: Disco

    public func goToDiskSelection() {
        diskService.start()
        step = .selectDisk
    }

    /// Navegación hacia atrás desde la barra de pasos: solo a pasos ya visitados
    /// y nunca durante un build en curso (no se interrumpe una operación destructiva).
    public func goTo(step target: Step) {
        guard !isBuilding else { return }
        let order: [Step] = [.selectISO, .selectDisk, .confirm, .build]
        guard let from = order.firstIndex(of: step),
              let to = order.firstIndex(of: target),
              to < from else { return }
        if target == .selectDisk { diskService.start() }
        step = target
    }

    // MARK: - Paso 3: Confirmación

    public func goToConfirm() {
        guard selectedDisk != nil else { return }
        if !FAT32Label.isValid(label) { label = FAT32Label.sanitize(label) }
        confirmedDestructive = false
        step = .confirm
    }

    public var canStartBuild: Bool {
        guard selectedDisk != nil, confirmedDestructive else { return false }
        // El flujo raw (Linux) no usa etiqueta FAT32; solo Windows la exige.
        return isRawFlow || FAT32Label.isValid(label)
    }

    // MARK: - Paso 4: Build

    public func startBuild() {
        guard let disk = selectedDisk,
              let mounted = mountedISO,
              let info = isoInfo else { return }
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

    /// Reinicia el wizard para crear otro USB.
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

    // MARK: - Orquestación (hilo de fondo)

    /// Despacha al flujo correcto según el tipo de arranque del ISO.
    private func runBuild(disk: Disk, mounted: MountedISO, info: ISOInfo, label: String) throws {
        switch info.bootType {
        case .windows:
            try runWindowsBuild(disk: disk, mounted: mounted, info: info, label: label)
        case .hybridRaw:
            try runRawBuild(disk: disk, info: info)
        case .elToritoOnly, .notBootable:
            // No debería llegar aquí (el wizard filtra antes), pero por seguridad.
            throw BuildError.unsupportedISO
        }
    }

    /// Flujo Windows: formatear FAT32 → copiar → dividir install.wim → finalizar.
    private func runWindowsBuild(disk: Disk, mounted: MountedISO, info: ISOInfo, label: String) throws {
        let cancelled: () -> Bool = { [cancelToken] in cancelToken.isCancelled }
        func checkpoint() throws { if cancelled() { throw CancellationSignal() } }

        // ---- Fase 1: Formatear ----
        setProgress(.formatting, 0.1, loc("build.detail.revalidating"))
        // S-3: el identificador puede haber cambiado de dueño tras una reconexión.
        guard DiskRevalidation.isStillValid(selected: disk, in: diskService.snapshot()) else {
            throw BuildError.diskChanged
        }
        try checkpoint()

        setProgress(.formatting, 0.3, loc("build.detail.requestingAuth"))
        try helper.registerIfNeeded()
        try checkpoint()

        // Cierra el hueco del "volumen viejo con la misma etiqueta": si ya hay un
        // /Volumes/<label> montado (de un intento previo u otro disco), desmóntalo
        // antes de formatear, para que el único que aparezca sea el RECIÉN formateado
        // y la verificación por efecto no se confunda.
        let labelMount = "/Volumes/\(label)"
        if FileManager.default.fileExists(atPath: labelMount) {
            _ = Subprocess.run("/usr/sbin/diskutil", ["unmount", "force", labelMount])
        }

        setProgress(.formatting, 0.5, loc("build.detail.formatting \(disk.displayName) \(disk.sizeDescription)"))
        // Lanza el formateo (XPC) y avanza EN CUANTO el volumen formateado aparece,
        // sin esperar el reply (que el helper puede perder al salir). Verificación
        // por efecto instantánea (política: EraseDecision).
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

        // ---- Fase 2: Copiar (todo menos install.wim) ----
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

        // ---- Fase 3: install.wim (dividir si > 4 GiB, si no copiar entero) ----
        let sourcesDir = usbVolume.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        let wimURL = mounted.mountPoint.appendingPathComponent("sources/install.wim")

        if info.requiresWIMSplit {
            splitMeter.reset()
            // Tamaño del WIM para traducir la fracción de wimlib a bytes reales.
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

        // ---- Fase 4: Finalizar (desmontar ISO + expulsar USB) ----
        setProgress(.finalizing, 0.3, loc("build.detail.unmountingISO"))
        detachISOIfNeeded()
        setProgress(.finalizing, 0.7, loc("build.detail.ejecting"))
        _ = Subprocess.run("/usr/sbin/diskutil", ["eject", "/dev/\(disk.id)"])
        setProgress(.finalizing, 1.0, loc("build.detail.finalized"))
    }

    /// Flujo raw (Linux/isohíbrido): escribir el ISO CRUDO al disco con el helper
    /// root (no formatear/etiqueta/split). El helper desmonta, escribe `/dev/rdiskN`
    /// y expulsa; aquí solo orquestamos y reportamos el progreso por callback.
    private func runRawBuild(disk: Disk, info: ISOInfo) throws {
        // S-3: revalidación JIT justo antes de la operación destructiva.
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

        // El helper escribe el ARCHIVO .iso (info.url), no el montaje. Puente
        // async→sync: lanzamos la escritura y esperamos su resolución. NOTA: el `dd`
        // del helper no es interrumpible, así que durante esta fase la cancelación
        // no aborta a mitad (el USB quedaría reformateable). La UI deshabilita Cancelar.
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

        // El helper ya expulsó el disco; solo queda soltar el ISO.
        setProgress(.finalizing, 0.6, loc("build.detail.unmountingISO"))
        detachISOIfNeeded()
        setProgress(.finalizing, 1.0, loc("build.detail.finalized"))
    }

    /// Pide el formateo por XPC y devuelve el volumen formateado EN CUANTO aparece
    /// montado, sin colgarse esperando el reply (que el helper puede perder al salir).
    /// Termina por la primera condición que ocurra:
    ///   - el volumen `/Volumes/<label>` aparece → éxito (verificación por efecto),
    ///   - el reply llega con error → fallo,
    ///   - cancelación → CancellationSignal,
    ///   - se agota `timeout` → último intento de ver el volumen, o `.eraseTimedOut`.
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
        // eraseDisk MS-DOS GPT crea EFI (s1) + FAT32 de datos (s2). El daemon root
        // NO auto-monta el volumen, así que lo detectamos por efecto en la partición
        // y lo montamos nosotros.
        let dataPartition = "\(bsdName)s2"
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if cancelToken.isCancelled { return .failure(CancellationSignal()) }
            if FileManager.default.fileExists(atPath: volumeURL.path) {
                return .success(volumeURL)          // formateo confirmado por efecto
            }
            // ¿La partición de datos ya es FAT32 con nuestra etiqueta? → montarla.
            if Self.isFormatted(partition: dataPartition, label: label) {
                _ = Subprocess.run("/usr/sbin/diskutil", ["mount", dataPartition])
                if FileManager.default.fileExists(atPath: volumeURL.path) {
                    return .success(volumeURL)
                }
            }
            lock.lock(); let done = replyDone; let err = replyError; lock.unlock()
            if done, let err { return .failure(err) } // el helper reportó un fallo real
            usleep(500_000)
        }
        if FileManager.default.fileExists(atPath: volumeURL.path) { return .success(volumeURL) }
        return .failure(replyError ?? BuildError.eraseTimedOut)
    }

    /// `true` si la partición ya es FAT32 con la etiqueta esperada (verificación por
    /// efecto del formateo, independiente del reply XPC y del auto-montaje).
    private static func isFormatted(partition: String, label: String) -> Bool {
        let r = Subprocess.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/\(partition)"])
        guard r.succeeded,
              let plist = (try? PropertyListSerialization.propertyList(from: r.stdout, options: [], format: nil)) as? [String: Any]
        else { return false }
        // diskutil reporta FilesystemType="msdos" (no contiene "fat"), por eso
        // aceptamos msdos/fat; el match de la etiqueta es la señal fuerte.
        let volumeName = plist["VolumeName"] as? String
        let fsType = ((plist["FilesystemType"] as? String)
            ?? (plist["FilesystemName"] as? String) ?? "").lowercased()
        return volumeName == label && (fsType.contains("fat") || fsType.contains("msdos"))
    }

    /// Espera a que el volumen recién formateado se monte en /Volumes/<label>.
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

    // MARK: - Limpieza / utilidades

    private func detachISOIfNeeded() {
        if let m = mountedISO {
            try? iso.detach(m)
            mountedISO = nil
        }
    }

    /// S-5: ante fallo o cancelación, dejar todo limpio (ISO desmontado).
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

    /// Ejecuta trabajo bloqueante en un hilo dedicado (no en el pool cooperativo
    /// ni en main). Seguro para combinar con el puente sync→async del XPC.
    private func background(_ body: @escaping () -> Void) {
        Thread.detachNewThread(body)
    }
}

/// Señal interna de cancelación (no es un error de usuario).
private struct CancellationSignal: Error {}

/// Errores de orquestación.
enum BuildError: LocalizedError {
    case diskChanged
    case usbVolumeNotFound
    case eraseTimedOut
    case unsupportedISO

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
        }
    }
}

/// Política de "verificación por efecto" del formateo: el formateo se da por bueno
/// si hubo reply limpio del helper, O si el volumen recién formateado apareció
/// montado (aunque el reply XPC se haya perdido). Evita colgar la app por un reply
/// perdido cuando el formateo sí ocurrió.
enum EraseDecision {
    static func succeeded(replyFailed: Bool, volumeAppeared: Bool) -> Bool {
        !replyFailed || volumeAppeared
    }
}

/// Bandera de cancelación segura entre hilos.
final class CancellationToken {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func reset() { lock.lock(); cancelled = false; lock.unlock() }
}
