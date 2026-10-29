import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:coriander_player/release_info.dart';
import 'package:coriander_player/update/update_downloader.dart';
import 'package:coriander_player/update/update_release.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects the exact installer hash', () {
    const manifest =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  other.exe\n'
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  Coriander.Player.1.5.1-kalin.10.Setup.exe\n';

    expect(
      expectedSha256(
        manifest,
        'Coriander.Player.1.5.1-kalin.10.Setup.exe',
      ),
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
  });

  test('downloads, reports progress, and verifies the installer', () async {
    final installerBytes = utf8.encode('installer payload');
    final installerName = 'Coriander.Player.1.5.1-kalin.10.Setup.exe';
    final installerHash = sha256.convert(installerBytes).toString();
    final server = await _startServer(
      checksum: '$installerHash  $installerName\n',
      installerBytes: installerBytes,
    );
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'coriander-update-test-',
    );
    addTearDown(() async {
      await server.close(force: true);
      await temporaryDirectory.delete(recursive: true);
    });

    final progress = <UpdateDownloadProgress>[];
    final result = await UpdateDownloader().downloadAndVerify(
      _candidate(server.port, installerName),
      temporaryDirectory,
      cancellation: UpdateCancellation(),
      onProgress: progress.add,
    );

    expect(await result.installer.readAsBytes(), installerBytes);
    expect(result.installLog.path, contains('.Install.log'));
    expect(progress.map((item) => item.phase),
        contains(UpdateDownloadPhase.downloading));
    expect(progress.last.phase, UpdateDownloadPhase.verifying);
    expect(
        progress
            .lastWhere((item) => item.phase == UpdateDownloadPhase.downloading)
            .fraction,
        1);
  });

  test('cleans the partial installer when the hash is wrong', () async {
    final installerName = 'Coriander.Player.1.5.1-kalin.10.Setup.exe';
    final server = await _startServer(
      checksum: '${'0' * 64}  $installerName\n',
      installerBytes: utf8.encode('installer payload'),
    );
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'coriander-update-test-',
    );
    addTearDown(() async {
      await server.close(force: true);
      await temporaryDirectory.delete(recursive: true);
    });

    await expectLater(
      UpdateDownloader().downloadAndVerify(
        _candidate(server.port, installerName),
        temporaryDirectory,
        cancellation: UpdateCancellation(),
        onProgress: (_) {},
      ),
      throwsA(isA<UpdateHashMismatchException>()),
    );
    expect(
      await File(
              '${temporaryDirectory.path}${Platform.pathSeparator}$installerName.part')
          .exists(),
      isFalse,
    );
    expect(
      await File(
              '${temporaryDirectory.path}${Platform.pathSeparator}$installerName')
          .exists(),
      isFalse,
    );
  });

  test('cancellation before download leaves no partial file', () async {
    final installerName = 'Coriander.Player.1.5.1-kalin.10.Setup.exe';
    final server = await _startServer(
      checksum: '${'a' * 64}  $installerName\n',
      installerBytes: utf8.encode('installer payload'),
    );
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'coriander-update-test-',
    );
    addTearDown(() async {
      await server.close(force: true);
      await temporaryDirectory.delete(recursive: true);
    });
    final cancellation = UpdateCancellation()..cancel();

    await expectLater(
      UpdateDownloader().downloadAndVerify(
        _candidate(server.port, installerName),
        temporaryDirectory,
        cancellation: cancellation,
        onProgress: (_) {},
      ),
      throwsA(isA<UpdateCancelledException>()),
    );
    expect(temporaryDirectory.listSync(), isEmpty);
  });

  test('reports HTTP errors as download failures', () async {
    final installerName = 'Coriander.Player.1.5.1-kalin.10.Setup.exe';
    final server = await _startServer(
      checksum: 'not used',
      installerBytes: const [],
      checksumStatus: HttpStatus.notFound,
    );
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'coriander-update-test-',
    );
    addTearDown(() async {
      await server.close(force: true);
      await temporaryDirectory.delete(recursive: true);
    });

    await expectLater(
      UpdateDownloader().downloadAndVerify(
        _candidate(server.port, installerName),
        temporaryDirectory,
        cancellation: UpdateCancellation(),
        onProgress: (_) {},
      ),
      throwsA(isA<UpdateDownloadException>()),
    );
  });

  test('network failures leave the temporary directory empty', () async {
    final installerName = 'Coriander.Player.1.5.1-kalin.10.Setup.exe';
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'coriander-update-test-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    await expectLater(
      UpdateDownloader().downloadAndVerify(
        _candidate(1, installerName),
        temporaryDirectory,
        cancellation: UpdateCancellation(),
        onProgress: (_) {},
      ),
      throwsA(isA<UpdateDownloadException>()),
    );
    expect(temporaryDirectory.listSync(), isEmpty);
  });

  for (final stallHeaders in [true, false]) {
    test(
        'cancel interrupts ${stallHeaders ? 'waiting for headers' : 'a stalled body'} and retry works',
        () async {
      const name = 'Coriander.Player.1.5.1-kalin.10.Setup.exe';
      final started = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var stall = true;
      server.listen((request) async {
        if (stall && (stallHeaders || request.uri.path != '/SHA256SUMS.txt')) {
          if (!stallHeaders) {
            request.response.bufferOutput = false;
            request.response.contentLength = 32768;
            request.response.add(List<int>.filled(16384, 1));
            await request.response.flush();
          }
          if (stallHeaders && !started.isCompleted) started.complete();
          return; // Intentionally keep the response open with no further data.
        }
        final bytes = utf8.encode('payload');
        request.response.write(request.uri.path == '/SHA256SUMS.txt'
            ? '${sha256.convert(bytes)}  $name\n'
            : 'payload');
        await request.response.close();
      });
      final directory =
          await Directory.systemTemp.createTemp('coriander-stall-');
      final downloader = UpdateDownloader();
      final cancellation = UpdateCancellation();
      final downloading = downloader.downloadAndVerify(
          _candidate(server.port, name), directory, cancellation: cancellation,
          onProgress: (progress) {
        if (!stallHeaders &&
            progress.receivedBytes > 0 &&
            !started.isCompleted) {
          started.complete();
        }
      });
      final outcome = downloading.then<Object>((value) => value,
          onError: (Object error, StackTrace _) => error);
      addTearDown(() async {
        cancellation.cancel();
        await outcome.timeout(const Duration(seconds: 1));
        await server.close(force: true);
        await directory.delete(recursive: true);
      });
      await started.future.timeout(const Duration(seconds: 3));
      cancellation.cancel();
      expect(await outcome.timeout(const Duration(milliseconds: 500)),
          isA<UpdateCancelledException>());
      expect(directory.listSync(), isEmpty);
      stall = false;
      final verified = await downloader.downloadAndVerify(
          _candidate(server.port, name), directory,
          cancellation: UpdateCancellation(), onProgress: (_) {});
      expect(await verified.installer.readAsString(), 'payload');
    });
  }

  for (final stallBody in [false, true]) {
    test(
        'stalled ${stallBody ? 'body' : 'headers'} times out and removes partial files',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (!stallBody) return;
        if (request.uri.path == '/SHA256SUMS.txt') {
          request.response.write('${'a' * 64}  Setup.exe\n');
          await request.response.close();
        } else {
          request.response.bufferOutput = false;
          request.response.contentLength = 32768;
          request.response.add(List<int>.filled(16384, 1));
          await request.response.flush();
        }
      });
      final directory =
          await Directory.systemTemp.createTemp('coriander-timeout-');
      addTearDown(() async {
        await server.close(force: true);
        await directory.delete(recursive: true);
      });
      await expectLater(
          UpdateDownloader(timeout: const Duration(milliseconds: 100))
              .downloadAndVerify(
                  _candidate(server.port, 'Setup.exe'), directory,
                  cancellation: UpdateCancellation(), onProgress: (_) {}),
          throwsA(isA<UpdateDownloadException>()));
      expect(directory.listSync(), isEmpty);
    });
  }
}

UpdateCandidate _candidate(int port, String installerName) {
  return UpdateCandidate(
    version: ForkReleaseVersion.parse('1.5.1-kalin.10'),
    releaseName: 'Coriander Player 1.5.1-kalin.10',
    releaseNotes: '',
    publishedAt: null,
    releasePageUri: Uri.parse(
        'https://github.com/Kalincc/coriander_player/releases/tag/v1.5.1-kalin.10'),
    installerFileName: installerName,
    installerUri: Uri.parse('http://127.0.0.1:$port/$installerName'),
    checksumUri: Uri.parse('http://127.0.0.1:$port/SHA256SUMS.txt'),
  );
}

Future<HttpServer> _startServer({
  required String checksum,
  required List<int> installerBytes,
  int checksumStatus = HttpStatus.ok,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == '/SHA256SUMS.txt') {
      request.response
        ..statusCode = checksumStatus
        ..headers.contentType = ContentType.text
        ..write(checksum);
      await request.response.close();
      return;
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentLength = installerBytes.length
      ..add(installerBytes);
    await request.response.close();
  });
  return server;
}
