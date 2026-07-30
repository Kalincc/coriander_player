import 'package:coriander_player/component/settings_tile.dart';
import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/page/settings_page/issue_report.dart';
import 'package:coriander_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:go_router/go_router.dart';
import 'package:coriander_player/app_paths.dart' as app_paths;

class CreateIssueTile extends StatelessWidget {
  const CreateIssueTile({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      description: "报告问题",
      action: FilledButton.icon(
        onPressed: () => context.push(app_paths.SETTINGS_ISSUE_PAGE),
        label: const Text("创建问题"),
        icon: const Icon(Symbols.help),
      ),
    );
  }
}

class SettingsIssuePage extends StatefulWidget {
  const SettingsIssuePage({super.key});

  @override
  State<SettingsIssuePage> createState() => _SettingsIssuePageState();
}

class _SettingsIssuePageState extends State<SettingsIssuePage> {
  final titleEditingController = TextEditingController();
  final descEditingController = TextEditingController();
  final logEditingController = TextEditingController();
  final submitBtnController = WidgetStatesController();

  Future<void> createIssue() async {
    submitBtnController.update(WidgetState.disabled, true);

    try {
      final uri = buildIssueReportUri(
        title: titleEditingController.text,
        description: descEditingController.text,
        log: logEditingController.text,
      );
      final opened = await launchInBrowser(uri: uri.toString());
      showTextOnSnackBar(opened ? "已在浏览器打开" : "无法打开浏览器");
    } catch (err, trace) {
      showTextOnSnackBar(err.toString());
      LOGGER.e(err, stackTrace: trace);
    } finally {
      submitBtnController.update(WidgetState.disabled, false);
    }
  }

  @override
  void initState() {
    super.initState();
    final logStrBuf = StringBuffer();
    for (final event in LOGGER_MEMORY.buffer) {
      for (var line in event.lines) {
        logStrBuf.writeln(line);
      }
    }
    logEditingController.text = logStrBuf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Focus(
                    onFocusChange: HotkeysHelper.onFocusChanges,
                    child: TextField(
                      controller: titleEditingController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: "标题",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: FilledButton(
                    statesController: submitBtnController,
                    onPressed: createIssue,
                    child: const Text("报告问题"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Focus(
                onFocusChange: HotkeysHelper.onFocusChanges,
                child: TextField(
                  controller: descEditingController,
                  textAlignVertical: const TextAlignVertical(y: -1),
                  expands: true,
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText: "描述",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Focus(
                onFocusChange: HotkeysHelper.onFocusChanges,
                child: TextField(
                  controller: logEditingController,
                  textAlignVertical: const TextAlignVertical(y: -1),
                  expands: true,
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText: "日志",
                    helperText: "你可以随意修改日志内容。",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const Padding(padding: EdgeInsets.only(bottom: 96.0))
          ],
        ),
      ),
    );
  }
}
