/// An SVG image read from a local file path. A browser has no local files:
/// there the path is loaded as a URL.
export 'svg_file_picture_io.dart'
    if (dart.library.js_interop) 'svg_file_picture_web.dart';
