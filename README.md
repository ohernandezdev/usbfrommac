# WinUSB Mac

Create a bootable Windows 11 USB drive from an ISO on macOS — safely. A minimalist "Rufus for Mac".

[![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://www.apple.com/macos/)
[![License: GPLv3](https://img.shields.io/badge/license-GPLv3-green.svg)](LICENSE)
[![Language: Swift](https://img.shields.io/badge/language-Swift%205.9-orange.svg)](https://swift.org)

WinUSB Mac is a native macOS app (Swift 5.9 + SwiftUI) that turns a Windows 11 ISO into a bootable USB stick — without Boot Camp, without third-party closed binaries, and without ever putting your internal disk at risk.

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

- **USB-only by design.** The drive picker lists *only* external, physical USB disks enumerated through DiskArbitration. Your internal/boot disk is never shown — it is excluded at the code level (a hard whitelist), not by a UI filter you could click past.
- **Privileged work is isolated.** The single destructive step (`diskutil eraseDisk`) runs in a separate root helper installed via `SMAppService` and reached over XPC. Everything else runs as your normal user. We do **not** use `AuthorizationExecuteWithPrivileges`.
- **FAT32-safe install.wim handling.** The whole ISO is copied except `sources/install.wim`, which is split into `.swm` segments of 3800 MiB with [wimlib](https://wimlib.net) so it fits on FAT32. Windows Setup reassembles them automatically.
- **Optional SHA-256 verification.** Paste the official hash and the app computes and compares it before writing.
- **Secure Boot awareness.** Warns when an ISO looks old enough to be signed only with the soon-to-be-revoked "PCA 2011" certificate, which may fail to boot with Secure Boot enabled.
- **Real progress everywhere.** Live bytes / % / MB/s / ETA for every phase — not just an indeterminate spinner.
- **Bilingual UI.** English and Spanish (i18n).

## Screenshots

<!-- TODO: add screenshots — see docs/ for captures of the disk picker, confirmation, and progress views -->

## Safety model

WinUSB Mac formats disks and runs code as root, so safety is the core of its design rather than an afterthought. Two mechanisms make it hard to lose data:

**1. Internal-disk whitelist.** The disk enumerator (`DiskFilter` / `DiskArbitrationSource`) only ever surfaces candidates that are `external` + `physical` + removable USB media. The system boot disk is filtered out explicitly, and mounted disk images, cryptexes and virtual devices (`busProtocol == "Disk Image"`, `Virtual`) are rejected too. The internal disk physically cannot appear in the picker.

**2. Privilege isolation.** Only `diskutil eraseDisk` needs root. It lives in a minimal daemon (`WinUSBMacHelper`) registered with `SMAppService` and invoked over XPC. The helper independently re-checks that its target is external/removable before erasing (safeguard **S-4**). The rest of the pipeline — copy, split, verify, eject — runs unprivileged.

On top of that, the build flow enforces the destructive-operation safeguards **S-2 … S-5**: an explicit confirmation showing the exact disk name and size (S-2), re-validation of the disk identifier *immediately* before formatting (S-3), the helper-side external-media check (S-4), and fail-safe error handling that aborts cleanly with no half-formatted state (S-5).

## Requirements

- macOS 13 (Ventura) or later — Intel or Apple Silicon
- A Windows 11 ISO
- A USB drive of 8 GB or more (its contents will be erased)

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
open WinUSBMac.xcodeproj
```

The app bundles `wimlib-imagex` and `libwim.*.dylib` under `App/Resources/`; these must be present (and signed) for the split step to work. They are copied into `Contents/Resources` of the app bundle as an explicit resource phase.

For a **signed local build** (Developer ID, for running on real hardware) use the dogfooding script:

```bash
scripts/dogfood.sh
```

It signs the app and re-signs the helper with the correct identifier (`com.omar.winusbmac.helper`) — see [docs/DOGFOODING.md](docs/DOGFOODING.md) for the gotchas around `SMAppService`, XPC and the on-demand daemon. Notarized distribution outside the Mac App Store is planned but not yet shipped.

## How it works

The build runs in four phases with real progress reporting:

1. **Format** — the root helper runs `diskutil eraseDisk` to lay down a fresh **FAT32 / GPT** layout, then the app explicitly mounts the resulting data partition.
2. **Copy** — the entire ISO is copied to the USB *except* `sources/install.wim`.
3. **Split** — `install.wim` is split into `install.swm`, `install2.swm`, … of ≤ 3800 MiB each with wimlib, so it fits within the FAT32 4 GiB file-size limit. Windows Setup reassembles them automatically at install time.
4. **Finish** — the volume is flushed and safely ejected.

## Localization

The interface is fully localized in **English** and **Spanish**. Code comments follow the language of the file they live in.

## License

WinUSB Mac is released under the **GNU General Public License v3.0** — see [LICENSE](LICENSE) for the full text.

GPLv3 is required because the app bundles and distributes [wimlib](https://wimlib.net), which is itself GPLv3-licensed. Any redistribution must keep the source available under the same terms.

## Acknowledgements

- [wimlib](https://wimlib.net) — the WIM library that makes FAT32-safe `install.wim` splitting possible.
- [IBM Carbon Design System](https://carbondesignsystem.com) — design language reference for the UI.
