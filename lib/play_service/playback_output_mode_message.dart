import 'package:coriander_player/src/bass/output_mode_switch.dart';

String? outputModeSwitchMessage(OutputModeSwitchResult result) {
  return switch (result.failureReason) {
    null => null,
    ExclusiveFailureReason.unsupportedFormat =>
      '当前歌曲的格式不受音频设备独占模式支持，已恢复共享模式播放。',
    ExclusiveFailureReason.deviceUnavailable => '音频设备暂时无法用于独占模式，已恢复共享模式播放。',
    ExclusiveFailureReason.initialization => '无法启动独占模式，已恢复共享模式播放。',
    ExclusiveFailureReason.recovery => '独占模式启动失败，恢复共享播放失败。请重新打开歌曲或音频设备。',
  };
}
