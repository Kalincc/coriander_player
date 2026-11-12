import 'package:coriander_player/page/page_scaffold.dart';
import 'package:coriander_player/page/settings_page/check_update.dart';
import 'package:coriander_player/page/settings_page/create_issue.dart';
import 'package:coriander_player/page/settings_page/other_settings.dart';
import 'package:coriander_player/page/settings_page/theme_settings.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: "设置",
      actions: const [],
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96.0),
        children: const [
          _Section('播放', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('播放快捷键'),
              subtitle: Text('空格：播放 / 暂停　 Ctrl + ← / →：上一首 / 下一首'),
            ),
          ]),
          _Section('歌词', [DefaultLyricSourceControl()]),
          _Section('外观', [
            DynamicThemeSwitch(),
            UseSystemThemeSwitch(),
            ThemeSelector(),
            UseSystemThemeModeSwitch(),
            ThemeModeControl(),
            SelectFontCombobox(),
          ]),
          _Section('音乐库', [LibrarySettings()]),
          _Section('存储与诊断', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('本地数据'),
              subtitle: Text('歌单、播放历史和索引保存在「文档」中的 coriander_player 文件夹。'),
            ),
            CreateIssueTile(),
          ]),
          _Section('更新', [CheckForUpdate()]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.settings);

  final String title;
  final List<Widget> settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  )),
              for (final setting in settings) ...[
                const SizedBox(height: 12),
                setting,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
