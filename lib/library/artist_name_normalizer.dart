import 'package:opencc/opencc.dart';

final _traditionalToSimplified = ZhConverter('t2s');

String normalizeArtistName(String rawName) {
  return _traditionalToSimplified.convert(rawName);
}
