import 'dart:math' as math;
import 'dart:ui' as ui;

import '../color_mix.dart';
import '../ruler.dart';
import '../text_paragraph.dart';
import 'context.dart';
import 'look.dart';
import 'patterns.dart';

// 몸통의 바탕 눈금: 눈금마다 세로 점선, 한 칸 걸러 아주 옅은 바탕 띠, 0년 자리의 파선, 현재선,
// 그리고 기준선(`.tl-marker`)과 기간 재기 띠(`.tl-band-measure`).
// 지금 연표의 css 그대로다 — `.tl-gl`(1px dotted #dcd7e3 · 불투명도 .85) · `.tl-gl.is-zero`(1px dashed)
// · `.tl-gband`(rgba(150,110,50,.035)) · `.tl-now`(1px dashed accent 45% · 불투명도 .7).
// 띠와 선은 모두 네모 묶음에 모아 한 번에 그린다 — 눈금마다 선을 그으면 600개에 칠하기 2ms가 든다.
//
// **쌓임 차례 — 감독 결정 2026-10-25 "연도 세로줄은 띠 위에 안 그려지게 · 뒷바탕으로만": 세로줄은 늘 바탕이다.**
// 눈금마다의 세로 점선과 0년 파선은 보통 밀도 · 조감 모두 [paint](그림판 바탕 바로 위 · 사람 띠의 실 · 그릇 · 관계선 · 띠 · 칸 · 막대보다 아래)에서 긋는다.
// 예전에는 지금 연표(격자 상자 `.tl-grid`가 `z-index: 1`이라 띠 · 칸 위에 얹힘)처럼 보통 밀도에서만 점선을 띠 위([paintOver])에 그었다.
// **바탕에 한 번 · 위는 차례대로 얹기 — 셈 없음**(감독 2026-10-25 15시 '맨 아래 연도 쭉 그려져 있고 그 위에 차례대로 얹는 것처럼'):
// 줄은 몸통 높이 통째로 한 번 긋고, 띠 쪽 그림의 자리에 맞춰 빼지 않는다. 그 위에 얹는 **띠 쪽 그림은 아래를 가리는 종이(불투명)**라
// 그 자리의 줄은 저절로 덮인다 — 반투명 칠(바탕 문화 · 그릇 칠 · 흐린 띠 · 옅어지는 끝 · 떠오르는 타일)은 그 자리 바탕색과 미리 섞은
// 불투명 색으로, 테만 있는 칸(기관 칸 · 흰 사슬 칸 · 점선 받침 카드)은 테 안에 바탕색 종이를 깔고 칠한다(그 몫은 각 층에서).
// 띠 사이 빈 바탕에는 아무것도 얹지 않으니 줄이 그대로 남는다.
// 연 단위 세로줄이 아닌 **표시**는 그대로 위다 — 현재선(지금 해의 세로선과 '현재')과 기준선 · 기간 재기는 [paintOver](띠 · 칸 · 막대 뒤 · 사건 앞)에서.
// 조감에서는 css가 `.tl.is-bird .tl-grid { z-index: auto }`로 격자를 통째로 띠 아래로 내리므로 현재선도 띠 · 실 · 관계선 아래이고
// 기준선 · 기간 재기만 위에 남는다(`.tl.is-bird .tl-marker, .tl-band-measure { z-index: 3 }`). 다만 조감의 현재선은 대범위 테두리 · 그릇 ·
// 접힌 줄의 종이(불투명 — 세로줄 얹기)보다는 위다([paintBirdNow] — 그리개가 뒤 판의 그 걸음들 뒤에 부른다): 예전 9% 칠 밑에서는 비쳐 보였는데
// 종이 밑에 깔면 테두리 안에서 통째로 사라진다(세로줄 얹기 검토). 연 단위 세로줄이 아니라 표시라 종이가 가릴 것이 아니다.
class GridLayer {
  /// 세로 점선(1 켜고 1 끔)과 0년 파선(3 켜고 2 끔)의 무늬 — 가로 줄무늬를 1px 폭으로 잘라 세로 점선으로 쓴다.
  static const _dotted = PatternSpec.stripes(0, 1, 2), _dashed = PatternSpec.stripes(0, 3, 5);

  /// 세로 점선(1px 점 · 1px 틈) · 0년 자리의 파선 · 현재선과 그 이름.
  static final gridLine = withAlpha(Look.gridLine, .85);
  static final zeroLine = mixSrgb(0xffa0bcc5, 0xffcccccc, .6);
  static final nowLine = withAlpha(Look.accent, .45 * .7);
  static final nowLook = TextLook(11, ui.FontWeight.w400, withAlpha(Look.accent, .7));

  /// 기준선(`.tl-marker` — 2px `--warn` 세로선 + 흰 글의 딱지)과 기간 재기 띠(`.tl-band-measure`).
  static const warn = 0xff000000;
  static final measureFill = withAlpha(Look.accent, .12);
  static const pillLook = TextLook(11, ui.FontWeight.w700, 0xffffffff, spacing: -.14);

  /// 기준선의 자리(분)와 그 위의 날짜 글, 기간 재기의 두 끝(분)과 가운데 글. 총괄이 채운다.
  double? marker;
  String markerText = '';
  (double, double)? measure;
  String measureText = '';

  /// 조감인가 — 그러면 현재선도 격자 상자째 띠 아래다(css `.tl.is-bird .tl-grid { z-index: auto }` — 세로 점선 · 0년 파선은 조감과 상관없이
  /// 늘 띠 아래 바탕이므로(감독 결정 2026-10-25) 이 판단은 현재선의 자리만 정한다).
  /// 밀도 조감(V)뿐 아니라 **자동 조감**(보기 폭이 2,600년을 넘음)도 조감이다 — 지금 연표의 `is-bird`는 `isBird()`(밀도 조감 · 자동 조감)로 붙는다
  /// (js:1434 · 1742). 밀도만 보면 자동 조감에서 현재선이 띠 위로 올라와 띠 안 이름을 가로지른다(2026-10-25 고침 — 조감 글자 겹침 갈래).
  static bool isBird(PaintContext c) => c.layout.bird;

  /// 이번 장면에 그은 연도 세로줄(점선 · 0년 파선)의 열 — 1px 줄의 왼쪽 x(정수 · 왼쪽부터). [paint]가 장면마다 채운다.
  /// 띠 뒤 관계선 · 사람 띠의 실이 제 세로 획과 같은 자리의 줄을 그 밑에서 걷는다(0.1.1 · 이어 주는 선 미룸 1 — [touching]).
  final columns = <double>[];

  /// [columns] 가운데 x [x] · 반굵기 [half]인 세로 획이 덮거나 1px 안에 맞닿는 열(줄의 px [l, l + 1]이 [x − half − 1, x + half + 1]과 겹침).
  static Iterable<double> touching(List<double> columns, double x, double half) sync* {
    final lo = x - half - 1, hi = x + half + 1;
    for (final l in columns) {
      if (l + 1 <= lo) continue;
      if (l >= hi) break;
      yield l;
    }
  }

  /// 띠 · 칸 · 막대를 그린 뒤 · 사건 앞에 얹을 것 — 표시(현재선 · 기준선 · 기간 재기)만. 그리개가 앞 판을 끝낸 뒤 한 번 부른다.
  void paintOver(PaintContext c, RulerModel marks) {
    if (!isBird(c)) _now(c);
    _marks(c);
    c.flushShapes();
    c.flushText();
  }

  void paint(PaintContext c, RulerModel marks) {
    // **한 칸 걸러 바탕 띠(회색 · 흰색의 구간 구분)는 늘 띠 아래다**(감독 결정 2026-09-22 — "띠 색은 파스텔 색이지 투명한 게 아니다":
    // 지금 연표는 격자 상자가 띠 위에 얹혀 그 구분 색이 띠 위로 비치지만, 새 앱에서는 띠가 그것을 가린다).
    // **세로 점선 · 0년 파선도 늘 띠 아래다**(감독 결정 2026-10-25 — 세로줄은 늘 바탕 · 머리 주석). 조감의 현재선은 [paintBirdNow](종이 위 · 띠 아래).
    _grid(c, marks);
    c.flushShapes();
    c.flushText();
  }

  /// 조감의 현재선 — 띠 · 실 · 관계선 아래(css 조감의 격자 상자)이되 대범위 테두리 · 그릇 · 접힌 줄의 종이 위(머리 주석). 보통 밀도는 [paintOver].
  /// 그리개 · SVG가 뒤 판의 종이 걸음(접힌 줄 · 그릇 · 바탕 문화) 바로 뒤에 한 번 부른다.
  void paintBirdNow(PaintContext c) {
    if (!isBird(c)) return;
    _now(c);
    c.flushShapes();
    c.flushText();
  }

  /// 한 칸 걸러 바탕 띠와 눈금마다의 세로 점선 · 0년 파선 — 그림판 바탕 바로 위에 한 번에. 그 위에 띠 쪽 그림이 종이처럼 얹혀 덮는다(머리 주석).
  void _grid(PaintContext c, RulerModel marks) {
    final v = c.v, w = c.w, h = c.h, head = c.head, left = c.left;
    int count = 0;
    columns.clear();
    for (final t in marks.ticks) {
      if (t.band) {
        final l = math.max(v.xOf(t.minute), left), r = math.min(t.end.isFinite ? v.xOf(t.end) : w, w);
        if (r > l) {
          c.quads.add(l, head, r, h, Look.gridBand);
          // 그 위에 얹는 반투명 칠이 이 바탕 띠와 섞이게 바탕 칸으로 알린다(paint/grounds.dart — 지금은 투명이라 아무것도 하지 않는다).
          c.grounds.tint(l, head, r, h, Look.gridBand);
          c.stats.shapes++;
        }
      }
      if (!t.shown) continue;
      final x = v.xOf(t.minute);
      // 오른쪽 끝에 딱 맞는 눈금도 긋는다(지금 연표의 격자도 그렇다) — 소수점 흔들림만큼 너그럽게.
      if (x < left - .5 || x > w + .5) continue;
      // 0년 자리의 선만 파선, 나머지는 1px 점선. 무늬는 세계 좌표가 아니라 날짜 칸 아래에서 시작한다(세로로 움직여도 제자리).
      // 끊는 길이와 시작 자리는 기준 그림의 픽셀에서 읽었다 — 점선은 몸통 맨 위에서 한 칸 띄고(1 켜고 1 끔),
      // 파선은 몸통 맨 위에서 바로(3 켜고 2 끔).
      // 점선을 점마다 네모로 모으면 선 하나가 수백~천 개의 네모가 된다(돋보기 50%에서 장면당 1만 개 · 2ms) —
      // 가로 줄무늬를 채운 1px 폭의 네모 하나로 그린다(무늬 묶음). 끊는 길이와 시작 자리는 같다.
      final l = x.floorToDouble();
      columns.add(l);
      if (t.zero) {
        _line(c, _dashed, l, head, h, zeroLine, head);
      } else {
        _line(c, _dotted, l, head, h, gridLine, head + 1);
      }
      c.stats.shapes++;
      count++;
    }
    columns.sort();
    c.debug?.gridLines = count;
  }

  /// 세로줄 하나([l] ~ [l] + 1 · [top] ~ [bottom]) — 몸통 높이 통째로 무늬 네모 하나. 무늬는 [phaseY]에서 시작한다(세로로 움직여도 점 · 파선이 제자리).
  static void _line(PaintContext c, PatternSpec spec, double l, double top, double bottom, int argb, double phaseY) =>
      c.patterns.add(spec, l, top, l + 1, bottom, argb, phaseY: phaseY);

  /// 현재선(지금 해의 세로 파선과 '현재') — 연 단위 세로줄이 아니라 표시라 보통 밀도에서는 띠 위([paintOver]) · 조감에서는 종이 위 · 띠 아래([paintBirdNow]).
  void _now(PaintContext c) {
    final v = c.v, w = c.w, h = c.h, head = c.head, left = c.left;
    final nowX = v.xOf(DateTime.now().millisecondsSinceEpoch / 60000);
    if (nowX >= left && nowX <= w) {
      c.quads.vLine(nowX, head, h, nowLine, dash: 3, gap: 3, phase: head);
      c.stats.shapes++;
      c.later.add('now', '현재', nowLook, nowX + 5, head + 2);
    }
  }

  /// 기준선과 기간 재기 띠 — 격자 상자 안에서 `z-index: 2`라 바탕 눈금 위 · 사건 아래다.
  void _marks(PaintContext c) {
    final v = c.v, w = c.w, h = c.h, head = c.head, left = c.left;
    final range = measure;
    if (range != null) {
      final l = v.xOf(range.$1).clamp(left, w), r = v.xOf(range.$2).clamp(left, w);
      if (r > l) {
        c.quads
          ..add(l, head, r, h, measureFill)
          ..add(l, head, l + 1, h, Look.accent)
          ..add(r - 1, head, r, h, Look.accent);
        c.stats.shapes++;
        if (measureText.isNotEmpty) _pill(c, (l + r) / 2, head + 5, measureText, Look.accent, centered: true);
      }
    }
    final at = marker;
    if (at == null) return;
    final x = v.xOf(at);
    if (x < left - 1 || x > w + 1) return;
    c.quads.add(x, head, x + 2, h, warn);
    c.stats.shapes++;
    if (markerText.isNotEmpty) _pill(c, x + 5, head + 3, markerText, warn, centered: false);
  }

  /// 기준선 · 기간 재기의 글 딱지(둥근 알약 + 흰 글). 모서리는 그림판이 없어 네모 하나로 갈음한다.
  void _pill(PaintContext c, double x, double y, String text, int color, {required bool centered}) {
    final width = c.text.widthOf(text, pillLook);
    if (width == null) return;
    final padX = centered ? 9.0 : 6.0;
    final l = centered ? x - width / 2 - padX : x;
    c.quads.add(l, y, l + width + padX * 2, y + pillLook.size * 1.4, color);
    c.stats.shapes++;
    c.later.add('mark', text, pillLook, l + padX, y + pillLook.size * .2);
  }
}
