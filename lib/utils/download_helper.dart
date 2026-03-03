// Conditional export: dart:html on web, no-op stub elsewhere.
export 'download_helper_stub.dart'
    if (dart.library.html) 'download_helper_web.dart';
