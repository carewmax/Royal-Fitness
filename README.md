# Royal Fitness — Android app

The Royal Fitness website and member app, packaged as a real Android app (APK) with Capacitor.
GitHub builds the APK for you. No Android Studio needed.

## Get the APK

1. Create a new repository on GitHub, for example `royal-fitness-app`.
2. Unzip this package and upload **everything** inside it, including the `.github` folder.
   The `.github` folder is hidden on some computers. If you can't see it, turn on "show hidden files",
   or create the file on GitHub directly: **Add file → Create new file**, name it
   `.github/workflows/build-apk.yml`, and paste in the contents.
3. Open the **Actions** tab. The build "Build Android APK" starts by itself and takes about 5–8 minutes.
4. When it shows a green tick, open **Releases** (right side of the repository page).
   Download `RoyalFitness.apk` on an Android phone and install it.

Every time you upload a change, a new APK is built (v1.0.1, v1.0.2 …).
To rebuild without changes: **Actions → Build Android APK → Run workflow**.

## Change the app

| What | Where |
|---|---|
| The app itself (pages, prices, schedule, menu) | `www/index.html` → the `CONFIG`, `SCHEDULE`, `MENU` and `EQUIPMENT` sections near the top of the script |
| App icon and splash logo | `assets/logo.png` (1024 × 1024). Replace with the original high-resolution logo |
| App name / ID | `capacitor.config.json` |

## What this build is

- A debug-signed test APK: fine for installing on phones and showing the client. It cannot go to the Play Store.
- Data is stored on the phone only. Payments, SMS codes, AI analysis and wearables are demo states until the backend is connected.
- Camera permission is included for QR scanning, food photos and form-check videos.
