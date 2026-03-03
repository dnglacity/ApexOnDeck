// Stub implementation for non-web platforms.
// The web implementation in download_helper_web.dart uses dart:html.

void downloadCsvBytes(List<int> bytes, String fileName) {
  // No-op on non-web; callers handle mobile separately.
}
