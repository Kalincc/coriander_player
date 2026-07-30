import 'package:coriander_player/release_info.dart';

Uri buildIssueReportUri({
  required String title,
  required String description,
  required String log,
}) {
  final body = StringBuffer()
    ..writeln('## 描述')
    ..writeln(description)
    ..writeln()
    ..writeln('## 日志')
    ..writeln('```')
    ..writeln(log)
    ..writeln('```');

  return Uri.https(
    'github.com',
    '/$releaseRepositoryOwner/$releaseRepositoryName/issues/new',
    {'title': title, 'body': body.toString()},
  );
}
