# Flutter WebView App Template

A basic Flutter template for creating a mobile app that primarily displays a web application within a WebView.

## Overview

This app serves as a simple wrapper around a web application, providing a native mobile shell. Key features include:

- Loads a configurable URL in a full-screen WebView.
- Handles basic WebView interactions (navigation, loading states).
- Includes a simple file download handler for files initiated from the WebView (including basic Blob URL support).
- Sends custom headers and URL parameters to the web application to identify the mobile context.
- Injects JavaScript variables (window.isWebViewApp, window.webViewAppPlatform, window.webViewAppVersion) and dispatches a custom event (webViewAppReady) for the web app to detect the mobile environment.
- Includes configuration for generating native launcher icons and splash screens.
- Provides basic back-button handling (navigate back in WebView history, double-tap to exit).

## Configuration

The primary configuration points are:

1. `lib/config/app_config.dart`:

   - `baseUrl`: Change this constant to the URL of your web application.
   - `appName`: Set the name displayed to the user (e.g., in the app title).
   - `appVersion`: Define the application's version string (should match `pubspec.yaml`).
   - `appId`: Set your unique application identifier (e.g., `com.yourcompany.yourapp`). Remember to update this ID in the native Android and iOS project files as commented in `app_config.dart`.

2. `pubspec.yaml`:

   - Update `name`, `description`, and `version` to match your application.
   - Configure `flutter_launcher_icons` with your icon assets (`assets/icon/app_icon.png`, `assets/icon/app_icon_foreground.png`).
   - Configure `flutter_native_splash` with your splash screen assets (`assets/icon/splash_logo.png`) and desired colors.

3. Native Project Settings:
   - Android: Modify `android/app/build.gradle` (`namespace`, `applicationId`), `android/app/src/main/AndroidManifest.xml` (`android:label`), `android/app/src/main/kotlin/.../MainActivity.kt` (package name) if you change the `appId`.
   - iOS: Modify `ios/Runner.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER`), `ios/Runner/Info.plist` (`CFBundleName`, `CFBundleDisplayName`) if you change the `appId`.

## Mobile Detection in Web App

Your web application can detect if it's running inside this mobile app wrapper using the following:

### 1. URL Parameters

The initial URL loaded will include:

- `?mobile=true`
- `&platform=android` or `&platform=ios`

### 2. Custom HTTP Headers

Requests originating from the WebView will include:

- `User-Agent`: (e.g., "YourAppName Mobile App/Android (Flutter WebView)")
- `X-Mobile-App`: (Your app name from `AppConfig.appName`)
- `X-Platform`: `Android` or `iOS`
- `X-App-Version`: (Your app version from `AppConfig.appVersion`)

### 3. JavaScript Injection

The following are injected into the `window` object after the page loads:

```js
window.isWebViewApp = true;
window.webViewAppPlatform = "android" | "ios";
window.webViewAppVersion = "{version}"; // e.g., "1.0.0"

// Custom event dispatched when JS is injected
window.addEventListener("webViewAppReady", (event) => {
  console.log("WebView App Ready:", event.detail);
  // event.detail = { platform: "android" | "ios", version: "{version}" }
});
```

### 4. CSS Classes

The `<body>` element will have the following classes added:

- `webview-app`
- `webview-app-android` or `webview-app-ios`

You can use these signals in your web app's logic (JavaScript) and styling (CSS) to provide a tailored mobile experience.

## Building and Running

### Prerequisites

- Flutter SDK installed.
- Android Studio / Xcode setup for native builds.
- App icon (`assets/icon/app_icon.png`, `assets/icon/app_icon_foreground.png`) and splash screen logo (`assets/icon/splash_logo.png`) placed correctly.

### Generate Icons and Splash Screens

Run these commands after configuring `pubspec.yaml`:

```bash
flutter pub run flutter_launcher_icons
flutter pub run flutter_native_splash:create
```

### Run in Development

```bash
flutter run
```

### Build Release Version

```bash
# Android App Bundle (for Google Play)
flutter build appbundle --release

# Android APK
flutter build apk --release

# iOS App (requires macOS and Xcode setup)
flutter build ipa --release
```

## Project Structure

```text
webview_app_template/
├── android/          # Android native project
├── ios/              # iOS native project
├── lib/
│   ├── config/
│   │   └── app_config.dart # Main configuration file (URL, App Name, etc.)
│   ├── services/
│   │   └── download_service.dart # Handles file downloads
│   ├── main.dart       # App entry point
│   └── webview_screen.dart # Contains the WebView widget and logic
├── assets/
│   └── icon/         # Launcher icons and splash screen image source files
├── test/             # Unit and widget tests (optional)
├── analysis_options.yaml # Dart static analysis configuration
├── pubspec.yaml      # Project dependencies and metadata
└── README.md         # This file
```

## Notes

- This template uses `flutter_inappwebview` for its feature set.
- Error handling for WebView loading is basic; enhance as needed.
- File download handling covers common scenarios but might need adjustments based on specific server configurations or file types.
- No push notification, analytics, or crash reporting features are included. Integrate third-party services if required.
