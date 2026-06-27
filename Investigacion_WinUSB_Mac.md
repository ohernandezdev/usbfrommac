# Investigación: USB booteable de Windows 11 desde macOS (verificado)

**Fecha:** 2026-06-27
**Objetivo:** que el USB final arranque perfecto en una PC moderna con UEFI, validando cada paso contra fuentes autoritativas (Microsoft, proyecto Rufus/pbatard, Arch Wiki, wimlib).

---

## TL;DR — el método correcto para Mac

En macOS el camino confiable es **FAT32 + dividir `install.wim` con wimlib**. No intentes el método NTFS de Rufus: macOS no escribe NTFS de forma nativa ni estable, así que ese enfoque no es práctico en Mac. FAT32 sí es escribible nativamente y es lo que el firmware UEFI siempre sabe leer.

Tres cosas que tienen que estar bien para que arranque perfecto:

1. **El archivo:** `install.wim` pesa >4 GB y FAT32 no admite archivos de más de 4 GB → hay que dividirlo en `.swm`. Windows Setup los reensambla solo.
2. **El arranque:** USB en FAT32, con la ruta `\EFI\BOOT\BOOTX64.EFI` (ya viene en el ISO oficial). El esquema GPT o MBR del USB da igual para UEFI.
3. **La BIOS de la PC destino:** modo UEFI, CSM/Legacy desactivado, Fast Boot desactivado.

---

## 1. El problema del `install.wim` y la división (verificado)

- **FAT32 tiene un límite duro de 4 GB por archivo**, y FAT32 es lo que el firmware UEFI lee con garantía. El `install.wim` de Windows 11 24H2/25H2 supera los 4 GB (medido ~5 GB en 24H2; en 25H2 varía según la edición del ISO, pero siempre >4 GB). Por eso no se puede copiar tal cual. *(Microsoft Learn; The Windows Club; MiniTool)*

- **Solución oficial:** dividir en `.swm`. Microsoft lo hace con `Dism /Split-Image`; en Mac el equivalente es **wimlib** (`wimlib-imagex split`). *(Microsoft Learn; wimlib man page)*

- **Tamaño del fragmento (`PART_SIZE`):** se interpreta en **mebibytes (MiB)** y es un **objetivo, no un tope duro** — un recurso individual no se puede partir entre fragmentos, así que un `.swm` puede superar ligeramente el valor pedido. `4096 MiB = exactamente 4 GiB`, que es justo el techo de FAT32 → **arriesgado**. Por eso se recomienda **3800** (o como mucho 4000) para dejar margen y que ningún fragmento cruce los 4 GB. *(wimlib LIMITATIONS; Arch man page)*

- **Convención de nombres obligatoria:** `install.swm`, `install2.swm`, `install3.swm`… El primero **debe** llamarse `install.swm`. *(Microsoft Learn)*

- **CRÍTICO — reensamblado automático:** Windows Setup **detecta y reúne los `.swm` solo, sin ninguna acción del usuario**, siempre que todos estén en la misma carpeta `sources` del USB. Microsoft: *"copy the set of .swm files into the Sources folder… and then run Windows Setup."* Sin flags, sin merge manual. *(Microsoft Learn; Arch Wiki)*

- **wimlib en Mac:** `brew install wimlib`. En Apple Silicon usa el Homebrew nativo arm64 (`/opt/homebrew`); wimlib compila nativo para arm64, no necesita Rosetta. *(Homebrew Formulae)*

- **Alternativa sin dividir:** un ISO basado en `install.esd` (más comprimido, suele quedar bajo 4 GB) copia directo a FAT32. Tradeoff: el ESD es de solo lectura/altamente comprimido. *(The Windows Club; Eleven Forum)*

## 2. Esquema de partición y formato (verificado)

- **Para el disco destino** donde se instala Windows: **GPT obligatorio** en UEFI. *(Microsoft Learn)*
- **Para el USB en sí:** el esquema (GPT o MBR) **no es determinante** — el firmware UEFI escanea la partición FAT sin importar el esquema. Tu comando con `GPT` está bien; `MBR` también funcionaría (algunas guías de Mac lo prefieren por compatibilidad amplia). *(diskutil man; pbatard)*
- **Formato:** debe ser **FAT (FAT32 en la práctica)**. El firmware UEFI solo lee FAT con garantía; exFAT y NTFS no arrancan en firmware estándar sin un driver/shim. *(UEFI Spec; Easy2Boot; pbatard/uefi-ntfs)*
- **Ruta de arranque removible:** `\EFI\BOOT\BOOTX64.EFI` debe existir; **el ISO oficial de Windows 11 x64 ya la incluye**, así que copiar los archivos a un USB FAT32 ya lo hace booteable sin inyectar nada. *(UEFI Spec; Eleven Forum)*
- **El comando `diskutil eraseDisk MS-DOS "WIN11" GPT /dev/diskN` es correcto:** produce un layout FAT32 booteable por UEFI. `MS-DOS` selecciona FAT32 automáticamente para 16–32 GB. **Cuidado:** la etiqueta FAT32 admite máximo **11 caracteres** ("WIN11" está bien). Es **necesario pero no suficiente** — no resuelve el problema del `install.wim`, eso lo hace wimlib aparte. *(diskutil man; Medium guía macOS 2025)*
- Para un USB de 16–32 GB **no hay** problema de tamaño de volumen ni de clúster; el único límite real de FAT32 aquí es el de 4 GB por archivo.

## 3. Secure Boot y TPM 2.0 (verificado — hay un punto nuevo importante de 2026)

- **Requisitos oficiales de Windows 11 (24H2 = 25H2, idénticos):** TPM 2.0, firmware UEFI "Secure Boot capable", CPU de 64 bits en la lista aprobada (Intel 8.ª gen+, AMD Zen 2/Ryzen 2000+), 4 GB RAM, 64 GB almacenamiento. *(Microsoft Support; pureinfotech)*

- **"Secure Boot capable" ≠ "Secure Boot activado".** Microsoft solo exige *capacidad* para la verificación de requisitos. Pero para **arrancar** una PC con Secure Boot activado, el bootloader del USB debe estar firmado por un certificado Microsoft de confianza. *(Microsoft Support; Rufus FAQ)*

- **Un USB hecho a mano copiando el ISO oficial SÍ arranca con Secure Boot activado**, porque los archivos de arranque de Windows (`bootmgfw.efi`/`bootx64.efi`) están firmados por Microsoft y copiarlos conserva la firma. *(Microsoft Support; Eleven Forum)*

- **⚠️ NOVEDAD 2026 (importante):** el certificado de Secure Boot **"PCA 2011"** de Microsoft está siendo **revocado** a medida que expira en 2026. ISOs antiguos cuyo `bootmgfw.efi` solo esté firmado con el cert de 2011 **pueden fallar al arrancar** con Secure Boot en firmware que ya aplicó la revocación (actualización DBX) — aunque sean genuinamente de Microsoft. Solo los ISOs firmados con el nuevo **"Windows UEFI CA 2023"** arrancan con garantía. **Mitigación: usar un ISO reciente** — tu `Win11_25H2_..._v2.iso` es justo eso, así que estás cubierto. *(Microsoft Support; pbatard/rufus #2244)*

- **Bypass de TPM/Secure Boot (si la PC no cumple):** en la pantalla "This PC can't run Windows 11", `Shift+F10` → `regedit` → crear `HKLM\SYSTEM\Setup\LabConfig` con DWORD `BypassTPMCheck=1` y `BypassSecureBootCheck=1`. Solo afecta la *verificación de requisitos*, no el arranque del USB. Riesgo: Microsoft marca estos equipos como "no con derecho a actualizaciones" y la garantía no cubre daños. *(Tom's Hardware; Microsoft Support)*

## 4. ¿Vale la pena el enfoque NTFS+UEFI:NTFS de Rufus? (verificado)

- **Qué hace Rufus por defecto con `install.wim` >4 GB:** crea **dos particiones** — una NTFS grande con los archivos + una FAT diminuta al final con el bootloader **UEFI:NTFS**. **No** divide el WIM por defecto. *(pbatard/uefi-ntfs)*
- **UEFI:NTFS sí es compatible con Secure Boot** (firmado por Microsoft para x64/ARM64). El mito de que "rompe Secure Boot" es falso desde Rufus 3.17+. *(pbatard/uefi-ntfs)*
- **Pero en Mac no es práctico:** macOS **no escribe NTFS de forma nativa**; la vía libre (macFUSE + ntfs-3g) es frágil y está rota/no soportada en macOS reciente (Ventura+). Por eso **en Mac el enfoque FAT32 + wimlib es el correcto**. Si quisieras el resultado exacto de Rufus, lo más limpio es correr Rufus real en una VM de Windows (UTM/Parallels). *(How-To Geek; iBoysoft; pbatard)*

## 5. Errores comunes que arruinan el USB y cómo evitarlos (verificado)

**No arranca:**
- **Modo de arranque desajustado:** BIOS en Legacy/CSM con media UEFI/GPT (o viceversa). Fix: **modo UEFI** + **desactivar CSM/Legacy**. Es la causa #1 de "el USB aparece pero no arranca". *(Tom's Hardware)*
- **Fast Boot** impide enumerar el USB → desactivarlo; probar un puerto **USB 2.0**. *(varios)*
- Faltan los archivos EFI en una ubicación FAT legible (no pasa si copiaste el ISO completo a FAT32).

**Falla la instalación tras arrancar:**
- **`install.wim` no dividido / copia truncada** en FAT32 → dividir con wimlib (lo de arriba).
- **"No se encuentran controladores" / no aparece el disco:** suele ser el controlador de almacenamiento **Intel RST/VMD** en CPUs Intel nuevas → "Cargar controlador" (IRST). A veces indica ISO corrupto → re-descargar. *(pureinfotech; Microsoft)*
- **"No se pudo crear una nueva partición" / "no se puede instalar en este disco (GPT)":** borrar la partición destino, o `Shift+F10` → `diskpart` → `clean`; en EFI el disco debe ser GPT. *(EaseUS; PartitionWizard)*

## 6. Verificar el ISO y el tema del "v2" (verificado)

- **Verificar en Mac:** `shasum -a 256 /ruta/Win11_25H2_Spanish_x64_v2.iso` y comparar con el valor publicado por Microsoft. *(Microsoft Q&A)*
- **Fuente autoritativa del hash:** el SHA-256 que Microsoft muestra **en la propia página de descarga**, en la sección "Verify your download", para el archivo exacto que te ofreció en esa sesión. *(Microsoft Q&A)*
- **Por qué el "v2" tiene hash distinto:** Microsoft **refresca/re-publica los ISOs (v1 → v2)** con builds más nuevos / cumulative updates integrados; **cada versión tiene su propio SHA-256 único**, así que un hash distinto en un "v2" es **legítimo y esperado**, no señal de manipulación. Las listas viejas (de v1) no coinciden con un v2 aunque ambos sean genuinos. Por eso comparas contra el hash de la **misma** sesión de descarga, no contra una lista vieja. *(Microsoft Q&A; windowslatest; winhelponline)*
- Tu caso: lo bajaste de microsoft.com por HTTPS → es genuino; el desajuste con la tabla vieja se explica 100% por ser la revisión v2.

---

## 7. Método final validado (pasos para Terminal)

```bash
# 1. Verificar integridad (compara con el hash de la página de descarga de Microsoft)
shasum -a 256 ~/Downloads/Win11_25H2_Spanish_x64_v2.iso

# 2. Identificar el USB (¡verifica tamaño y que sea external!). USB de >=16 GB.
diskutil list

# 3. Formatear FAT32 / GPT (reemplaza diskN por el tuyo; etiqueta <=11 chars)
diskutil eraseDisk MS-DOS "WIN11" GPT /dev/diskN

# 4. Montar el ISO (o doble clic). Se monta en /Volumes/CCCOMA_...
hdiutil attach ~/Downloads/Win11_25H2_Spanish_x64_v2.iso

# 5. Copiar todo MENOS install.wim
rsync -avh --progress --exclude=sources/install.wim /Volumes/CCCOMA_*/ /Volumes/WIN11/

# 6. Dividir install.wim en .swm (3800 MiB = margen seguro bajo 4 GB)
brew install wimlib
wimlib-imagex split /Volumes/CCCOMA_*/sources/install.wim /Volumes/WIN11/sources/install.swm 3800

# 7. Expulsar de forma segura
hdiutil detach /Volumes/CCCOMA_*
diskutil eject /dev/diskN
```

**En la PC destino:** entra a la BIOS/UEFI → modo **UEFI**, **CSM/Legacy OFF**, **Fast Boot OFF**. Secure Boot puede quedar **ON** (tu ISO 25H2 v2 usa el cert 2023). Arranca desde el menú de boot (F12/F10/Esc/Supr según placa).

---

## Cambios vs. la guía inicial

- **Tamaño de split:** confirmado **3800** como valor seguro (el `PART_SIZE` es objetivo en MiB, no tope; 4096 es arriesgado).
- **GPT vs MBR del USB:** confirmado que **da igual** para UEFI; tu `GPT` está perfecto.
- **NTFS/Rufus:** descartado en Mac por falta de escritura NTFS nativa → FAT32+wimlib es lo correcto.
- **Nuevo:** alerta del **certificado Secure Boot 2011 revocado en 2026** → usar ISO reciente (ya lo tienes con el v2).
- **Nuevo:** BIOS — desactivar CSM y Fast Boot; ojo con driver Intel RST/VMD si no aparece el disco.

---

## Fuentes

- Microsoft Learn — Split a Windows image (.wim): https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/split-a-windows-image--wim--file-to-span-across-multiple-dvds
- Microsoft Learn — MBR vs GPT / UEFI partitions: https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-installing-using-the-mbr-or-gpt-partition-style
- Microsoft Support — Windows 11 system requirements: https://support.microsoft.com/en-us/windows/windows-11-system-requirements-86c11283-ea52-4782-9efd-7674389a7ba3
- Microsoft Support — Secure Boot certificate expiration / CA updates (2026): https://support.microsoft.com/en-us/topic/windows-secure-boot-certificate-expiration-and-ca-updates-7ff40d33-95dc-4c3c-8725-a9b95457578e
- Microsoft Support — Windows 11 on devices that don't meet requirements: https://support.microsoft.com/en-us/windows/windows-11-on-devices-that-don-t-meet-minimum-system-requirements-0b2dc4a2-5933-4ad4-9c09-ef0a331518f1
- wimlib man (split): https://www.systutorials.com/docs/linux/man/1-wimlib-imagex-split/
- Arch man — wimsplit: https://man.archlinux.org/man/wimsplit.1.en
- Homebrew — wimlib: https://formulae.brew.sh/formula/wimlib
- pbatard / uefi-ntfs (Rufus): https://github.com/pbatard/uefi-ntfs/blob/master/README.md
- Rufus FAQ: https://github.com/pbatard/rufus/wiki/FAQ
- Rufus issue #2244 (cert 2011 revocation): https://github.com/pbatard/rufus/issues/2244
- UEFI Spec 2.10 — Boot Manager: https://uefi.org/specs/UEFI/2.10/03_Boot_Manager.html
- diskutil man: https://ss64.com/mac/diskutil.html
- Guía macOS 2025 (diskutil + wimlib): https://ptuladhar3.medium.com/create-a-bootable-windows-usb-on-macos-in-2025-step-by-step-guide-94947d200c09
- windows-usb-installer-macos: https://github.com/DavidAGInnovation/windows-usb-installer-macos
- Tom's Hardware — bypass TPM: https://www.tomshardware.com/how-to/bypass-windows-11-tpm-requirement
- Microsoft Q&A — SHA256 de ISOs: https://learn.microsoft.com/en-us/answers/questions/3859049/where-to-get-sha256-hash-for-microsoft-iso-downloa
- winhelponline — checksums 25H2: https://www.winhelponline.com/blog/25h2-26200-6584-sha256-checksum/
- windowslatest — refresh mensual de ISOs 25H2: https://www.windowslatest.com/2026/04/01/download-windows-11-25h2-iso-offline-installer-and-always-save-a-copy/
- The Windows Club — install.wim too large: https://www.thewindowsclub.com/how-to-fix-windows-10-install-wim-file-too-large-for-usb-flash-drive
