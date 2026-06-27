# Contributing to WinUSB Mac

Thanks for your interest in improving WinUSB Mac. This app erases disks and runs a root helper, so contributions are held to a high safety bar. Please read the safety rules below before sending code.

## Development setup

This project uses [XcodeGen](https://github.com/yonsk/XcodeGen); the `.xcodeproj` is generated, not committed.

```bash
brew install xcodegen wimlib
xcodegen generate
open WinUSBMac.xcodeproj
```

`wimlib-imagex` and `libwim.*.dylib` live under `App/Resources/` and are bundled into the app. They must be present for the split step.

## Running tests

```bash
xcodebuild test -scheme WinUSBMac -destination 'platform=macOS'
```

The test suite focuses on the safety-critical logic: disk filtering (`DiskFilterTests`) and the split-size / build-flow decisions (`BuildFlowTests`). New safety-relevant code must come with tests.

## Code style

- Match the existing style of the surrounding code.
- Write comments in the language of the file you are editing (most app code mixes English identifiers with Spanish comments — keep each file consistent).
- Keep privileged code (the helper) minimal. Anything that does not strictly require root belongs in the unprivileged app.

## The golden safety rule

**Never touch the internal disk.** The disk whitelist (`DiskFilter`, `DiskArbitrationSource`, `SystemBootDisk`) only ever exposes external, physical, removable USB media. Any change to disk enumeration or to the privileged helper requires:

- Extreme care and explicit reasoning in the PR description.
- New or updated tests proving the internal/boot disk and virtual/disk-image devices stay excluded.
- A reviewer sign-off specifically on the safety aspect.

## Destructive-operation safeguards (S-2 … S-5)

Any change that touches the format/erase path must preserve these safeguards (see [docs/DOGFOODING.md](docs/DOGFOODING.md) for context):

- **S-2** — Explicit destructive confirmation showing the exact disk name and size.
- **S-3** — Re-validate the disk identifier *immediately* before formatting (BSD names can change after replug).
- **S-4** — The privileged helper independently verifies the target is external/removable before erasing.
- **S-5** — Fail safe: any error aborts cleanly and never leaves a half-formatted disk.

If your change weakens or bypasses any of these, it will not be merged.

## Pull request process

1. Fork and create a feature branch.
2. Make your change; run the tests and confirm they pass.
3. If you changed the UI, update **both** the English and Spanish strings.
4. Fill out the PR template, including the safety checklist.
5. Open the PR against the default branch. Safety-relevant PRs get an extra review pass.

By contributing you agree your work is licensed under the project's GPLv3 license.
