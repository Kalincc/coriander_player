import 'package:flutter/material.dart';

abstract final class LyricScrollPositioner {
  static const duration = Duration(milliseconds: 300);
  static const curve = Curves.fastOutSlowIn;

  static Future<void> center(
    GlobalKey targetKey, {
    bool animate = true,
  }) async {
    final targetContext = targetKey.currentContext;
    if (targetContext == null || !targetContext.mounted) return;

    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.5,
      duration: animate ? duration : Duration.zero,
      curve: curve,
    );
  }
}
