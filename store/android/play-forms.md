# BizHub POS: answers for the Play Console forms

Based on the app as it is now: `pubspec.yaml` plugins, the Android permissions (ours + the plugins'), and the API it talks to. Update **Data safety** if you add analytics, ads or a new SDK.

- **App:** BizHub POS · `com.bizhubcambodia.pos` · Free · no ads · no in-app purchases
- **Developer:** Blackcorp Enterprise · bizhubcambodia@gmail.com · https://bizhubcambodia.com
- **Privacy policy:** https://bizhubcambodia.com/privacy (it already covers staff attendance location, camera and photos)
- **Signing:** the same upload key as the owner app (`~/keys/bizhub-upload.jks`, alias `upload`). Google allows one upload key for many apps.

## 1. App access (Sign in details) — filled 22 Oct 2026

**Is any part restricted?** Yes · **Full access** ticked (every POS type has a demo).

| Field | Value |
|---|---|
| Name | Try a demo (no account needed) |
| Username / password | empty |
| Instructions | No sign-in needed. Open the app, go through the welcome pages and choose any POS type. On the link screen tap 'Try a demo' to open a sample business. Staff PIN: 1234 (also shown on the screen). Restaurant: type any amount to open the shift, then tap 'Start selling'. Attendance: choose Staff phone or Door tablet, then 'Try a demo'. Stamp Card and Event Tickets: tap 'Try a demo', then type PIN 1234. |

The demo businesses belong to `playreview@bizhubcambodia.com` on production: Mekong Kitchen, Lucky Mini Mart, Lotus Guest House, Lucky Team (attendance: branch with door kiosk, demo staff +85512000123 / 1234), Mekong Coffee Stamps (desk PIN 1234) and Khmer New Year Party (event "Riverside Night Market", team member Demo Door / 1234). `bizhub-api/scripts/demo-pos.js --yes` fills them and is safe to run again (re-run it before the event date passes, so the door phone keeps an upcoming event). `src/biz/pos_demo.js` is the "Try demo" API. Old demo sales, stays and clock-ins (older than 2 days) are removed automatically.

## 2. Ads

No.

## 3. Content rating (IARC)

Category **All other app types**. Every question **No** (no violence, no user-to-user chat, no gambling, no web browser, no location sharing with other users). Purchases: **No** (the POS sells nothing digital). Expected: **Everyone / PEGI 3 / IARC 3+**.

## 4. Target audience

**18 and over.** A tool for shop staff. Not for children.

## 5. Data safety

| Question | Answer |
|---|---|
| Collects or shares required user data? | **Yes** |
| Encrypted in transit? | **Yes** (HTTPS only) |
| Account creation | **The app doesn't allow users to create an account**. **Login with accounts made outside the app: Yes → through employment** (attendance staff log in with the phone + PIN their employer made) |
| Way to request deletion? | **Yes**: https://bizhubcambodia.com/delete-account (the owner deletes the business; data from linked devices goes with it) |
| Status | **Saved 22 Oct 2026**, with all the types below |
| Shared with third parties? | **No** for every type (Vercel, MongoDB Atlas, Cloudinary and Telegram are service providers working for BizHub) |

Tick these. Each one: **Collected: Yes · Shared: No · Processed ephemerally: No · Required or optional: see table**.

| Category → type | Required? | Purpose | Where |
|---|---|---|---|
| **Location → Precise location** | Optional | App functionality | Attendance: the staff phone's position when they press Clock in / out (geolocator, only at that moment, never in the background) |
| **Location → Approximate location** | Optional | App functionality | The same check (ACCESS_COARSE_LOCATION is declared too) |
| **Personal info → Name** | Optional | App functionality | Guest names (guest house), member names (rewards), debtor names, staff names |
| **Personal info → Phone number** | Optional | App functionality | Guest, member and debtor phones |
| **Personal info → Other info** | Optional | App functionality | Guest ID / passport number and nationality (guest house register) |
| **Financial info → Purchase history** | Required | App functionality | Sales, bills, payments and shifts of the shop |
| **Photos and videos → Photos** | Optional | App functionality | Attendance selfie, product photos taken on the POS |
| **App activity → Other user-generated content** | Required | App functionality | Orders, bookings, notes on bills |

**Do not tick:** contacts, calendar, messages, files, audio, health, web browsing, app info and performance (the POS has no crash reporter), device IDs (no advertising ID), card numbers.

**Camera / barcode scanning** reads the camera image on the device only (mobile_scanner); only photos the user chooses to upload are collected (covered by Photos). **Bluetooth** (print_bluetooth_thermal) only talks to receipt printers paired in Android settings.

## 6. Other declarations

| Form | Answer |
|---|---|
| Government app | No |
| Financial features | **My app doesn't provide any financial features** (it records the shop's own sales; no loans, banking, wallets or money transfers). Do NOT tick "Rewards": on a personal developer account it makes the app organisation-only, which is why the owner app was rejected once. |
| Health | No health features |
| News | No |
| Advertising ID | No (the app doesn't use it) |
| Foreground service / exact alarms | None |
| Photo and video permissions | Uses the system photo picker (image_picker); no broad media permission |

## 7. Testing before production

A new app on a personal account needs **its own** closed test: at least **12 testers opted in for 14 days**, even though the owner app already did one. Use the same **BizHub testers** email list (13 people) on the Alpha track and send them the BizHub POS opt-in link.
