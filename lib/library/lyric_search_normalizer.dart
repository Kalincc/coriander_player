import 'package:pinyin/pinyin.dart';

List<String> lyricSearchFormsFor(String text) {
  final normalizedText = _normalize(text);
  final simplifiedText = _normalize(
    ChineseHelper.convertToSimplifiedChinese(normalizedText),
  );
  final spacedPinyin = _normalize(
    PinyinHelper.getPinyin(simplifiedText, separator: ' '),
  );
  final compactPinyin = spacedPinyin.replaceAll(' ', '');

  return {
    normalizedText,
    simplifiedText,
    spacedPinyin,
    compactPinyin,
  }.where((form) => form.isNotEmpty).toList();
}

bool lyricSearchMatches(String query, Iterable<String> indexedForms) {
  final queryForms = lyricSearchFormsFor(query);
  if (queryForms.isEmpty) {
    return false;
  }

  return queryForms.any(
    (queryForm) => indexedForms.any(
      (indexedForm) => _normalize(indexedForm).contains(queryForm),
    ),
  );
}

String _normalize(String text) => text.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
