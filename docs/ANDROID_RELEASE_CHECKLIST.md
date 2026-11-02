# Android Release Checklist

Nothing has been uploaded or released.

## Facts (from `android/app/build.gradle.kts`, manifest, `pubspec.yaml`)
| Item | Value |
|---|---|
| Application id / namespace | `com.adani.canteen_adani` |
| Version | `1.0.5+6` from `pubspec.yaml` (name 1.0.5, code 6) – **bump the code before every upload** |
| minSdk / targetSdk | Flutter defaults (`flutter.minSdkVersion` / `flutter.targetSdkVersion`) |
| Signing | release config read from `android/key.properties`; build **fails** if the keystore is missing (no debug fallback) |
| Keystore | `android/upload-keystore.jks` and `key.properties` exist locally, git-ignored, never committed. **Back them up** (password manager + offline copy); losing the upload key blocks updates. |
| R8 / minify | not enabled |
| Label | FoodPrint |
| Permissions | INTERNET, CAMERA, READ_EXTERNAL_STORAGE (≤ SDK 32), BLUETOOTH + BLUETOOTH_ADMIN, ACCESS_FINE/COARSE_LOCATION (≤ SDK 30), BLUETOOTH_SCAN (neverForLocation), BLUETOOTH_CONNECT |

## Build
```powershell
flutter clean; flutter pub get
flutter build appbundle --release -t lib/main.dart
```
`-t lib/main.dart` is required in this environment; without it the build fails with "Error when reading '/main.dart'". Output: `build\app\outputs\bundle\release\app-release.aab`. Last build: 58.8 MB, SHA-256 `4267675B150F41FC0FA66874237A1378674A39D841930E551BE66BF0BFB1623C` (from `Get-FileHash`).

## Before upload (you)
1. Bump `version:` in `pubspec.yaml` (e.g. `1.0.6+7`).
2. Verify the signer: `keytool -printcert -jarfile build\app\outputs\bundle\release\app-release.aab` (keytool ships with Android Studio's JDK) – fingerprint must equal your upload key, not the debug key.
3. Install the **release** build on a real cashier phone and test: login, bill, print on the real printer, kill and reopen the app, Bluetooth off/on, deny/allow Nearby-devices permission, airplane mode (should show clear failure), day closing, Excel export/share.
4. Upload to an **internal testing** track first. Do not promote to production before step 3 passes on at least two devices.
5. Deploy Firestore stopgap rules **before** wide rollout, per the deployment checklist.

## Known toolchain warnings
Kotlin 2.1.0 (Flutter will require ≥ 2.2.20 soon); `share_plus` applies the Kotlin Gradle Plugin; `blue_thermal_printer` uses deprecated Java APIs. Builds still succeed; plan an upgrade in a separate change.
