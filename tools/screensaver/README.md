# Standalone screen saver build tools

- `build.sh`: build a new optimized universal, ad-hoc signed local candidate.
- `validate.py BUNDLE`: check the bundle payload, assets, identity, native slices,
  deployment target, system dependencies and signature. `--distribution` requires
  Developer ID, hardened runtime and a timestamp; it does not replace notarization.
- `package.sh --identity IDENTITY --notary-profile PROFILE`: explicitly sign,
  package, submit to Apple's notary service, staple and assess a fresh candidate
  DMG. Requires configured credentials. Never installs or publishes.
- `INSTALL.txt`: installation, update and removal instructions included in a DMG.

Run from any directory; outputs are confined to a new ignored repository `.build`
directory. Build/test commands do not use signing accounts or make network calls.
The packaging command intentionally contacts Apple and remains unverified end to
end until signing/distribution validation is performed.

[Full candidate documentation](../../docs/STANDALONE_SCREEN_SAVER.md).
