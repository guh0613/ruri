# Ruri

A Minecraft Java launcher for macOS.

Documentation coming soon.

## Local contributor signing

To keep Keychain authorization stable across local rebuilds, install an Apple Development
certificate with its private key in your login keychain, then find its SHA-1 fingerprint:

```sh
security find-identity -v -p codesigning
```

Select that identity explicitly when packaging:

```sh
RURI_CONTRIBUTOR_SIGN_IDENTITY=<SHA-1> scripts/build-app.sh debug
```

The identity must have a valid Apple Development certificate chain and a Team ID.
The app and its CLI helper share the signing identifier and designated requirement.
On the first account access, choose **Always Allow** in the Keychain authorization
dialog to retain access across rebuilds using that identity.

Contributor signing is rejected when `RURI_REQUIRE_SIGNING=1`, `CI`, or
`GITHUB_ACTIONS` is set. It does not produce a release signature. Without
`RURI_CONTRIBUTOR_SIGN_IDENTITY`, packaging keeps its existing signing behavior.
To verify a contributor package separately, set the same variable when running
`python3 scripts/release/signing.py verify build/Ruri.app`.
