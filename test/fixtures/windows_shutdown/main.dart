import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// Deliberately has no player services, plugins, music files, or user data.
void main(List<String> arguments) {
  runApp(const SizedBox.shrink());
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await const MethodChannel('shutdown_probe').invokeMethod<void>(
      arguments.isEmpty ? 'quit' : arguments.single,
    );
  });
}
