import 'dart:math' as math;
import 'dart:ui' as ui;

import '../color_mix.dart';
import '../text_paragraph.dart';
import 'context.dart';
import 'gutter.dart' show Gut;
import 'ink.dart';
import 'look.dart';

/// 작은 꼬리표 — 접힌 그릇이 안의 띠를 대신 보이는 꼴(목업 d5-b · d2-b의 packTags · smallTag).
/// 리메이크 조각 ②의 접힌 문화권 머리 단(왼쪽 칸 층)과 조각 ③의 접힌 폴더(대범위 층)가 함께 쓴다. 접힌 폴더는 4단계 흠 고침(G5 #8 흠 라 ③ · 스위치 `flaw`)부터
/// 몸통 안에 끝 `+n` 하나로 늘어놓는다([packCounted]) — 접힌 상자(과제 7 걸음 2)도 같은 길에 셋까지([packCounted]의 `max`) · 접힌 문화권 머리 단은 예전 [pack] 그대로.
/// 꼬리표는 높이 13 · 왼쪽 두 귀 모따기 3 · 구멍 · 이름 8.5 굵게, `+n` 칩은 종이 · 먹 40 테(먹은 그림판 먹 단계 — 테 45 · 글 60 · 구멍 45).
abstract final class SmallTags {
  static const height = 13.0, size = 8.5, gap = 4.0;
  static const _cham = 3;

  /// [items](띠의 시작 x · 이름 · 색 — 시작 x 차례)를 [startX]부터 [xmax]까지 늘어놓는다. 앞 꼬리표에 막혀 제자리에 못 서면
  /// 비켜 앉고, 그 사이에 묻힌 띠는 `+n` 칩으로 세며, 오른쪽 끝을 넘는 나머지도 `+n` 하나로. 놓은 것은 (왼쪽 x · 너비 · 글 · 색 — `+n`은 null).
  /// 글자 폭을 아직 모르면 null이다(부르는 쪽이 다음 판을 청한다).
  static List<(double, double, String, int?)>? pack(PaintContext c, List<(double, String, int)> items, double startX, double xmax) {
    const look = TextLook(size, ui.FontWeight.w700, Look.ink);
    double? tagW(String text) {
      final w = c.text.widthOf(text, look);
      return w == null ? null : (w + 15).roundToDouble();
    }

    final out = <(double, double, String, int?)>[];
    var last = startX;
    int i = 0;
    while (i < items.length) {
      final cur = items[i];
      final w = tagW(cur.$2);
      if (w == null) return null;
      final x = math.max(cur.$1, last + gap).roundToDouble();
      if (x + w > xmax) {
        final rest = '+${items.length - i}', rw = tagW(rest);
        if (rw != null && x + rw <= xmax) out.add((x, rw, rest, null));
        break;
      }
      // 이 꼬리표(와 뒤에 붙일 +n 칩)가 덮는 사이에 시작하는 띠는 묻는다.
      int j = i + 1;
      double end() {
        final more = j - i - 1;
        return x + w + (more > 0 ? gap + (tagW('+$more') ?? 0) : 0);
      }

      while (j < items.length && items[j].$1 < end() + gap) {
        j++;
      }
      out.add((x, w, cur.$2, cur.$3));
      final more = j - i - 1;
      if (more > 0) {
        final xp = (x + w + gap).roundToDouble(), s = '+$more', mw = tagW(s);
        if (mw != null && xp + mw <= xmax) out.add((xp, mw, s, null));
      }
      last = end();
      i = j;
    }
    return out;
  }

  /// 접힌 폴더 **몸통 안**의 작은 꼬리표(4단계 감독 고름 G5 #8 흠 라 ③ — 고르기 판 `g-g5-8.js` closedFolder fix): [items]를 [startX]부터 제 해 자리에
  /// 늘어놓되 앞 꼬리표에 묻히는 띠는 건너뛰고(사이 `+n` 칩 없이), **끝에 `+n` 하나** — n = [total](그릇 구성원 수) − 놓은 꼬리표 수(0 이하면 없음).
  /// 꼬리표마다 그 뒤에 끝 칩이 들 자리를 남기고 [xmax]까지 — 넘으면 거기서 멈춘다. 답의 꼴은 [pack]과 같다(`+n`은 색 null). 글자 폭을 아직 모르면 null.
  /// [max]는 놓을 꼬리표의 가장 많은 수(접힌 상자는 셋 — 과제 7 걸음 2 · 목업 범례 '넘치면 +n') — 다 차면 나머지는 끝 `+n`이 센다. 기본은 끝까지.
  static List<(double, double, String, int?)>? packCounted(PaintContext c, List<(double, String, int)> items, double startX, double xmax, int total, {int max = 1 << 30}) {
    const look = TextLook(size, ui.FontWeight.w700, Look.ink);
    double? tagW(String text) {
      final w = c.text.widthOf(text, look);
      return w == null ? null : (w + 15).roundToDouble();
    }

    final out = <(double, double, String, int?)>[];
    var last = startX - gap; // 놓은 마지막 꼬리표의 오른쪽 끝(처음에는 첫 꼬리표가 startX에 서게)
    var placed = 0;
    for (final (x0, label, color) in items) {
      if (placed >= max) break;
      final w = tagW(label);
      if (w == null) return null;
      if (placed > 0 && x0 < last + gap) continue; // 앞 꼬리표 밑에 시작하는 띠는 묻는다 — 끝의 +n이 센다
      final x = math.max(x0, last + gap).roundToDouble();
      final rest = total - placed - 1;
      final rw = rest > 0 ? tagW('+$rest') : 0.0;
      if (rw == null) return null;
      if (x + w + (rest > 0 ? gap + rw : 0) > xmax) break;
      out.add((x, w, label, color));
      placed++;
      last = x + w;
    }
    final n = total - placed;
    if (n > 0) {
      final s = '+$n', mw = tagW(s);
      if (mw == null) return null;
      final x = (placed > 0 ? last + gap : startX).roundToDouble();
      if (x + mw <= xmax) out.add((x, mw, s, null));
    }
    return out;
  }

  /// 놓은 꼬리표 하나([spot] — [pack]의 답)를 세로 가운데 [mid]에 그린다. 구멍의 점은 [dot](지름 · 왼쪽 · 위 · 색)으로 —
  /// 층마다 제 점 그림판을 쓴다. [tag]는 글자 판의 이름(시험이 찾는다).
  static void paint(PaintContext c, (double, double, String, int?) spot, double mid, void Function(double size, double left, double top, int argb) dot,
      {String tag = 'smallTag'}) {
    final (x, w, label, color) = spot;
    const h = height, k = _cham;
    final y0 = (mid - h / 2).roundToDouble(), y1 = y0 + h;
    final fill = color == null ? Look.paper : mixSrgb(color, Look.paper, .24);
    final edge = color == null ? CanvasInk.gray(.4) : mixOklab(color, Look.ink, .84);
    final ink = color == null ? CanvasInk.gray(.6) : mixSrgb(color, Look.ink, .22);
    for (int i = 0; i < k; i++) {
      c.quads.add(x + k - i, y0 + i, x + w, y0 + i + 1, fill);
      c.quads.add(x + k - i, y1 - i - 1, x + w, y1 - i, fill);
      c.quads.add(x + k - i - 1, y0 + i, x + k - i, y0 + i + 1, edge);
      c.quads.add(x + k - i - 1, y1 - i - 1, x + k - i, y1 - i, edge);
    }
    c.quads.add(x, y0 + k, x + w, y1 - k, fill);
    c.quads.hLine(x + k, x + w, y0, edge);
    c.quads.hLine(x + k, x + w, y1 - 1, edge);
    c.quads.vLine(x, y0 + k, y1 - k, edge);
    c.quads.vLine(x + w - 1, y0, y1, edge);
    c.stats.shapes++;
    if (color != null) {
      dot(4, x + 3, mid - 2, CanvasInk.gray(.45));
      dot(2, x + 4, mid - 1, Look.paper);
    }
    final look = TextLook(size, ui.FontWeight.w700, ink);
    c.later.add(tag, label, look, x + (color == null ? 5 : 9), Gut.textTopAt(mid - size * Gut.lineRatio / 2, size * Gut.lineRatio, size));
  }
}
