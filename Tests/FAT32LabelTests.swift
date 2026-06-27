import XCTest
@testable import UsbFromMac

final class FAT32LabelTests: XCTestCase {

    func testValidLabels() {
        XCTAssertTrue(FAT32Label.isValid("WIN11"))
        XCTAssertTrue(FAT32Label.isValid("INSTALL_USB"))      // 11 exactos
        XCTAssertTrue(FAT32Label.isValid("A"))
    }

    func testInvalidLabels() {
        XCTAssertFalse(FAT32Label.isValid(""))                 // vacío
        XCTAssertFalse(FAT32Label.isValid("DEMASIADO_LARGO"))  // > 11
        XCTAssertFalse(FAT32Label.isValid("win11"))            // minúsculas no permitidas
        XCTAssertFalse(FAT32Label.isValid("WIN 11"))           // espacio
        XCTAssertFalse(FAT32Label.isValid("WÍN11"))            // acento
    }

    func testSanitizeUppercasesAndStrips() {
        XCTAssertEqual(FAT32Label.sanitize("win 11!"), "WIN11")
        XCTAssertEqual(FAT32Label.sanitize("Mi USB ñ"), "MIUSB")
    }

    func testSanitizeTruncatesToElevenChars() {
        let result = FAT32Label.sanitize("ABCDEFGHIJKLMNOP")
        XCTAssertEqual(result.count, 11)
        XCTAssertEqual(result, "ABCDEFGHIJK")
    }

    func testSanitizeFallbackWhenEmpty() {
        XCTAssertEqual(FAT32Label.sanitize("¡!¿?"), "WIN11")
        XCTAssertEqual(FAT32Label.sanitize("", fallback: "USB"), "USB")
    }

    func testSanitizeOutputIsAlwaysValid() {
        for raw in ["win 11", "¡hola!", "ABCDEFGHIJKLMNOP", "x", "Ñoño_2026"] {
            XCTAssertTrue(FAT32Label.isValid(FAT32Label.sanitize(raw)),
                          "sanitize(\(raw)) debería ser válido")
        }
    }
}
