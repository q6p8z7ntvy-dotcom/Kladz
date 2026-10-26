# Kladz

Free and open-source iPhone location teleport. Tap the map, search a place, or drive a route — Kladz injects coordinates through Apple’s **developer location service** into `locationd`, so Maps and other apps see the spoofed GPS (not just a Wi‑Fi lookup that outdoor GPS will overwrite).

<p align="center">
  <img src="docs/screenshots/map.png" alt="Kladz map with spoof pin" width="180" />
  <img src="docs/screenshots/spoofing.png" alt="Kladz spoofing in 3D" width="180" />
  <img src="docs/screenshots/joystick.png" alt="Kladz joystick controls" width="180" />
  <img src="docs/screenshots/route.png" alt="Kladz route on map" width="180" />
</p>

## Features

- One-tap teleport (map pin or place search)
- Live joystick — walk / run / cycle / drive with light speed variation
- Walk/Drive routing on real roads & footpaths (MapKit)
- Draw a path or import / export GPX
- Background keep-alive + live status bar + drop alerts
- Favorites & recents
- First-run setup walkthrough
- No account or analytics. Favorites and recents stay on-device; pairing credentials use iOS Data Protection and are excluded from device backups. Apple MapKit may process place-search and route requests. See [SECURITY.md](SECURITY.md) for the security model and its limits.

## Install

See [SETUP.md](SETUP.md) for full steps. Grab a prebuilt IPA from [Releases](https://github.com/q6p8z7ntvy-dotcom/kladz/releases), or build from source below.

Bundle ID: `com.chrismack.kladz`

### LiveContainer

File pickers often don’t work inside LiveContainer. Use one of these:

1. Long-press **Kladz** → **Settings** → enable **Fix File Picker**, then try Import again.
2. Share the pairing file **into LiveContainer → Kladz**.
3. Copy the RPPairing plist contents → in Kladz use **Paste RPPairing from clipboard** (setup or Settings).

## How it works

Kladz uses the MIT-licensed [idevice](https://github.com/jkcoxson/idevice) FFI to talk to Apple’s DVT location simulation over an on-device developer tunnel (the same class of mechanism Xcode uses).

**iOS 27:** Settings → **Pair on this iPhone** advertises `_remotepairing-pairable-host._tcp`. Confirm the 6-digit code under Settings › Privacy & Security › Developer Mode › Pair with Host — no computer.

**iOS 18–26:** import an **RPPairing** file once from [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases).

Also install **[LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)** (loopback tunnel, default `10.7.0.1`), then sideload Kladz.

Start a teleport on Wi‑Fi first; the session can keep working on cellular afterward.

### Pokémon GO & similar games

Kladz spoofs location the same way Xcode’s developer tools do: it tells iOS “you’re here,” and other apps read that from the system. Apps that just trust GPS (Apple Maps, etc.) will follow it.

**Pokémon GO is different.** It runs its own location checks and often rejects developer / simulated GPS (e.g. “Failed to detect location”). That’s expected with this method, not a Kladz bug, and there’s no supported fix for it in this app.

Tools like **iPogo** (and similar modified clients such as SpooferPro) work differently: they’re a **modified Pokémon GO app**, not a system-wide location spoof. Features live *inside* that altered game client, instead of feeding coordinates through iOS for every app. Kladz never patches or replaces Pokémon GO; it only changes what the system reports. So those tools can appear to “work in Pokémon GO” while Kladz correctly drives Maps but still gets blocked by Pokémon GO’s checks.

Kladz is for system-level teleporting. It isn’t a Pokémon GO client or an anti-cheat bypass.

## Build

Building an unsigned IPA from source does not require an Apple Developer account. Installing it on a device still requires a compatible sideloading tool to sign it; a paid developer account is not generally required for personal sideloading.

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if needed: `brew install xcodegen`
2. Set your **Team ID** in `project.yml` (`DEVELOPMENT_TEAM`), *or* pick your team under Xcode → Signing & Capabilities after generating the project.
3. Generate and open:

```bash
xcodegen generate
open Locus.xcodeproj
```

Or build from the CLI (the generated project keeps its legacy `Locus.xcodeproj` filename for compatibility; the app target/scheme is `Kladz`. The legacy `Locus` scheme is also retained for existing IPA workflows. Replace with your Team ID from [developer.apple.com/account](https://developer.apple.com/account) → Membership):

```bash
xcodegen generate
xcodebuild -project Locus.xcodeproj -scheme Kladz -configuration Release \
  -destination 'generic/platform=iOS' DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

### Build an IPA with GitHub Actions

Open the repository's **Actions → Build Kladz IPA → Run workflow**, or open a pull request to `main`. Download the `Kladz-unsigned-IPA` artifact from the completed run. A push of a `v*` tag also attaches the IPA to that GitHub Release.

The workflow creates an **unsigned** IPA because the repository does not contain your Apple signing certificate or provisioning profile. Import it into your sideloading tool (for example Feather, SideStore, or AltStore) so that tool can sign it for your device. The artifact by itself is not a ready-to-install signed IPA.

## License

MIT. `Vendor/idevice` contains the idevice FFI (MIT). Kladz is an independent open-source project. It is not affiliated with Apple or the idevice project maintainers.
