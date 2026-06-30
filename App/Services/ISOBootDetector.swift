import Foundation

/// How an ISO must be written for the USB to boot. This determines the STRATEGY,
/// it's not a cosmetic detail: copying files vs. writing the raw image are
/// incompatible processes.
public enum ISOBootType: Equatable {
    /// Windows installer: format FAT32/GPT + copy files + split
    /// install.wim (the current path, already proven on hardware).
    case windows
    /// Isohybrid ISO (modern Linux/BSD): must be written RAW (raw / `dd`)
    /// to the whole disk. Copying its files does NOT make it bootable.
    case hybridRaw
    /// Bootable as a CD (El Torito) but WITHOUT a hybrid MBR → writing raw isn't
    /// reliable. Better to reject than to produce a USB that won't boot.
    case elToritoOnly
    /// No known boot mechanism was detected.
    case notBootable

    /// Can the app create a bootable USB from this ISO today or with the raw POC?
    public var isSupportable: Bool { self == .windows || self == .hybridRaw }
}

/// Classifies an ISO by reading its header (MBR + ISO9660 El Torito descriptor).
/// The classification logic is pure (it operates on `Data`) so it can be tested
/// without a real ISO; the IO wrapper only reads the sectors it needs.
public enum ISOBootDetector {

    // ISO9660: the "Boot Record Volume Descriptor" lives in logical sector 17
    // (2048 bytes/sector → offset 0x8800). El Torito marks it there.
    static let sectorSize = 2048
    static let bootRecordOffset = 17 * 2048   // 0x8800

    // MARK: - Pure logic (testable over bytes)

    /// Sector 0 ends in the MBR boot signature `0x55 0xAA` (offset 510-511).
    /// A sign of a raw-writable isohybrid image.
    public static func hasMBRSignature(sector0: Data) -> Bool {
        guard sector0.count >= 512 else { return false }
        return sector0[sector0.startIndex + 510] == 0x55
            && sector0[sector0.startIndex + 511] == 0xAA
    }

    /// The sector 17 descriptor is an El Torito Boot Record:
    ///   byte 0 = 0x00 (Boot Record type), bytes 1-5 = "CD001", byte 6 = 0x01,
    ///   bytes 7-38 = "EL TORITO SPECIFICATION" (NUL-padded).
    public static func hasElTorito(sector17: Data) -> Bool {
        guard sector17.count >= 39 else { return false }
        let b = [UInt8](sector17.prefix(39))
        guard b[0] == 0x00 else { return false }
        guard Array(b[1...5]) == Array("CD001".utf8) else { return false }
        let id = String(bytes: b[7..<39], encoding: .ascii)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
        return id == "EL TORITO SPECIFICATION"
    }

    /// Decides the strategy from the signals. Windows wins (its file-based detection
    /// is the most reliable); then hybrid MBR (raw); then plain El Torito.
    public static func classify(isWindows: Bool, hasMBR: Bool, hasElTorito: Bool) -> ISOBootType {
        if isWindows { return .windows }
        if hasMBR { return .hybridRaw }
        if hasElTorito { return .elToritoOnly }
        return .notBootable
    }

    // MARK: - IO

    /// Reads the needed sectors from the ISO and classifies. `isWindows` comes from
    /// the existing file inspection (`ISOInfo.isWindowsInstaller`).
    public static func detect(isoAt url: URL, isWindows: Bool) -> ISOBootType {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return .notBootable }
        defer { try? fh.close() }

        let sector0 = (try? readBytes(fh, at: 0, count: 512)) ?? Data()
        let sector17 = (try? readBytes(fh, at: UInt64(bootRecordOffset), count: 64)) ?? Data()

        return classify(isWindows: isWindows,
                        hasMBR: hasMBRSignature(sector0: sector0),
                        hasElTorito: hasElTorito(sector17: sector17))
    }

    private static func readBytes(_ fh: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try fh.seek(toOffset: offset)
        return try fh.read(upToCount: count) ?? Data()
    }
}
