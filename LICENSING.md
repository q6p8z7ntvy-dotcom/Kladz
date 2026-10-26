# Kladz

Kladz is an iPhone location utility with a device-bound activation key for the official build.

## Activation keys

The app verifies an Ed25519-signed license token. The signing private key is **not** stored in this repository or embedded in the app. Keep the private key file offline and backed up securely.

The activation screen displays a device code. After payment through your chosen sales channel, use that code to issue a license:

```bash
python3 -m pip install cryptography
python3 tools/issue-key.py --private-key /secure/path/kladz-license-private.pem --device-id DEVICE-CODE --days 365
```

Send the generated token to the customer. The token is tied to that device code and expires after the selected number of days. Use `--days 36500` for an effectively perpetual license. Do not put your private key in GitHub, a release, or the app.

**Important limitation:** this is offline license verification, not payment processing or a remote revocation service. Because the project source is open source, someone who builds a modified app can remove the client-side check. Stronger enforcement for a commercial service requires a backend and a clear purchase flow.

## Build

1. Install XcodeGen: `brew install xcodegen`
2. Generate the Xcode project: `xcodegen generate`
3. Open `Kladz.xcodeproj` and build the `Kladz` scheme.

The project keeps the upstream MIT license and required third-party notices.
