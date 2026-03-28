# Onyx Project Analysis

Onyx delivers a distraction-free Instagram experience across three surfaces:

- **Chrome extension (Manifest v3)** that hides Reels, Explore, and sponsored posts and offers an in-page control panel.
- **Android app** that wraps Instagram in a hardened WebView with the same filters, desktop user-agent for calls, and notification interception.
- **iOS app** scaffolded via XcodeGen with light configuration for camera/microphone permissions and social networking category.

## Component breakdown

### Chrome extension (root files)
- `manifest.json` loads `content.js` at `document_start` on `instagram.com` and exposes `options.html` as the action popup.
- `content.js` stores settings in `chrome.storage.sync`, redirects away from `/reels` when blocking is enabled, injects CSS to hide Reels/Explore/ads (disabled inside DMs), and renders a floating ⚙︎ button plus modal panel to toggle features. A `MutationObserver` re-applies UI and styles when the DOM changes.
- `options.html` / `options.js` provide the popup toggles wired to the same stored settings.

### Android app (`android-app/`)
- Kotlin app targeting SDK 34 (min 24) with Java 17 and Material components.
- `MainActivity` configures a WebView with desktop UA, enables storage/media, injects the same filters and custom call lobby JS/CSS, and blocks Reels/Explore navigation according to shared preferences.
- Notification support: creates message/call channels, requests POST_NOTIFICATIONS on Tiramisu (Android 13+), and includes `InstagramNotificationListener` to intercept Instagram notifications. A settings screen exposes user controls.

### iOS app (`ios-app/`)
- XcodeGen project (`project.yml`) defining an unsigned iOS 15+ app bundle (`com.onyx.app`) with camera/microphone usage descriptions and social-networking category. Sources live under `ios-app/Sources/`.
- GitHub Actions workflow (`.github/workflows/ios_build.yml`) generates the project and produces an unsigned IPA artifact on pushes to the default branch.

## Build, run, and verification
- **Chrome extension:** Load the repo root as an unpacked extension in `chrome://extensions`, then visit instagram.com and use the floating ⚙︎ to toggle filters.
- **Android:** Open `android-app` in Android Studio or run `./gradlew assembleDebug` from that directory; install the debug APK from `app/build/outputs/apk/debug/`. Enable notification access for full functionality.
- **iOS:** Install XcodeGen, run `xcodegen generate` inside `ios-app`, then build/run in Xcode with your own signing. CI already builds an unsigned IPA.
- **Tests:** No automated tests or linters are present; verification is manual across the three surfaces.

## Notable observations and risks
- Filters rely on Instagram DOM/text selectors (including locale-specific strings like “Sponsored”/“Sponsorisé”); upstream UI changes or different locales may bypass the hides.
- The Android WebView injects sizeable CSS/JS and depends on MutationObserver; performance should be watched on low-end devices.
- No automated test coverage means regressions need manual validation during changes.
