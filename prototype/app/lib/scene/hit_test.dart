import 'labels.dart';
import 'layout.dart';
import 'levels.dart';
import 'paint/bands.dart' show BandLayer;
import 'scene.dart';
import 'viewport.dart';

// 선택 판정. 그린 것과 같은 목록(같은 판의 이름 자리 · 같은 타일)에서, 그릴 때와 같은 셈으로 자리를 구한다.
// 자리는 모두 배치 px(100% 배율)이다 — 돋보기가 켜져 있으면 부르는 쪽이 화면 px을 배율로 나눠 준다.
//
// 한곳으로 모은다: 층마다 제 맞히기 함수를 두되, 겹칠 때의 차례는 여기가 정한다(지금 연표의 쌓임 순서 그대로).
//   표식 · 단추 → 사건(점 · 이름 · 알약) → 기간 막대 · 구슬 → 인물 막대 → 이름표 → 칸 → 띠 · 탭
// 다른 층의 파일을 불러오지 않으려고 [HitSources]의 함수 밭으로 받는다 — 총괄이 층의 함수를 [Hit]으로 바꿔 끼운다.

enum HitKind {
  none,
  event,
  pill,

  /// 띠(정권 · 문화 · 기관 …)와 그 아래 탭.
  band,

  /// 띠 안의 칸(왕조 · 지도자 · 내각 · 기관 · 시기 · 지위 · 예속)과 날짜 칸.
  cell,

  /// 인물의 활동 막대 · 속국 이름표와 구역 탭.
  figure,
  hang,

  /// 소속 펼치기 단추 `▸ n` · 할거 모아 보기 단추 · 매달린 속국 접기 단추 `▾ 속국 n`(줄은 [Hit.row]).
  memberButton,
  scopeButton,
  hangButton,

  /// 꼬리표 윗변의 플래그(리메이크 2부 — 접고 펴는 것을 모은 창을 연다 · 띠는 [Hit.bandId]).
  flag,

  /// 건국 · 멸망 네모.
  square,

  /// 승계선 · 소속선.
  link,
}

class Hit {
  const Hit(this.kind, {this.eventId = 0, this.row = -1, this.lo = 0, this.hi = 0, this.bandId = 0, this.itemId = 0, this.ref = '', this.count = 0});
  final HitKind kind;
  final int eventId, row;

  /// 알약이면 그 알약에 적힌 수(묶인 사건의 수). 묶음 카드의 머리글이 목록을 받기 전에도 수를 적을 수 있게 싣는다.
  /// 알약이 아니면 0이다.
  final int count;

  /// 그 항목이 매인 띠의 번호(띠 · 칸 · 인물 · 이름표 · 단추 · 네모 · 선). 없으면 0.
  final int bandId;

  /// 일반 구역(계약 6-4 · 6-7 · 6-10)의 항목 번호. 없으면 0.
  final int itemId;

  /// 칸의 참조 글자(`leader:3` · `era:2` …) — 칸이 아니면 빈 글.
  final String ref;

  /// 알약이면 그 통의 분 범위(양 끝 포함) — 이 범위로 사건 목록을 연다.
  final double lo, hi;
  static const none = Hit(HitKind.none);

  bool get isNone => kind == HitKind.none;
}

/// 다른 층이 내놓는 맞히기 함수들. 층마다 목록이라 한 층이 여럿을 걸 수도 있고, 비어 있으면 그 갈래는 건너뛴다.
/// 함수는 배치 px을 받아 제 것이 맞으면 [Hit]을, 아니면 null을 돌려준다.
typedef HitProbe = Hit? Function(double x, double y);

class HitSources {
  const HitSources({
    this.marks = const [],
    this.rails = const [],
    this.figures = const [],
    this.hangs = const [],
    this.cells = const [],
    this.bands = const [],
  });

  /// 맨 위에 그려지는 것: 건국 · 멸망 네모 · 문 · 소속/할거 단추 · 관계선.
  final List<HitProbe> marks;

  /// 기간 막대 · 구슬(구역 33~36). 비어 있으면 타일에서 바로 셈한 자리로 맞힌다.
  final List<HitProbe> rails;

  /// 인물의 활동 막대(구역 37 · 38).
  final List<HitProbe> figures;

  /// 띠에 매달린 속국 이름표 · 구역 탭(구역 16 · 17).
  final List<HitProbe> hangs;

  /// 띠 안의 칸과 날짜 칸.
  final List<HitProbe> cells;

  /// 띠와 책갈피 탭.
  final List<HitProbe> bands;

  bool get isEmpty => marks.isEmpty && rails.isEmpty && figures.isEmpty && hangs.isEmpty && cells.isEmpty && bands.isEmpty;
}

/// 글줄 가운데의 세로 자리(배치 px). 글줄 높이는 그 줄의 것을 쓴다 —
/// 조감은 글줄이 하나뿐이고 그 높이가 띠 전체라, 같은 식이 곧 띠의 세로 가운데가 된다(css 1804 · 명세 05 7.2).
/// [lift]는 두 장 꼬리표에서 칸 뭉치가 없는 띠의 사건 칸을 올리는 몫(paint/bands.dart [BandLayer.eventLiftOf]).
double lineCenter(SceneView v, SceneLayout layout, int row, int line, [double lift = 0]) {
  final geo = layout.geo(row);
  return v.yOf(layout.rowTop(row) + geo.textTop + (line + .5) * geo.lineH - lift);
}

/// 기간 막대 칸(구역 33~36 · paint/rails.dart)의 자리: 줄의 railTop + 3.5 + 단 × 7. 누를 때는 위아래 [barGrab]px까지 잡는다.
const railOffset = 3.5, railPitch = 7.0, barGrab = 5.0;

Hit hitTest(TimelineScene scene, double x, double y, {HitSources sources = const HitSources()}) {
  final v = scene.controller.view;
  if (x < v.left || y < v.head) return Hit.none;

  Hit? ask(List<HitProbe> probes) {
    for (final probe in probes) {
      final hit = probe(x, y);
      if (hit != null && !hit.isNone) return hit;
    }
    return null;
  }

  // 1) 표식 · 단추 · 관계선이 가장 위에 그려진다.
  final mark = ask(sources.marks);
  if (mark != null) return mark;

  // 2) 사건의 점 · 이름 · 알약.
  final event = hitEvents(scene, x, y);
  if (!event.isNone) return event;

  // 3) 기간 막대 · 구슬 — 그 층이 함수를 걸어 주면 그것을, 아니면 타일에서 바로 셈한다.
  final rail = ask(sources.rails) ?? hitRailsFromTile(scene, x, y);
  if (rail != null && !rail.isNone) return rail;

  // 4) 인물 막대 → 5) 이름표 · 구역 탭 → 6) 칸.
  for (final probes in [sources.figures, sources.hangs, sources.cells]) {
    final hit = ask(probes);
    if (hit != null) return hit;
  }

  // 7) 띠와 탭. 걸어 준 함수가 없으면 타일의 띠 상자로 맞힌다.
  final band = ask(sources.bands);
  if (band != null) return band;
  final id = bandAt(scene, x, y);
  return id == 0 ? Hit.none : Hit(HitKind.band, bandId: id, row: bandRowAt(scene, x, y));
}

/// 사건의 점 · 이름 · 개수 알약만 맞힌다(층의 공개 맞히기 함수).
Hit hitEvents(TimelineScene scene, double x, double y) {
  final v = scene.controller.view, layout = scene.layout;
  final batch = scene.labelBatch, out = scene.labelOutput;
  if (batch == null || out == null) return Hit.none;
  final bird = layout.bird;
  // 조감 모양 b · c에는 점 · 알약이 그려지지 않으니 잡히지도 않는다(명세 05 7.5).
  if (bird && !(layout.birdShape?.dots ?? true)) return Hit.none;
  final input = batch.input;
  final bucket = bucketMinutes(scene.level).toDouble();
  // 조감에서 띠 안 이름 · 단추에 가려 **그리지 않은** 점 · 알약은 잡히지도 않아야 한다(명세 05의 7-3).
  // 자리는 띠 층이 장면 곁에 적어 둔다 — 층의 함수를 받는 [HitSources]와 달리 값 하나뿐이라 여기서 바로 읽는다.
  final names = bird ? BandLayer.of(scene) : null;
  bool hiddenByName(int row, double x, double r) => names?.birdHides(row, x - r, x + r) ?? false;
  for (int i = 0; i < out.shownCount; i++) {
    final cand = out.shownCandidate[i], row = input.row[cand];
    if (row >= layout.rowCount || !layout.hasBody(row)) continue;
    final cy = lineCenter(v, layout, row, out.shownLine[i], BandLayer.of(scene)?.eventLiftOf(layout, row, input.band[cand]) ?? 0);
    // 잡는 높이는 그 줄의 글줄 절반 — 조감(글줄 하나 = 띠 전체)에서도 이웃 줄까지 잡히지 않는다.
    if ((y - cy).abs() > layout.geo(row).lineH / 2) continue;
    final look = input.look[cand], flags = out.shownFlags[i], side = out.shownSide[i];
    final small = bird || flags & LabelFlag.small != 0;
    final at = v.xOf(out.shownAt[i]);
    // 점은 그릴 때와 같은 자리에서 잡는다(`.tl-ev`의 translateX · padding-right가 만드는 어긋남 — 명세 8.3-1).
    final cx = at + EventLook.dotDx(look, side: side, small: small);
    if (hiddenByName(row, cx, EventLook.dotRadius(look, small))) continue;
    if ((x - cx).abs() <= EventLook.dotBox(look, small: small) / 2 + 2) {
      return Hit(HitKind.event, eventId: input.eventId[cand], row: row, bandId: input.band[cand]);
    }
    // 조감에는 사건 이름이 없다 — 조감 전에 셈한 옛 판이 잠시 남아도 그 이름을 맞히지 않는다(사건 층과 같은 조건).
    if (side == LabelSide.none || bird) continue;
    final run = batch.runOf(cand, at, side, flags);
    if (x >= run.left && x <= run.right) {
      return Hit(HitKind.event, eventId: input.eventId[cand], row: row, bandId: input.band[cand]);
    }
  }
  // 개수 알약: 누르면 그 묶음이 덮는 시간 범위로 사건 목록을 연다.
  for (int i = 0; i < out.clusters; i++) {
    final row = out.clusterRow[i];
    if (row >= layout.rowCount || !layout.hasBody(row)) continue;
    // 그린 자리와 같게 — 대표가 든 띠의 사건 칸을 올린 몫(paint/events.dart의 _cluster · 대표가 없으면 0).
    final pillLead = out.clusterLead[i];
    final pillLift = pillLead < 0 ? 0.0 : BandLayer.of(scene)?.eventLiftOf(layout, row, input.band[pillLead]) ?? 0.0;
    final cy = lineCenter(v, layout, row, out.clusterLine[i], pillLift), cx = v.xOf(out.clusterAt[i]);
    final height = bird || out.clusterFlags[i] & ClusterFlag.small != 0 ? LabelGeo.smallPillHeight : LabelGeo.pillHeight;
    if ((y - cy).abs() > height / 2 + 2 || (x - cx).abs() > out.clusterWidth[i] / 2) continue;
    // 조감에서 띠 안 이름 · 단추에 가려 그리지 않은 알약은 잡히지도 않는다 — 사건 층과 같은 조건으로, 띠 범위를 묻지 않는다
    // (타일 경계에서 잘린 띠의 묶음은 한쪽 끝이 ±무한이다 — paint/events.dart의 _cluster).
    if (hiddenByName(row, cx, out.clusterWidth[i] / 2)) continue;
    final lo = out.clusterLo[i], hi = out.clusterHi[i];
    final lead = out.clusterLead[i];
    // 통 하나가 통째로 한 묶음이면 통의 범위, 아니면 묶인 점이 덮는 범위.
    return Hit(
      HitKind.pill,
      row: row,
      lo: lo,
      hi: hi > lo ? hi : (lo / bucket).floorToDouble() * bucket + bucket - 1,
      bandId: lead >= 0 && lead < input.band.length ? input.band[lead] : 0,
      count: out.clusterCount[i],
    );
  }
  return Hit.none;
}

/// 기간 막대 위의 사건. 자리는 자료가 실어 준 단(rail 0~1비트)으로 — 그리는 쪽(rails.dart)과 같은 셈이다.
Hit? hitRailsFromTile(TimelineScene scene, double x, double y) {
  final v = scene.controller.view, layout = scene.layout;
  for (final d in scene.draw) {
    final t = d.tile;
    for (final i in t.barIndices) {
      final row = t.eventRow[i];
      if (row >= layout.rowCount || !layout.hasBody(row)) continue;
      final geo = layout.geo(row);
      if (geo.railTop < 0) continue;
      final cy = v.yOf(layout.rowTop(row) + geo.railTop + railOffset + (t.eventRail[i] & 3) * railPitch);
      if ((y - cy).abs() > barGrab) continue;
      if (x >= v.xOf(t.origin + t.eventX0[i]) - 2 && x <= v.xOf(t.origin + t.eventX1[i]) + 2) {
        return Hit(HitKind.event, eventId: t.eventId[i], row: row, bandId: t.eventBand[i]);
      }
    }
  }
  return null;
}

/// 커서 아래의 띠(없으면 0).
int bandAt(TimelineScene scene, double x, double y) => _bandUnder(scene, x, y).$1;

/// 커서 아래의 띠가 놓인 줄(없으면 -1).
int bandRowAt(TimelineScene scene, double x, double y) => _bandUnder(scene, x, y).$2;

(int, int) _bandUnder(TimelineScene scene, double x, double y) {
  final v = scene.controller.view, layout = scene.layout;
  if (x < v.left || y < v.head) return (0, -1);
  for (final d in scene.draw) {
    final t = d.tile;
    for (int i = 0; i < t.bandCount; i++) {
      final row = t.bandRow[i];
      if (row >= layout.rowCount || !layout.hasBody(row)) continue;
      final top = v.yOf(layout.rowTop(row) + layout.geo(row).bandTop);
      if (y < top || y > top + layout.geo(row).bandHeight) continue;
      if (x >= v.xOf(t.origin + t.bandX0[i]) && x <= v.xOf(t.origin + t.bandX1[i])) return (t.bandId[i], row);
    }
  }
  return (0, -1);
}
