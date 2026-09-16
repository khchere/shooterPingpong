// 음성 인식 문장에서 선수 이름을 찾는다.
// 오인식("현찰", "형철" → 김현철)에 대비해 한글을 자모(초성·중성·종성)로 풀어
// 가장 비슷한 이름을 고른다. 이름 수가 적다는 전제(수십 명 이하).
class NameMatcher {
  /// 이름 두 글자 기준 허용 자모 오차 (6개 중 2개까지 달라도 인정)
  static const _maxMismatch2 = 2;
  /// 세 글자(성 포함) 기준 허용 자모 오차
  static const _maxMismatch3 = 3;

  /// [text]에 등장한 순서대로 선수 이름 반환 (중복 없음).
  /// 정확히 일치하는 이름을 우선하고, 없으면 자모 유사도로 가장 가까운 이름을 고른다.
  static List<String> match(String text, List<String> names) {
    // 한글 음절만 남김 (조사·구분어는 유사도가 낮아 자연히 걸러짐)
    final syllables = text.runes
        .where((r) => r >= 0xAC00 && r <= 0xD7A3)
        .map((r) => String.fromCharCode(r))
        .toList();
    if (syllables.isEmpty) return [];

    // 후보: (선수, 문장 내 위치, 길이, 오차)
    final candidates = <({String name, int pos, int len, int mismatch})>[];
    for (final name in names) {
      final variants = <String>{name};
      if (name.length >= 3) variants.add(name.substring(name.length - 2));
      for (final v in variants) {
        final len = v.length;
        final allowed = len >= 3 ? _maxMismatch3 : _maxMismatch2;
        for (var pos = 0; pos + len <= syllables.length; pos++) {
          final window = syllables.sublist(pos, pos + len).join();
          final mismatch = _jamoMismatch(window, v);
          if (mismatch <= allowed) {
            candidates.add(
                (name: name, pos: pos, len: len, mismatch: mismatch));
          }
        }
      }
    }

    // 오차 적은 순(같으면 긴 매칭 우선)으로 확정하되, 같은 선수·겹치는 구간은 제외
    candidates.sort((a, b) {
      final c = a.mismatch.compareTo(b.mismatch);
      if (c != 0) return c;
      return b.len.compareTo(a.len);
    });
    final accepted = <({String name, int pos, int len, int mismatch})>[];
    for (final c in candidates) {
      if (accepted.any((a) => a.name == c.name)) continue;
      final overlaps = accepted.any(
          (a) => c.pos < a.pos + a.len && a.pos < c.pos + c.len);
      if (overlaps) continue;
      accepted.add(c);
    }
    accepted.sort((a, b) => a.pos.compareTo(b.pos));
    return [for (final a in accepted) a.name];
  }

  /// 같은 길이의 두 한글 문자열을 자모로 비교해 다른 자모 개수 반환
  static int _jamoMismatch(String a, String b) {
    var mismatch = 0;
    for (var i = 0; i < a.length; i++) {
      final ja = _jamo(a.codeUnitAt(i));
      final jb = _jamo(b.codeUnitAt(i));
      for (var k = 0; k < 3; k++) {
        if (!_similar(k, ja[k], jb[k])) mismatch++;
      }
    }
    return mismatch;
  }

  /// 음절 → [초성, 중성, 종성] 인덱스 (한글이 아니면 -1)
  static List<int> _jamo(int code) {
    if (code < 0xAC00 || code > 0xD7A3) return [-1, -1, -1];
    final n = code - 0xAC00;
    return [n ~/ (21 * 28), (n % (21 * 28)) ~/ 28, n % 28];
  }

  /// 발음이 비슷해 오인식되기 쉬운 자모는 같은 것으로 취급
  static bool _similar(int kind, int x, int y) {
    if (x == y) return true;
    if (kind == 1) {
      // 중성: ㅐ/ㅔ, ㅒ/ㅖ, ㅚ/ㅙ/ㅞ
      const groups = [
        {1, 5},
        {3, 7},
        {11, 10, 15},
      ];
      return groups.any((g) => g.contains(x) && g.contains(y));
    }
    return false;
  }
}
