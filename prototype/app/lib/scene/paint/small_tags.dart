import 'dart:math' as math;
import 'dart:ui' as ui;

import '../color_mix.dart';
import '../text_paragraph.dart';
import 'context.dart';
import 'gutter.dart' show Gut;
import 'look.dart';

/// 작은 꼬리표 — 접힌 그릇이 안의 띠를 대신 보이는 꼴(목업 d5-b · d2-b의 packTags · smallTag).
/// 리메이크 조각 ②의 접힌 문화권 머리 단(왼쪽 칸 층)과 조각 ③의 접힌 폴더(대범위 층)가 함께 쓴다.
/// 꼬리표는 높이 13 · 왼쪽 두 귀 모따기 3 · 구멍 · 이름 8.5 굵게, `+n` 칩은 종이 · 먹 40 테.
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

  /// 놓은 꼬리표 하나([spot] — [pack]의 답)를 세로 가운데 [mid]에 그린다. 구멍의 점은 [dot](지름 · 왼쪽 · 위 · 색)으로 —
  /// 층마다 제 점 그림판을 쓴다. [tag]는 글자 판의 이름(시험이 찾는다).
  static void paint(PaintContext c, (double, double, String, int?) spot, double mid, void Function(double size, double left, double top, int argb) dot,
      {String tag = 'smallTag'}) {
    final (x, w, label, color) = spot;
    const h = height, k = _cham;
    final y0 = (mid - h / 2).roundToDouble(), y1 = y0 + h;
    final fill = color == null ? Look.paper : mixSrgb(color, Look.paper, .24);
    final edge = color == null ? mixSrgb(Look.ink, Look.paper, .4) : mixOklab(color, Look.ink, .84);
    final ink = color == null ? mixSrgb(Look.ink, Look.paper, .6) : mixSrgb(color, Look.ink, .22);
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
      dot(4, x + 3, mid - 2, mixSrgb(Look.ink, Look.paper, .45));
      dot(2, x + 4, mid - 1, Look.paper);
    }
    final look = TextLook(size, ui.FontWeight.w700, ink);
    c.later.add(tag, label, look, x + (color == null ? 5 : 9), Gut.textTopAt(mid - size * Gut.lineRatio / 2, size * Gut.lineRatio, size));
  }
}
