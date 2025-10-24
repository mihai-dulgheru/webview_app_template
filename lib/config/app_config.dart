/// Application configuration constants
class AppConfig {
  /// Application version
  /// This should match the version in pubspec.yaml
  static const String appVersion = '1.0.0';

  /// Application name displayed to the user
  static const String appName = 'WebView App Template';

  /// The initial URL the WebView will load.
  /// *** THIS IS THE MAIN CONFIGURATION POINT ***
  /// Change this URL to point to your web application.
  static const String baseUrl = 'https://flutter.dev'; // <-- CHANGE THIS URL

  /// The application ID used in Android and iOS configurations.
  /// Replace 'com.example.webviewapptemplate' with your desired package name.
  /// Make sure to update it in:
  /// - android/app/build.gradle (namespace and applicationId)
  /// - android/app/src/.../AndroidManifest.xml (package)
  /// - android/app/src/.../MainActivity.kt (package)
  /// - ios/Runner.xcodeproj/project.pbxproj (PRODUCT_BUNDLE_IDENTIFIER)
  /// - ios/Runner/Info.plist (CFBundleName) - Optional, often derived
  static const String appId = 'com.example.webviewapptemplate';
}
