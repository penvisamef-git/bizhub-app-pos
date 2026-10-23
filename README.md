# BizHub POS

The counter app for staff (Android, iOS). One device = one POS: Restaurant, Mini Mart, Guest House, Attendance
(door tablet or staff phone) or Stamp Card (staff desk). It works on the device first and syncs with Biz Hub when online.

First open: 4 welcome pages → choose the POS → link it (6-digit code from the owner, or a QR / link for Attendance and
Stamp Card) → that POS.

## Run

`env.json` (copy `env.example.json`, never commit it):

```json
{ "API_HOST": "https://YOUR-API.vercel.app", "API_AUTH_KEY": "same value as VITE_API_AUTH_KEY", "SITE_URL": "https://bizhubcambodia.com" }
```

`SITE_URL` must be the website the QR codes open (staff attendance links, stamp cards, guest pages).

```bash
flutter pub get
flutter run --dart-define-from-file=env.json
```

With the local API on Wi-Fi (on a real phone use your computer's IP, not localhost):

```bash
flutter run --dart-define=API_HOST=http://192.168.1.10:8086 --dart-define=API_AUTH_KEY=… --dart-define=SITE_URL=http://192.168.1.10:3000
```

## Release (Android)

### 1. The upload key — once, keep it forever

Make it on your own computer and back it up (Google Drive + a USB stick). If it is lost, the app on Google Play can't be
updated any more. Never put it in git or send it in chat.

```bash
keytool -genkey -v -keystore ~/keys/bizhub-pos-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then `android/key.properties` (never in git — `.gitignore` already blocks it):

```properties
storePassword=YOUR_PASSWORD
keyPassword=YOUR_PASSWORD
keyAlias=upload
storeFile=/Users/YOU/keys/bizhub-pos-upload.jks
```

Without `key.properties` a release build is signed with the debug key: fine for testing on your own phones, but Google
Play refuses it.

### 2. Version

`pubspec.yaml` → `version: 1.0.0+1`. Raise the number after `+` for every upload (1.0.1+2, 1.0.2+3 …).

### 3. Build

```bash
flutter build appbundle --release --dart-define-from-file=env.json   # → build/app/outputs/bundle/release/app-release.aab (Google Play)
flutter build apk --release --split-per-abi --dart-define-from-file=env.json   # → build/app/outputs/flutter-apk/*.apk (install directly)
```

Install an APK on a phone / terminal with a cable (USB debugging on): `adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
Most phones and POS terminals are arm64; very old or cheap terminals may need `app-armeabi-v7a-release.apk`.
Or send the APK file (Telegram / Drive) and open it on the device ("install unknown apps" must be allowed).

### 4. Google Play

- App ID: `com.bizhubcambodia.pos` (a separate listing from the owner app `com.bizhubcambodia.app`).
- The app asks for **location** and **camera** (Attendance: clock in at work, selfie, door QR; barcode / card scanning)
  and **Nearby devices** (Bluetooth receipt printers). Play's *Data safety* form needs these, and a privacy policy link.
- Location is only used while the staff presses Clock in (not in the background).

## Devices

- **Dual-screen Android terminals** (customer display): Mini Mart / Guest House show the bill and the payment QR on the
  second screen (`MainActivity.kt` starts it).
- **Printers**: Bluetooth (paired in Android settings first) or Wi-Fi / LAN (IP:9100), 58 or 80 mm. On Android 12+ the
  app asks for "Nearby devices" the first time it prints by Bluetooth.
- **Door tablet** (Attendance): the screen stays on while it shows the QR. Put it on a charger.

## Texts

`assets/i18n/en.json` and `km.json` are made from the website's own text files, so both say the same thing:

```bash
node tool/extract_texts.js ../bizhub/src assets/i18n
```

Words only the app has are in `lib/core/app_text.dart`.

## Code map

- `lib/core` — app state (which POS, the link), API clients, texts, theme, printing, customer display
- `lib/features/start` — choose the POS, link with a 6-digit code
- `lib/features/restaurant` · `mart` · `guesthouse` — each POS: `engine/` (offline data + sync) and the screens
- `lib/features/attendance` — door tablet (`att_kiosk`) and staff phone (`att_staff`, `att_month`, `att_more`)
- `lib/features/stamp` — the stamp card staff desk (card drawing + counter shared with the owner app)
- `lib/widgets` — shared UI, the QR scanner
