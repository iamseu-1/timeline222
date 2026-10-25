import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../color_mix.dart';
import '../emphasis.dart' as em;
import '../label_batch.dart';
import '../labels.dart';
import '../layout.dart';
import '../marks.dart';
import '../text_paragraph.dart';
import '../tile.dart';
import '../viewport.dart';
import 'bands.dart' show BandLayer;
import 'context.dart';
import 'look.dart';
import 'patterns.dart';

// 사건: 글줄 안내선 · 점(보통 · 빈 점 · 점선 빈 점 · 마름모 · 동전 겹침) · 이름 · 이름 옆 연도 · 하위 수 알약 · 개수 알약(자리 선 · 눈금 · 분류 색줄) · 정밀도 괄호.
// 자리는 뒤의 작업자가 계산한 마지막 판(labels.dart)을 쓴다 — 분에 매여 있어 옆으로 움직여도 그대로다.
// 값은 모두 명세 docs/명세-3단계/02-사건의-표현.md(2절 점 · 3절 이름 · 5절 개수 알약)와 기준 덤프의 숫자다.
// 항목마다 canvas를 부르지 않는다: 둥근 것은 제 그림판([EventSprites])의 조각, 네모 · 선은 c.quads, 글자는 c.later에 모아 한 번에 낸다.

/// 강조에 든 것의 색(css `--warn: #d49a45`) — 사건 이름 아래의 1.5px 밑줄.
const _warn = 0xff000000;

class EventLayer extends SceneLayer {
  final _sprites = EventSprites();
  ui.Offset? _selectedAt;
  double _selectedSize = 7;

  /// 렌즈(주제 보기 — 감독 선택 D5 결정 5 A): 켠 주제의 사건 번호(렌즈가 꺼졌거나 아직 받는 중이면 null)와 그 사건의 고리 색.
  /// 그 주제의 사건만 또렷 + 점 둘레에 1.5px 종이 + 1.5px 주제 색 고리, 나머지 사건 · 묶음 알약은 .26(웹의 `.is-lens` · `.no-lens` — 거르지 않는다).
  Set<int>? _lensEvents;
  int _lensRing = 0;
  static const _lensFaint = .26;

  /// 밝기 상태(고르기 · 강조 · 기간 조명 · 가문). 장면에 아직 밭이 없어 층이 들고 있다 —
  /// 총괄이 `c.scene.emphasis`를 넣으면 여기에 그것을 걸면 된다(없으면 중립: 모두 1).
  em.Emphasis? emphasis;
  static final _neutral = em.Emphasis();

  /// 색 셈을 장면마다 되풀이하지 않게 띠 색마다 보관한다.
  final _tone = <int, _Tone>{};

  /// 바로 앞에 쓴 색(한 띠의 사건이 잇달아 오므로 대개 여기서 끝난다 — 표를 뒤지지 않는다).
  int _toneKey = 0;
  _Tone? _toneLast;

  /// 글줄 안내선의 색(띠 색 → 섞은 색) — oklab 섞기는 색마다 한 번이면 된다.
  final _laneInk = <int, int>{};

  /// 개수 알약의 글과 그 폭 · 하위 수 알약의 폭 — 수마다 한 번만 재고 보관한다(배율이 바뀌면 비운다).
  final _pillText = <int, String>{};
  final _pillWidth = <int, double>{}, _countWidth = <int, double>{};

  /// 이름 줄의 자리를 담아 돌려 쓰는 그릇(장면마다 수백 개의 새 객체를 만들지 않는다).
  final _run = LabelRunBox();

  /// 바로 앞에 본 줄의 글줄 자리(같은 줄의 사건이 잇달아 온다) — 장면마다 비운다.
  int _rowMemo = -1;
  double _rowBase = 0, _rowLineH = 0;

  /// 폭을 재는 길은 글자 쪽이 그대로면 다시 만들지 않는다(장면마다 새 닫힘을 만들지 않게).
  SceneText? _measureFor;

  /// 마지막 장면에서 날짜를 정확히 모르는 점 가운데 모르는 구간이 화면에서 넉넉해진 것(사건 번호 → 후보). 날짜는 범위로 그리지 않고 적은 자리에
  /// 점 하나로만 찍으므로(감독 결정 2026-10-13 "적당하게 한 곳을 찍어서 단일로 · 범위 표현 x" · 2026-10-14 "일 기준까지 확대해도 범위로 진행 x" —
  /// 예전의 정밀도 괄호 · 안개 · 구간 가운데로 옮겨 가기를 없앰) 모른다는 것은 그 점의 풍선 글로만 말한다.
  final _vague = <int, int>{};
  LabelBatch? _vagueBatch;

  /// [eventId]의 점에 올렸을 때의 풍선 글 — "이름 · 1905년 — 그해 안 어느 날인지 모름"(예전 괄호의 설명). 그때 그런 점이 아니면 null.
  String? vagueTip(int eventId) {
    final batch = _vagueBatch, cand = _vague[eventId];
    if (batch == null || cand == null || cand >= batch.input.eventId.length) return null;
    return batch.precTip(cand);
  }

  @override
  void setScale(double scale) {
    _sprites.setScale(scale);
    // 글자 그림판을 다시 뜨면 잰 폭도 다시 잰다.
    _pillWidth.clear();
    _countWidth.clear();
  }

  _Tone _toneOf(int argb) {
    final last = _toneLast;
    if (last != null && _toneKey == argb) return last;
    final tone = _tone[argb] ??= _Tone(argb);
    _toneKey = argb;
    _toneLast = tone;
    return tone;
  }

  /// 글줄 가운데의 세로 자리(hit_test의 `lineCenter`와 같은 셈) — 줄마다의 몫을 기억해 두고 글줄만 셈한다.
  /// [lift]는 두 장 꼬리표에서 칸 뭉치가 없는 띠의 사건 칸을 올리는 몫(bands.dart [BandLayer.eventLiftOf]).
  double _lineY(SceneView v, SceneLayout layout, int row, int line, [double lift = 0]) {
    if (row != _rowMemo) {
      final geo = layout.geo(row);
      _rowMemo = row;
      _rowBase = layout.rowTop(row) + geo.textTop;
      _rowLineH = geo.lineH;
    }
    return v.yOf(_rowBase + (line + .5) * _rowLineH - lift);
  }

  /// 사건이 든 띠 [band]의 사건 칸을 올리는 몫(띠 층이 이번 장면에 모은 look으로).
  double _liftOf(PaintContext c, int row, int band) => band == 0 ? 0 : BandLayer.of(c.scene)?.eventLiftOf(c.layout, row, band) ?? 0;

  @override
  void paint(PaintContext c) {
    _vague.clear();
    _vagueBatch = null;
    if (c.hide.contains('events')) return;
    // 이름의 폭을 재는 길을 걸어 둔다 — 다음 판의 후보 모으기(LabelBatch.collect)가 이 길로 잰다.
    if (!identical(_measureFor, c.text)) {
      final text = c.text;
      _measureFor = text;
      EventText.measure = text.widthOf;
    }
    // 줄마다의 글줄 자리는 장면마다 다시 본다(줄이 흐르면 자리가 바뀐다).
    _rowMemo = -1;
    final bright = emphasis ?? _neutral;
    final bird = c.layout.bird;
    final stats = c.scene.stats
      ..nameBatch = -1
      ..namesDrawn = 0
      ..ghostNames = 0;
    // 조감 모양 b · c는 사건 점 · 알약을 아예 그리지 않는다(`BIRD.b.dots = false` · 명세 05 7.5).
    if (bird && !(c.layout.birdShape?.dots ?? true)) return;
    _lanes(c);
    final scene = c.scene;
    final lensMarks = SceneMarks.of(scene);
    _lensEvents = c.layout.themeLens.isEmpty ? null : lensMarks.lensEvents;
    // 고리 색 = color-mix(in srgb, 주제 색 85%, --paper-ink).
    _lensRing = _lensEvents == null ? 0 : mixSrgb(0xff000000 | lensMarks.lensColor, Look.ink, .85);
    final batch = scene.labelBatch, out = scene.labelOutput;
    stats.nameBatch = batch?.input.version ?? -1;
    if (batch == null || out == null) {
      _flushShapes(c);
      return;
    }
    final v = c.v, layout = c.layout, w = c.w, h = c.h, left = c.left, head = c.head;
    final input = batch.input;
    final fade = scene.nameFade, fades = c.text.canFade, now = scene.now;
    _vagueBatch = batch;
    final monthGate = _monthGate(v);

    final matched = bright.look.events;
    final selectedId = scene.selectedEventId;
    final rowCount = layout.rowCount;
    final run = _run;
    for (int i = 0; i < out.shownCount; i++) {
      final cand = out.shownCandidate[i], row = input.row[cand];
      if (row >= rowCount || !layout.hasBody(row)) continue;
      final look = input.look[cand], flags = out.shownFlags[i], side = out.shownSide[i];
      final id = input.eventId[cand];
      // 조감의 점은 모두 작은 점이고, 자리는 띠의 세로 가운데다(css 1789~1795 · 1804).
      final small = bird || flags & LabelFlag.small != 0;
      final at = v.xOf(out.shownAt[i]);
      final x = at + EventLook.dotDx(look, side: side, small: small);
      if (x < left - 400 || x > w + 400) continue;
      // 조감: 띠 안 이름 · 단추의 자리에 걸친 점은 **옮기지 않고 숨긴다**(명세 05의 7-3 · js:3608).
      if (bird && _hiddenByName(c, row, x, EventLook.dotRadius(look, small))) {
        c.debug?.note('조감가림', '점 $row ${x.toStringAsFixed(1)}');
        continue;
      }
      // 꼬리표 갈래 E: 화면 왼쪽에 붙어 따라오는 머리 이름(첫 글줄)에 걸친 점도 옮기지 않고 숨긴다(조감과 같은 길 · bands.dart [headHides]).
      final firstLine = !bird && out.shownLine[i] == 0;
      if (firstLine && _hiddenByHead(c, row, x, EventLook.dotRadius(look, small))) {
        c.debug?.note('머리가림', '점 $row ${x.toStringAsFixed(1)}');
        continue;
      }
      final y = _lineY(v, layout, row, out.shownLine[i], _liftOf(c, row, input.band[cand]));
      if (y < head - 12 || y > h + 12) continue;
      final tone = _toneOf(batch.colorOf(cand));
      final named = side != LabelSide.none;
      // 밝기: 고르기 · 강조의 값을 색의 알파에 곱한다(층을 뜨지 않는다). 이름 없는 점은 그 위에 .75(.is-bare).
      // 렌즈를 켰으면 그 주제가 아닌 사건은 .26 — 점 · 이름 · 괄호가 함께(웹의 `.no-lens`).
      final lens = _lensEvents;
      final lensHit = lens != null && lens.contains(id);
      final dim = bright.eventAlpha(id, row) * (lens == null || lensHit ? 1.0 : _lensFaint);
      final size = _dot(c, x, y, look, tone,
          small: small, more: flags & LabelFlag.more != 0, alpha: (named ? 1 : .75) * dim, scale: bright.dotScale(id), ring: lensHit ? _lensRing : 0);
      if (!bird) _noteVague(batch, out.shownPrec[i], cand, monthGate);
      c.debug?.dots.add(DebugDot(id, ui.Offset(x, y), out.shownExtra[i]));
      if (selectedId == id) {
        _selectedAt = ui.Offset(x, y);
        _selectedSize = size;
      }
      if (!named) continue;
      // 막 들어온 이름은 0.2초에 걸쳐 짙어진다(옅어짐을 할 수 있는 글자 방식에서만). 크게 바뀐 뒤 새 판을 기다리는 동안은 그리지 않는다.
      final alpha = (fades ? fade.alphaOf(id, now) : (fade.heldAt(now) ? 0.0 : 1.0)) * dim;
      if (alpha <= 0) continue;
      final font = batch.sizeOf(cand);
      final yearW = flags & LabelFlag.year != 0 ? input.yearWidth[cand] : 0.0;
      final countW = flags & LabelFlag.count != 0 ? input.countWidth[cand] : 0.0;
      batch.runInto(run, cand, at, side, flags);
      // 가장자리 자르기(명세 7절): 글자가 그림 영역의 양 끝을 넘으면 그 글자만 가린다 — 폭을 다시 재지 않는다.
      if (run.left < left || run.right > w) continue;
      // 화면 왼쪽에 붙은 머리 이름에 걸친 이름도 그 장면에는 숨긴다(이름 자리 셈은 그대로).
      if (firstLine && (BandLayer.of(scene)?.headHides(row, run.left, run.right) ?? false)) continue;
      final name = EventFont.name(font, input.importance[cand], look);
      // 미정인 사건의 이름은 조금 옅다(.is-unk { opacity: .82 }) — 투명도 대신 종이와 섞은 고른 색(감독 건의 2026-10-15 2번).
      final shown = EventLook.unknown(look) ? name.withColor(mixSrgb(over(name.color, Look.paper), Look.paper, .82)) : name;
      c.later.add('event', batch.title(cand), shown, run.nameLeft, y - name.size * .6, alpha);
      stats.namesDrawn++;
      // 강조에 든 사건(is-match): 이름 아래에 1.5px --warn 밑줄(css 338의 box-shadow 0 1.5px 0).
      if (matched != null && matched.contains(id)) {
        final bottom = y + font * .75;
        c.quads.add(run.nameLeft, bottom, run.nameRight, bottom + 1.5, withAlpha(_warn, alpha));
      }
      if (yearW > 0) {
        final year = EventFont.year(font);
        c.later.add('year', batch.date(cand), year, run.yearLeft, y - year.size * .6, alpha);
      }
      if (countW > 0) _countPill(c, run, y, out.shownExtra[i], tone, alpha);
    }
    // 빠진 이름은 제자리에서 옅어진다.
    if (fades) {
      for (final ghost in fade.ghosts(now)) {
        final name = ghost.name;
        if (name.row >= rowCount || !layout.hasBody(name.row)) continue;
        final x = v.xOf(name.at);
        if (x < left - 400 || x > w + 400) continue;
        final y = _lineY(v, layout, name.row, name.line, _liftOf(c, name.row, name.band));
        if (y < head - 12 || y > h + 12) continue;
        final look = EventFont.name(name.size, name.importance, name.look);
        c.later.add('ghost', name.title, look, x + name.dx, y - look.size * .6, ghost.alphaAt(now));
        stats.ghostNames++;
      }
    }
    // 조명이 하나도 없으면 묶음마다 구간을 맞대 볼 일이 없다.
    final spotted = bright.look.spots.isNotEmpty;
    for (int i = 0; i < out.clusters; i++) {
      _cluster(c, batch, out, i, bright, spotted);
    }
    // 대조용 기록: 후보와 묶음의 셈이 지금 연표와 어긋날 때 어디서 갈라졌는지 숫자로 남긴다.
    if (c.debug != null) {
      int noBand = 0, hidden = 0;
      for (int i = 0; i < input.at.length; i++) {
        if (!input.bandLo[i].isFinite && !input.bandHi[i].isFinite) noBand++;
      }
      for (int i = 0; i < out.shownCount; i++) {
        if (out.shownFlags[i] & LabelFlag.small != 0) hidden++;
      }
      c.debug!.note('사건','후보 ${input.at.length} · 보임 ${out.shownCount} · 작은 점 $hidden · 띠 못 찾음 $noBand · 묶음 ${out.clusters}'
          ' · 비켜 갈 구간 ${input.zoneLo?.length ?? 0}');
      for (int i = 0; i < out.clusters; i++) {
        c.debug!.note('묶음', '${out.clusterCount[i]}@${v.xOf(out.clusterAt[i]).round()} 줄${out.clusterRow[i]}·글줄${out.clusterLine[i]}'
            ' 폭${out.clusterWidth[i].round()} 점${out.clusterTickAt[i + 1] - out.clusterTickAt[i]}'
            ' 자리선 ${v.xOf(out.clusterLo[i]).round()}~${v.xOf(out.clusterHi[i]).round()}');
      }
    }
    _flushShapes(c);
    final selected = _selectedAt;
    if (selected != null) {
      // 고른 사건: 점 둘레에 강조 고리 하나(항목마다 부르지 않게 장면에 하나뿐인 그리기).
      c.canvas.drawCircle(
        selected,
        _selectedSize / 2 + 4.5,
        c.stroke
          ..color = const ui.Color(Look.accent)
          ..strokeWidth = 2,
      );
      c.stroke.strokeWidth = 1;
      c.debug?.selectionAt = selected;
      _selectedAt = null;
    }
    c.flushText();
  }

  /// 모아 둔 도형을 내보낸다. 안내선 무늬가 맨 아래(가장 먼저 모은 것) · 그 위에 네모 · 맨 위에 조각 — 모으던 차례 그대로다.
  void _flushShapes(PaintContext c) {
    c.patterns.flush(c.canvas);
    c.quads.flush(c.canvas);
    _sprites.flush(c.canvas);
  }

  /// 글줄 안내선의 점선 무늬: 3px 칠하고 2px 비우는 되풀이(끊어 그리던 `dash: 3, gap: 2`와 같은 무늬).
  /// 세로 줄무늬를 1px 높이로 잘라 쓰면 안내선 하나가 네모 하나다 — 점마다 네모로 모으면 한 줄이 수백 개가 된다.
  static const _laneDash = PatternSpec.stripes(90, 3, 5);

  /// 글줄 안내선: 띠 안에 글줄 수 − 1개, 옅은 1px 점선(명세 1.4). 띠 테두리에서 좌우 14px을 들여 그린다.
  void _lanes(PaintContext c) {
    if (c.hide.contains('bands')) return;
    // 조감에는 글줄이 하나뿐이라 안내선이 없다(명세 05 7.2).
    if (c.layout.bird) return;
    final v = c.v, layout = c.layout;
    final rowCount = layout.rowCount, left = c.left, w = c.w;
    for (final d in c.scene.draw) {
      final t = d.tile;
      for (int b = 0; b < t.bandCount; b++) {
        final row = t.bandRow[b];
        if (row >= rowCount || !layout.hasBody(row)) continue;
        final geo = layout.geo(row);
        if (geo.textLines < 2) continue;
        final rowTop = layout.rowTop(row);
        final top = v.yOf(rowTop + geo.bandTop);
        if (!c.rowOnScreen(row, top, geo.bandHeight)) continue;
        // 띠의 진짜 끝에서만 14px(+ 테두리 1)을 들인다 — 타일 경계에서 잘린 조각의 끝까지 들이면 긴 띠의 안내선이 경계마다 30px쯤 끊긴다.
        // 점선의 박자는 시각에 매어(1970년 0분 자리를 무늬 한 주기로 줄인 값 — 무늬 좌표가 커지지 않게) 경계 양쪽 조각이 한 줄로 이어진다.
        final flags = t.bandFlags[b];
        final x0 = v.xOf(t.origin + t.bandX0[b]) + (flags & Tile.clipLeft != 0 ? 0 : 1 + 14);
        final x1 = v.xOf(t.origin + t.bandX1[b]) - (flags & Tile.clipRight != 0 ? 0 : 1 + 14);
        if (x1 <= x0 || x1 < left || x0 > w) continue;
        final raw = 0xff000000 | t.bandColor[b];
        final argb = _laneInk[raw] ??= withAlpha(mixOklab(raw, Look.ink, .92), .38);
        final lo = x0 < left ? left : x0, hi = x1 > w ? w : x1;
        final phase = v.xOf(0) % _laneDash.period;
        for (int k = 1; k < geo.textLines; k++) {
          // 안내선은 글줄의 윗변에 놓인다(실측: 글줄 615 · 636 · 657 …에 안내선 636 · 657 …).
          final y = v.yOf(rowTop + geo.textTop + k * geo.lineH).floorToDouble();
          c.patterns.add(_laneDash, lo, y, hi, y + 1, argb, phaseX: phase);
        }
      }
    }
  }

  /// 점 하나. 돌려주는 값은 그린 점의 폭(고른 사건의 고리에 쓴다). [scale]은 고른 사건의 1.25배(css 335).
  double _dot(PaintContext c, double x, double y, int look, _Tone tone,
      {required bool small, required bool more, required double alpha, double scale = 1, int ring = 0}) {
    final s = _sprites;
    final unknown = EventLook.unknown(look), shared = EventLook.shared(look), child = EventLook.child(look);
    final cert = EventLook.estimated(look) || EventLook.legend(look);
    final fill = withAlpha(tone.fill, alpha), edge = withAlpha(tone.edge, alpha);
    final paper = withAlpha(Look.paper, alpha);
    c.stats.shapes++;
    void put(ui.Rect sprite, double diameter, int argb) => s.add(sprite, x - diameter * scale / 2, y - diameter * scale / 2, argb, scale);
    // 렌즈 주제의 사건: 점(몸통) 둘레에 1.5px 종이 + 1.5px 주제 색 고리 — 웹의 `.tl-ev.is-lens .d { box-shadow: 0 0 0 1.5px paper, 0 0 0 3px 고리 }`가
    // 점의 제 둘레(box-shadow)를 갈아 끼우므로 그때는 제 둘레(halo)를 그리지 않는다. [d]는 몸통의 지름(마름모는 한 변).
    final ownHalo = ring == 0;
    void ringed(double d, {bool diamond = false}) {
      if (ring == 0) return;
      final sprite = diamond ? s.diamond(5) : s.disc(13), unit = diamond ? 5.0 : 13.0, box = diamond ? math.sqrt2 : 1.0;
      s.add(sprite, x - (d + 6) * box * scale / 2, y - (d + 6) * box * scale / 2, withAlpha(ring, alpha), scale * (d + 6) / unit);
      s.add(sprite, x - (d + 3) * box * scale / 2, y - (d + 3) * box * scale / 2, paper, scale * (d + 3) / unit);
    }

    // 겹친 사건(.has-more): 점과 **같은 가운데**의 고리 — 1.5px 종이빛 틈 + 1.5px 고리(동전 빛깔 = 제 색 80%)가 점의 둘레를 갈아 끼운다.
    // 예전에는 웹처럼 오른쪽 위로 2.5px 비켜 한 장 더 포갠 동전이었는데, 점과 테가 어긋나 보였다(감독 2026-10-16 "두 개 정도 뭉쳤을 때 색점이랑 겉 테두리가 어긋나").
    // 렌즈 고리([ringed])와 같은 자리라 렌즈를 켠 동안은 렌즈 고리가 이긴다.
    void stacked(double d, {bool diamond = false}) {
      if (ring != 0) return;
      final sprite = diamond ? s.diamond(5) : s.disc(13), unit = diamond ? 5.0 : 13.0, box = diamond ? math.sqrt2 : 1.0;
      s.add(sprite, x - (d + 6) * box * scale / 2, y - (d + 6) * box * scale / 2, withAlpha(tone.coin, alpha), scale * (d + 6) / unit);
      s.add(sprite, x - (d + 3) * box * scale / 2, y - (d + 3) * box * scale / 2, paper, scale * (d + 3) / unit);
    }

    if (small) {
      // 좁은 띠 · 조감의 작은 점(css 1789~1795) — 다른 모든 규칙을 덮어쓴다.
      if (EventLook.treaty(look)) {
        ringed(4, diamond: true);
        if (ownHalo) put(s.diamondHalo(4), 7 * math.sqrt2, edge);
        put(s.diamond(4), 4 * math.sqrt2, fill);
        return 4 * math.sqrt2 * scale;
      }
      if (shared || unknown) {
        // 7×7 · 테두리 1.5px · 둘레 없음. 미정은 점선 그대로.
        ringed(7);
        put(s.disc(7), 7, paper);
        if (unknown) {
          put(s.dashRing7, 7, withAlpha(tone.unknown, alpha));
        } else {
          put(s.disc(7), 7, withAlpha(tone.raw, alpha));
          put(s.disc(4), 4, paper);
        }
        return 7 * scale;
      }
      final d = child ? 4.0 : 5.0;
      ringed(d);
      if (ownHalo) put(s.disc(child ? 7 : 9), child ? 7 : 9, child ? paper : withAlpha(tone.small, alpha));
      put(s.disc(d), d, fill);
      return d * scale;
    }
    if (EventLook.treaty(look)) {
      // 조약: 5px 정사각을 45° 돌린 마름모. 공동 · 확실성 · 미정과 겹치면 6.4px의 빈 마름모, 하위는 4px.
      final double side;
      bool hollow = false, dashed = false, halo = true;
      if (unknown) {
        side = 6.4;
        hollow = dashed = true;
        halo = false;
      } else if (shared && !EventLook.pair(look) && !cert) {
        side = 5; // 제 자리의 조약은 채운 마름모로 되돌린다
      } else if (shared || cert) {
        side = 6.4;
        hollow = true;
      } else {
        side = child ? 4 : 5;
      }
      final box = side * math.sqrt2;
      ringed(side, diamond: true);
      if (more) {
        stacked(side, diamond: true);
      } else if (halo && ring == 0) {
        put(s.diamondHalo(side), (side + 3) * math.sqrt2, edge);
      }
      if (dashed) {
        put(s.diamond(side), box, paper);
        put(s.diamondDash, box, withAlpha(tone.unknown, alpha));
      } else if (hollow) {
        put(s.diamond(side), box, withAlpha(tone.raw, alpha));
        put(s.diamond(side - 3), (side - 3) * math.sqrt2, paper);
      } else {
        put(s.diamond(side), box, fill);
      }
      return box * scale;
    }
    if (unknown) {
      // 미정: 점선 빈 점 10px(둘레 없음 · 조금 옅게 — 투명도 .85 대신 종이와 섞은 고른 색 · 감독 건의 2026-10-15 2번).
      ringed(10);
      put(s.disc(10), 10, paper);
      put(s.dashRing, 10, withAlpha(tone.unknown, alpha));
      return 10 * scale;
    }
    if (shared) {
      ringed(9);
      if (more) {
        stacked(9);
      } else if (ownHalo) {
        put(s.disc(15), 15, edge);
      }
      put(s.disc(9), 9, withAlpha(tone.raw, alpha));
      put(s.disc(5), 5, paper);
      return 9 * scale;
    }
    if (cert) {
      ringed(7);
      if (more) {
        stacked(7);
      } else if (ownHalo) {
        put(s.disc(13), 13, edge);
      }
      put(s.disc(7), 7, withAlpha(tone.raw, alpha));
      put(s.disc(3), 3, paper);
      return 7 * scale;
    }
    if (child) {
      // 하위 사건: 5px 점에 2px 종이빛 둘레.
      ringed(5);
      if (more) {
        stacked(5);
      } else if (ownHalo) {
        put(s.disc(9), 9, paper);
      }
      put(s.disc(5), 5, fill);
      return 5 * scale;
    }
    ringed(7);
    if (more) {
      stacked(7);
    } else if (ownHalo) {
      put(s.disc(13), 13, edge);
    }
    put(s.disc(7), 7, fill);
    return 7 * scale;
  }

  /// 수의 글(`'3'` 같은 짧은 글) — 장면마다 다시 잇지 않고 수마다 하나를 보관한다.
  String _numeral(int n) => _pillText[n] ??= '$n';

  /// 이름 뒤의 하위 수 알약(`.cnt`) — 글자 크기는 본문 14px × 0.82로 고정이다(명세 8.3-2).
  void _countPill(PaintContext c, LabelRunBox run, double y, int count, _Tone tone, double alpha) {
    final text = _numeral(count), look = EventFont.count(tone.countInk);
    // 폭은 글과 크기만으로 정해진다(색과 무관) — 수마다 한 번 재고 보관한다.
    var width = _countWidth[count];
    if (width == null) {
      width = c.text.widthOf(text, look);
      if (width == null) return;
      _countWidth[count] = width;
    }
    final w = width + 8, h = 17.2;
    _stadium(c, run.countLeft, y - h / 2, run.countLeft + w, y + h / 2, withAlpha(tone.countFill, alpha));
    c.later.add('count', text, look, run.countLeft + 4, y - look.size * .6, alpha);
    c.stats.shapes++;
  }

  /// 모른다는 글을 붙일 때의 '달 눈금' 문턱(예전 정밀도 괄호가 나타나던 때 그대로 — 감독 결정 2026-09-22 "월까지 확대되었을 때만"):
  /// 한 달이 58px(날짜 칸이 달마다 눈금을 적는 문턱 — ruler.dart의 '1개월')일 때 0 → 72px에서 1로(smoothstep).
  static double _monthGate(SceneView v) {
    final u = ((v.ppm * 43830 - 58) / 14).clamp(0.0, 1.0);
    return u * u * (3 - 2 * u);
  }

  /// 모르는 구간이 화면에서 넉넉해졌으면(구간 폭 f) 그 점을 적어 둔다 — 그리지는 않는다. 연도 · 달 · 날까지만 적은 사건은 [monthGate]를 받고,
  /// 세기 초 · 중 · 말(정밀도 5~7)은 구간 폭만 본다(예전 괄호의 문턱과 같다).
  void _noteVague(LabelBatch batch, double f, int cand, double monthGate) {
    if (f <= .02 || batch.input.precLo[cand].isNaN) return;
    if ((batch.precisionOf(cand) >= 5 ? 1.0 : monthGate) <= .02) return;
    _vague[batch.input.eventId[cand]] = cand;
  }

  /// 조감에서 [row]의 [x]를 가운데로 하는 반지름 [r]의 점(또는 반폭 [r]의 알약)이 띠 안 이름 · 단추에 걸리는가.
  /// 띠 층을 그리개가 이어 주지 않아도 되게 장면 곁에서 찾는다([BandLayer.of]) — 띠 층의 `beginFrame`이 먼저 돈다.
  bool _hiddenByName(PaintContext c, int row, double x, double r) => BandLayer.of(c.scene)?.birdHides(row, x - r, x + r) ?? false;

  /// 꼬리표 갈래 E: 화면 왼쪽에 붙어 따라오는 머리 이름(첫 글줄)에 걸치는가.
  bool _hiddenByHead(PaintContext c, int row, double x, double r) => BandLayer.of(c.scene)?.headHides(row, x - r, x + r) ?? false;

  /// 개수 알약과 그 아래의 자리 선 · 눈금, 안쪽 아랫단의 분류 비율 색줄(명세 5절).
  /// 밝기는 고른 것이 있으면 .45다(css 1139의 `.tl.is-picked .tl-clu`) — [em.Emphasis.trimDim]과 같은 값.
  void _cluster(PaintContext c, LabelBatch batch, LabelOutput out, int i, em.Emphasis bright, bool spotted) {
    final v = c.v, layout = c.layout, row = out.clusterRow[i];
    if (row >= layout.rowCount || !layout.hasBody(row)) return;
    final x = v.xOf(out.clusterAt[i]);
    if (x < c.left - 100 || x > c.w + 100) return;
    // 대표가 없는 통의 개수 알약은 lead −1(labels.dart) — 그때는 올리지 않는다(줄의 사건 칸 그대로).
    final lead = out.clusterLead[i];
    final y = _lineY(v, layout, row, out.clusterLine[i], lead < 0 ? 0 : _liftOf(c, row, batch.input.band[lead]));
    if (y < c.head - 12 || y > c.h + 12) return;
    final small = out.clusterFlags[i] & ClusterFlag.small != 0;
    // 렌즈: 그 주제의 사건이 하나도 들지 않은 묶음은 .26(웹의 `.tl-clu.no-lens`).
    final dim = bright.trimDim * (_lensEvents == null || _clusterHasLens(out, i, _lensEvents!) ? 1.0 : _lensFaint);
    final tone = _toneOf(_clusterColor(c, batch, out, i));
    // 조명 강조의 묶음 표시(is-hit): 그 시기의 사건을 품은 알약은 테두리를 제 색 짙게 · 숫자를 글자색으로(css 1340).
    final hit = spotted && _spotHit(batch, out, i, bright);
    final count = out.clusterCount[i], text = _numeral(count);
    final look = TextLook(small ? 8 : 9.5, ui.FontWeight.w700, withAlpha(hit ? Look.ink : tone.pillInk, dim));
    // 알약의 글 폭도 글과 크기만으로 정해진다 — 수 · 크기마다 한 번 재고 보관한다.
    final widthKey = count * 2 + (small ? 1 : 0);
    var textWidth = _pillWidth[widthKey];
    if (textWidth == null) {
      textWidth = c.text.widthOf(text, look);
      if (textWidth == null) return;
      _pillWidth[widthKey] = textWidth;
    }
    final w = math.max(out.clusterWidth[i], textWidth + 10), h = small ? LabelGeo.smallPillHeight : LabelGeo.pillHeight;
    final lo = x - w / 2, hi = x + w / 2;
    // 조감: 알약도 띠 안 이름 · 단추의 자리에 걸리면 옮기지 않고 숨긴다(명세 05의 7-3).
    // 다만 **띠가 있는 묶음만**이다 — 지금 연표도 이 가림을 `if (bb)`(그 묶음의 띠 범위가 있을 때) 안에서만 한다(js:3699).
    // 띠가 없는 사건(공통 줄 · 바탕 문화)의 알약은 띠 안 이름과 상관없이 그대로 선다.
    // 견주는 폭은 **자리를 잡을 때의 폭**(`clusterWidth`)이다 — 지금 연표도 `pillW(n)`으로 재고 견준다.
    if (layout.bird && out.clusterBandLo[i].isFinite && out.clusterBandHi[i].isFinite && _hiddenByName(c, row, x, out.clusterWidth[i] / 2)) {
      c.debug?.note('조감가림', '알약 $row ${(x - w / 2).toStringAsFixed(1)}~${(x + w / 2).toStringAsFixed(1)}');
      return;
    }
    final ring = withAlpha(hit ? tone.edgeDeep : tone.pillRing, dim);
    // 아래의 자리 선과 눈금: 묶인 점이 알약보다 넓게 흩어져 있을 때만.
    final spread = !small && (v.xOf(out.clusterHi[i]) - v.xOf(out.clusterLo[i])) > w - 8;
    if (spread) {
      final band = out.clusterBandLo[i].isFinite ? v.xOf(out.clusterBandLo[i]) + 1.5 : double.negativeInfinity;
      final bandHi = out.clusterBandHi[i].isFinite ? v.xOf(out.clusterBandHi[i]) - 1.5 : double.infinity;
      final wl = math.max(v.xOf(out.clusterLo[i]), band), wr = math.min(v.xOf(out.clusterHi[i]), bandHi);
      if (wr > wl) {
        c.quads.add(wl, y - .5, wr, y + .5, withAlpha(tone.rail, dim));
        final from = out.clusterTickAt[i], to = out.clusterTickAt[i + 1];
        for (int k = from; k < to && k - from < 40; k++) {
          final tx = v.xOf(out.clusterTick[k]);
          if (tx < wl - .5 || tx > wr + .5) continue;
          c.quads.add(tx - .5, y - 3.5, tx + .5, y + 3.5, withAlpha(tone.tick, dim));
        }
      }
    }
    // 둘레: 3px 종이빛 · 1px 제 색. 작은 알약은 둘레 없이 안쪽 1px 테.
    if (small) {
      // 작은 알약(좁은 띠 · 조감)은 바깥 둘레 없이 안쪽 1px 테(조명에 들면 1.5px).
      final edge = hit ? 1.5 : 1.0;
      _stadium(c, lo, y - h / 2, hi, y + h / 2, ring);
      _stadium(c, lo + edge, y - h / 2 + edge, hi - edge, y + h / 2 - edge, withAlpha(tone.pillFill, dim));
    } else {
      // 종이빛 둘레는 **좌우로만** 3px(감독 2026-10-16 "숫자로 뭉친 사건 점이 띠 밖으로 나가"): 알약 14 + 테 1 + 둘레 3이 사건 칸(18)보다 커서
      // 위아래 둘레가 칸막이 · 띠 아랫변을 끊고 바탕(회색)으로 삐져나왔다. 사건 칸이 이미 흰색이라 위아래 둘레는 쓸모가 없다 — 테 바깥으로 넓히지 않는다.
      final edge = hit ? 1.5 : 1.0;
      _stadium(c, lo - 3, y - h / 2 - edge, hi + 3, y + h / 2 + edge, withAlpha(Look.paper, dim));
      _stadium(c, lo - edge, y - h / 2 - edge, hi + edge, y + h / 2 + edge, ring);
      _stadium(c, lo, y - h / 2, hi, y + h / 2, withAlpha(tone.pillFill, dim));
      // 분류 비율 색줄: 받은 대표로만 센다(성긴 단계의 나머지는 셀 수 없다 — 명세 8.2).
      final from = out.clusterCatAt[i], to = out.clusterCatAt[i + 1];
      int total = 0;
      for (int k = from; k < to; k++) {
        total += out.clusterCatCount[k];
      }
      if (total > 0) {
        final segLo = lo + 4, segW = w - 8;
        double at = segLo;
        for (int k = from; k < to; k++) {
          final part = segW * out.clusterCatCount[k] / total;
          c.quads.add(at, y + h / 2 - 3, at + part, y + h / 2 - 1.5, withAlpha(_catColor(c, out.clusterCat[k]), .9 * dim));
          at += part;
        }
      }
    }
    c.later.add('pill', text, look, x - textWidth / 2, y - look.size * .62, dim);
    c.stats.shapes++;
  }

  /// 그 묶음에 렌즈 주제의 사건이 하나라도 드는가(묶인 점의 사건 번호 — 옛 꼴의 판이면 대표 하나로).
  bool _clusterHasLens(LabelOutput out, int i, Set<int> lens) {
    final ids = out.clusterIds;
    if (ids != null && ids.length == out.clusterTick.length) {
      for (int k = out.clusterTickAt[i]; k < out.clusterTickAt[i + 1]; k++) {
        if (lens.contains(ids[k])) return true;
      }
    }
    return false;
  }

  /// 그 묶음이 기간 조명에 걸치는가 — 대표가 든 띠의 조명 구간과 묶음의 시간 범위를 맞대 본다(명세 06 3-3의 spotHi).
  bool _spotHit(LabelBatch batch, LabelOutput out, int i, em.Emphasis bright) {
    final lead = out.clusterLead[i];
    if (lead < 0) return false;
    if (lead >= batch.input.band.length) return false;
    final band = batch.input.band[lead];
    if (band == 0) return false;
    final lo = out.clusterLo[i], hi = out.clusterHi[i] > lo ? out.clusterHi[i] : lo;
    // 흐르는 동안에는 꺼지는 구간도 함께 온다 — 아직 조금이라도 남은 구간(`glow > 0`)까지 표시를 켠다(꺼짐은 160ms에 걸쳐 빠진다).
    for (final spot in bright.spotsOf(band)) {
      if (spot.glow <= 0) continue;
      if (spot.start <= hi && spot.end >= lo) return true;
    }
    return false;
  }

  int _clusterColor(PaintContext c, LabelBatch batch, LabelOutput out, int i) {
    final lead = out.clusterLead[i];
    if (lead >= 0 && lead < batch.input.at.length) return batch.colorOf(lead);
    return _catColor(c, out.clusterCatAt[i] < out.clusterCatAt[i + 1] ? out.clusterCat[out.clusterCatAt[i]] : 255);
  }

  int _catColor(PaintContext c, int category) {
    final cats = c.layout.categories;
    return category < cats.length ? 0xff000000 | cats[category].color : 0xffa4b1b7;
  }

  /// 둥근 끝의 알약(css의 `border-radius: 999px` — 모서리 반지름은 짧은 변의 절반).
  /// 모서리는 제 그림판의 4분원 조각, 몸통과 옆구리는 네모 묶음에 모은다.
  void _stadium(PaintContext c, double l, double t, double r, double b, int argb) {
    final radius = math.min(b - t, r - l) / 2;
    if (radius <= 0) return;
    // 가로로 누운 알약(거의 모두)은 위아래가 꽉 찬 둥근 끝 둘이면 된다 — 같은 동그라미를 넷으로 가르지 않아 조각이 절반이다.
    // 찍히는 자리 · 크기 · 조각의 자리가 모서리 둘을 잇댄 것과 같아 그림은 한 픽셀도 달라지지 않는다.
    if (b - t <= r - l) {
      _sprites.cap(false, l, t, radius, argb);
      _sprites.cap(true, r - radius, t, radius, argb);
      if (r - radius > l + radius) c.quads.add(l + radius, t, r - radius, b, argb);
      return;
    }
    _sprites.corner(0, l, t, radius, argb);
    _sprites.corner(1, r - radius, t, radius, argb);
    _sprites.corner(2, l, b - radius, radius, argb);
    _sprites.corner(3, r - radius, b - radius, radius, argb);
    if (r - radius > l + radius) c.quads.add(l + radius, t, r - radius, b, argb);
    c.quads.add(l, t + radius, l + radius, b - radius, argb);
    c.quads.add(r - radius, t + radius, r, b - radius, argb);
  }
}

/// 띠 색 하나에서 끌어낸 사건의 색들(명세 2.2 · 3.2 · 5절). 색마다 한 번만 셈한다.
class _Tone {
  _Tone(this.raw)
    : fill = mixSrgb(raw, Look.ink, .80),
      edge = mixSrgb(raw, Look.paper, .15),
      small = mixSrgb(raw, Look.paper, .12),
      coinEdge = mixSrgb(raw, Look.paper, .10),
      coin = over(withAlpha(raw, .80), Look.paper),
      countFill = mixSrgb(raw, Look.paper, .22),
      countInk = mixSrgb(raw, Look.ink, .78),
      pillFill = mixSrgb(raw, Look.paper, .24),
      pillInk = mixSrgb(raw, Look.ink, .42),
      pillRing = over(withAlpha(raw, .55), Look.paper),
      edgeDeep = mixOklab(raw, Look.ink, .84),
      rail = over(withAlpha(raw, .50), Look.paper),
      tick = withAlpha(mixSrgb(raw, Look.ink, .70), .5),
      unknown = mixSrgb(over(raw, Look.paper), Look.paper, .85);
  final int raw, fill, edge, small, coinEdge, coin, countFill, countInk, pillFill, pillInk, pillRing, edgeDeep, rail, tick;

  /// 미정 사건의 점선 고리 · 마름모 — 예전 투명도 .85를 종이와 섞은 고른 색으로(감독 건의 2026-10-15 2번).
  final int unknown;
}

/// 사건 층의 작은 그림판: 지름별 동그라미 · 점선 고리 · 마름모 · 알약의 둥근 끝을 흰색으로 한 번 그려 두고
/// 장면마다 drawRawAtlas 한 번으로 수천 개를 찍는다(색은 찍을 때 입힌다). 공용 sprites.dart는 고치지 않고 층이 제 그림판을 둔다.
class EventSprites {
  static const _discSizes = [3.0, 4.0, 5.0, 7.0, 7.4, 9.0, 9.4, 10.0, 11.0, 11.4, 13.0, 15.0];
  static const _diamondSides = [3.4, 4.0, 5.0, 6.4];
  static const sheetWidth = 128.0, sheetHeight = 84.0;

  /// 알약의 둥근 끝을 만드는 큰 동그라미(반으로 갈라 줄여 쓴다).
  static const _capDisc = 32.0, _capTop = 48.0;
  static const _dashTop = 16.0, _diamondTop = 28.0;

  final _disc = <double, ui.Rect>{};
  final _diamond = <double, ui.Rect>{}, _diamondHalo = <double, ui.Rect>{}, _diamondCoin = <double, ui.Rect>{};
  late ui.Rect dashRing, dashRing7, diamondDash;
  ui.Image? _image;
  double _scale = 2;

  EventSprites() {
    double x = 0;
    for (final d in _discSizes) {
      _disc[d] = ui.Rect.fromLTWH(x, 0, d, d);
      x += d + 1;
    }
    dashRing = const ui.Rect.fromLTWH(0, _dashTop, 10, 10);
    // 좁은 띠 · 조감의 미정 점: 7px 점선 고리(테두리 1.5px).
    dashRing7 = const ui.Rect.fromLTWH(11, _dashTop, 7, 7);
    diamondDash = ui.Rect.fromLTWH(19, _dashTop, 6.4 * math.sqrt2, 6.4 * math.sqrt2);
    x = 0;
    for (final side in _diamondSides) {
      for (final (map, extra) in [(_diamond, 0.0), (_diamondHalo, 3.0), (_diamondCoin, 2.4)]) {
        final box = (side + extra) * math.sqrt2;
        map[side] = ui.Rect.fromLTWH(x, _diamondTop, box, box);
        x += box + 1;
      }
    }
  }

  ui.Rect disc(double diameter) => _disc[diameter] ?? _disc[7.0]!;
  ui.Rect diamond(double side) => _diamond[side] ?? _diamond[5.0]!;
  ui.Rect diamondHalo(double side) => _diamondHalo[side] ?? _diamondHalo[5.0]!;
  ui.Rect diamondCoin(double side) => _diamondCoin[side] ?? _diamondCoin[5.0]!;

  void setScale(double scale) {
    // 조각을 적어도 2배로 떠 둔다 — 점선 고리 · 마름모처럼 1.5px 선이 든 조각은 1배로 뜨면 흐려져
    // 기준 그림의 또렷한 점선이 되지 않는다(판 하나가 256×168뿐이라 값이 크지 않다).
    final next = ((scale < 2 ? 2 : scale) * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _image?.dispose();
    _image = null;
    _scale = next;
  }

  ui.Image _sheet() {
    final have = _image;
    if (have != null) return have;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(_scale);
    final white = ui.Paint()..color = const ui.Color(0xffffffff);
    for (final entry in _disc.entries) {
      canvas.drawCircle(entry.value.center, entry.key / 2, white);
    }
    // 점선 고리: 화면의 `1.5px dashed` 테두리를 여덟 토막의 호로.
    void dashed(ui.Rect cell, double diameter, double stroke) {
      final paint = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const ui.Color(0xffffffff);
      final rect = ui.Rect.fromCircle(center: cell.center, radius: (diameter - stroke) / 2);
      for (int i = 0; i < 8; i++) {
        canvas.drawArc(rect, i * math.pi / 4, math.pi / 4 * .56, false, paint);
      }
    }

    dashed(dashRing, 10, 1.5);
    dashed(dashRing7, 7, 1.5);
    void tilted(ui.Rect cell, double side, double radius) {
      canvas.save();
      canvas.translate(cell.center.dx, cell.center.dy);
      canvas.rotate(math.pi / 4);
      canvas.drawRRect(ui.RRect.fromRectXY(ui.Rect.fromCenter(center: ui.Offset.zero, width: side, height: side), radius, radius), white);
      canvas.restore();
    }

    for (final side in _diamondSides) {
      tilted(_diamond[side]!, side, 1);
      tilted(_diamondHalo[side]!, side + 3, 2.5);
      tilted(_diamondCoin[side]!, side + 2.4, 2.2);
    }
    canvas.save();
    canvas.translate(diamondDash.center.dx, diamondDash.center.dy);
    canvas.rotate(math.pi / 4);
    canvas.drawRRect(
      ui.RRect.fromRectXY(ui.Rect.fromCenter(center: ui.Offset.zero, width: 6.4 - 1.2, height: 6.4 - 1.2), 1, 1),
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const ui.Color(0xffffffff),
    );
    canvas.restore();
    canvas.drawCircle(const ui.Offset(_capDisc / 2, _capTop + _capDisc / 2), _capDisc / 2, white);
    final picture = recorder.endRecording();
    final image = picture.toImageSync((sheetWidth * _scale).ceil(), (sheetHeight * _scale).ceil());
    picture.dispose();
    return _image = image;
  }

  Float32List _transforms = Float32List(4 * 1024), _rects = Float32List(4 * 1024);
  Int32List _colors = Int32List(1024);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  int get count => _n;

  /// 조각 하나를 왼쪽 위 자리(배치 px)에 찍는다. [scale]은 조각을 줄여 찍을 비율.
  void add(ui.Rect source, double left, double top, int argb, [double scale = 1]) {
    if (argb == 0) return;
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    final p = _n * 4, s = _scale;
    _transforms[p] = scale / s;
    _transforms[p + 1] = 0;
    _transforms[p + 2] = left;
    _transforms[p + 3] = top;
    _rects[p] = source.left * s;
    _rects[p + 1] = source.top * s;
    _rects[p + 2] = source.right * s;
    _rects[p + 3] = source.bottom * s;
    _colors[_n] = argb;
    _n++;
  }

  /// 둥근 모서리(0 왼쪽 위 · 1 오른쪽 위 · 2 왼쪽 아래 · 3 오른쪽 아래). 큰 동그라미를 넷으로 갈라 줄여 찍는다.
  void corner(int which, double left, double top, double radius, int argb) {
    const half = _capDisc / 2;
    final x = which & 1 == 0 ? 0.0 : half, y = _capTop + (which < 2 ? 0.0 : half);
    add(ui.Rect.fromLTWH(x, y, half, half), left, top, argb, 2 * radius / _capDisc);
  }

  /// 알약의 둥근 끝(왼쪽 · 오른쪽). 같은 동그라미를 반으로만 갈라 조각 하나로 찍는다 — 모서리 넷보다 둘이 적다.
  /// 찍히는 자리 · 크기는 위아래 모서리 둘을 잇댄 것과 같다(위 [left] · [top]에서 폭 [radius] · 높이 2 × [radius]).
  void cap(bool right, double left, double top, double radius, int argb) {
    const half = _capDisc / 2;
    add(ui.Rect.fromLTWH(right ? half : 0, _capTop, half, _capDisc), left, top, argb, 2 * radius / _capDisc);
  }

  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    canvas.drawRawAtlas(_sheet(), Float32List.sublistView(_transforms, 0, _n * 4), Float32List.sublistView(_rects, 0, _n * 4),
        Int32List.sublistView(_colors, 0, _n), ui.BlendMode.modulate, null, _paint);
    _n = 0;
  }

  void dispose() {
    _image?.dispose();
    _image = null;
  }
}

