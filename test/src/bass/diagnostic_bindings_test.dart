import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:coriander_player/src/bass/bass.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'diagnostic bindings preserve native float and non-consuming buffer query',
      () {
    (int, int, int)? queried;
    final cpu = ffi.NativeCallable<ffi.Float Function()>.isolateLocal(
        () => 12.5,
        exceptionalReturn: 0.0);
    final buffer = ffi.NativeCallable<
        DWORD Function(DWORD, ffi.Pointer<ffi.Void>, DWORD)>.isolateLocal(
      (int handle, ffi.Pointer<ffi.Void> pointer, int length) {
        queried = (handle, pointer.address, length);
        return 96000;
      },
      exceptionalReturn: 0xffffffff,
    );
    final bass = Bass.fromLookup(<T extends ffi.NativeType>(String symbol) {
      return switch (symbol) {
        'BASS_GetCPU' => cpu.nativeFunction.cast<T>(),
        'BASS_ChannelGetData' => buffer.nativeFunction.cast<T>(),
        _ => throw StateError(symbol),
      };
    });
    try {
      expect(bass.BASS_GetCPU(), 12.5);
      expect(bass.BASS_ChannelGetData(42, ffi.nullptr, 0), 96000);
      expect(queried, (42, 0, 0));
    } finally {
      cpu.close();
      buffer.close();
    }
  });

  final nativePath = Platform.environment['CORIANDER_BASS_DLL'];
  test('real BASS diagnostic exports work without opening an audio device', () {
    final library = ffi.DynamicLibrary.open(nativePath!);
    try {
      final bass = Bass(library);
      expect(bass.BASS_GetCPU(), greaterThanOrEqualTo(0));
      expect(bass.BASS_ChannelGetData(0, ffi.nullptr, 0), 0xffffffff);
      expect(bass.BASS_ErrorGetCode(), BASS_ERROR_HANDLE);
    } finally {
      library.close();
    }
  },
      skip: nativePath == null
          ? 'Set CORIANDER_BASS_DLL for native smoke test'
          : false);

  test('shared device initialization and teardown timing (no music played)',
      () {
    final library = ffi.DynamicLibrary.open(nativePath!);
    final bass = Bass(library);
    var initialized = false;
    try {
      final initWatch = Stopwatch()..start();
      initialized = bass.BASS_Init(
              1, 48000, BASS_DEVICE_REINIT, ffi.nullptr, ffi.nullptr) ==
          TRUE;
      initWatch.stop();
      expect(initialized, isTrue,
          reason: 'BASS error ${bass.BASS_ErrorGetCode()}');
      final freeWatch = Stopwatch()..start();
      expect(bass.BASS_Free(), TRUE);
      initialized = false;
      freeWatch.stop();
      // Timing evidence only, not a flaky machine-dependent latency assertion.
      // ignore: avoid_print
      print('Native shared device: init=${initWatch.elapsedMilliseconds}ms, '
          'free=${freeWatch.elapsedMilliseconds}ms');
    } finally {
      if (initialized) bass.BASS_Free();
      library.close();
    }
  },
      skip: nativePath == null ||
          Platform.environment['CORIANDER_TEST_AUDIO_DEVICE'] != '1');
}
