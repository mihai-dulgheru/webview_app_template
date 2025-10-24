import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_app_template/config/app_config.dart';

/// Service class for handling file downloads initiated from the WebView.
class DownloadService {
  /// Initiates a file download. Handles regular URLs and Blob URLs.
  /// Includes retry logic for potentially transient network errors.
  static Future<void> downloadFile(
    BuildContext context,
    Uri url, {
    InAppWebViewController? webViewController,
    String? suggestedFilename, // Filename from content-disposition if available
    String? contentDisposition, // Raw content-disposition header
    int retryCount = 0,
    int maxRetries = 1, // Allow one retry by default
  }) async {
    try {
      // Show initial or retry message.
      if (retryCount == 0) {
        _showSnackBar(context, 'Starting download...', isSuccess: true);
      } else {
        _showSnackBar(
          context,
          'Retrying download... (Attempt ${retryCount + 1})',
          isSuccess: true,
        );
      }

      // Handle Blob URLs using JavaScript interaction.
      if (url.scheme == 'blob') {
        await _downloadBlobUrl(context, url, webViewController);
        return;
      }

      // Handle regular HTTP/HTTPS URLs (or other schemes if needed).
      // Note: Direct download logic for http/https is removed as InAppWebView handles
      // common cases via onDownloadStartRequest, which then calls this function.
      // If direct HTTP download is needed without relying on the WebView event,
      // it would be added here using a package like 'http' or 'dio'.
      // For this template, we assume downloads are triggered via WebView actions.

      // If we reach here for a non-blob URL, it might be an unhandled case.
      if (url.scheme != 'blob') {
        print(
          "DownloadService: Received non-blob URL: $url. Relying on WebView's default handling or onDownloadStartRequest.",
        );
        // Optionally, show a message or attempt direct download if necessary.
        // For now, let the WebView handle it or assume onDownloadStartRequest triggered it.
      }
    } catch (e) {
      // Check if the error is potentially retryable and if retries are left.
      if (retryCount < maxRetries && _isRetryableError(e)) {
        // Exponential backoff for retries.
        await Future.delayed(Duration(seconds: (retryCount + 1) * 2));
        if (context.mounted) {
          // Retry the download.
          return downloadFile(
            context,
            url,
            webViewController: webViewController,
            suggestedFilename: suggestedFilename,
            contentDisposition: contentDisposition,
            retryCount: retryCount + 1,
            maxRetries: maxRetries,
          );
        }
        return; // Stop if context is no longer mounted.
      }

      // Handle final failure after retries or for non-retryable errors.
      if (context.mounted) {
        _handleDownloadError(context, e, retryCount > 0);
      }
    }
  }

  /// Determines if an error suggests a transient network issue suitable for retrying.
  static bool _isRetryableError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    // Common network-related error messages.
    return errorStr.contains('timeout') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('connection reset') ||
        errorStr.contains('network is unreachable') ||
        errorStr.contains('socket') ||
        errorStr.contains('handshake') ||
        errorStr.contains('fail to fetch') || // Common JS fetch error
        errorStr.contains('fetch') ||
        errorStr.contains('network error') ||
        errorStr.contains('http error') ||
        errorStr.contains('host lookup') ||
        // Server-side errors that might be temporary.
        errorStr.contains('500') ||
        errorStr.contains('502') ||
        errorStr.contains('503') ||
        errorStr.contains('504');
  }

  /// Handles displaying specific error messages based on the exception.
  static void _handleDownloadError(
    BuildContext context,
    dynamic e,
    bool wasRetried,
  ) {
    String errorMessage;
    final errorString = e.toString();

    // Specific error mapping
    if (errorString.contains('No host')) {
      errorMessage =
          'Network Error: Cannot connect. Check internet connection.';
    } else if (errorString.contains('timeout')) {
      errorMessage = wasRetried
          ? 'Download timed out after retry. Please try again later.'
          : 'Download timed out. Retrying...'; // Initial timeout message implies retry
    } else if (errorString.contains('Invalid URL')) {
      errorMessage = 'Invalid download link: $errorString';
    } else if (errorString.contains('blob URL requires webViewController')) {
      errorMessage = 'Download Error: Cannot download this file type directly.';
    } else if (errorString.contains('Blob download failed:')) {
      // Extract the specific JS error if available
      final jsErrorMatch = RegExp(
        r'Blob download failed: (.*)',
      ).firstMatch(errorString);
      errorMessage =
          'Download Failed: ${jsErrorMatch?.group(1) ?? "Could not retrieve file data."}';
    } else if (errorString.toLowerCase().contains('fetch')) {
      errorMessage = wasRetried
          ? 'Download failed after retry. Please check connection or try again later.'
          : 'Download Failed: Could not fetch file. Retrying...';
    } else if (errorString.contains('404')) {
      errorMessage = 'Download Failed: File not found (404).';
    } else if (errorString.contains('403')) {
      errorMessage = 'Download Failed: Access denied (403).';
    } else if (errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503')) {
      errorMessage = wasRetried
          ? 'Server error after retry. Please try again later.'
          : 'Server error occurred. Retrying...';
    } else if (errorString.contains('permission denied')) {
      errorMessage =
          'Download Failed: Permission denied. Check storage permissions.';
    } else {
      errorMessage =
          'Download failed. Error: ${errorString.substring(0, min(errorString.length, 100))}'; // Truncate long errors
    }
    _showSnackBar(context, errorMessage, isSuccess: false);
  }

  /// Downloads content from a Blob URL by executing JavaScript in the WebView.
  static Future<void> _downloadBlobUrl(
    BuildContext context,
    Uri blobUrl,
    InAppWebViewController? webViewController,
  ) async {
    if (webViewController == null) {
      throw Exception(
        'Blob URL download requires an active webViewController.',
      );
    }

    try {
      // Unique ID for this download attempt to retrieve results from JS.
      final downloadId = 'blob_${DateTime.now().millisecondsSinceEpoch}';

      // JavaScript code to retrieve blob data as Base64.
      // It first checks the cache, then tries captured blob references,
      // and finally falls back to fetching via XHR or Fetch API.
      final javascript =
          '''
        (function() {
          const downloadId = '$downloadId';
          // Ensure a global object exists to store results.
          window.blobDownloadResults = window.blobDownloadResults || {};

          try {
            const blobUrl = '${blobUrl.toString()}';
            let blobData = null;
            let blob = null;
            let resultStatus = 'pending'; // To track the outcome

            // 1. Check our custom Base64 cache first.
            if (window.blobDataCache && window.blobDataCache.has(blobUrl)) {
              blobData = window.blobDataCache.get(blobUrl);
              window.blobDownloadResults[downloadId] = {
                success: true, data: blobData.data, type: blobData.type, size: blobData.size
              };
               console.log('Blob found in cache:', blobUrl);
              return 'cached_success';
            }

            // 2. Check captured blob references (if createObjectURL was overridden).
            if (window.capturedBlobs && window.capturedBlobs.has(blobUrl)) {
              blob = window.capturedBlobs.get(blobUrl);
               console.log('Blob found in capturedBlobs:', blobUrl);
            }

            // 3. If not found, try the last generated blob URL as a fallback.
            if (!blob && window.lastGeneratedBlobUrl === blobUrl && window.capturedBlobs && window.capturedBlobs.has(window.lastGeneratedBlobUrl)) {
                 blob = window.capturedBlobs.get(window.lastGeneratedBlobUrl);
                 console.log('Blob found using lastGeneratedBlobUrl:', blobUrl);
            }


            // 4. If we have a blob reference, convert it to Base64.
            if (blob) {
              resultStatus = 'processing_direct_blob';
              const reader = new FileReader();
              reader.onload = function(event) {
                try {
                  const result = event.target.result;
                  const base64Index = result.indexOf(',');
                  const base64Data = result.substring(base64Index + 1);
                  window.blobDownloadResults[downloadId] = {
                    success: true, data: base64Data, type: blob.type || 'application/octet-stream', size: blob.size
                  };
                   console.log('Direct blob processed successfully:', blobUrl);
                } catch (e) {
                   console.error('FileReader error (direct blob):', e);
                  window.blobDownloadResults[downloadId] = { success: false, error: 'FileReader error (direct): ' + e.message };
                }
              };
               reader.onerror = function(event) {
                 console.error('FileReader failed (direct blob):', event.target.error);
                 window.blobDownloadResults[downloadId] = { success: false, error: 'FileReader failed (direct)' };
               };
              reader.readAsDataURL(blob);
              return 'direct_blob_started';
            }

            // 5. If no blob reference, try fetching the blob URL content. Use Fetch API first.
             console.log('No direct blob found, attempting fetch:', blobUrl);
             resultStatus = 'fetching';
             fetch(blobUrl)
                .then(response => {
                    if (!response.ok) {
                        throw new Error('Fetch failed with status: ' + response.status);
                    }
                    return response.blob();
                })
                .then(fetchedBlob => {
                    resultStatus = 'processing_fetched_blob';
                    const reader = new FileReader();
                    reader.onload = function(event) {
                        try {
                            const result = event.target.result;
                            const base64Index = result.indexOf(',');
                            const base64Data = result.substring(base64Index + 1);
                            window.blobDownloadResults[downloadId] = {
                                success: true, data: base64Data, type: fetchedBlob.type || 'application/octet-stream', size: fetchedBlob.size
                            };
                             console.log('Fetched blob processed successfully:', blobUrl);
                        } catch (e) {
                           console.error('FileReader error (fetch):', e);
                           window.blobDownloadResults[downloadId] = { success: false, error: 'FileReader error (fetch): ' + e.message };
                        }
                    };
                    reader.onerror = function(event) {
                       console.error('FileReader failed (fetch):', event.target.error);
                       window.blobDownloadResults[downloadId] = { success: false, error: 'FileReader failed (fetch)' };
                    };
                    reader.readAsDataURL(fetchedBlob);
                })
                .catch(fetchError => {
                  // Fetch failed, potentially due to CORS or other issues. Log and set error.
                   console.error('Fetch API failed for blob URL:', blobUrl, fetchError);
                    window.blobDownloadResults[downloadId] = { success: false, error: 'Fetch failed: ' + fetchError.message };
                    // Optionally, could try XMLHttpRequest here as a fallback, but Fetch is generally preferred.
                });

             return 'fetch_started'; // Indicate that fetch attempt has begun.


          } catch (error) {
            // Catch synchronous errors during setup.
             console.error('General JavaScript error during blob download setup:', error);
            window.blobDownloadResults[downloadId] = { success: false, error: 'JS setup error: ' + error.message };
            return 'error_setup';
          }
        })();
      ''';

      // Execute the JavaScript.
      await webViewController.evaluateJavascript(source: javascript);

      // --- Poll for the result ---
      Map<String, dynamic>? result;
      int attempts = 0;
      const maxAttempts = 20; // Wait up to 20 seconds.
      const pollInterval = Duration(
        milliseconds: 500,
      ); // Check every 500ms initially
      const longPollInterval = Duration(
        seconds: 1,
      ); // Check every 1s after initial attempts

      while (attempts < maxAttempts) {
        // Use shorter interval for the first few seconds
        await Future.delayed(attempts < 6 ? pollInterval : longPollInterval);
        attempts++;

        try {
          final checkResult = await webViewController.evaluateJavascript(
            source:
                'window.blobDownloadResults && window.blobDownloadResults["$downloadId"]',
          );

          if (checkResult != null && checkResult is Map) {
            result = Map<String, dynamic>.from(checkResult);
            // console.log('Blob result received:', result); // Optional: Debug log
            break; // Exit loop once result is found.
          }
          // console.log('Polling attempt', attempts, ' - no result yet for', downloadId); // Optional: Debug log
        } catch (evalError) {
          // Handle potential errors during JS evaluation itself
          print("Error evaluating JS for blob result: $evalError");
          // Decide if this error is fatal or if polling should continue
          if (attempts >= maxAttempts) {
            throw Exception('Error fetching blob result from JS: $evalError');
          }
        }
      }

      // --- Cleanup JavaScript variable ---
      await webViewController.evaluateJavascript(
        source:
            'if (window.blobDownloadResults) { delete window.blobDownloadResults["$downloadId"]; }',
      );

      // --- Process Result ---
      if (result == null) {
        throw Exception(
          'Blob download timed out after ${maxAttempts * (longPollInterval.inSeconds)} seconds.',
        );
      }

      if (result['success'] == true) {
        final base64Data = result['data'] as String?;
        final mimeType =
            result['type'] as String? ?? 'application/octet-stream';
        final fileSize = (result['size'] as num?)?.toInt() ?? 0;

        if (base64Data != null && base64Data.isNotEmpty) {
          final bytes = base64Decode(base64Data);
          if (context.mounted) {
            // Save the decoded bytes to a file.
            await _saveBytesToFile(
              context,
              bytes,
              mimeType,
              fileSize,
              blobUrl.path,
            );
          }
        } else {
          throw Exception('Blob download succeeded but returned empty data.');
        }
      } else {
        final errorMessage = result['error'] ?? 'Unknown JavaScript error';
        throw Exception('Blob download failed: $errorMessage');
      }
    } catch (e) {
      // Catch errors from Flutter side (JS evaluation, timeout, etc.)
      throw Exception('Failed to download blob: $e');
    }
  }

  /// Saves the downloaded byte data to a file on the device.
  static Future<void> _saveBytesToFile(
    BuildContext context,
    Uint8List bytes,
    String? mimeType,
    int fileSize, [
    String? blobPathHint,
  ]) async {
    String fileName = _generateFileName(mimeType, bytes, blobPathHint);

    try {
      String namePart = fileName;
      String extPart = "";
      if (fileName.contains('.')) {
        namePart = fileName.substring(0, fileName.lastIndexOf('.'));
        extPart = fileName.substring(fileName.lastIndexOf('.') + 1);
      } else {
        // If no extension could be determined, use a default based on mime if possible
        extPart = _extensionFromMime(mimeType) ?? 'bin';
        fileName = '$namePart.$extPart'; // Update full filename
      }

      // Use file_saver package for cross-platform saving.
      final savedPath = await FileSaver.instance.saveAs(
        name: namePart, // Name without extension
        bytes: bytes,
        fileExtension: extPart, // Extension
        mimeType: _mapMimeTypeToEnum(mimeType),
      );

      if (context.mounted) {
        if (savedPath != null && savedPath.isNotEmpty) {
          String displayPath = "Saved"; // Default message
          if (Platform.isAndroid) {
            // Try to make the Android path more user-friendly
            displayPath = savedPath.replaceFirst(
              '/storage/emulated/0/',
              'Internal Storage > ',
            );
            if (displayPath.startsWith('/document/')) {
              // Handle paths from Storage Access Framework (SAF) if needed
              displayPath = "Saved via File Picker";
            }
          } else if (Platform.isIOS || Platform.isMacOS) {
            displayPath =
                "Saved via File Picker"; // iOS/macOS paths are less predictable
          }
          _showSnackBar(
            context,
            'Downloaded: $fileName\nLocation: $displayPath\nSize: ${_formatFileSize(bytes.lengthInBytes)}', // Use actual bytes length
            isSuccess: true,
          );
        } else {
          _showSnackBar(
            context,
            'Download cancelled or failed to save.',
            isSuccess: false,
          );
        }
      }
    } catch (e) {
      print("Error saving file: $e");
      if (context.mounted) {
        _handleDownloadError(context, e, false); // Show specific save error
      }
    }
  }

  /// Generates a filename based on MIME type, content, or timestamp.
  static String _generateFileName(
    String? mimeType,
    Uint8List? fileBytes, [
    String? blobPathHint,
  ]) {
    String? extension;

    // 1. Try to get extension from blobPathHint if it looks like a filename
    if (blobPathHint != null &&
        blobPathHint.contains('/') &&
        blobPathHint.contains('.')) {
      final lastSegment = blobPathHint.split('/').last;
      if (lastSegment.contains('.')) {
        final parts = lastSegment.split('.');
        if (parts.length > 1 &&
            parts.last.length <= 4 &&
            parts.last.isNotEmpty) {
          extension = '.${parts.last.toLowerCase()}';
        }
      }
    }

    // 2. If no extension yet, try detecting from file content (magic bytes).
    if (extension == null && fileBytes != null && fileBytes.isNotEmpty) {
      extension = _detectFileTypeFromContent(fileBytes);
    }

    // 3. If still no extension, derive from MIME type.
    if (extension == null && mimeType != null) {
      extension = _extensionFromMime(mimeType);
    }

    // 4. Default extension if none found.
    extension ??= '.bin';

    // Generate timestamp for uniqueness.
    final timestamp = DateTime.now();
    final dateStr =
        '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}-${timestamp.minute.toString().padLeft(2, '0')}-${timestamp.second.toString().padLeft(2, '0')}';

    // Construct filename: AppName_Date_Time.extension
    return '${AppConfig.appName.replaceAll(' ', '_')}_${dateStr}_$timeStr$extension';
  }

  /// Tries to determine a common file extension from a MIME type string.
  static String? _extensionFromMime(String? mimeType) {
    if (mimeType == null) return null;
    final lowerMime = mimeType.toLowerCase();

    // Common types mapping
    const mimeExtensionMap = {
      'application/pdf': '.pdf',
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'image/svg+xml': '.svg',
      'text/plain': '.txt',
      'text/csv': '.csv',
      'text/html': '.html',
      'application/zip': '.zip',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
          '.docx',
      'application/msword': '.doc',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
          '.xlsx',
      'application/vnd.ms-excel': '.xls',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation':
          '.pptx',
      'application/vnd.ms-powerpoint': '.ppt',
      'application/json': '.json',
      'application/xml': '.xml',
      'audio/mpeg': '.mp3',
      'audio/ogg': '.ogg',
      'video/mp4': '.mp4',
      'video/webm': '.webm',
      // Add more common types as needed
    };

    if (mimeExtensionMap.containsKey(lowerMime)) {
      return mimeExtensionMap[lowerMime];
    }

    // Fallback for generic types
    if (lowerMime.startsWith('image/')) return '.img'; // Generic image
    if (lowerMime.startsWith('audio/')) return '.audio'; // Generic audio
    if (lowerMime.startsWith('video/')) return '.video'; // Generic video
    if (lowerMime.startsWith('text/')) return '.txt'; // Generic text
    if (lowerMime.contains('octet-stream')) return '.bin'; // Binary data

    return null; // Cannot determine extension
  }

  /// Detects common file types based on the first few bytes (magic numbers).
  static String? _detectFileTypeFromContent(Uint8List bytes) {
    if (bytes.isEmpty) return null;

    // PDF Check (%PDF)
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return '.pdf';
    }
    // PNG Check (‰PNG)
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return '.png';
    }
    // JPEG Check (ÿØÿ)
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return '.jpg';
    }
    // GIF Check (GIF87a or GIF89a)
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61) {
      return '.gif';
    }
    // ZIP / Office Open XML Check (PK..)
    if (bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04) {
      // Could be .zip, .docx, .xlsx, .pptx - default to .zip for simplicity,
      // rely on MIME type or filename if available for specifics.
      return '.zip';
    }
    // Microsoft Office legacy formats Check (ÐÏà¡±...)
    if (bytes.length >= 8 &&
        bytes[0] == 0xD0 &&
        bytes[1] == 0xCF &&
        bytes[2] == 0x11 &&
        bytes[3] == 0xE0 &&
        bytes[4] == 0xA1 &&
        bytes[5] == 0xB1 &&
        bytes[6] == 0x1A &&
        bytes[7] == 0xE1) {
      // Could be .doc, .xls, .ppt
      return '.doc'; // Default guess for legacy MS Office
    }

    // Add more magic number checks if needed (e.g., MP3, MP4)

    return null; // Unknown based on content.
  }

  /// Formats file size in bytes into a human-readable string (B, KB, MB, GB).
  static String _formatFileSize(int bytes) {
    if (bytes < 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Maps a string MIME type to the `MimeType` enum used by `file_saver`.
  static MimeType _mapMimeTypeToEnum(String? mimeType) {
    if (mimeType == null) return MimeType.other;
    final lower = mimeType.toLowerCase();

    // Map common MIME types to the enum.
    if (lower.contains('pdf')) return MimeType.pdf;
    if (lower.contains('png')) return MimeType.png;
    if (lower.contains('jpeg') || lower.contains('jpg')) return MimeType.jpeg;
    if (lower.contains('gif')) return MimeType.gif;
    if (lower.contains('bmp')) return MimeType.bmp;
    if (lower.contains('webp')) return MimeType.webp;
    if (lower.contains('svg')) return MimeType.svg;
    if (lower.contains('aac')) return MimeType.aac;
    if (lower.contains('mp3') || lower.contains('mpeg')) return MimeType.mp3;
    if (lower.contains('mp4')) return MimeType.mp4Video;
    if (lower.contains('csv')) return MimeType.csv;
    if (lower.contains('zip')) return MimeType.zip;
    if (lower.contains('rar')) return MimeType.rar;
    if (lower.contains('text') || lower.contains('plain')) return MimeType.text;
    if (lower.contains('json')) return MimeType.json;
    if (lower.contains('xml')) return MimeType.xml;
    if (lower.contains('yaml') || lower.contains('yml')) return MimeType.yaml;
    if (lower.contains('msword') ||
        lower.contains(
          'vnd.openxmlformats-officedocument.wordprocessingml.document',
        )) {
      return MimeType.microsoftWord;
    }
    if (lower.contains('vnd.ms-excel') ||
        lower.contains(
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        )) {
      return MimeType.microsoftExcel;
    }
    if (lower.contains('vnd.ms-powerpoint') ||
        lower.contains(
          'vnd.openxmlformats-officedocument.presentationml.presentation',
        )) {
      return MimeType.microsoftPresentation;
    }

    // Default if no specific match.
    return MimeType.other;
  }

  /// Shows a SnackBar message to the user.
  static void _showSnackBar(
    BuildContext context,
    String message, {
    required bool isSuccess,
  }) {
    // Ensure context is still valid before showing SnackBar.
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            maxLines: 3, // Allow slightly longer messages
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: isSuccess
              ? Colors.green.shade700
              : Colors.red.shade700,
          duration: Duration(
            seconds: isSuccess ? 4 : 6,
          ), // Longer duration for errors
          behavior: SnackBarBehavior.floating, // Floating style
          margin: const EdgeInsets.all(10), // Add margin
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ), // Rounded corners
        ),
      );
    }
  }
}
