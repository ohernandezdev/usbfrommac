## Summary

Briefly describe what this PR changes and why.

## Related issue

Closes #

## Checklist

- [ ] Tests pass locally (`xcodebuild test -scheme WinUSBMac -destination 'platform=macOS'`).
- [ ] Preserves the destructive-operation safeguards **S-2 … S-5** (explicit confirmation, disk re-validation, helper-side check, fail-safe error handling).
- [ ] Does **not** touch or expose the internal/boot disk; the disk whitelist remains intact.
- [ ] Any change to disk enumeration or the privileged helper has new/updated tests proving the internal disk and virtual/disk-image devices stay excluded.
- [ ] If the UI changed, both English and Spanish strings were updated.
- [ ] Comments are written in the language of the file being edited.

## Safety notes

If this PR touches disk enumeration, the helper, or the format/erase path, explain the safety reasoning here.
