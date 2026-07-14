> **Historical document.** This is the original product spec that kicked off the
> project, written before it was renamed to **Flint**. Kept for context on the
> original design rationale; superseded by [README.md](../README.md) for
> current architecture and features. Left in the original Spanish.

# PRD — "WinUSB Mac": Creador de USB booteable de Windows 11 desde macOS

**Versión:** 1.0
**Fecha:** 2026-06-27
**Autor:** Omar
**Estado:** Listo para handoff a Claude Code

---

## 1. Resumen

App nativa de macOS (Swift + SwiftUI) que crea una memoria USB booteable de
Windows 11 a partir de un archivo ISO oficial, replicando de forma segura y
guiada el proceso manual de Terminal (`diskutil` + `rsync` + división de
`install.wim` con wimlib). El objetivo es un "Rufus para Mac" minimalista,
seguro por diseño y enfocado en Windows 11.

---

## 2. Problema

En macOS no existe una herramienta gratuita, confiable y de confianza para crear
USBs booteables de Windows 11. El proceso manual funciona pero:

- Exige Terminal y conocimientos de `diskutil`, lo que es propenso a errores
  graves (borrar el disco equivocado).
- El `install.wim` de Windows 11 supera los 4 GB, rompiendo el límite de FAT32
  (requerido para arranque UEFI), lo que obliga a dividir el archivo con wimlib.
- Las apps de terceros existentes son escasas, de pago o de origen dudoso.

## 3. Objetivo

Que un usuario sin conocimientos de Terminal cree un USB booteable de Windows 11
en pocos clics, **sin riesgo de borrar un disco que no sea el USB seleccionado**.

## 4. Usuarios objetivo

- Usuarios de Mac que arman/reparan PCs y necesitan instalar Windows 11.
- Técnicos y entusiastas que hoy usan el método manual de Terminal.

---

## 5. Alcance

### Dentro de v1
- Selección de un ISO local de Windows 11 (file picker).
- Verificación opcional del SHA-256 del ISO contra un valor pegado por el usuario.
- Enumeración **en vivo** de discos USB externos (nunca internos).
- Formateo del USB (FAT32 / esquema GPT) con confirmación explícita.
- Montaje del ISO, copia de archivos y división automática de `install.wim`.
- Barra de progreso por fases y reporte de errores claro.
- Expulsión segura del USB al terminar.

### Fuera de v1 (roadmap)
- Descarga del ISO dentro de la app.
- Esquema de doble partición FAT32 + NTFS con bootloader UEFI:NTFS (evita dividir
  el `.wim`).
- Soporte para Windows 10 y otras distribuciones (Linux ISOs).
- Localización multi-idioma de la UI.

---

## 6. Flujo de usuario (happy path)

1. El usuario abre la app y arrastra/selecciona el ISO de Windows 11.
2. (Opcional) Pega el SHA-256 oficial; la app calcula y compara.
3. La app lista los USBs conectados con nombre, tamaño y modelo. El usuario
   elige uno.
4. La app muestra una advertencia inequívoca: "Se borrará TODO en `<nombre>`
   (`<tamaño>`)". El usuario confirma escribiendo o con un toggle de seguridad.
5. La app pide autorización de administrador (una sola vez) para el formateo.
6. Progreso por fases: Formatear → Copiar archivos → Dividir install.wim →
   Finalizar.
7. Mensaje de éxito + expulsión segura. Instrucciones de arranque (F12/F2/Supr).

---

## 7. Requisitos funcionales

- **RF-1** Listar únicamente discos `external` y `physical`; jamás el disco
  interno ni el disco de arranque. Refrescar en vivo al conectar/desconectar.
- **RF-2** Mostrar por cada disco: nombre de volumen, tamaño, modelo/identificador
  (p. ej. `disk4`), y si es removible.
- **RF-3** Validar que el USB tenga ≥ 16 GB; advertir si es menor a 8 GB.
- **RF-4** Verificación SHA-256 opcional con resultado visual (coincide / no
  coincide) — sin bloquear, solo informar.
- **RF-5** Formatear: `diskutil eraseDisk MS-DOS "<label>" GPT /dev/diskN`.
- **RF-6** Montar ISO con `hdiutil attach -nobrowse`.
- **RF-7** Copiar todo el contenido del ISO al USB **excepto** `sources/install.wim`.
- **RF-8** Dividir `install.wim` en `.swm` de ≤ 3800 MB con wimlib en
  `sources/`.
- **RF-9** Desmontar ISO y expulsar USB al finalizar (`diskutil eject`).
- **RF-10** Reporte de progreso granular y manejo de cancelación segura.

---

## 8. Arquitectura técnica

### 8.1 Componentes

- **UI (SwiftUI):** vistas de selección de ISO, lista de discos, confirmación,
  progreso.
- **DiskService:** enumeración de discos vía el framework **DiskArbitration**
  (preferido) o parseando `diskutil list -plist`. Filtra removibles/externos.
- **Privileged Helper (XPC):** herramienta separada instalada con
  **`SMAppService`** (macOS 13+). Ejecuta SOLO las operaciones que requieren root:
  el `diskutil eraseDisk`. El resto corre como usuario.
- **CopyService:** copia de archivos (FileManager o `rsync` empaquetado/sistema)
  con exclusión de `install.wim` y reporte de progreso.
- **WimService:** división de `install.wim` usando **wimlib** (ver §10).

### 8.2 Modelo de privilegios

- Montar el ISO (`hdiutil`) → **no requiere root**.
- Copiar al volumen ya montado y escribible → **no requiere root**.
- Dividir el `.wim` en el volumen montado → **no requiere root**.
- Formatear el disco (`diskutil eraseDisk`) → **requiere root** → único trabajo
  del privileged helper. Comunicación app↔helper por XPC. Instalación/registro
  con `SMAppService.daemon`.
- **No** usar `AuthorizationExecuteWithPrivileges` (deprecado e inseguro).

### 8.3 Distribución

- App **notarizada por Apple, distribuida fuera del Mac App Store**. El sandbox
  del App Store impide el acceso a disco crudo necesario para formatear, así que
  la distribución directa (Developer ID + notarización) es la única vía viable.

---

## 9. Seguridad y salvaguardas (críticas — no recortar)

- **S-1** Lista blanca de discos: solo `external` + `physical`. El disco de
  arranque y cualquier interno se excluyen a nivel de código, no solo de UI.
- **S-2** Confirmación destructiva explícita mostrando nombre y tamaño exactos
  del disco; idealmente exigir una acción deliberada (toggle "Entiendo que se
  borrará" o escribir el nombre del volumen).
- **S-3** Re-validar el identificador del disco **justo antes** de formatear
  (puede haber cambiado tras reconexión).
- **S-4** El privileged helper valida que el target sea removible/externo antes
  de ejecutar `eraseDisk`; nunca confía ciegamente en el argumento recibido.
- **S-5** Manejo de errores sin pérdida de datos: cualquier fallo aborta y deja
  el estado claro; nunca un formateo "a medias" silencioso.
- **S-6** Verificación de integridad del ISO opcional pero visible (SHA-256).
- **S-7** Recomendar/validar que el ISO sea reciente: por la **revocación del
  certificado Secure Boot "PCA 2011" en 2026**, los ISOs antiguos pueden no
  arrancar con Secure Boot activado. Solo los firmados con "Windows UEFI CA 2023"
  arrancan con garantía. La app puede advertir si detecta un ISO viejo.
  *(verificado: Microsoft Support; pbatard/rufus #2244)*

---

## 10. Dependencia clave: wimlib

- `install.wim` > 4 GB no cabe en FAT32. Solución estándar: dividir en `.swm`
  con **wimlib** (`wimlib-imagex split ... 3800`). Windows Setup reensambla los
  `.swm` automáticamente, sin acción del usuario, si están todos en `sources/`.
  *(verificado: Microsoft Learn)*
- **Tamaño del fragmento:** `PART_SIZE` está en **MiB** y es un **objetivo, no un
  tope duro** (un recurso individual no se parte entre fragmentos). `4096 MiB =
  4 GiB` = techo de FAT32, así que es arriesgado. Usar **3800** (máx. 4000) para
  dejar margen. *(verificado: wimlib LIMITATIONS)*
- **Opciones de integración:**
  1. Enlazar `libwim` (C) desde Swift vía un bridging header.
  2. Empaquetar y firmar el binario `wimlib-imagex` y ejecutarlo como subproceso.
- **Licencia:** wimlib es **GPLv3**. Si la app es de código cerrado, la vía más
  limpia es empaquetar el binario y ejecutarlo como proceso separado (mera
  agregación) o, mejor, **liberar la app como open source**. Decidir antes de
  implementar. *(Decisión pendiente del owner.)*
- **Alternativa futura (sin wimlib):** doble partición FAT32 (boot) + NTFS
  (install.wim) con bootloader UEFI:NTFS estilo Rufus. Más complejo; fuera de v1.

---

## 11. Casos borde y errores

- ISO seleccionado que no es de Windows / corrupto / no montable.
- USB con fallos de escritura o protegido contra escritura.
- USB demasiado pequeño.
- Usuario cancela a mitad de proceso → abortar limpio, desmontar ISO.
- Desconexión del USB durante el proceso → abortar con mensaje claro.
- Falta de espacio durante la copia o la división.
- Autorización de administrador denegada.

---

## 12. Stack y estructura sugerida

- **Lenguaje/UI:** Swift 5.9+, SwiftUI, macOS 13+ (por `SMAppService`).
- **Frameworks:** DiskArbitration, ServiceManagement, Foundation.
- **Build:** Xcode project + (opcional) un target para el privileged helper.

```
WinUSBMac/
├── WinUSBMac/                 # App principal (SwiftUI)
│   ├── App.swift
│   ├── Views/                 # ISOPickerView, DiskListView, ConfirmView, ProgressView
│   ├── Services/
│   │   ├── DiskService.swift          # DiskArbitration / diskutil -plist
│   │   ├── ISOService.swift           # hdiutil attach/detach, SHA-256
│   │   ├── CopyService.swift          # copia con exclusión + progreso
│   │   ├── WimService.swift           # división install.wim (wimlib)
│   │   └── HelperClient.swift         # XPC hacia el privileged helper
│   ├── Models/                # Disk, ISOInfo, BuildPhase, BuildProgress
│   └── Resources/             # binarios empaquetados (wimlib-imagex) si aplica
├── PrivilegedHelper/          # Daemon root: SOLO eraseDisk vía XPC
│   ├── main.swift
│   └── HelperProtocol.swift
└── Tests/
```

---

## 13. Criterios de aceptación

- **CA-1** La app nunca lista ni permite seleccionar el disco interno/arranque.
- **CA-2** Un USB creado arranca el instalador de Windows 11 en una PC UEFI real.
- **CA-3** El SHA-256 calculado coincide con `shasum -a 256` del mismo archivo.
- **CA-4** Cancelar a mitad deja el sistema sin daños y el ISO desmontado.
- **CA-5** El formateo solo ocurre tras confirmación explícita del usuario.
- **CA-6** Pruebas unitarias para DiskService (filtrado de discos) y la lógica de
  cálculo de tamaño de split.

---

## 14. Roadmap futuro

- Descarga del ISO oficial dentro de la app.
- Doble partición FAT32+NTFS (eliminar dependencia de wimlib).
- Soporte Windows 10 y Linux ISOs (modo `dd`).
- Persistencia de últimas selecciones y verificación automática de hash desde
  una lista oficial.

---

## 15. Prompt de handoff para Claude Code

> Copia y pega esto como primer mensaje en Claude Code, en una carpeta vacía.

```
Quiero que construyas una app nativa de macOS en Swift + SwiftUI llamada
"WinUSB Mac": un creador de USB booteable de Windows 11 desde macOS (un "Rufus
para Mac" enfocado en Win11). Objetivo: replicar de forma SEGURA y guiada el
proceso manual de Terminal (diskutil + rsync + división de install.wim con
wimlib) para que un usuario sin conocimientos técnicos cree el USB en pocos
clics, sin riesgo de borrar el disco equivocado.

Requisitos técnicos clave:
- Swift 5.9+, SwiftUI, target mínimo macOS 13.
- Enumerar SOLO discos externos/removibles usando DiskArbitration; NUNCA listar
  ni permitir el disco interno o de arranque (lista blanca a nivel de código).
- El formateo (diskutil eraseDisk MS-DOS "<label>" GPT /dev/diskN) requiere root:
  impleméntalo en un privileged helper separado, registrado con SMAppService y
  comunicado por XPC. No uses AuthorizationExecuteWithPrivileges. Todo lo demás
  (hdiutil attach del ISO, copia de archivos, división del .wim) corre como
  usuario sobre el volumen ya montado.
- install.wim supera 4 GB y FAT32 no lo admite: copia todo el ISO al USB EXCEPTO
  sources/install.wim, y divide install.wim en .swm de <= 3800 MB con wimlib
  (empaqueta y firma el binario wimlib-imagex y ejecútalo como subproceso, o
  enlaza libwim). wimlib es GPLv3: tenlo en cuenta.
- Verificación SHA-256 del ISO opcional (el usuario pega el valor oficial).
- Flujo: seleccionar ISO -> (opcional verificar hash) -> elegir USB -> confirmación
  destructiva explícita con nombre y tamaño -> autorización admin -> progreso por
  fases (Formatear, Copiar, Dividir, Finalizar) -> expulsión segura.

Salvaguardas obligatorias (no las recortes):
- Re-validar el identificador del disco justo antes de formatear.
- El helper valida que el target sea removible/externo antes de ejecutar eraseDisk.
- Confirmación destructiva con acción deliberada del usuario.
- Manejo de errores sin formateos a medias; cancelar deja todo limpio y el ISO
  desmontado.

Estructura sugerida: app principal (Views, Services: DiskService, ISOService,
CopyService, WimService, HelperClient; Models), target PrivilegedHelper, Tests.

Empieza proponiendo el plan de implementación y la estructura de archivos del
proyecto Xcode antes de escribir código. Luego implementa por fases, empezando
por DiskService con pruebas unitarias del filtrado de discos.
```
