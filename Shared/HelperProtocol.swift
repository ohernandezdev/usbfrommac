import Foundation

/// XPC contract between the app and the privileged helper (root daemon).
///
/// The helper exposes EXCLUSIVELY the destructive formatting (`diskutil eraseDisk`),
/// which is the only operation that requires root. Everything else (mounting the
/// ISO, copying, splitting the .wim) runs as the user on the already-mounted volume.
///
/// The protocol is compiled into both targets (app and helper) by sharing this
/// file, which is the standard pattern for NSXPC.
@objc public protocol HelperProtocol {

    /// Formats `bsdName` as FAT32 with a GPT scheme and the given label.
    ///
    /// SECURITY (S-4): the helper REVALIDATES on its own that the target is a
    /// whole, external, removable physical disk before executing anything. It never
    /// blindly trusts the arguments received over XPC.
    ///
    /// - Parameters:
    ///   - bsdName: BSD identifier of the whole disk, e.g. "disk4".
    ///   - label: FAT32 label (≤ 11 characters, uppercase).
    ///   - reply: `(ok, errorMessage?)`.
    func eraseDisk(bsdName: String,
                   label: String,
                   reply: @escaping (Bool, String?) -> Void)

    /// Writes the ISO RAW (`dd`-style) onto the `bsdName` disk.
    ///
    /// For isohybrid ISOs (Linux/BSD) that must be dumped byte by byte to the device.
    /// Applies the SAME safeguards as `eraseDisk` (S-4): it revalidates that the
    /// target is whole + external + removable and that it is NOT the boot disk,
    /// unmounts the disk, and writes to `/dev/rdiskN`. Progress is reported over the
    /// reverse channel (`HelperProgressProtocol`).
    ///
    /// NOTE: the helper opens `isoPath` itself, which requires it to have Full Disk
    /// Access if the ISO lives under a TCC-protected folder (Downloads, Desktop, …) —
    /// root does not bypass TCC's per-folder protections. (An earlier attempt passed
    /// an already-open `FileHandle` over XPC instead, to avoid that requirement, but
    /// NSXPCInterface rejected it at decode time with "not in the interface of the
    /// remote object" even after whitelisting the class via `setClasses`, for reasons
    /// that weren't worth chasing further — reverted in favor of this simpler,
    /// verifiable path + a one-time Full Disk Access grant.)
    ///
    /// - Parameters:
    ///   - isoPath: absolute path of the .iso file to dump.
    ///   - bsdName: BSD identifier of the whole disk, e.g. "disk4".
    ///   - reply: `(ok, errorMessage?)`.
    func writeImage(isoPath: String,
                    bsdName: String,
                    reply: @escaping (Bool, String?) -> Void)

    /// Version of the installed helper (to check that app and helper agree).
    func helperVersion(reply: @escaping (String) -> Void)
}

/// Reverse progress channel: implemented by the APP and invoked by the HELPER
/// during a long operation (raw write) to report bytes written live.
@objc public protocol HelperProgressProtocol {
    func didWrite(bytes: Int64, of total: Int64)
}

/// Shared constants app ↔ helper.
public enum HelperConstants {
    /// Mach service name (must match the launchd plist and SMAppService).
    public static let machServiceName = "com.omarhernandez.flint.helper"

    /// Name of the embedded launchd plist (used by SMAppService.daemon(plistName:)).
    public static let plistName = "com.omarhernandez.flint.helper.plist"

    /// Contract/helper version.
    public static let version = "1.0.0"

    /// Maximum length of a FAT32 label.
    public static let maxFAT32LabelLength = 11

    public static let appBundleID = "com.omarhernandez.flint"
    public static let helperBundleID = "com.omarhernandez.flint.helper"

    // Apple Team ID: OU of the Developer ID certificate; validates the cross XPC
    // signature. (Omar's team — Developer ID Application C34D3V8484.) With local
    // ad-hoc signing ("-") this validation does NOT pass (which is expected): it
    // only applies to builds signed with Developer ID / Apple Development from this same team.
    public static let teamID = "C34D3V8484"

    /// Requirement the APP demands of the HELPER (that the helper is yours and not impersonated).
    public static var helperCodeSigningRequirement: String {
        "identifier \"\(helperBundleID)\" and anchor apple generic and "
        + "certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// Requirement the HELPER demands of the CLIENT (that whoever asks it to format is your app).
    public static var clientCodeSigningRequirement: String {
        "identifier \"\(appBundleID)\" and anchor apple generic and "
        + "certificate leaf[subject.OU] = \"\(teamID)\""
    }
}
