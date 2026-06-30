# Dogfooding — findings and fixes

## Windows flow (validated on real hardware)

Notes from the first real-hardware test of **USB from Mac**, creating a bootable
Windows 11 USB (ISO `Win11_25H2_Spanish_x64_v2.iso`) on a 62 GB Lexar stick.

**Environment:** macOS 15.7.7 (Sequoia) · Apple Silicon · **Developer ID
Application** signing (Team `C34D3V8484`). The test used `scripts/dogfood.sh`
(local signed build, un-notarized — valid only on this machine).

The app ended up creating the USB **end to end with no intervention**
(Format → Copy → Split → Finish → eject), and a real Windows install was
completed from it. Dogfooding surfaced 5 real bugs that only appear when running
against a physical USB.

---

### Bugs found and fixed

#### 1. The app hung at "Format" (lost XPC reply)
- **Symptom:** the bar stayed at "Formatting…" forever, even though the disk
  *was* formatted (`diskutil list` showed the `WIN11` volume).
- **Root cause:** the root helper is an *on-demand* daemon; after running
  `diskutil eraseDisk` and replying, launchd shuts it down once idle and the XPC
  reply is lost to timing. The app waited for that reply with a timeout-less
  `DispatchSemaphore` → permanent hang.
- **Fix (defense in depth):**
  - `BuildCoordinator.formatAndAwaitVolume`: **verification by effect** — it
    advances as soon as `/Volumes/<label>` appears (~0.4 s), without depending on
    the reply. For a destructive operation, confirming the disk's real state is
    the correct success criterion (this is not a *fallback* that hides the bug).
  - 180 s timeout as a backstop (`BuildError.eraseTimedOut`).
  - `HelperClient`: the XPC connection resolves through **every** path (reply,
    send error, interruption, invalidation) → it never hangs at the XPC level.
  - Policy documented and tested in `EraseDecision` (`Tests/BuildFlowTests`).

#### 2. "Couldn't communicate with a helper application"
- **Symptom:** after approving the daemon, the XPC connection invalidated instantly.
- **Root cause:** a *tool* target with no `Info.plist` is signed with the
  **executable name** as its identifier (`UsbFromMacHelper`), but the cross-signing
  requirement demanded `identifier "com.omarhernandez.usbfrommac.helper"`. They
  didn't match. Verified with `codesign -dvvv`.
- **Fix:** `scripts/dogfood.sh` re-signs the helper with
  `--identifier com.omarhernandez.usbfrommac.helper`.
- **Note:** when re-signing you must **kill the old daemon** (`sudo killall
  UsbFromMacHelper`) or launchd keeps running the previous binary in memory.

#### 3. Raw error message on first launch
- **Symptom:** "Couldn't register the privileged component: Operation not
  permitted" — scary, but it is the NORMAL approval flow.
- **Fix:** `HelperClient.registerIfNeeded` detects the `.requiresApproval` state
  and shows friendly guidance ("Approve it in Settings → Login Items").

#### 4. Disk images showed up as "USBs"
- **Symptom:** iOS simulators, cryptexes and mounted `.dmg`s were offered as a
  target (they are `external` + `removable` but `Protocol: Disk Image`, `Virtual`).
- **Fix:** `DiskFilter` excludes candidates with `busProtocol == "Disk Image"`.
  Test: `DiskFilterTests.testMountedDiskImageIsExcluded`.

#### 6. The formatted volume was left UNMOUNTED (deeper root cause)
- **Symptom:** with the "anti-hang" build, the app reported "Formatting took too
  long to respond" (timeout) even though `diskutil list` showed the disk already
  formatted as `WIN11` FAT32. `diskutil info diskNs2` → `Mounted: No`.
- **Root cause:** a **root daemon doesn't inherit the user's DiskArbitration
  auto-mount session**. So `diskutil eraseDisk` run by the helper creates the
  volume but **doesn't mount it** at `/Volumes/<label>`. Verification by effect
  was polling `/Volumes/<label>`, which never appeared → timeout.
- **Fix:** `BuildCoordinator.formatAndAwaitVolume` detects the data partition
  (`diskNs2`) already formatted as FAT32 with the label (`isFormatted`, via
  `diskutil info -plist`) and **mounts it explicitly** (`diskutil mount diskNs2`)
  before continuing. Independent of the XPC reply and of auto-mount.
- **Lesson:** after a disk operation in a root daemon, do NOT assume auto-mount;
  mount the result yourself.

#### 5. Stale volume with the same label
- **Risk:** if a `/Volumes/<label>` was already mounted, verification by effect
  could mistake it for the freshly formatted one.
- **Fix:** `BuildCoordinator` unmounts any prior `/Volumes/<label>` before formatting.

---

### How the USB was made the first time (manual reference flow)

While the app still hung, the format (the only root step) had already happened,
and the rest (user-level) was completed by hand — exactly the method the app
replicates:

```bash
SRC=/Volumes/CCCOMA_X64FRE_ES-ES_DV9   # mounted ISO
DST=/Volumes/WIN11                     # USB formatted FAT32/GPT
rsync -rt --exclude='sources/install.wim' "$SRC/" "$DST/"
/opt/homebrew/bin/wimlib-imagex split "$SRC/sources/install.wim" "$DST/sources/install.swm" 3800
diskutil eject /dev/disk11
```

`install.wim` (7.0 GB) was split into `install.swm` (3.2) + `install2.swm` (3.7) +
`install3.swm` (93 MB) — Windows Setup reassembles them by itself.

---

## Linux raw flow (pending hardware dogfooding — A1)

The Linux path writes the ISO **raw** (`dd`-style) to `/dev/rdiskN` from the root
helper. The detector is validated against a real `ubuntu-26.04-desktop-amd64.iso`
(classified `hybridRaw`), and the full pipeline compiles with green tests — but
the raw write has **never run on real hardware yet**. Until a real machine has
booted from a stick this app produced, the Linux flow is not "validated".

What to do:

1. **Re-approve the helper for the current bundle id.** The helper is registered
   with `SMAppService` under `com.omarhernandez.usbfrommac.helper`; to the system
   this is a *new* service, so the previous approval doesn't carry over. After
   `scripts/dogfood.sh`:
   ```bash
   sudo killall UsbFromMacHelper        # drop any old daemon from memory
   ```
   then approve it in **System Settings → General → Login Items** when the app
   asks on first run.
2. **Create a real Ubuntu USB** with the app (pick the Ubuntu ISO → the picker
   should show "Linux ISO", no FAT32 label field, the raw "Write image" phase
   with live bytes/%).
3. **Boot a real machine** from that stick and confirm it reaches the installer.
4. Watch for hardware-only bugs (the Windows flow surfaced 6). Likely suspects:
   last-block alignment/padding, `F_FULLFSYNC` timing, and eject behavior.

Conservative rule: if the detector is unsure about an ISO, do NOT offer the raw
write — better to reject than to hand the user a stick that won't boot.

---

## Pending (optional, doesn't block use)

- **Notarization** to distribute to other Macs: `scripts/build-notarize.sh`.
  Un-notarized, the build is only valid on this machine (no quarantine).
