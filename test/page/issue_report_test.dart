import 'package:coriander_player/page/settings_page/issue_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a prefilled issue URL for the fork', () {
    final uri = buildIssueReportUri(
      title: '歌词搜索异常',
      description: '输入周杰伦后没有结果',
      log: 'line 1\nline 2',
    );

    expect(uri.host, 'github.com');
    expect(uri.path, '/Kalincc/coriander_player/issues/new');
    expect(uri.queryParameters['title'], '歌词搜索异常');
    expect(uri.queryParameters['body'], contains('## 描述'));
    expect(uri.queryParameters['body'], contains('输入周杰伦后没有结果'));
    expect(uri.queryParameters['body'], contains('```\nline 1\nline 2\n```'));
  });
}
