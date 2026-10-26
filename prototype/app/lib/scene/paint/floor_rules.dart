import 'context.dart'; // 묶음 연장(Quads · DashedQuads)은 context.dart가 batch.dart를 다시 내보낸다
import 'ink.dart';
import 'paint_pick.dart';

// 칸 층 사이 흐린 가로선 — 감독 지적(2026-10-25 "등불왕국 명목기 부분에 가로선도 흐릿하게라도 보이면 좋겠는데 지금은 너무 세로 구분선만 보여서").
//
// 띠 몸통의 층 사이 금은 띠 층(bands.dart `_paintTwoPiece` — 테 빛깔을 종이와 섞은 옅은 금)이 칸보다 먼저 긋는다. 그런데 할거기 칠
// (scopes.dart `paintOverBands` — 띠 위에 종이 92%)이 띠 칠과 함께 그 금도 덮어, 등불 왕국 412년 뒤(명목기 — 아홉 불씨 할거)처럼 칸 층이
// 길게 이어진 자리에는 칸 사이 세로 금(먹 25)만 남아 보였다. 그래서 칸 층(paint/strips.dart)이 칸을 그릴 때 **칸이 놓인 자리의 층 위아래**에
// 먹 가로선을 하나 더 긋는다 — 띠 칠 · 할거기 칠 위 · 칸 글자 아래 · 띠 테 안쪽.
//   · 자리: 층의 윗선 줄(첫 층은 이름 색줄 아랫변의 금 줄 — 색줄과 첫 층 사이)과 층의 아랫줄(= 다음 층의 윗선 줄 · 마지막 층이면 흰 사건 칸의 윗줄).
//     띠 층의 층 사이 금과 같은 줄이라 겹금이 되지 않는다(그 금 위에 먹이 얹힌다).
//   · 가로 폭: 그 층에 그린 칸의 자리만(칸 상자 — 0.5px 틈은 메워 이음) · 띠 테 안쪽으로 자름. 칸이 없는 층 · 칸이 없는 자리(빈 층)에는 긋지 않는다
//     (이웃 층에 칸이 있으면 그 층의 윗선 · 아랫선은 그 칸이 긋는다). 빽빽한 칸(한 단을 한 칸으로 — strips.dart `_dense`)은 제 파선 테가 있어 긋지 않는다.
//   · 맞닿음(감독 결정 2026-10-25 "왕 세로선부분이랑 가로선 부분이랑 딱 맞닿게 해줘 틈 없게" · "모든 가로세로 구분선은 맞닿게"): 세로 칸 구분선은
//     위 가로 금 바로 아랫줄부터 아래 가로 금 줄 앞까지(strips.dart `_dividerSpan` — 예전 위아래 1px 들임 없앰 · 가로 금 줄은 칠하지 않아 만나는 점에
//     먹이 한 번), 가로선의 끝은 그 칸이 그은 구분선의 열까지(`_ruleEnds` — 구분선 밖 1px 꼬리 없음) · 띠 테에 닿는 끝은 테 바로 옆 열부터(테는 floor 열).
//     띠 층의 층 사이 금 · 테 귀도 정수 열에 맞춘다(bands.dart `_innerSpan` · `_edgeSpan` · 세로 테 위아래 끝 `_sideSpan` — 세로 소수 자리에서도 귀가 비지
//     않게). 파선 · 점선 띠 테와 가로 금의 T자는 무늬가 빈 줄이면 그 점 하나를 테 빛깔로(`_dashTees`), 집권 · 실권 칸의 2px 밑줄은 구분선 열 · 테 옆 열의
//     정수 px(strips.dart `_underSpan`), 타일 이음매에 딱 놓인 칸 경계는 두 타일의 가로선이 이음매에서 만난다(`_seamAt`). 꼴 off는 이 갈래 전 그림 그대로
//     (맞닿음도 없음).
//   · 없음: 꼬리표 밑 흰 사슬 단(제 종이 테) · 접힌 줄 · 조감(칸이 없다 — 모양 a · b · c 모두) · 꼬리표 밖 · 빌린 칸의 층 윗줄(제 윗변 파선이 맡는다).
//   · 밝기: 띠의 밝기(띠 층의 층 사이 금과 같은 길 — 띠의 흐림 · 기간 조명 구간). 가로선은 띠 몸통의 짜임이라 칸마다의 밝기(고른 칸 · 빌린 칸 .72 ·
//     실권 칸 .55)는 타지 않는다. 같은 줄에서 두 칸(위 층의 아랫선 · 아래 층의 윗선)이 겹치면 한 번만 — 먹이 두 번 얹히지 않게 타일마다 모아
//     합친 뒤 한 번씩 긋는다([FloorRules.emit] — 밝기가 다르면 밝은 쪽).
//   · 꼴: 감독이 고를 셋([FloorRule] — 스위치 `--paint-rows=a|b|c|off`) 가운데 감독 결정(2026-10-25 "b로 하고") 기본 b — [FloorRuleLook].

/// 칸 층 사이 가로선의 꼴 값(감독이 고를 셋 — [FloorRule]).
abstract final class FloorRuleLook {
  /// 가로선의 먹 — a · b는 12(가는 선), c는 25(점선이라 한 단 짙게).
  static double inkOf(FloorRule rule) => rule == FloorRule.c ? CanvasInk.a25 : CanvasInk.a12;

  /// 점선의 긋기 · 띄우기(c — 1 긋고 2 띄움). 실선은 0.
  static double dashOf(FloorRule rule) => rule == FloorRule.c ? 1 : 0;
  static double gapOf(FloorRule rule) => rule == FloorRule.c ? 2 : 0;

  /// 세로 칸 구분선을 낮춘 먹 — b만 12(가로와 같게). 다른 꼴은 null(그대로 — 먹 25).
  static double? dividerOf(FloorRule rule) => rule == FloorRule.b ? CanvasInk.a12 : null;
}

/// 한 타일의 가로선 조각을 모았다가 띠 · 줄마다 합쳐 긋는다(칸 층 [paint/strips.dart]가 타일마다 쓴다).
/// 조각 = (띠 · 줄 y · 가로 [x0, x1) · 밝기). 밝기가 음수인 조각은 '긋지 않는 자리'(빌린 칸의 윗변) — 겹친 다른 조각을 이긴다.
/// 타일은 서로 겹치지 않고(painter.dart `_pass`) 타일에 걸친 칸은 정수 px 이음매에서 갈리므로, 겹침은 한 타일 안에서만 합치면 된다.
final class FloorRules {
  final _band = <int>[];
  final _y = <double>[], _x0 = <double>[], _x1 = <double>[], _alpha = <double>[];
  final _order = <int>[];
  final _cuts = <double>[], _active = <int>[];

  bool get isEmpty => _band.isEmpty;

  /// 모은 조각 수(검사용).
  int get length => _band.length;

  /// 조각 하나. [x0] · [x1]은 정수 px(부르는 쪽이 띠 테 안쪽으로 잘라 반올림한 값) · [alpha]는 그 칸의 밝기(0 이하면 버림).
  void add(int band, double y, double x0, double x1, double alpha) {
    if (x1 - x0 < .5 || alpha <= .004) return;
    _push(band, y, x0, x1, alpha);
  }

  /// 긋지 않는 자리(겹친 조각을 지운다).
  void exclude(int band, double y, double x0, double x1) {
    if (x1 - x0 < .5) return;
    _push(band, y, x0, x1, -1);
  }

  void _push(int band, double y, double x0, double x1, double alpha) {
    _band.add(band);
    _y.add(y.floorToDouble());
    _x0.add(x0);
    _x1.add(x1);
    _alpha.add(alpha);
  }

  void clear() {
    _band.clear();
    _y.clear();
    _x0.clear();
    _x1.clear();
    _alpha.clear();
  }

  /// 모은 조각을 (띠 · 줄)마다 합쳐 [rule]의 꼴로 긋고 비운다. 겹친 자리는 밝은 조각 하나 · 긋지 않는 조각이 있으면 비움 · 이웃한 같은 밝기는 한 선으로.
  /// [phase]는 점선 무늬가 시작하는 자리(세계에 붙은 x — 옆으로 옮겨도 무늬가 해에 붙어 있게).
  void emit(PaintContext c, FloorRule rule, double phase) {
    final n = _band.length;
    if (n == 0) return;
    if (rule == FloorRule.off) {
      clear();
      return;
    }
    final ink = FloorRuleLook.inkOf(rule), dash = FloorRuleLook.dashOf(rule), gap = FloorRuleLook.gapOf(rule);
    _order
      ..clear()
      ..addAll(Iterable<int>.generate(n));
    _order.sort((a, b) {
      final d = _band[a].compareTo(_band[b]);
      if (d != 0) return d;
      final dy = _y[a].compareTo(_y[b]);
      return dy != 0 ? dy : _x0[a].compareTo(_x0[b]);
    });
    int i = 0;
    while (i < n) {
      final head = _order[i], band = _band[head], y = _y[head];
      int j = i + 1;
      while (j < n && _band[_order[j]] == band && _y[_order[j]] == y) {
        j++;
      }
      _line(c, i, j, band, y, ink, dash, gap, phase);
      i = j;
    }
    clear();
  }

  /// 한 (띠 · 줄)의 조각 [_order] [from, to)를 합쳐 긋는다 — 끊는 자리(조각의 두 끝)마다 덮는 조각 가운데 가장 밝은 것(긋지 않는 조각이 있으면 없음).
  /// 장면 통계의 도형 수(`stats.shapes`)에는 세지 않는다 — 띠 층의 층 사이 금처럼 띠 몸통의 짜임이라(그 띠는 이미 하나로 셌다).
  void _line(PaintContext c, int from, int to, int band, double y, double ink, double dash, double gap, double phase) {
    final cuts = _cuts..clear();
    for (int k = from; k < to; k++) {
      cuts
        ..add(_x0[_order[k]])
        ..add(_x1[_order[k]]);
    }
    cuts.sort();
    final active = _active..clear();
    int next = from;
    double runL = 0, runR = 0, runA = 0;
    void put() {
      if (runA <= .004 || runR - runL < .5) return;
      c.quads.hLine(runL, runR, y, CanvasInk.alpha(ink, runA), dash: dash, gap: gap, phase: phase);
      c.debug?.note('층선', '$band ${(y * 10).round()} ${(runL * 10).round()},${(runR * 10).round()} ${(runA * 1000).round()}');
    }

    for (int k = 0; k + 1 < cuts.length; k++) {
      final a = cuts[k], b = cuts[k + 1];
      if (b - a < 1e-6) continue;
      while (next < to && _x0[_order[next]] <= a + 1e-6) {
        active.add(_order[next++]);
      }
      active.removeWhere((p) => _x1[p] <= a + 1e-6);
      var alpha = 0.0;
      var cut = false;
      for (final p in active) {
        if (_alpha[p] < 0) {
          cut = true;
        } else if (_alpha[p] > alpha) {
          alpha = _alpha[p];
        }
      }
      if (cut) alpha = 0;
      if (alpha == runA && (a - runR).abs() < 1e-6) {
        runR = b;
        continue;
      }
      put();
      runL = a;
      runR = b;
      runA = alpha;
    }
    put();
  }
}
