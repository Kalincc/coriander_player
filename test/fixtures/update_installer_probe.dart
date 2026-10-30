// Harmless Windows child process: it never installs or changes the registry.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

// Reproduce Inno Setup's quote-toggle parser, not Dart/CRT's argv parser.
// https://github.com/jrsoftware/issrc/blob/main/Projects/Src/Shared.CommonFunc.pas
List<String> _innoArguments() {
  final getCommandLine = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<Pointer<Uint16> Function(), Pointer<Uint16> Function()>(
          'GetCommandLineW');
  final pointer = getCommandLine();
  var length = 0;
  while (pointer[length] != 0) {
    length++;
  }
  final raw = String.fromCharCodes(pointer.asTypedList(length));
  final result = <String>[];
  var index = 0;
  while (index < raw.length) {
    while (index < raw.length && raw.codeUnitAt(index) <= 32) {
      index++;
    }
    if (index == raw.length) break;
    final value = StringBuffer();
    var quoted = false;
    while (index < raw.length && (raw.codeUnitAt(index) > 32 || quoted)) {
      final character = raw[index++];
      if (character == '"') {
        quoted = !quoted;
      } else {
        value.write(character);
      }
    }
    result.add(value.toString());
  }
  return result;
}

Future<void> main(List<String> arguments) async {
  try {
    final parsed = _innoArguments();
    final logPath = parsed
        .singleWhere((value) => value.startsWith('/LOG='))
        .substring('/LOG='.length);
    if (arguments.contains('--exit-early')) {
      exit(7);
    }
    await File('$logPath.arguments.json').writeAsString(jsonEncode(parsed));
    await File(logPath).writeAsString('probe: startup log created');
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(seconds: 10) &&
        !await File('$logPath.stop').exists()) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  } catch (error) {
    stderr.writeln(error);
    exit(13);
  }
}
