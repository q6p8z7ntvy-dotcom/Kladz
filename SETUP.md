# Kladz — install & first teleport

## 1. Sideload the IPA

Download the IPA from [Releases](https://github.com/q6p8z7ntvy-dotcom/kladz/releases) (or build from source), then import it into Feather, SideStore, AltStore, Sideloadly, or LiveContainer. These tools handle signing for installation. GitHub Actions currently publishes an **unsigned** IPA, so the raw artifact cannot be installed directly as a signed app.

Bundle ID: `com.chrismack.kladz`

### LiveContainer

File pickers often break inside LiveContainer. Do one of the following:

1. Long-press **Kladz** in LiveContainer → **Settings** → enable **Fix File Picker**, then try Import again.
2. Share / open the pairing file **into LiveContainer → Kladz** (iOS share sheet).
3. Copy the RPPairing plist contents, open Kladz → **Paste RPPairing from clipboard** (setup or Settings).

## 2. Pairing

### On iOS 27 — no computer

1. Open Kladz → **Settings → Pair on this iPhone** → **Start pairing**.
2. Allow **Local Network** (and Location / Notifications if asked).
3. Leave Kladz open. Go to **Settings › Privacy & Security › Developer Mode › Pair with Host**.
4. Pick **Kladz** → **Pair**.
5. Enter your **iPhone unlock passcode** first (authorizes pairing).
6. When the second prompt appears, type the **6-digit code** Kladz shows (also sent as a notification).
7. Done — RPPairing file is saved on-device.

### On iOS 18–26

1. On a computer, download [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases).
2. Plug in your iPhone, unlock, Trust.
3. Generate an **RPPairing** file (not lockdown / SideStore `.mobiledevicepairing`).
4. AirDrop / Share → Open in **Kladz**, **Import**, or **Paste from clipboard**.

## 3. LocalDevVPN

Install [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044), connect it (default tunnel IP `10.7.0.1`).

## 4. Teleport

On Wi‑Fi: drop a pin → **Teleport**. Then joystick / routes / GPX work; the session can continue on cellular.
