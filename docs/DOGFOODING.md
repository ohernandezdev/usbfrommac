# Dogfooding — hallazgos y fixes (sesión inicial)

Notas de la primera prueba en hardware real de **WinUSB Mac**, creando un USB
booteable de Windows 11 (ISO `Win11_25H2_Spanish_x64_v2.iso`) sobre un pendrive
Lexar de 62 GB.

**Entorno:** macOS 15.7.7 (Sequoia) · Apple Silicon · firma **Developer ID
Application** (Team `C34D3V8484`). La prueba se hizo con `scripts/dogfood.sh`
(build firmado local, sin notarizar — válido solo en esta máquina).

La app terminó creando el USB **de principio a fin sin intervención**
(Formatear → Copiar → Dividir → Finalizar → expulsar). El dogfooding sacó 5 bugs
reales que solo aparecen ejecutando contra un USB físico.

---

## Bugs encontrados y resueltos

### 1. La app se colgaba en "Formatear" (reply XPC perdido)
- **Síntoma:** la barra se quedaba en "Formateando…" para siempre, aunque el
  disco SÍ quedaba formateado (`diskutil list` mostraba el volumen `WIN11`).
- **Causa raíz:** el helper root es un daemon *on-demand*; tras ejecutar
  `diskutil eraseDisk` y responder, launchd lo apaga al quedar idle, y el reply
  del XPC se pierde por timing. La app esperaba ese reply con un
  `DispatchSemaphore` **sin timeout** → cuelgue permanente.
- **Fix (defensa en profundidad):**
  - `BuildCoordinator.formatAndAwaitVolume`: **verificación por efecto** — avanza
    en cuanto aparece `/Volumes/<label>` (~0,4 s), sin depender del reply. Para
    una operación destructiva, confirmar el estado real del disco es el criterio
    de éxito correcto (no es un *fallback* que oculta el problema).
  - Timeout de 180 s como backstop (`BuildError.eraseTimedOut`).
  - `HelperClient`: la conexión XPC resuelve por **todos** los caminos (reply,
    error de envío, interrupción, invalidación) → nunca se cuelga a nivel XPC.
  - Política documentada y testeada en `EraseDecision` (`Tests/BuildFlowTests`).

### 2. "Couldn't communicate with a helper application"
- **Síntoma:** tras aprobar el daemon, la conexión XPC se invalidaba al instante.
- **Causa raíz:** un target *tool* sin `Info.plist` se firma con el **nombre del
  ejecutable** como identifier (`WinUSBMacHelper`), pero el requisito de firma
  cruzada exigía `identifier "com.omar.winusbmac.helper"`. No coincidían.
  Verificado con `codesign -dvvv`.
- **Fix:** `scripts/dogfood.sh` re-firma el helper con
  `--identifier com.omar.winusbmac.helper`.
- **Nota:** al re-firmar, hay que **matar el daemon viejo** (`sudo killall
  WinUSBMacHelper`) o launchd sigue ejecutando el binario anterior en memoria.

### 3. Mensaje de error crudo en el primer arranque
- **Síntoma:** "No se pudo registrar el componente con privilegios: Operation
  not permitted" — asusta, pero es el flujo NORMAL de aprobación.
- **Fix:** `HelperClient.registerIfNeeded` detecta el estado `.requiresApproval`
  y muestra la guía amable ("Autoriza en Ajustes → Elementos de inicio").

### 4. Imágenes de disco aparecían como "USBs"
- **Síntoma:** simuladores de iOS, cryptexes, `.dmg` montados se ofrecían como
  destino (son `external` + `removable` pero `Protocol: Disk Image`, `Virtual`).
- **Fix:** `DiskFilter` excluye candidatos con `busProtocol == "Disk Image"`.
  Test: `DiskFilterTests.testMountedDiskImageIsExcluded`.

### 6. El volumen formateado quedaba SIN montar (causa raíz más profunda)
- **Síntoma:** con el build "anti-cuelgue", la app daba "El formateo tardó
  demasiado en responder" (timeout) aunque `diskutil list` mostraba el disco ya
  formateado como `WIN11` FAT32. `diskutil info diskNs2` → `Mounted: No`.
- **Causa raíz:** un **daemon root no hereda la sesión de auto-montaje de
  DiskArbitration del usuario**. Por eso `diskutil eraseDisk` ejecutado por el
  helper crea el volumen pero **no lo monta** en `/Volumes/<label>`. La
  verificación por efecto sondeaba `/Volumes/<label>`, que nunca aparecía → timeout.
- **Fix:** `BuildCoordinator.formatAndAwaitVolume` detecta la partición de datos
  (`diskNs2`) ya formateada como FAT32 con la etiqueta (`isFormatted`, vía
  `diskutil info -plist`) y la **monta explícitamente** (`diskutil mount diskNs2`)
  antes de continuar. Independiente del reply XPC y del auto-montaje.
- **Lección:** tras una operación de disco en un daemon root, NO asumas
  auto-montaje; monta tú el resultado.

### 5. Volumen viejo con la misma etiqueta
- **Riesgo:** si ya había un `/Volumes/<label>` montado, la verificación por
  efecto podía confundirlo con el recién formateado.
- **Fix:** `BuildCoordinator` desmonta cualquier `/Volumes/<label>` previo antes
  de formatear.

---

## Cómo se hizo el USB la primera vez (flujo manual de referencia)

Cuando la app aún se colgaba, el formateo (único paso root) ya había ocurrido, y
el resto (usuario) se completó a mano — exactamente el método que la app replica:

```bash
SRC=/Volumes/CCCOMA_X64FRE_ES-ES_DV9   # ISO montado
DST=/Volumes/WIN11                     # USB formateado FAT32/GPT
rsync -rt --exclude='sources/install.wim' "$SRC/" "$DST/"
/opt/homebrew/bin/wimlib-imagex split "$SRC/sources/install.wim" "$DST/sources/install.swm" 3800
diskutil eject /dev/disk11
```

`install.wim` (7,0 GB) se dividió en `install.swm` (3,2) + `install2.swm` (3,7) +
`install3.swm` (93 MB) — Windows Setup los reensambla solo.

---

## Pendiente (opcional, no bloquea el uso)

- **Notarización** para distribuir a otros Macs: `scripts/build-notarize.sh`.
  Sin notarizar, el build solo es válido en esta máquina (sin cuarentena).
- **LICENSE GPLv3** (texto canónico de gnu.org) — wimlib es GPLv3 y la app es
  open source.
