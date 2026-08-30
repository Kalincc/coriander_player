import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

String? readInnoInstallLocation(String subKeyPath) {
  final subKey = subKeyPath.toNativeUtf16();
  final valueName = 'InstallLocation'.toNativeUtf16();
  final byteCount = calloc<Uint32>();

  try {
    final sizeResult = RegGetValue(
      HKEY_CURRENT_USER,
      subKey,
      valueName,
      RRF_RT_REG_SZ,
      nullptr,
      nullptr,
      byteCount,
    );
    if (sizeResult != ERROR_SUCCESS || byteCount.value == 0) {
      return null;
    }

    final buffer = calloc<Uint8>(byteCount.value);
    try {
      final readResult = RegGetValue(
        HKEY_CURRENT_USER,
        subKey,
        valueName,
        RRF_RT_REG_SZ,
        nullptr,
        buffer,
        byteCount,
      );
      if (readResult != ERROR_SUCCESS) {
        return null;
      }
      return buffer.cast<Utf16>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  } finally {
    calloc.free(byteCount);
    calloc.free(valueName);
    calloc.free(subKey);
  }
}
