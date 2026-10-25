import 'text_paragraph.dart';

// 관점(lens) — 나라마다 제 이름(명세 06의 8-15 · 대조표 기능-10). 같은 사건 · 같은 띠를 어느 나라의 눈으로 부르는가만 바꾸고,
// **자료에는 닿지 않는다**: 줄 쌓기 · 타일 · 거르개 · 묶음의 개수는 그대로고 화면에 적는 글만 갈린다.
//
// 채우는 것은 총괄이다: 조회 `{"op":"lens_names","lens":"local"|"<트랙 번호 글>"}` →
// `{"events":{"<번호>":"이름"},"bands":{"<띠 번호>":"이름"}}`를 받아 [put]으로 갈아 끼운다.
// `SceneMarks.lens`가 바뀌면 다시 묻고, 답이 오면 [version]이 올라 이름 자리 셈이 다시 돈다.
//
// 읽는 곳: 사건 이름은 `label_batch.dart`(후보의 제목과 그 폭), 띠 이름은 `paint/bands.dart`(책갈피 탭 · 조감의 띠 안 이름).
// 장면의 밭을 늘리지 않으려고 곁에 매단다.

class LensTitles {
  static final _byScene = Expando<LensTitles>('관점의 이름');

  /// 그 장면의 것(없으면 만든다).
  static LensTitles of(Object scene) => _byScene[scene] ??= LensTitles();

  /// 사건 번호 → 그 관점에서 부르는 이름. 비어 있으면 자료의 이름 그대로다.
  Map<int, String> events = const {};

  /// 띠 번호 → 그 관점에서 부르는 이름.
  Map<int, String> bands = const {};

  /// 답이 바뀔 때마다 오른다. 읽는 쪽은 이 번호가 달라졌을 때 다시 셈한다
  /// (장면의 이름 자리 판 번호에도 이 값이 들어가야 한다 — `scene.dart`의 signature).
  int version = 0;

  bool get isEmpty => events.isEmpty && bands.isEmpty;

  /// 한 관점의 답을 통째로 갈아 끼운다. 같은 값이면 번호를 올리지 않는다(장면을 괜히 다시 그리지 않게).
  void put({Map<int, String>? events, Map<int, String>? bands}) {
    final nextEvents = events ?? const <int, String>{};
    final nextBands = bands ?? const <int, String>{};
    if (_same(this.events, nextEvents) && _same(this.bands, nextBands)) return;
    this.events = nextEvents;
    this.bands = nextBands;
    _widths.clear();
    version++;
  }

  /// 관점을 끄면(기본 이름으로 되돌리면) 부른다.
  void clear() => put();

  /// 그 사건을 이 관점에서 부르는 이름(없으면 null — 부르는 쪽이 자료의 이름을 쓴다).
  String? titleOf(int eventId) => events.isEmpty ? null : events[eventId];

  /// 그 띠를 이 관점에서 부르는 이름(없으면 null).
  String? bandTitleOf(int bandId) => bands.isEmpty ? null : bands[bandId];

  /// 관점 이름의 글자 폭. 자료의 이름은 타일에 걸어 두지만(`Tile.eventNameWidth`) 관점의 이름은 타일에 없으므로
  /// 여기에 건다 — 사건 · 글자 모양마다 한 번만 재고, [version]이 오르면 함께 버린다.
  /// [measure]가 폭을 모르면(글자가 아직 안 올라왔으면) NaN이 오고, 그 값은 걸어 두지 않는다.
  final _widths = <int, double>{};

  double widthOf(int eventId, String name, TextLook look, double Function(String, TextLook) measure) {
    final key = (eventId * 131) ^ ((look.size * 16).round() << 12) ^ look.shapeKey;
    final known = _widths[key];
    if (known != null) return known;
    final width = measure(name, look);
    if (width.isNaN) return width;
    return _widths[key] = width;
  }

  static bool _same(Map<int, String> a, Map<int, String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}
