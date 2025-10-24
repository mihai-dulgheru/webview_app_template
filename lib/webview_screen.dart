import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_app_template/config/app_config.dart';
import 'package:webview_app_template/services/download_service.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? webViewController;
  bool isLoading = true;
  String currentUrl = '';
  DateTime? lastBackPressed;

  @override
  void initState() {
    super.initState();
    _setNeutralStatusBar();
  }

  // Set status bar style for the webview screen.
  void _setNeutralStatusBar() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor:
            Colors.transparent, // Transparent for web content overlap
        statusBarIconBrightness:
            Brightness.dark, // Icons visible on light backgrounds
        statusBarBrightness: Brightness.light, // iOS status bar style
      ),
    );
  }

  @override
  void dispose() {
    // Clean up resources if needed when the widget is removed.
    super.dispose();
  }

  // Handle download requests initiated by the WebView.
  Future<void> _handleDownload(
    DownloadStartRequest downloadStartRequest,
  ) async {
    // Ensure the widget is still mounted before proceeding.
    if (!mounted) return;

    // Use the DownloadService to handle the file download.
    await DownloadService.downloadFile(
      context,
      downloadStartRequest.url,
      webViewController: webViewController,
    );
  }

  // Custom back button behavior for WebView navigation and app exit confirmation.
  Future<bool> _onWillPop() async {
    // Check if the WebView can navigate back.
    if (webViewController != null) {
      final canGoBack = await webViewController!.canGoBack();
      if (canGoBack) {
        // If WebView has history, navigate back within the WebView.
        await webViewController!.goBack();
        return false; // Prevent default back behavior (app exit).
      }
    }

    // Handle app exit confirmation (double-tap back).
    final now = DateTime.now();
    // Check if it's the first press or too much time has passed since the last press.
    if (lastBackPressed == null ||
        now.difference(lastBackPressed!) > const Duration(seconds: 2)) {
      lastBackPressed = now; // Record the time of the press.

      // Show a confirmation message to the user.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating, // Make it less intrusive.
          ),
        );
      }
      return false; // Prevent app exit on first press.
    }

    // If pressed again within 2 seconds, allow app exit.
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Use PopScope for finer control over back button behavior.
    return PopScope(
      canPop: false, // Disable default pop behavior.
      onPopInvokedWithResult: (didPop, result) async {
        // This callback is triggered when a pop is attempted.
        if (!didPop) {
          // Check our custom logic if the pop was prevented.
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) {
            // If custom logic allows popping, exit the app.
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        // Use SafeArea to avoid intrusions by OS UI (notches, status bars).
        body: SafeArea(
          child: Stack(
            children: [
              // The main WebView widget.
              InAppWebView(
                // Set the initial URL request using the configured base URL.
                initialUrlRequest: URLRequest(
                  url: WebUri(_buildUrlWithMobileHeaders()),
                  // Send custom headers to identify the mobile app.
                  headers: _getMobileHeaders(),
                ),
                // Configure WebView settings.
                initialSettings: InAppWebViewSettings(
                  useShouldOverrideUrlLoading:
                      true, // Allow URL loading interception.
                  mediaPlaybackRequiresUserGesture: false, // Allow autoplay.
                  allowsInlineMediaPlayback:
                      true, // Allow inline video playback.
                  iframeAllow: "camera; microphone", // Permissions for iframes.
                  iframeAllowFullscreen: true,
                  useHybridComposition:
                      true, // Recommended for Android performance.
                  supportZoom: false, // Disable pinch-to-zoom.
                  transparentBackground: true, // Allow transparent backgrounds.
                  // Performance and stability settings
                  cacheEnabled: true,
                  databaseEnabled: true,
                  domStorageEnabled: true,
                  // File access settings
                  allowFileAccessFromFileURLs: true,
                  allowUniversalAccessFromFileURLs: true,
                  // Security settings for mixed content (HTTP/HTTPS).
                  mixedContentMode:
                      MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
                  // Set a custom user agent string.
                  applicationNameForUserAgent:
                      '${AppConfig.appName}/${AppConfig.appVersion}',
                ),
                // Callback when the WebView is created.
                onWebViewCreated: (controller) {
                  webViewController = controller;
                },
                // Callback when page loading starts.
                onLoadStart: (controller, url) {
                  setState(() {
                    isLoading = true; // Show loading indicator.
                    currentUrl = url.toString();
                  });
                },
                // Callback when page loading finishes.
                onLoadStop: (controller, url) {
                  setState(() {
                    isLoading = false; // Hide loading indicator.
                    currentUrl = url.toString();
                  });
                  // Inject JavaScript for mobile detection after page loads.
                  _injectMobileDetectionScript();
                },
                // Callback for page loading errors.
                onReceivedError: (controller, request, error) {
                  setState(() {
                    isLoading = false; // Hide loading indicator on error.
                  });
                  // Log errors to console for debugging.
                  print(
                    "WebView Error: ${error.description} for ${request.url}",
                  );
                },
                // Handle permission requests (e.g., camera, microphone).
                onPermissionRequest: (controller, request) async {
                  // Grant all requested permissions automatically.
                  // Adjust this logic for more granular control if needed.
                  return PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.GRANT,
                  );
                },
                // Intercept URL loading requests (optional).
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  // Allow all navigation actions by default.
                  // Add logic here to block or handle specific URLs differently.
                  return NavigationActionPolicy.ALLOW;
                },
                // Callback for download requests.
                onDownloadStartRequest:
                    (controller, downloadStartRequest) async {
                      await _handleDownload(downloadStartRequest);
                    },
              ),
              // Show a loading indicator overlay while pages load.
              if (isLoading)
                const Center(
                  // Customize the indicator color.
                  child: CircularProgressIndicator(color: Color(0xFF1976D2)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Build the initial URL with mobile-specific query parameters.
  String _buildUrlWithMobileHeaders() {
    final uri = Uri.parse(AppConfig.baseUrl);
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters, // Keep existing parameters.
            'mobile': 'true', // Signal mobile app context.
            'platform': Platform.isAndroid
                ? 'android'
                : 'ios', // Signal platform.
          },
        )
        .toString();
  }

  // Define custom HTTP headers to send with requests.
  Map<String, String> _getMobileHeaders() {
    return {
      'User-Agent': _buildUserAgent(), // Custom User-Agent.
      'X-Mobile-App': AppConfig.appName, // App identifier.
      'X-Platform': Platform.isAndroid
          ? 'Android'
          : 'iOS', // Platform identifier.
      'X-App-Version': AppConfig.appVersion, // App version.
    };
  }

  // Construct a custom User-Agent string.
  String _buildUserAgent() {
    final platform = Platform.isAndroid ? 'Android' : 'iOS';
    // Example: "WebView App Template Mobile App/Android (Flutter WebView)"
    return '${AppConfig.appName} Mobile App/$platform (Flutter WebView)';
  }

  // Inject JavaScript into the loaded web page to signal mobile context.
  void _injectMobileDetectionScript() {
    webViewController?.evaluateJavascript(
      source:
          '''
      // Use a flag to prevent multiple injections on the same page load.
      if (!window.webViewAppTemplateInitialized) {
        window.webViewAppTemplateInitialized = true;

        // --- Core Mobile Detection Variables ---
        window.isWebViewApp = true; // Generic flag for any webview app based on this template
        window.webViewAppPlatform = '${Platform.isAndroid ? 'android' : 'ios'}';
        window.webViewAppVersion = '${AppConfig.appVersion}';

        // --- Download Helper Setup (for Blob URLs) ---
        // Store blob references keyed by their generated URL.
        window.capturedBlobs = new Map();
        // Keep track of the most recently created blob URL.
        window.lastGeneratedBlobUrl = null;
        // Cache blob data (Base64) immediately upon creation.
        window.blobDataCache = new Map();

        // --- Override URL.createObjectURL ---
        const originalCreateObjectURL = URL.createObjectURL;
        URL.createObjectURL = function(blob) {
          const url = originalCreateObjectURL.call(this, blob);
          window.lastGeneratedBlobUrl = url; // Update last generated URL
          window.capturedBlobs.set(url, blob); // Store blob reference

          // Convert blob to Base64 immediately and cache it.
          const reader = new FileReader();
          reader.onload = function(event) {
            try {
              const result = event.target.result;
              const base64Index = result.indexOf(',');
              const base64Data = result.substring(base64Index + 1);

              window.blobDataCache.set(url, {
                data: base64Data,
                type: blob.type || 'application/octet-stream',
                size: blob.size,
                timestamp: Date.now() // Track when it was cached
              });
              // console.log('Blob cached:', url, blob.type, blob.size);
            } catch (e) {
              console.error('Failed to cache blob data:', e);
            }
          };
           reader.onerror = function(event) {
             console.error('FileReader error during blob caching:', event.target.error);
           };
          reader.readAsDataURL(blob);

          // --- Cache Cleanup ---
          // Limit cache size to prevent memory issues.
          const MAX_CACHE_SIZE = 15;
          if (window.blobDataCache.size > MAX_CACHE_SIZE) {
            // Find the oldest entry based on timestamp.
            let oldestUrl = null;
            let oldestTimestamp = Infinity;
            for (const [key, value] of window.blobDataCache.entries()) {
              if (value.timestamp < oldestTimestamp) {
                oldestTimestamp = value.timestamp;
                oldestUrl = key;
              }
            }
            if (oldestUrl) {
              window.capturedBlobs.delete(oldestUrl);
              window.blobDataCache.delete(oldestUrl);
              // console.log('Cleaned oldest blob cache entry:', oldestUrl);
            }
          }

          return url;
        };

        // --- Override URL.revokeObjectURL ---
        const originalRevokeObjectURL = URL.revokeObjectURL;
        URL.revokeObjectURL = function(url) {
          // Remove from active blob reference map, but keep in cache for potential download.
          window.capturedBlobs.delete(url);
          // Don't immediately delete from blobDataCache, it might be needed for download.
          originalRevokeObjectURL.call(this, url);
        };

        // --- App Ready Event ---
        // Dispatch a custom event to notify the web application.
        window.dispatchEvent(new CustomEvent('webViewAppReady', {
          detail: {
            platform: window.webViewAppPlatform,
            version: window.webViewAppVersion,
          }
        }));
        console.log('WebViewApp Template Initialized: Platform=' + window.webViewAppPlatform + ', Version=' + window.webViewAppVersion);

        // --- Add CSS Classes ---
        // Add classes to the body for platform-specific styling if needed.
        document.body.classList.add('webview-app');
        document.body.classList.add('webview-app-' + window.webViewAppPlatform);
      }
    ''',
    );
  }
}
