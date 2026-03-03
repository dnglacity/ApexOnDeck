// Web implementation — only compiled when targeting Flutter web.
// Uses dart:html to trigger a browser file download via a Blob URL.
// dart:html is deprecated upstream in favour of package:web, but remains
// fully functional for Flutter web; we suppress the info to keep CI clean.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void downloadCsvBytes(List<int> bytes, String fileName) {
  final blob = html.Blob([bytes], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);
  // ignore: unused_local_variable
  final _ = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}
