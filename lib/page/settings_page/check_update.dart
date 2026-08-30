import 'dart:async';

import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/src/rust/api/utils.dart';
import 'package:coriander_player/update/update_controller.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:material_symbols_icons/symbols.dart';

class CheckForUpdate extends StatefulWidget {
  const CheckForUpdate({super.key, this.controller});

  final UpdateControllerView? controller;

  @override
  State<CheckForUpdate> createState() => _CheckForUpdateState();
}

class _CheckForUpdateState extends State<CheckForUpdate> {
  late final UpdateControllerView _controller;
  UpdateController? _ownedController;
  late UpdateState _state;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    final providedController = widget.controller;
    if (providedController == null) {
      _ownedController = UpdateController.production();
      _controller = _ownedController!;
    } else {
      _controller = providedController;
    }
    _state = _controller.state;
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _ownedController?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {
      _state = _controller.state;
      if (_state is UpdateAvailable) _dismissed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = _state is UpdateChecking ||
        _state is UpdateDownloading ||
        _state is UpdateVerifying ||
        _state is UpdatePreparingInstall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FilledButton.icon(
              key: const Key('check-update-button'),
              icon: const Icon(Symbols.update),
              label: const Text('检查更新'),
              onPressed: busy ? null : () => unawaited(_controller.check()),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('当前版本：${AppSettings.version}'),
            ),
            if (_state is UpdateChecking)
              const SizedBox(
                width: 16.0,
                height: 16.0,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (!_dismissed) _buildStateView(context),
      ],
    );
  }

  Widget _buildStateView(BuildContext context) {
    final state = _state;
    return switch (state) {
      UpdateIdle() || UpdateChecking() || UpdateCurrent() =>
        _buildPassiveState(state),
      UpdateAvailable() => _buildAvailable(context, state),
      UpdateDownloading() => _buildDownloading(state),
      UpdateVerifying() => _buildMessage('正在校验安装包…'),
      UpdatePreparingInstall() => _buildMessage('正在准备安装…'),
      UpdateCancelled() => _buildMessage('已取消更新。'),
      UpdateFailed() => _buildFailed(context, state),
    };
  }

  Widget _buildPassiveState(UpdateState state) {
    if (state is UpdateCurrent) {
      return const Padding(
        padding: EdgeInsets.only(top: 8.0),
        child: Text('已是最新版本'),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildAvailable(BuildContext context, UpdateAvailable state) {
    final candidate = state.candidate;
    return Card(
      margin: const EdgeInsets.only(top: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              candidate.releaseName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (candidate.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 8.0),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: candidate.releaseNotes,
                    onTapLink: (text, href, title) {
                      final uri = href == null ? null : Uri.tryParse(href);
                      if (uri != null) unawaited(_openUri(uri));
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8.0),
            if (state.canAutoInstall)
              const Text('安装版可自动覆盖当前目录，安装完成后会重启播放器。')
            else
              const Text('当前为 Portable 版本，无法在原位置自动安装，请前往发布页面下载。'),
            const SizedBox(height: 12.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _dismissed = true),
                  child: const Text('暂不更新'),
                ),
                const SizedBox(width: 8.0),
                if (state.canAutoInstall)
                  FilledButton(
                    key: const Key('install-update-button'),
                    onPressed: () => unawaited(_controller.install()),
                    child: const Text('立即更新'),
                  )
                else
                  OutlinedButton.icon(
                    key: const Key('open-update-release-button'),
                    onPressed: () =>
                        unawaited(_openUri(candidate.releasePageUri)),
                    icon: const Icon(Symbols.open_in_new),
                    label: const Text('下载新版本'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloading(UpdateDownloading state) {
    final progress = state.progress;
    final fraction = progress.fraction;
    final percent = fraction == null
        ? null
        : '${(fraction.clamp(0, 1) * 100).round()}%';
    return Card(
      margin: const EdgeInsets.only(top: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              key: const Key('update-download-progress'),
              value: fraction,
            ),
            const SizedBox(height: 8.0),
            Text(percent == null ? '正在下载更新…' : '正在下载更新… $percent'),
            const SizedBox(height: 8.0),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('cancel-update-download-button'),
                onPressed: _controller.cancelDownload,
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Text(message),
    );
  }

  Widget _buildFailed(BuildContext context, UpdateFailed state) {
    return Card(
      margin: const EdgeInsets.only(top: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (state.releasePageUri != null)
                  TextButton(
                    key: const Key('open-update-release-button'),
                    onPressed: () =>
                        unawaited(_openUri(state.releasePageUri!)),
                    child: const Text('打开发布页面'),
                  ),
                if (state.canRetry)
                  FilledButton(
                    key: const Key('retry-update-button'),
                    onPressed: () => unawaited(_controller.check()),
                    child: const Text('重试'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUri(Uri uri) async {
    if (uri.scheme != 'https' && uri.scheme != 'http') return;
    try {
      final opened = await launchInBrowser(uri: uri.toString());
      if (!opened && mounted) showTextOnSnackBar('无法打开发布页面');
    } catch (error, stackTrace) {
      LOGGER.e(error, stackTrace: stackTrace);
      if (mounted) showTextOnSnackBar('无法打开发布页面');
    }
  }
}
