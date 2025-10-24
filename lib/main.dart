import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_app_template/config/app_config.dart';
import 'package:webview_app_template/webview_screen.dart';

void main() async {
  // Ensure Flutter bindings are initialized.
  WidgetsFlutterBinding.ensureInitialized();

  // Run the application.
  runApp(const WebViewApp());
}

class WebViewApp extends StatelessWidget {
  const WebViewApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Set default status bar style.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF1976D2), // Example color, adjust as needed
        statusBarIconBrightness: Brightness.light,
      ),
    );

    return MaterialApp(
      // Use the app name from the configuration.
      title: AppConfig.appName,
      // Hide the debug banner in release builds.
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Define the primary color scheme.
        primarySwatch: Colors.blue,
        primaryColor: const Color(0xFF1976D2), // Example color
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1976D2), // Example color
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        // Ensure visual density adapts to the platform.
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // Set the initial screen of the app.
      home: const WebViewScreen(),
    );
  }
}
