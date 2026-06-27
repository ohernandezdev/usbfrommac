import Foundation

/// Cómo debe escribirse un ISO para que el USB arranque. Determina la ESTRATEGIA,
/// no es un detalle cosmético: copiar archivos vs. escribir la imagen cruda son
/// procesos incompatibles.
public enum ISOBootType: Equatable {
    /// Instalador de Windows: formatear FAT32/GPT + copiar archivos + partir
    /// install.wim (el camino actual, ya probado en hardware).
    case windows
    /// ISO isohíbrido (Linux/BSD modernos): debe escribirse CRUDO (raw / `dd`)
    /// al disco entero. Copiar sus archivos NO lo hace booteable.
    case hybridRaw
    /// Booteable como CD (El Torito) pero SIN MBR híbrido → escribir crudo no es
    /// fiable. Mejor rechazar que producir un USB que no arranca.
    case elToritoOnly
    /// No se detectó ningún mecanismo de arranque conocido.
    case notBootable

    /// ¿La app puede crear un USB booteable de este ISO hoy o con el POC raw?
    public var isSupportable: Bool { self == .windows || self == .hybridRaw }
}

/// Clasifica un ISO leyendo su cabecera (MBR + descriptor El Torito de ISO9660).
/// La lógica de clasificación es pura (opera sobre `Data`) para poder testearla
/// sin un ISO real; el wrapper de IO solo lee los sectores necesarios.
public enum ISOBootDetector {

    // ISO9660: el "Boot Record Volume Descriptor" vive en el sector lógico 17
    // (2048 bytes/sector → offset 0x8800). El Torito lo marca ahí.
    static let sectorSize = 2048
    static let bootRecordOffset = 17 * 2048   // 0x8800

    // MARK: - Lógica pura (testeable sobre bytes)

    /// El sector 0 termina en la firma de arranque MBR `0x55 0xAA` (offset 510-511).
    /// Señal de imagen isohíbrida escribible cruda.
    public static func hasMBRSignature(sector0: Data) -> Bool {
        guard sector0.count >= 512 else { return false }
        return sector0[sector0.startIndex + 510] == 0x55
            && sector0[sector0.startIndex + 511] == 0xAA
    }

    /// El descriptor del sector 17 es un Boot Record El Torito:
    ///   byte 0 = 0x00 (tipo Boot Record), bytes 1-5 = "CD001", byte 6 = 0x01,
    ///   bytes 7-38 = "EL TORITO SPECIFICATION" (rellenado con NUL).
    public static func hasElTorito(sector17: Data) -> Bool {
        guard sector17.count >= 39 else { return false }
        let b = [UInt8](sector17.prefix(39))
        guard b[0] == 0x00 else { return false }
        guard Array(b[1...5]) == Array("CD001".utf8) else { return false }
        let id = String(bytes: b[7..<39], encoding: .ascii)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
        return id == "EL TORITO SPECIFICATION"
    }

    /// Decide la estrategia a partir de las señales. Windows manda (su detección por
    /// archivos es la más fiable); luego MBR híbrido (raw); luego El Torito a secas.
    public static func classify(isWindows: Bool, hasMBR: Bool, hasElTorito: Bool) -> ISOBootType {
        if isWindows { return .windows }
        if hasMBR { return .hybridRaw }
        if hasElTorito { return .elToritoOnly }
        return .notBootable
    }

    // MARK: - IO

    /// Lee los sectores necesarios del ISO y clasifica. `isWindows` proviene de la
    /// inspección de archivos ya existente (`ISOInfo.isWindowsInstaller`).
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
