import Foundation

/// Root-side implementation of the XPC contract.
///
/// It is deliberately SELF-CONTAINED (it shares no code with the app other than
/// the protocol): this minimizes the attack surface of the privileged component
/// and guarantees that the security revalidation doesn't depend on the app's logic.
final class HelperService: NSObject, HelperProtocol {

    private let diskutil = "/usr/sbin/diskutil"

    func helperVersion(reply: @escaping (String) -> Void) {
        reply(HelperConstants.version)
    }

    func eraseDisk(bsdName: String,
                   label: String,
                   reply: @escaping (Bool, String?) -> Void) {

        // 1. The identifier must be a WHOLE disk: "diskN", with no partition
        //    suffixes or paths. Blocks injection and formatting of stray partitions.
        guard Self.isValidWholeDiskBSD(bsdName) else {
            return reply(false, "Invalid disk identifier: \(bsdName)")
        }

        // 2. Sanitized FAT32 label (≤ 11, safe charset).
        guard let safeLabel = Self.sanitizedFAT32Label(label) else {
            return reply(false, "Invalid FAT32 label (max. 11 characters allowed).")
        }

        // 3. It must not be the boot disk (revalidated here; the app is not trusted).
        if let boot = Self.bootDiskBSDName(), boot == bsdName {
            return reply(false, "Operation rejected: the target is the system boot disk.")
        }

        // 4. INDEPENDENT REVALIDATION (S-4): the helper queries diskutil and requires
        //    the target to be whole + NOT internal + removable. If anything doesn't
        //    add up, it aborts without touching anything.
        if case .failure(let message) = Self.validateRemovableExternal(bsdName, diskutil: diskutil) {
            return reply(false, message)
        }

        // 5. Only here, with everything validated, does it format.
        let result = Self.runDiskutilErase(bsdName: bsdName, label: safeLabel, diskutil: diskutil)
        reply(result.ok, result.message)
    }

    // MARK: - Raw write (isohybrid / Linux ISOs)

    func writeImage(isoPath: String,
                    bsdName: String,
                    reply: @escaping (Bool, String?) -> Void) {
        // Same safeguards as formatting: the raw write is just as destructive.
        guard Self.isValidWholeDiskBSD(bsdName) else {
            return reply(false, "Invalid disk identifier: \(bsdName)")
        }
        guard FileManager.default.fileExists(atPath: isoPath) else {
            return reply(false, "The image wasn't found at \(isoPath).")
        }
        if let boot = Self.bootDiskBSDName(), boot == bsdName {
            return reply(false, "Operation rejected: the target is the system boot disk.")
        }
        if case .failure(let message) = Self.validateRemovableExternal(bsdName, diskutil: diskutil) {
            return reply(false, message)
        }

        // The WHOLE disk must be unmounted before writing to the raw device.
        let unmount = Self.runProcess(diskutil, ["unmountDisk", "force", "/dev/\(bsdName)"])
        guard unmount.status == 0 else {
            let msg = String(data: unmount.stderr, encoding: .utf8) ?? ""
            return reply(false, "Couldn't unmount the disk before writing: \(msg)")
        }

        // Re-validate right before opening the device: unmounting takes real wall-clock
        // time, which is a window where the disk could have been unplugged and a
        // different device reassigned the same bsdName. Closing it here, immediately
        // before the write, rather than trusting the check from before the unmount.
        if case .failure(let message) = Self.validateRemovableExternal(bsdName, diskutil: diskutil) {
            return reply(false, "Re-validation before write failed: \(message)")
        }

        // Reverse progress channel back to the app (if available).
        let progress = NSXPCConnection.current()?.remoteObjectProxy as? HelperProgressProtocol

        let result = Self.rawWrite(isoPath: isoPath, bsdName: bsdName) { written, total in
            progress?.didWrite(bytes: written, of: total)
        }
        if result.ok {
            _ = Self.runProcess(diskutil, ["eject", "/dev/\(bsdName)"])
        }
        reply(result.ok, result.message)
    }

    /// Dumps the ISO byte by byte onto `/dev/rdiskN` (raw device, fast).
    /// Writes are aligned to the device's block size (the last block is padded
    /// with zeros, which is harmless). No fallback: any IO failure aborts.
    static func rawWrite(isoPath: String,
                         bsdName: String,
                         progress: (Int64, Int64) -> Void) -> (ok: Bool, message: String?) {

        let total = (try? FileManager.default.attributesOfItem(atPath: isoPath)[.size] as? NSNumber)??.int64Value ?? 0

        guard let input = FileHandle(forReadingAtPath: isoPath) else {
            return (false, "Couldn't open the image for reading. Grant Full Disk Access to Flint in System Settings → Privacy & Security → Full Disk Access, then try again.")
        }
        defer { try? input.close() }

        // Raw device: /dev/rdiskN is much faster than /dev/diskN.
        let fd = open("/dev/r\(bsdName)", O_RDWR)
        guard fd >= 0 else {
            return (false, "Couldn't open the device /dev/r\(bsdName) (errno \(errno)).")
        }
        defer { close(fd) }

        // Physical block size of the device (used to align writes).
        var blockSize: UInt32 = 512
        _ = ioctl(fd, 0x40046418 /* DKIOCGETBLOCKSIZE */, &blockSize)
        let bs = Int(blockSize == 0 ? 512 : blockSize)
        let chunk = max(bs, (4 * 1024 * 1024 / bs) * bs)   // ~4 MiB, multiple of the block

        var writtenTotal: Int64 = 0
        while true {
            let data = (try? input.read(upToCount: chunk)) ?? Data()
            if data.isEmpty { break }

            // Align the last block: pad with zeros up to a multiple of the block size.
            var buf = data
            if buf.count % bs != 0 {
                buf.append(Data(count: bs - (buf.count % bs)))
            }

            let wrote: Int = buf.withUnsafeBytes { raw in
                write(fd, raw.baseAddress, buf.count)
            }
            if wrote < 0 {
                return (false, "Write error on the device (errno \(errno)).")
            }
            writtenTotal += Int64(data.count)
            progress(min(writtenTotal, total), total)
        }

        // Flush the device's write cache before ejecting, using the disk-level ioctl
        // (the same one `diskutil eject` uses) rather than `fcntl(F_FULLFSYNC)`, which
        // is meant for files on a mounted filesystem, not a raw block device.
        //
        // ENOTTY here means the device's driver doesn't implement ANY explicit-sync
        // ioctl — not that the write failed. That's expected for some generic USB
        // mass-storage controllers, and it's harmless: writes to the raw `/dev/rdiskN`
        // node are already unbuffered/synchronous (that's the whole point of "raw"
        // vs the buffered `/dev/diskN`), so there is no dirty cache left to flush.
        // Any OTHER errno here is a real fault and still aborts.
        if ioctl(fd, 0x20006416 /* DKIOCSYNCHRONIZECACHE */, 0) != 0 && errno != ENOTTY {
            return (false, "Couldn't sync the device (errno \(errno)).")
        }
        return (true, nil)
    }

    // MARK: - Validation

    static func isValidWholeDiskBSD(_ bsd: String) -> Bool {
        bsd.range(of: "^disk[0-9]+$", options: .regularExpression) != nil
    }

    static func sanitizedFAT32Label(_ label: String) -> String? {
        let upper = label.uppercased()
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard !upper.isEmpty,
              upper.count <= HelperConstants.maxFAT32LabelLength,
              upper.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return upper
    }

    enum ValidationResult { case success, failure(String) }

    static func validateRemovableExternal(_ bsd: String, diskutil: String) -> ValidationResult {
        let r = runProcess(diskutil, ["info", "-plist", "/dev/\(bsd)"])
        guard r.status == 0,
              let plist = (try? PropertyListSerialization.propertyList(from: r.stdout,
                                                                       options: [],
                                                                       format: nil)) as? [String: Any] else {
            return .failure("Couldn't read the disk info for \(bsd).")
        }
        let whole = (plist["WholeDisk"] as? Bool) ?? false
        // Fail-safe: if unknown, treat it as internal (reject).
        let isInternal = (plist["Internal"] as? Bool) ?? true
        let ejectable = (plist["Ejectable"] as? Bool) ?? false
        let removable = (plist["RemovableMedia"] as? Bool) ?? false
        // Defense in depth (S-4): reject virtual devices / disk images even if
        // they present themselves as external + removable.
        let virtualOrPhysical = (plist["VirtualOrPhysical"] as? String) ?? ""

        guard whole else { return .failure("The target is not a whole physical disk.") }
        guard !isInternal else { return .failure("The target is an internal disk. Operation rejected.") }
        guard virtualOrPhysical.caseInsensitiveCompare("Virtual") != .orderedSame else {
            return .failure("The target is a virtual device (disk image). Operation rejected.")
        }
        guard ejectable || removable else {
            return .failure("The target is not removable media. Operation rejected.")
        }
        return .success
    }

    // MARK: - Formatting

    static func runDiskutilErase(bsdName: String, label: String, diskutil: String) -> (ok: Bool, message: String?) {
        let r = runProcess(diskutil, ["eraseDisk", "MS-DOS", label, "GPT", "/dev/\(bsdName)"])
        if r.status == 0 { return (true, nil) }
        let err = String(data: r.stderr, encoding: .utf8) ?? ""
        let out = String(data: r.stdout, encoding: .utf8) ?? ""
        let message = (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines)
        return (false, message.isEmpty ? "diskutil failed (code \(r.status))." : message)
    }

    // MARK: - Utilities

    /// Physical disk backing "/", normalized to "diskN".
    static func bootDiskBSDName() -> String? {
        var s = statfs()
        guard statfs("/", &s) == 0 else { return nil }
        let from = withUnsafeBytes(of: &s.f_mntfromname) { raw -> String in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        let dev = from.hasPrefix("/dev/") ? String(from.dropFirst(5)) : from
        guard dev.hasPrefix("disk") else { return nil }
        let digits = dev.dropFirst(4).prefix { $0.isNumber }
        return digits.isEmpty ? nil : "disk" + digits
    }

    static func runProcess(_ launchPath: String, _ args: [String]) -> (status: Int32, stdout: Data, stderr: Data) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do {
            try task.run()
        } catch {
            return (-1, Data(), Data("Couldn't run \(launchPath): \(error)".utf8))
        }
        let oData = out.fileHandleForReading.readDataToEndOfFile()
        let eData = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, oData, eData)
    }
}
