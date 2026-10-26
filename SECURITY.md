# Security and privacy

Kladz can control simulated device location through Apple's developer-location services. Treat pairing files and device-pairing codes as sensitive credentials.

## Protections in the app

- Pairing material is stored inside the app's Application Support sandbox, not in a shared Documents folder.
- Pairing files use iOS Data Protection with the `Complete Until First User Authentication` protection class. On supported devices, iOS encrypts protected files at rest and controls access to the encryption keys.
- Pairing files are excluded from device backups and use restrictive POSIX permissions as an additional defense-in-depth measure.
- Favorites and recent places are stored locally. Kladz does not require an account and does not include analytics.
- Apple MapKit may process place-search and route requests. The app cannot promise that those requests remain only on-device.
- Kladz connects to the configured LocalDevVPN tunnel and uses Apple's developer location simulation. Only use pairing material and tunnels on devices and networks you trust.

## Important limitations

- iOS Data Protection is platform-provided encryption at rest; it is **not** a claim of custom end-to-end encryption. Kladz does not encrypt every app file with a separate app-managed key.
- Imported pairing files are credentials. Do not share them, paste them into public issues, or include them in screenshots or logs. Remove pairing material from Settings when it is no longer needed.
- The GitHub Actions workflow currently builds an **unsigned** IPA. A release artifact is not signed, notarized, or independently security-audited by this workflow.
- Location simulation can violate third-party app terms or game rules. Use it only where permitted.

## Reporting a vulnerability

Please do not publish credentials, pairing files, private device data, or an exploitable vulnerability in a public issue. Contact the repository maintainer privately through GitHub to coordinate a responsible disclosure.
