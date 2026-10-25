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
// **쌓임 차례**(기준 그림의 픽셀로 확인): 지금 연표의 격자 상자 `.tl-grid`는 `z-index: 1`이라 **띠 · 칸 위에** 얹히고
// (한 칸 걸러 바탕 띠도 세로 점선도), 사건(`z-index: 2`)보다는 아래다. 그래서 [paintOver]에서 그린다.
// 조감에서는 css가 `.tl.is-bird .tl-grid { z-index: auto }`로 격자를 **띠 아래로** 내리므로([paint]에서 그린다),
// 기준선 · 기간 재기만 위에 남는다(`.tl.is-bird .tl-marker, .tl-band-measure { z-index: 3 }`).
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

  /// 조감(밀도 2)인가 — 그러면 격자가 띠 아래로 내려간다(css `.tl.is-bird .tl-grid { z-index: auto }`).
  static bool isBird(PaintContext c) => c.layout.conditions.density >= 2;

  /// 띠 · 칸 · 막대를 그린 뒤 · 사건 앞에 얹을 것. 그리개가 앞 판을 끝낸 뒤 한 번 부른다.
  void paintOver(PaintContext c, RulerModel marks) {
    if (!isBird(c)) _grid(c, marks, bands: false);
    _marks(c);
    c.flushShapes();
    c.flushText();
  }

  void paint(PaintContext c, RulerModel marks) {
    // **한 칸 걸러 바탕 띠(회색 · 흰색의 구간 구분)는 늘 띠 아래다**(감독 결정 2026-09-22 — "띠 색은 파스텔 색이지 투명한 게 아니다":
    // 지금 연표는 격자 상자가 띠 위에 얹혀 그 구분 색이 띠 위로 비치지만, 새 앱에서는 띠가 그것을 가린다). 세로 점선은 지금 연표처럼 띠 위에 —
    // 조감에서만 점선도 띠 아래다.
    _grid(c, marks, lines: isBird(c));
    c.flushShapes();
    c.flushText();
  }

  /// [bands] 한 칸 걸러 바탕 띠 · [lines] 세로 점선과 현재선 — 두 번에 나눠 그린다(바탕 띠는 띠 아래 · 점선은 띠 위).
  void _grid(PaintContext c, RulerModel marks, {bool bands = true, bool lines = true}) {
    final v = c.v, w = c.w, h = c.h, head = c.head, left = c.left;
    int count = 0;
    for (final t in marks.ticks) {
      if (bands && t.band) {
        final l = math.max(v.xOf(t.minute), left), r = math.min(t.end.isFinite ? v.xOf(t.end) : w, w);
        if (r > l) {
          c.quads.add(l, head, r, h, Look.gridBand);
          c.stats.shapes++;
        }
      }
      if (!lines || !t.shown) continue;
      final x = v.xOf(t.minute);
      // 오른쪽 끝에 딱 맞는 눈금도 긋는다(지금 연표의 격자도 그렇다) — 소수점 흔들림만큼 너그럽게.
      if (x < left - .5 || x > w + .5) continue;
      // 0년 자리의 선만 파선, 나머지는 1px 점선. 무늬는 세계 좌표가 아니라 날짜 칸 아래에서 시작한다(세로로 움직여도 제자리).
      // 끊는 길이와 시작 자리는 기준 그림의 픽셀에서 읽었다 — 점선은 몸통 맨 위에서 한 칸 띄고(1 켜고 1 끔),
      // 파선은 몸통 맨 위에서 바로(3 켜고 2 끔).
      // 점선을 점마다 네모로 모으면 선 하나가 수백~천 개의 네모가 된다(돋보기 50%에서 장면당 1만 개 · 2ms) —
      // 가로 줄무늬를 채운 1px 폭의 네모 하나로 그린다(무늬 묶음). 끊는 길이와 시작 자리는 같다.
      final l = x.floorToDouble();
      if (t.zero) {
        c.patterns.add(_dashed, l, head, l + 1, h, zeroLine, phaseY: head);
      } else {
        c.patterns.add(_dotted, l, head, l + 1, h, gridLine, phaseY: head + 1);
      }
      c.stats.shapes++;
      count++;
    }
    if (!lines) return;
    c.debug?.gridLines = count;
    // 현재선
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
