# Security Policy

WinUSB Mac erases disks and runs a privileged (root) helper, so security is central to its design. This document explains the threat model, what is in scope, and how to report a vulnerability.

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**

Email **omarsro@gmail.com** with:

- A description of the issue and its impact.
- Steps to reproduce (or a proof of concept).
- Affected version / commit, and your macOS version and Mac model.

You will get an acknowledgement as soon as possible. Please give a reasonable window to release a fix before any public disclosure.

## Threat model (brief)

The app's most sensitive capabilities are: (1) it can erase a disk, and (2) it installs and talks to a root daemon. The design goal is that neither capability can be turned against the user's data or system.

- **Wrong-disk erase.** Mitigated by a code-level whitelist: only `external` + `physical` + removable USB media is ever offered, the system boot disk is filtered out, and disk images / virtual devices are rejected. The disk identifier is re-validated immediately before erasing, and the helper independently re-checks the target is removable before acting.
- **Privilege escalation via the helper.** The helper (`WinUSBMacHelper`) is registered with `SMAppService` and reached over XPC. Its surface is intentionally tiny — effectively only `eraseDisk`. The XPC connection is validated by code-signing requirement so only the legitimate, correctly-signed app can drive it.
- **Tampered binaries.** The app and helper are signed; the helper is signed with the fixed identifier `com.omar.winusbmac.helper` and the cross-signing requirement must match. Notarized distribution is planned to extend this to download integrity.
- **Tampered ISO.** Optional SHA-256 verification lets the user confirm the ISO matches the official hash before writing.

## In scope

- The disk whitelist / enumeration logic (`DiskFilter`, `DiskArbitrationSource`, `SystemBootDisk`, `DiskRevalidation`).
- The XPC interface and the privileged helper (`WinUSBMacHelper`, `HelperClient`).
- Code-signing requirement validation between the app and the helper.

## Out of scope

- Vulnerabilities in third-party tools we bundle (e.g. wimlib) — please report those upstream, though we appreciate a heads-up.
- Issues that require an already-root or physically-present attacker with no privilege boundary crossed.
