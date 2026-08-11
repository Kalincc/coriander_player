import 'package:pinyin/pinyin.dart';

class CompiledLyricQuery {
  final List<String> forms;

  const CompiledLyricQuery._(this.forms);

  factory CompiledLyricQuery.compile(String query) =>
      CompiledLyricQuery._(_searchFormsFor(query));

  bool get isEmpty => forms.isEmpty;

  bool matches(Iterable<String> indexedForms) {
    if (isEmpty) return false;

    final normalizedIndexedForms = indexedForms.map(_normalize).toList();
    return forms.any(
      (queryForm) => normalizedIndexedForms.any(
        (indexedForm) => indexedForm.contains(queryForm),
      ),
    );
  }
}

List<String> lyricSearchFormsFor(String text) =>
    CompiledLyricQuery.compile(text).forms;

bool lyricSearchMatches(String query, Iterable<String> indexedForms) =>
    CompiledLyricQuery.compile(query).matches(indexedForms);

List<String> _searchFormsFor(String text) {
  final normalizedText = _normalize(text);
  final traditionalText = _normalize(
    ChineseHelper.convertToTraditionalChinese(normalizedText),
  );
  final simplifiedText = _normalize(
    ChineseHelper.convertToSimplifiedChinese(normalizedText),
  );
  final spacedPinyin = _normalize(
    PinyinHelper.getPinyin(simplifiedText, separator: ' '),
  );
  final compactPinyin = spacedPinyin.replaceAll(' ', '');

  return {
    traditionalText,
    normalizedText,
    simplifiedText,
    spacedPinyin,
    compactPinyin,
  }.where((form) => form.isNotEmpty).toList();
}

String _normalize(String text) => text.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
