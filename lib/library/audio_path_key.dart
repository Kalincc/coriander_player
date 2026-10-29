import 'package:path/path.dart' as path;

/// A stable identity for Windows paths without changing the path used for I/O.
/// Legacy indexes may mix drive case, separators and extended-length prefixes.
String audioPathKey(String value) {
  var windowsPath = value.replaceAll('/', r'\');
  if (windowsPath.toUpperCase().startsWith(r'\\?\UNC\')) {
    windowsPath = r'\\' + windowsPath.substring(8);
  } else if (windowsPath.startsWith(r'\\?\') &&
      RegExp(r'^[a-zA-Z]:\\').hasMatch(windowsPath.substring(4))) {
    windowsPath = windowsPath.substring(4);
  }
  if (!RegExp(r'^[a-zA-Z]:\\').hasMatch(windowsPath) &&
      !windowsPath.startsWith(r'\\')) {
    return value;
  }
  // Match the scanner's ASCII case folding; preserve non-ASCII file names.
  return path.windows.normalize(windowsPath).replaceAllMapped(
        RegExp('[A-Z]'),
        (match) => match[0]!.toLowerCase(),
      );
}
