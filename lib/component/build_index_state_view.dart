import 'dart:async';
import 'dart:io';

import 'package:coriander_player/src/rust/api/tag_reader.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';

typedef BuildIndexStream = Stream<IndexActionState> Function({
  required List<String> folders,
  required String indexPath,
});

class BuildIndexStateView extends StatefulWidget {
  const BuildIndexStateView(
      {super.key,
      required this.indexPath,
      required this.folders,
      required this.whenIndexBuilt,
      this.buildIndex = buildIndexFromFoldersRecursively});

  final Directory indexPath;
  final List<String> folders;
  final void Function() whenIndexBuilt;
  final BuildIndexStream buildIndex;

  @override
  State<BuildIndexStateView> createState() => _BuildIndexStateViewState();
}

class _BuildIndexStateViewState extends State<BuildIndexStateView> {
  late final Stream<IndexActionState> buildIndexStream;
  StreamSubscription? _subscription;
  Object? _error;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    buildIndexStream = widget
        .buildIndex(
          folders: widget.folders,
          indexPath: widget.indexPath.path,
        )
        .asBroadcastStream();

    _subscription = buildIndexStream.listen(
      (action) {
        LOGGER.i("[build index] ${action.progress}: ${action.message}");
      },
      onError: (Object error, StackTrace trace) {
        LOGGER.e('[build index] $error', stackTrace: trace);
        _failed = true;
        _error = error;
        if (mounted) setState(() {});
      },
      onDone: () {
        if (!_failed) widget.whenIndexBuilt();
        _subscription?.cancel();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder(
      stream: buildIndexStream,
      builder: (context, snapshot) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            LinearProgressIndicator(
              value: snapshot.data?.progress,
              borderRadius: BorderRadius.circular(2.0),
            ),
            const SizedBox(height: 8.0),
            Text(
              _error == null ? "${snapshot.data?.message}" : '索引创建失败：$_error',
              style: TextStyle(color: scheme.onSurface),
            ),
          ],
        );
      },
    );
  }
}
