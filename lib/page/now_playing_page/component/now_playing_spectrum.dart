import 'dart:async';
import 'dart:math' as math;

import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/src/bass/bass_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class SpectrumMenu extends StatelessWidget {
  const SpectrumMenu({
    super.key,
    required this.options,
    required this.exclusive,
    required this.onChanged,
  });

  final ValueListenable<SpectrumOptions> options;
  final ValueListenable<bool> exclusive;
  final ValueChanged<SpectrumOptions> onChanged;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([options, exclusive]),
        builder: (context, _) {
          final current = options.value;
          final enabled = !exclusive.value;
          return MenuAnchor(
            menuChildren: [
              for (final style in SpectrumStyle.values)
                MenuItemButton(
                  leadingIcon: Icon(
                      style == current.style ? Symbols.check : Symbols.circle),
                  onPressed: enabled
                      ? () => onChanged(
                          (style: style, particles: current.particles))
                      : null,
                  child: Semantics(
                      selected: style == current.style,
                      child: Text(style.label)),
                ),
              CheckboxMenuButton(
                value: current.particles,
                onChanged: enabled && current.style != SpectrumStyle.off
                    ? (checked) => onChanged(
                        (style: current.style, particles: checked == true))
                    : null,
                child: const Text('粒子效果'),
              ),
            ],
            builder: (context, controller, _) => IconButton(
              tooltip: enabled ? '频谱可视化' : '频谱可视化（仅共享模式）',
              isSelected: current.style != SpectrumStyle.off && enabled,
              onPressed: enabled
                  ? () =>
                      controller.isOpen ? controller.close() : controller.open()
                  : null,
              icon: const Icon(Symbols.equalizer),
              selectedIcon: Icon(Symbols.equalizer,
                  color: Theme.of(context).colorScheme.primary),
            ),
          );
        },
      );
}

class NowPlayingSpectrum extends StatelessWidget {
  const NowPlayingSpectrum({
    super.key,
    required this.options,
    required this.exclusive,
    required this.positions,
    required this.playerStates,
    required this.readSpectrum,
    required this.fallback,
  });

  final ValueListenable<SpectrumOptions> options;
  final ValueListenable<bool> exclusive;
  final Stream<double> positions;
  final Stream<PlayerState> playerStates;
  final double? Function(Float32List bins) readSpectrum;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([options, exclusive]),
        child: fallback,
        builder: (context, child) {
          final current = options.value;
          if (exclusive.value || current.style == SpectrumStyle.off) {
            return child!;
          }
          return _SpectrumSurface(
            options: current,
            positions: positions,
            playerStates: playerStates,
            readSpectrum: readSpectrum,
          );
        },
      );
}

class _SpectrumSurface extends StatefulWidget {
  const _SpectrumSurface({
    required this.options,
    required this.positions,
    required this.playerStates,
    required this.readSpectrum,
  });

  final SpectrumOptions options;
  final Stream<double> positions;
  final Stream<PlayerState> playerStates;
  final double? Function(Float32List bins) readSpectrum;

  @override
  State<_SpectrumSurface> createState() => _SpectrumSurfaceState();
}

class _SpectrumSurfaceState extends State<_SpectrumSurface>
    with WidgetsBindingObserver {
  final _bins = Float32List(BassPlayer.spectrumBinCount);
  final _motion = _SpectrumMotion();
  StreamSubscription<double>? _positions;
  StreamSubscription<PlayerState>? _playerStates;
  bool _pageVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageVisible =
        (ModalRoute.isCurrentOf(context) ?? true) && TickerMode.of(context);
    _watchPlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _watchPlayback();

  void _watchPlayback() {
    final state = WidgetsBinding.instance.lifecycleState;
    if (!_pageVisible ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _unsubscribe();
      _motion.clear();
      return;
    }
    // Reuse the player's existing 33 ms tick. No separate animation timer.
    _positions ??= widget.positions.listen((_) {
      final rate = widget.readSpectrum(_bins);
      if (rate == null) {
        _motion.clear();
      } else {
        _motion.update(_bins, rate);
      }
    });
    _playerStates ??= widget.playerStates.listen((state) {
      if (state != PlayerState.playing) _motion.clear();
    });
  }

  void _unsubscribe() {
    unawaited(_positions?.cancel());
    unawaited(_playerStates?.cancel());
    _positions = null;
    _playerStates = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unsubscribe();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ColoredBox(
        color: scheme.secondaryContainer,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _SpectrumPainter(
                _motion, widget.options, scheme.onSecondaryContainer),
            willChange: true,
          ),
        ),
      ),
    );
  }
}

class _SpectrumMotion extends ChangeNotifier {
  static const _bandCount = 48;
  final levels = Float32List(_bandCount);
  final _edges = Int32List(_bandCount + 1);
  double _rate = 0;
  int frame = 0;
  bool hasSignal = false;

  void update(Float32List bins, double rate) {
    if (_rate != rate) {
      _rate = rate;
      final binHz = rate / (2 * bins.length);
      final first = (45 / binHz).clamp(1.0, bins.length - 1.0);
      final end = (16000 / binHz + 1).clamp(first + 1, bins.length.toDouble());
      // Log-spaced bands keep most of the canvas useful on high-rate FLACs.
      for (var i = 0; i <= _bandCount; i++) {
        _edges[i] = (first * math.pow(end / first, i / _bandCount)).round();
      }
    }

    var active = false;
    for (var i = 0; i < _bandCount; i++) {
      final start = math.min(_edges[i], bins.length - 1);
      final end = math.max(start + 1, _edges[i + 1]);
      var peak = 0.0;
      for (var j = start; j < end; j++) {
        final bin = bins[j];
        if (bin.isFinite && bin > peak) peak = bin;
      }
      // Map -60 dB to silence; fast attack and slower decay reduce flicker.
      final target = peak <= 0.001
          ? 0.0
          : (1 + math.log(peak) / math.log(1000)).clamp(0.0, 1.0);
      final previous = levels[i];
      final level =
          previous + (target - previous) * (target > previous ? .7 : .25);
      levels[i] = level < .006 ? 0 : level;
      active |= levels[i] > 0;
    }
    if (active || hasSignal) {
      hasSignal = active;
      frame++;
      notifyListeners();
    }
  }

  void clear() {
    if (!hasSignal) return;
    levels.fillRange(0, levels.length, 0);
    hasSignal = false;
    notifyListeners();
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter(this.motion, this.options, this.ink)
      : super(repaint: motion);

  final _SpectrumMotion motion;
  final SpectrumOptions options;
  final Color ink;
  final _bar = Paint()..strokeCap = StrokeCap.round;
  final _reflection = Paint()..strokeCap = StrokeCap.round;
  final _particle = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (!motion.hasSignal || size.isEmpty) return;
    final levels = motion.levels;
    final circular = options.style == SpectrumStyle.circle;
    final mirror = options.style == SpectrumStyle.mirror;
    final center = Offset(size.width * .5, size.height * .47);
    final radius = size.shortestSide * .23;
    final step = size.width * .90 / levels.length;
    final baseline = size.height * (mirror ? .56 : .84);
    final maxLength =
        circular ? size.shortestSide * .18 : size.height * (mirror ? .30 : .54);
    _bar
      ..color = ink.withAlpha(78)
      ..strokeWidth = (circular ? radius * .10 : step * .56).clamp(1.0, 13.0);
    _reflection
      ..color = ink.withAlpha(31)
      ..strokeWidth = _bar.strokeWidth;

    for (var i = 0; i < levels.length; i++) {
      final level = levels[i];
      if (level == 0) continue;
      final angle = (i / levels.length - .25) * math.pi * 2;
      final direction = circular
          ? Offset(math.cos(angle), math.sin(angle))
          : const Offset(0, -1);
      final root = circular
          ? center + direction * radius
          : Offset(size.width * .05 + (i + .5) * step, baseline);
      final tip = root + direction * (maxLength * level);
      canvas.drawLine(root, tip, _bar);
      if (mirror) canvas.drawLine(root, root * 2 - tip, _reflection);

      if (options.particles && i.isEven && level > .07) {
        // At most 24 dots, drifting along the bar and fading out. No per-dot
        // timer, blur, or mutable particle pool.
        final age = (motion.frame * (.016 + (i % 5) * .004) + i * .137) % 1;
        final tangent = Offset(-direction.dy, direction.dx);
        final drift = size.shortestSide * (.025 + .045 * level) * age;
        final dot = tip + direction * drift + tangent * ((i % 3 - 1) * 9 * age);
        _particle.color = ink.withAlpha((148 * level * (1 - age)).round());
        canvas.drawCircle(
            dot, (1.3 + level * 1.8) * (1 - age * .45), _particle);
      }
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter oldDelegate) =>
      motion != oldDelegate.motion ||
      options != oldDelegate.options ||
      ink != oldDelegate.ink;
}
