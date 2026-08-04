import 'package:coriander_player/library/artist_name_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts Traditional Chinese to Simplified Chinese', () {
    expect(normalizeArtistName('張學友'), '张学友');
  });

  test('leaves Simplified, Latin, digits, and punctuation stable', () {
    expect(normalizeArtistName('张学友'), '张学友');
    expect(normalizeArtistName('YOASOBI (Live)'), 'YOASOBI (Live)');
    expect(normalizeArtistName('A1-测试'), 'A1-测试');
  });

  test('passes through unmapped characters unchanged', () {
    expect(normalizeArtistName('🎵'), '🎵');
  });
}
