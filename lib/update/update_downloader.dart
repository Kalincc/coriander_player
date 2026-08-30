import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import 'update_release.dart';

enum UpdateDownloadPhase { downloading, verifying }

class UpdateDownloadProgress {
  const UpdateDownloadProgress({
    required this.phase,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final UpdateDownloadPhase phase;
  final int receivedBytes;
  final int? totalBytes;

  double? get fraction => totalBytes == null || totalBytes == 0
      ? null
      : receivedBytes / totalBytes!;
}

class UpdateCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class UpdateCancelledException implements Exception {
  const UpdateCancelledException();
}

class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message, {this.uri, this.cause});

  final String message;
  final Uri? uri;
  final Object? cause;

  @override
  String toString() => 'UpdateDownloadException: $message';
}

class UpdateHashMismatchException implements Exception {
  const UpdateHashMismatchException({
    required this.expected,
    required this.actual,
  });

  final String expected;
  final String actual;

  @override
  String toString() =>
      'UpdateHashMismatchException: expected $expected, got $actual';
}

class VerifiedUpdate {
  const VerifiedUpdate({required this.installer, required this.installLog});

  final File installer;
  final File installLog;
}

String expectedSha256(String manifest, String fileName) {
  final linePattern = RegExp(r'^([0-9a-fA-F]{64})\s+(.+?)\s*$');
  for (final line in manifest.split(RegExp(r'\r?\n'))) {
    final parsed = linePattern.firstMatch(line.trim());
    if (parsed == null) continue;

    var listedName = parsed.group(2)!.trim();
    if (listedName.startsWith('*')) {
      listedName = listedName.substring(1);
    }
    if (listedName == fileName) {
      return parsed.group(1)!.toLowerCase();
    }
  }
  throw FormatException('SHA256SUMS.txt does not contain $fileName');
}

Future<String> fileSha256(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString().toLowerCase();
}

class UpdateDownloader {
  UpdateDownloader({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<VerifiedUpdate> downloadAndVerify(
    UpdateCandidate candidate,
    Directory temporaryDirectory, {
    required UpdateCancellation cancellation,
    required void Function(UpdateDownloadProgress progress) onProgress,
  }) async {
    final installer = File(
      path.join(temporaryDirectory.path, candidate.installerFileName),
    );
    final partial = File('${installer.path}.part');
    final installLogName = candidate.installerFileName.replaceFirst(
      RegExp(r'\.Setup\.exe$'),
      '.Install.log',
    );
    final installLog = File(
      path.join(temporaryDirectory.path, installLogName),
    );
    var installerMoved = false;

    try {
      _throwIfCancelled(cancellation);
      await temporaryDirectory.create(recursive: true);

      final manifest = await _readText(
        candidate.checksumUri,
        cancellation,
      );
      late final String expectedHash;
      try {
        expectedHash = expectedSha256(manifest, candidate.installerFileName);
      } on FormatException catch (error, stackTrace) {
        Error.throwWithStackTrace(
          UpdateDownloadException(
            '校验文件中未找到安装包哈希。',
            uri: candidate.checksumUri,
            cause: error,
          ),
          stackTrace,
        );
      }

      await _downloadInstaller(
        candidate.installerUri,
        partial,
        cancellation,
        onProgress,
      );
      _throwIfCancelled(cancellation);

      await partial.rename(installer.path);
      installerMoved = true;

      final totalBytes = await installer.length();
      onProgress(
        UpdateDownloadProgress(
          phase: UpdateDownloadPhase.verifying,
          receivedBytes: 0,
          totalBytes: totalBytes,
        ),
      );
      final actualHash = await fileSha256(installer);
      _throwIfCancelled(cancellation);
      if (actualHash != expectedHash) {
        throw UpdateHashMismatchException(
          expected: expectedHash,
          actual: actualHash,
        );
      }
      onProgress(
        UpdateDownloadProgress(
          phase: UpdateDownloadPhase.verifying,
          receivedBytes: totalBytes,
          totalBytes: totalBytes,
        ),
      );

      return VerifiedUpdate(installer: installer, installLog: installLog);
    } catch (_) {
      await _deleteIfExists(partial);
      if (installerMoved) {
        await _deleteIfExists(installer);
      }
      rethrow;
    }
  }

  Future<String> _readText(
    Uri uri,
    UpdateCancellation cancellation,
  ) async {
    final response = await _openResponse(uri, cancellation);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw UpdateDownloadException(
        '下载校验文件失败（HTTP ${response.statusCode}）。',
        uri: uri,
      );
    }

    final bytes = <int>[];
    try {
      await for (final chunk in response) {
        _throwIfCancelled(cancellation);
        bytes.addAll(chunk);
      }
      _throwIfCancelled(cancellation);
      return utf8.decode(bytes);
    } catch (error, stackTrace) {
      if (error is UpdateCancelledException ||
          error is UpdateDownloadException) {
        rethrow;
      }
      Error.throwWithStackTrace(
        UpdateDownloadException('下载校验文件失败。', uri: uri, cause: error),
        stackTrace,
      );
    }
  }

  Future<void> _downloadInstaller(
    Uri uri,
    File partial,
    UpdateCancellation cancellation,
    void Function(UpdateDownloadProgress progress) onProgress,
  ) async {
    final response = await _openResponse(uri, cancellation);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw UpdateDownloadException(
        '下载安装包失败（HTTP ${response.statusCode}）。',
        uri: uri,
      );
    }

    final totalBytes = response.contentLength >= 0
        ? response.contentLength
        : null;
    var receivedBytes = 0;
    final sink = partial.openWrite();
    var sinkClosed = false;
    try {
      await for (final chunk in response) {
        _throwIfCancelled(cancellation);
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress(
          UpdateDownloadProgress(
            phase: UpdateDownloadPhase.downloading,
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ),
        );
      }
      _throwIfCancelled(cancellation);
      await sink.close();
      sinkClosed = true;
    } catch (error, stackTrace) {
      if (!sinkClosed) {
        await sink.close();
        sinkClosed = true;
      }
      if (error is UpdateCancelledException ||
          error is UpdateDownloadException) {
        rethrow;
      }
      Error.throwWithStackTrace(
        UpdateDownloadException('下载安装包失败。', uri: uri, cause: error),
        stackTrace,
      );
    } finally {
      if (!sinkClosed) {
        await sink.close();
      }
    }
  }

  Future<HttpClientResponse> _openResponse(
    Uri uri,
    UpdateCancellation cancellation,
  ) async {
    _throwIfCancelled(cancellation);
    try {
      final request = await _client.getUrl(uri);
      _throwIfCancelled(cancellation);
      final response = await request.close();
      _throwIfCancelled(cancellation);
      return response;
    } on UpdateCancelledException {
      rethrow;
    } on UpdateDownloadException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        UpdateDownloadException('连接更新服务器失败。', uri: uri, cause: error),
        stackTrace,
      );
    }
  }

  void _throwIfCancelled(UpdateCancellation cancellation) {
    if (cancellation.isCancelled) {
      throw const UpdateCancelledException();
    }
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
