import 'dart:math' as math;
import 'dart:ui' as ui;

import '../color_mix.dart' as mix;
import 'batch.dart';

// 그 자리의 바탕색(불투명) — 장면마다 비우는 작은 목록(리메이크 4단계 · 감독 2026-10-25 15시 '맨 아래 연도 쭉 그려져 있고 그 위에 차례대로 얹는 것처럼').
// 연도 세로줄은 그림판 바탕 바로 위에 한 번 긋고(paint/grid.dart), 그 위의 띠 쪽 그림은 아래를 가리는 종이(불투명)로 얹는다.
// 반투명 칠(그릇 9% · 흐린 띠 · 바탕 문화 · 녹아드는 끝 …)은 **그 자리 바탕색과 미리 섞은 불투명 색**으로 칠해야 보이는 색이 예전과 같다
// (바탕이 단색이면 같은 픽셀 · 반올림 ±1 안). 바탕은 단색이 아니라(그릇 · 판 · 바탕 문화 · 한 칸 걸러 바탕 띠) **바탕 종이를 까는 층이
// 여기에 칸을 등록하고, 그 위에 얹는 층이 묻는다**. 줄(layout)은 그릇의 가로 범위 · 색 · 흐림을 모르므로 목록으로 둔다.
//
// 셈은 등록 칸 수(장면에 수십)만큼만 하고, 알파 < 1인 색에서만 묻는다. 세로줄 열을 셈하는 일은 없다.
// 칸은 가로로 선형(왼쪽 색 → 오른쪽 색)이라 옅어지는 끝도 담는다. 나중에 등록한 칸이 앞의 칸 위다(그리는 차례와 같다).

/// 장면의 바탕 칸 목록. 그리개는 [reset]에 그림판 바탕(`Look.ground`), SVG는 종이(`Look.paper` — SVG의 바탕이 종이라서)를 준다.
class Grounds {
  int _base = 0xffffffff;

  /// 칸이 없는 자리의 바탕색(불투명).
  int get base => _base;

  /// 지금 그리는 메움 타일의 자르기(그리개의 `_pass`가 건다) — 이 안에서 등록한 칸은 이 자리만큼만 등록된다(그 밖에는 그 칠이 그려지지 않았다).
  ui.Rect? clip;

  final _l = <double>[], _t = <double>[], _r = <double>[], _b = <double>[];
  final _cl = <int>[], _cr = <int>[];

  /// 등록한 칸 수.
  int get length => _l.length;

  /// 장면의 처음: 칸을 비우고 바탕색을 정한다.
  void reset(int base) {
    _base = 0xff000000 | base;
    clip = null;
    _l.clear();
    _t.clear();
    _r.clear();
    _b.clear();
    _cl.clear();
    _cr.clear();
  }

  /// 불투명한 바탕 칸 하나를 등록한다 — 왼쪽 끝 색 [colorL]에서 오른쪽 끝 색 [colorR](없으면 같음)으로 가로로 선형.
  /// [clip]이 걸려 있으면 그 안의 몫만(가로를 자르면 끝 색도 그 자리 값으로).
  void add(double l, double t, double r, double b, int colorL, [int? colorR]) {
    var cl = 0xff000000 | colorL, cr = 0xff000000 | (colorR ?? colorL);
    final k = clip;
    var nl = l, nt = t, nr = r, nb = b;
    if (k != null) {
      nl = math.max(l, k.left);
      nt = math.max(t, k.top);
      nr = math.min(r, k.right);
      nb = math.min(b, k.bottom);
    }
    if (nr - nl <= 0 || nb - nt <= 0) return;
    if (cl != cr && (nl != l || nr != r)) {
      final a = _lerp(cl, cr, (nl - l) / (r - l)), z = _lerp(cl, cr, (nr - l) / (r - l));
      cl = a;
      cr = z;
    }
    _l.add(nl);
    _t.add(nt);
    _r.add(nr);
    _b.add(nb);
    _cl.add(cl);
    _cr.add(cr);
  }

  /// 그 자리([x], [y])의 바탕색 — 그 자리를 품은 칸 가운데 가장 나중에 등록한 것, 없으면 [base].
  int at(double x, double y) {
    final i = _find(x, y);
    return i < 0 ? _base : _colorAt(i, x);
  }

  /// [argb]를 그 자리 바탕 위에 얹은 불투명 색 — 이미 불투명하면 그대로.
  int over(int argb, double x, double y) => (argb >>> 24) == 0xff ? argb : mix.over(argb, at(x, y));

  /// 그 자리 바탕색 종이를 깐다(테만 있는 칸 · 접힌 줄 줄무늬 밑 — 아래의 세로줄을 가린다). 등록 칸 경계에서 나눠 깐다.
  void paper(Quads q, double l, double t, double r, double b) => _split(l, t, r, b, (pl, pt, pr, pb, gl, gr) {
    if (gl == gr) {
      q.add(pl, pt, pr, pb, gl);
    } else {
      q.addFade(pl, pt, pr, pb, gl, gr);
    }
  });

  /// [argb]를 그 자리 바탕색과 섞은 불투명 색으로 칠한다(등록 칸 경계에서 나눠). [register]면 칠한 몫을 바탕 칸으로 등록한다(그 위에 얹는 층이 묻게).
  void fill(Quads q, double l, double t, double r, double b, int argb, {bool register = false}) =>
      fade(q, l, t, r, b, argb, argb, register: register);

  /// 왼쪽 [leftArgb] → 오른쪽 [rightArgb]로 번지는 칠(옅어지는 끝)을 그 자리 바탕색과 섞은 불투명 그러데이션으로 — 끝이 투명이면 그 자리 바탕색으로 녹는다.
  /// 바탕 칸도 번지는 자리(바탕 문화의 끝 위)는 4px씩 나눠 섞는다(두 번지는 값의 곱이 곧은 그러데이션이 아니라서).
  void fade(Quads q, double l, double t, double r, double b, int leftArgb, int rightArgb, {bool register = false}) {
    if (r - l <= 0 || b - t <= 0) return;
    if ((leftArgb >>> 24) == 0xff && (rightArgb >>> 24) == 0xff) {
      _emit(q, l, t, r, b, leftArgb, rightArgb, register);
      return;
    }
    final pieces = <(double, double, double, double, int, int)>[];
    _split(l, t, r, b, (pl, pt, pr, pb, gl, gr) {
      final steps = gl != gr && leftArgb != rightArgb ? math.max(1, ((pr - pl) / 4).ceil()) : 1;
      for (int i = 0; i < steps; i++) {
        final xa = pl + (pr - pl) * i / steps, xb = pl + (pr - pl) * (i + 1) / steps;
        final ga = _lerp(gl, gr, (xa - pl) / (pr - pl)), gb = _lerp(gl, gr, (xb - pl) / (pr - pl));
        final ta = _lerpArgb(leftArgb, rightArgb, (xa - l) / (r - l)), tb = _lerpArgb(leftArgb, rightArgb, (xb - l) / (r - l));
        pieces.add((xa, pt, xb, pb, mix.over(ta, ga), mix.over(tb, gb)));
      }
    });
    // 등록은 다 칠한 뒤 — 같은 칠의 앞 조각이 뒤 조각의 바탕으로 읽히지 않게.
    for (final p in pieces) {
      _emit(q, p.$1, p.$2, p.$3, p.$4, p.$5, p.$6, false);
    }
    if (register) {
      for (final p in pieces) {
        add(p.$1, p.$2, p.$3, p.$4, p.$5, p.$6);
      }
    }
  }

  /// 칠하지 않고 등록만 — 반투명 그대로 그린 칠(집합 보기의 판 · 한 칸 걸러 바탕 띠)이 그 자리 바탕을 바꾼 것을 알린다. 투명이면 아무것도 하지 않는다.
  void tint(double l, double t, double r, double b, int argb) {
    if ((argb >>> 24) == 0 || r - l <= 0 || b - t <= 0) return;
    final pieces = <(double, double, double, double, int, int)>[];
    _split(l, t, r, b, (pl, pt, pr, pb, gl, gr) => pieces.add((pl, pt, pr, pb, mix.over(argb, gl), mix.over(argb, gr))));
    for (final p in pieces) {
      add(p.$1, p.$2, p.$3, p.$4, p.$5, p.$6);
    }
  }

  void _emit(Quads q, double l, double t, double r, double b, int cl, int cr, bool register) {
    if (cl == cr) {
      q.add(l, t, r, b, cl);
    } else {
      q.addFade(l, t, r, b, cl, cr);
    }
    if (register) add(l, t, r, b, cl, cr);
  }

  /// [l] ~ [r] × [t] ~ [b]를 걸치는 칸의 경계에서 나눠, 조각마다 (자리, 왼쪽 끝 바탕색, 오른쪽 끝 바탕색)을 준다. 가로로 이웃한 같은 칸의 조각은 하나로 잇는다.
  void _split(double l, double t, double r, double b, void Function(double l, double t, double r, double b, int gl, int gr) emit) {
    if (r - l <= 0 || b - t <= 0) return;
    final hits = <int>[];
    for (int i = 0; i < _l.length; i++) {
      if (_l[i] < r && _r[i] > l && _t[i] < b && _b[i] > t) hits.add(i);
    }
    if (hits.isEmpty) {
      emit(l, t, r, b, _base, _base);
      return;
    }
    // 한 칸이 통째로 품으면 나눌 것이 없다(흔한 꼴 — 그릇 안의 띠).
    final last = hits.last;
    if (_l[last] <= l && _r[last] >= r && _t[last] <= t && _b[last] >= b) {
      emit(l, t, r, b, _colorAt(last, l), _colorAt(last, r));
      return;
    }
    final xs = <double>{l, r}, ys = <double>{t, b};
    for (final i in hits) {
      if (_l[i] > l) xs.add(_l[i]);
      if (_r[i] < r) xs.add(_r[i]);
      if (_t[i] > t) ys.add(_t[i]);
      if (_b[i] < b) ys.add(_b[i]);
    }
    final xl = xs.toList()..sort(), yl = ys.toList()..sort();
    for (int j = 0; j + 1 < yl.length; j++) {
      final y0 = yl[j], y1 = yl[j + 1], cy = (y0 + y1) / 2;
      var runFrom = xl[0], runCell = -2;
      for (int i = 0; i + 1 < xl.length; i++) {
        final cell = _findIn(hits, (xl[i] + xl[i + 1]) / 2, cy);
        if (runCell == -2) {
          runCell = cell;
        } else if (cell != runCell) {
          emit(runFrom, y0, xl[i], y1, _colorOr(runCell, runFrom), _colorOr(runCell, xl[i]));
          runFrom = xl[i];
          runCell = cell;
        }
      }
      emit(runFrom, y0, xl.last, y1, _colorOr(runCell, runFrom), _colorOr(runCell, xl.last));
    }
  }

  int _colorOr(int i, double x) => i < 0 ? _base : _colorAt(i, x);

  int _find(double x, double y) {
    for (int i = _l.length - 1; i >= 0; i--) {
      if (x >= _l[i] && x < _r[i] && y >= _t[i] && y < _b[i]) return i;
    }
    return -1;
  }

  int _findIn(List<int> hits, double x, double y) {
    for (int k = hits.length - 1; k >= 0; k--) {
      final i = hits[k];
      if (x >= _l[i] && x < _r[i] && y >= _t[i] && y < _b[i]) return i;
    }
    return -1;
  }

  int _colorAt(int i, double x) {
    final a = _cl[i], z = _cr[i];
    if (a == z) return a;
    final w = _r[i] - _l[i];
    return _lerp(a, z, w <= 0 ? 0 : ((x - _l[i]) / w).clamp(0.0, 1.0));
  }

  /// 불투명한 두 색 사이(감마 값 그대로 — 그림판의 꼭짓점 색 보간과 같다).
  static int _lerp(int a, int z, double f) {
    int ch(int s) => (((a >> s) & 0xff) + (((z >> s) & 0xff) - ((a >> s) & 0xff)) * f).round().clamp(0, 255);
    return 0xff000000 | ch(16) << 16 | ch(8) << 8 | ch(0);
  }

  /// 반투명한 두 색 사이 — 투명도를 곱한 값으로 보간한다(그림판의 꼭짓점 색 보간과 같다 · 같은 빛깔의 투명 끝이면 빛깔은 그대로 · 투명도만 곧게).
  static int _lerpArgb(int a, int z, double f) {
    if (a == z) return a;
    final aa = ((a >> 24) & 0xff) / 255, az = ((z >> 24) & 0xff) / 255;
    final alpha = aa + (az - aa) * f;
    if (alpha <= 0) return 0;
    int ch(int s) => ((((a >> s) & 0xff) * aa + (((z >> s) & 0xff) * az - ((a >> s) & 0xff) * aa) * f) / alpha).round().clamp(0, 255);
    return (alpha * 255).round().clamp(0, 255) << 24 | ch(16) << 16 | ch(8) << 8 | ch(0);
  }
}
