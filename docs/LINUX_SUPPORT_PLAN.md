# Plan — soporte universal de ISOs (Windows + Linux) + rebranding

Rama: `feature/linux-iso-support`. Objetivo: dejar de ser "solo Windows" y soportar
ISOs isohíbridos (Linux/BSD) por escritura cruda (`dd`), bajo un nombre genérico.

## Estado actual (hecho)

- ✅ **POC validado** (en `main`): `ISOBootDetector` (clasifica windows / hybridRaw /
  elToritoOnly / notBootable leyendo MBR + El Torito) y `RawImageWriter` (mecánica
  `dd` a archivo). 16 tests.
- ✅ **Capa privilegiada** (en esta rama): `HelperProtocol.writeImage` + canal inverso
  `HelperProgressProtocol`; `HelperService.rawWrite` (mismas salvaguardas S-4,
  `unmountDisk`, `/dev/rdiskN` alineado, `F_FULLFSYNC`, eject); XPC bidireccional;
  `HelperClient.writeImage(onProgress:)`. Compila, 87 tests verdes.

## Tarea 0 — Rebranding ✅ HECHO

Nombre nuevo: **UsbFromMac** (display "USB from Mac", módulo/targets `UsbFromMac*`,
bundle `com.omarhernandez.usbfrommac`). Repo renombrado `IsoFromMac` → `usbfrommac`.
Aplicado en las 3 capas (cosmética, módulo/targets, bundle/XPC); `xcodegen` + build +
87 tests verdes. **Pendiente solo en hardware:** tras `dogfood.sh`, `sudo killall
UsbFromMacHelper` y re-aprobar el servicio en Ajustes → Elementos de inicio (el
SMAppService cambió de identificador → es un servicio nuevo a ojos del sistema).

Orden seguro (3 capas, de menor a mayor riesgo):

1. **Capa C (cosmética):** `CFBundleName`/`CFBundleDisplayName` → "USB from Mac" en
   `Info.plist`; textos en README, CONTRIBUTING, SECURITY, docs, comentarios. Sin
   riesgo técnico.
2. **Capa B (módulo/targets):** renombrar targets en `project.yml`
   (`UsbFromMac*` → `UsbFromMac*`), `UsbFromMacApp.swift` → `UsbFromMacApp.swift`,
   `@testable import UsbFromMac` → `import UsbFromMac` en los 12 tests, scripts
   (`dogfood.sh`, `build-notarize.sh`), `ci.yml`. `xcodegen generate` + test.
3. **Capa A (bundle/XPC — coordinado):** cambiar `com.omarhernandez.usbfrommac` →
   `com.omarhernandez.usbfrommac` en `project.yml` (prefix + PRODUCT_BUNDLE_IDENTIFIER),
   `HelperProtocol` (`machServiceName`, `appBundleID`, `helperBundleID`, requisitos de
   firma), renombrar el `.plist` del daemon (archivo `com.omarhernandez.usbfrommac.helper.plist`
   + key del label), `dogfood.sh` (`--identifier`). Tras esto:
   `sudo killall UsbFromMacHelper` y re-aprobar en Ajustes → Elementos de inicio
   (el SMAppService es un servicio nuevo a ojos del sistema). Verificar end-to-end en
   hardware (formateo Windows) antes de seguir.

Criterio de aceptación: build + 87 tests verdes; un USB Windows se sigue creando
end-to-end con el nuevo bundle ID.

## Tarea 1 — Cablear el detector

- `ISOService.inspect` calcula `ISOBootDetector.detect(isoAt:isWindows:)` y lo expone
  en `ISOInfo.bootType: ISOBootType`.
- `ISOInfo`: añadir `bootType`; derivar `canBuild` = `bootType.isSupportable`.
- Tests: `ISOServiceTests` cubre que un ISO Windows → `.windows`.

## Tarea 2 — Ramificar `BuildCoordinator.runBuild`

- `switch info.bootType`:
  - `.windows` → camino actual (formatear FAT32 + copiar + split).
  - `.hybridRaw` → NO formatear/etiqueta/split: `helper.writeImage(isoPath:bsdName:onProgress:)`
    con fase de progreso real (bytes), luego eject. Revalidación JIT (S-3) igual.
  - `.elToritoOnly` / `.notBootable` → abortar con `BuildError` claro (no producir USB roto).
- Nueva `BuildPhase.writingImage` (peso ~0.95) con su título.
- El progreso del raw llega por `onProgress(written,total)` → `setProgress(.writingImage, …, bytes…)`.

## Tarea 3 — UI

- Paso 1 (ISOPicker): mostrar el tipo detectado ("Instalador de Windows" /
  "ISO de Linux (se escribirá completa)" / "No booteable"). Deshabilitar Continuar
  si `!isSupportable`.
- Paso 3 (Confirm): para `.hybridRaw`, ocultar el campo de etiqueta FAT32 (no aplica)
  y ajustar el texto ("se sobrescribirá el disco con la imagen").
- Paso 4 (Progress): la fase `writingImage` usa la barra de bytes ya existente.

## Tarea 4 — i18n

Nuevas claves EN/ES: tipo de ISO (windows/linux/no-booteable), fase "Escribir imagen",
textos de confirmación para raw. Mantener el patrón de `Localizable.xcstrings`.

## Tarea 5 — Validación real (BLOQUEANTE antes de merge)

- Correr `ISOBootDetector.detect` contra ISOs reales: Windows 11, Ubuntu, Fedora,
  Debian (confirmar clasificación correcta).
- Dogfooding en hardware: crear un USB Ubuntu booteable y arrancar una máquina real.
- Conservador: si el detector duda, NO ofrecer raw (mejor rechazar que USB roto).

## Tarea 6 — Docs + cierre

- README: features "Windows **y** Linux", actualizar nombre/tagline.
- Actualizar `docs/DOGFOODING.md` con el flujo raw.
- PR `feature/linux-iso-support` → `main`.

## Riesgos

- **Bundle ID (Tarea 0.A):** romper la comunicación con el helper si no se re-aprueba.
- **Detector (Tarea 5):** un ISO mal clasificado = USB que no arranca. Mitigar con
  validación real y rechazo conservador.
- **Escritura raw:** alineación de bloque y `F_FULLFSYNC` ya cubiertos; validar
  velocidad/parcial-last-block en hardware.
