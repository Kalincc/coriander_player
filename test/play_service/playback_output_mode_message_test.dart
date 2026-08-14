import 'package:coriander_player/play_service/playback_output_mode_message.dart';
import 'package:coriander_player/src/bass/output_mode_switch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('successful switches do not show an error message', () {
    expect(
      outputModeSwitchMessage(
        const OutputModeSwitchResult(actualExclusive: true),
      ),
      isNull,
    );
  });

  test('exclusive failures explain the shared fallback in Chinese', () {
    final expectedFragments = {
      ExclusiveFailureReason.unsupportedFormat: ['格式', '共享模式'],
      ExclusiveFailureReason.deviceUnavailable: ['音频设备', '共享模式'],
      ExclusiveFailureReason.initialization: ['独占模式', '共享模式'],
      ExclusiveFailureReason.recovery: ['恢复共享播放失败', '重新打开'],
    };

    for (final entry in expectedFragments.entries) {
      final message = outputModeSwitchMessage(
        OutputModeSwitchResult(
          actualExclusive: false,
          failureReason: entry.key,
        ),
      );
      expect(message, isNotNull);
      for (final fragment in entry.value) {
        expect(message, contains(fragment));
      }
      expect(message, isNot(contains('FormatException')));
      expect(message, isNot(contains('BASS')));
    }
  });
}
