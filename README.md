# USB from Mac

Create a bootable Windows or Linux USB drive from an ISO on macOS — safely. A minimalist "Rufus for Mac".

[![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://www.apple.com/macos/)
[![License: GPLv3](https://img.shields.io/badge/license-GPLv3-green.svg)](LICENSE)
[![Language: Swift](https://img.shields.io/badge/language-Swift%205.9-orange.svg)](https://swift.org)

USB from Mac is a native macOS app (Swift 5.9 + SwiftUI) that turns a Windows ISO **or** a Linux / isohybrid ISO into a bootable USB stick — without Boot Camp, without third-party closed binaries, and without ever putting your internal disk at risk.

The app inspects each ISO's boot structure and automatically picks the right strategy: Windows installers are copied to a FAT32 volume (with `install.wim` split so it fits), while Linux / isohybrid images are written raw, byte for byte, to the device.

## Table of Contents

- [Features](#features)
- [Screenshots](#screenshots)
- [Safety model](#safety-model)
- [Requirements](#requirements)
- [Building from source](#building-from-source)
- [How it works](#how-it-works)
- [Localization](#localization)
- [License](#license)
- [Acknowledgements](#acknowledgements)

## Features

- **Windows *and* Linux ISOs.** The ISO's boot structure (MBR signature + El Torito) is detected automatically and the build branches accordingly:
  - **Windows installers** → copied to a fresh **FAT32 / GPT** volume; `sources/install.wim` is split into `.swm` segments so it fits FAT32.
  - **Linux / isohybrid ISOs** (Ubuntu, Fedora, Debian, …) → written **raw** (byte-for-byte `dd`) to the device, exactly as the upstream image expects.
  - ISOs that are not bootable in a supported way are rejected up front, rather than producing a USB that won't boot.
- **USB-only by design.** The drive picker lists *only* external, physical USB disks enumerated through DiskArbitration. Your internal/boot disk is never shown — it is excluded at the code level (a hard whitelist), not by a UI filter you could click past.
- **Privileged work is isolated.** The two destructive steps — `diskutil eraseDisk` (Windows) and the raw image write (Linux) — run in a separate root helper installed via `SMAppService` and reached over XPC. Everything else runs as your normal user. We do **not** use `AuthorizationExecuteWithPrivileges`.
- **FAT32-safe install.wim handling.** For Windows, the whole ISO is copied except `sources/install.wim`, which is split into `.swm` segments of 3800 MiB with [wimlib](https://wimlib.net) so it fits on FAT32. Windows Setup reassembles them automatically.
- **Size guard for raw writes.** Before a raw write the app verifies the USB is at least as large as the ISO, so a too-small stick can't fail mid-`dd` and leave a half-written drive.
- **Optional SHA-256 verification.** Paste the official hash and the app computes and compares it before writing.
- **Secure Boot awareness.** For Windows ISOs, warns when an image looks old enough to be signed only with the soon-to-be-revoked "PCA 2011" certificate, which may fail to boot with Secure Boot enabled.
- **Real progress everywhere.** Live bytes / % / MB/s / ETA for every phase — including the raw write — not just an indeterminate spinner.
- **Bilingual UI.** English and Spanish (i18n).

## Screenshots

<!-- TODO: add screenshots — see docs/ for captures of the disk picker, confirmation, and progress views -->

## Safety model

USB from Mac formats disks and runs code as root, so safety is the core of its design rather than an afterthought. Several mechanisms make it hard to lose data:

**1. Internal-disk whitelist.** The disk enumerator (`DiskFilter` / `DiskArbitrationSource`) only ever surfaces candidates that are `external` + `physical` + removable USB media. The system boot disk is filtered out explicitly, and mounted disk images, cryptexes and virtual devices (`busProtocol == "Disk Image"`, `Virtual`) are rejected too. The internal disk physically cannot appear in the picker.

**2. Privilege isolation.** Only the destructive steps need root: `diskutil eraseDisk` (Windows flow) and the raw `dd`-style write to `/dev/rdiskN` (Linux flow). Both live in a minimal daemon (`UsbFromMacHelper`) registered with `SMAppService` and invoked over XPC. The helper independently re-checks that its target is external/removable before touching it (safeguard **S-4**). The rest of the pipeline — copy, split, verify, eject — runs unprivileged.

On top of that, the build flow enforces the destructive-operation safeguards **S-2 … S-5**: an explicit confirmation showing the exact disk name and size (S-2), re-validation of the disk identifier *immediately* before writing (S-3), the helper-side external-media check (S-4), and fail-safe error handling that aborts cleanly with no half-finished state (S-5). For the raw flow, the app additionally refuses to start unless the USB is at least the ISO's size, so a raw write can never be cut short by a too-small drive.

## Requirements

- macOS 13 (Ventura) or later — Intel or Apple Silicon
- A **Windows 11 ISO**, or a bootable **Linux / isohybrid ISO** (e.g. Ubuntu, Fedora, Debian)
- A USB drive whose contents you don't mind erasing:
  - Windows: 8 GB or more (16 GB recommended)
  - Linux: at least the size of the ISO

To build from source you additionally need:

- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [wimlib](https://wimlib.net) (`brew install wimlib`) — its `wimlib-imagex` binary and `libwim` dylib are bundled into the app

## Building from source

This project does not commit an `.xcodeproj`; it is generated from `project.yml` with XcodeGen.

```bash
# 1. Install tooling
brew install xcodegen wimlib

# 2. Generate the Xcode project
xcodegen generate

# 3. Open and build
open UsbFromMac.xcodeproj
```

The app bundles `wimlib-imagex` and `libwim.*.dylib` under `App/Resources/`; these must be present (and signed) for the Windows split step to work. They are copied into `Contents/Resources` of the app bundle as an explicit resource phase.

For a **signed local build** (Developer ID, for running on real hardware) use the dogfooding script:

```bash
scripts/dogfood.sh
```

It signs the app and re-signs the helper with the correct identifier (`com.omarhernandez.usbfrommac.helper`) — see [docs/DOGFOODING.md](docs/DOGFOODING.md) for the gotchas around `SMAppService`, XPC and the on-demand daemon. Notarized distribution outside the Mac App Store is planned but not yet shipped.

## How it works

The app first inspects the ISO and then runs one of two pipelines, both with real progress reporting.

**Windows installers** (FAT32 copy) run in four phases:

1. **Format** — the root helper runs `diskutil eraseDisk` to lay down a fresh **FAT32 / GPT** layout, then the app explicitly mounts the resulting data partition.
2. **Copy** — the entire ISO is copied to the USB *except* `sources/install.wim`.
3. **Split** — `install.wim` is split into `install.swm`, `install2.swm`, … of ≤ 3800 MiB each with wimlib, so it fits within the FAT32 4 GiB file-size limit. Windows Setup reassembles them automatically at install time.
4. **Finish** — the volume is flushed and safely ejected.

**Linux / isohybrid ISOs** (raw write) run as a single privileged phase:

1. **Write image** — after re-validating the target and confirming the USB fits the ISO, the root helper unmounts the whole disk and writes the ISO byte-for-byte to `/dev/rdiskN`, block-aligned and `F_FULLFSYNC`-flushed, then ejects it. No FAT32 layout, no label, no split — the isohybrid image already carries its own boot structure.

## Localization

The interface is fully localized in **English** and **Spanish**. All code, comments, and messages are written in English (open-source standard).

## License

USB from Mac is released under the **GNU General Public License v3.0** — see [LICENSE](LICENSE) for the full text.

GPLv3 is required because the app bundles and distributes [wimlib](https://wimlib.net), which is itself GPLv3-licensed. Any redistribution must keep the source available under the same terms.

## Acknowledgements

- [wimlib](https://wimlib.net) — the WIM library that makes FAT32-safe `install.wim` splitting possible.
- [IBM Carbon Design System](https://carbondesignsystem.com) — design language reference for the UI.
