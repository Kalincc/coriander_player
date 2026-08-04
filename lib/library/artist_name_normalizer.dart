import 'package:pinyin/pinyin.dart';

String normalizeArtistName(String rawName) {
  return ChineseHelper.convertToSimplifiedChinese(rawName);
}
