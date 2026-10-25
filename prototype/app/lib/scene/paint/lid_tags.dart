part of 'bands.dart';

// 그릇 노릇 객체의 꼴 — 제 줄의 납작한 뚜껑(리메이크 4단계 과제 8 걸음 1 · 스위치 lid · 설계 4-6 #6 A · 감독 허락 2026-10-25 '과제 8 셋 다').
// 뜻은 "안이 보이지 않는 그릇"(접힌 안쪽 그릇 · 동맹 한 뜻)이고, 꼴은 접힌 그릇과 같은 재료다 — 고르기 판 목업
// `.claude/research/stage4-choose/themes/w-common.js`의 `container()` closed 갈래(그 판의 '서하 자유시 동맹'이 접힌 그릇으로 그려진다).
//
// 대상([LidTags.isLid]): form 종류 17 동맹은 늘(제 소속 폴더가 펼쳐 있을 때만 빼고 — 아래) · 15 나라 · 16 동군연합은 구성원이 없을 때만
// (그 띠를 상국으로 삼는 소속 펼치기 변형이 배치에 없음).
// 뚜껑이 아닌 것: 14 시대(띠로 그리는 시대 — 감독 확인거리) · 18 사람 · form 0(옛 저장소 · 그림 띠) · 교단(제 꼬리표 — G6 가) ·
// 조감 · 바탕 문화 · 문화 띠 · 6px 알약(꼬리표 끝이 없는 길). 스위치 `lid`를 끄면(`--paint-off=lid` — 찍기 · 증명 전용) 예전 그대로다.
// 동맹을 상국으로 삼는 소속(상국이 하나뿐인 `partOf` member — 옛 꼴 자료의 길)이 있으면 내보내기가 동맹에도 소속 펼치기 변형을 짓고(variants.mjs —
// 상국 종류를 가리지 않음) 쌓기가 그 소속 폴더를 둔다. 그 폴더가 펼쳐 있는 동안은 안이 보이므로 동맹 띠도 폴더 첫 줄의 제 꼬리표다
// (닫힌 뚜껑이 열린 폴더의 머리가 되지 않게 — 과제 8 걸음 4 검토). 접으면 다시 뚜껑. '끌지 않는 그릇이라 폴더를 두지 않음'은 쌓기가 상국 종류를
// 모르므로(배치 답에 없음) 내보내기 몫이라 감독 확인거리로 남긴다.
//
// 띠 상자는 두 장 꼬리표와 같은 셈([BandLayer._tagBox] 하나를 함께 씀) — 줄 높이 · 띠 윗변 · 아랫변(몸통 아랫변) · 누름 상자 · 디버그 기록 · 고른 테 · 구멍 · 꼬리 마름모 ·
// 관계선의 구멍 셈([BandLayer.endOf]는 바꾸지 않음 — 관계선 · 받침 카드 · 종이 틈이 그대로) · 사건 점과 이름(events.dart) · 칸 층(strips.dart)은 그대로.
// 바뀌는 것은 칠 · 테 · 밑선 · 머리 이름의 먹뿐이다([LidLook]):
//   · 네 귀 모따기 6(목업 접힌 그릇 · 그릇 그림의 상자와 같은 값) — 화면에 잘린 쪽과 미정 끝은 직각.
//   · 칠은 사건 칸까지 하나(먹 6 → 그림판 먹 단계 4 — 불투명 회색이라 연도 세로줄이 비치지 않는다) · 나라 색 칠 · 무늬(빗금 · 점 · 연대 폭) ·
//     연맹 겹줄 · 깃대 · 칸 사이 금은 그리지 않는다(연합 조명은 띠 칠처럼 이름 색줄에).
//   · 테는 먹 30 → 단계 25 실선(대립 띠의 파선은 그대로 이김 · 검색 강조는 먹 · 올리면 한 단 짙게 — 예전 규칙).
//   · 밑선 먹 12는 이름 색줄의 아랫변 금 자리(색줄 끝 − 1). 목업은 위 + 6.5에 긋고 이름을 그 밑에 두지만, 앱은 이름이 머리 14 안이고
//     사건 칸이 그 밑이라 이름 자리와 사건 칸을 지키려고 금을 옮겼다(감독 확인거리). 몸통이 없는 줄(색줄뿐)은 밑선이 없다
//     (두 장 꼬리표와 같은 방어 길 — 지금 쌓기 `_bandOf`는 사건 칸을 늘 두어 생기지 않는다).
//   · 머리 이름은 자리 · 크기 9 그대로 먹 85(목업 접힌 그릇 이름 k(.85)) — 고른 · 올린 띠는 먹 · 부정된 띠는 옅은 먹 · 대립은 먹 60이 이긴다.
// 값은 그릇 그림(scopes.dart)의 접힌 상자(`ScopeLook.closedFill .06 · closedEdge .30 · boxRule .12` · 모따기 `boxCham` 6 · `_closedBox`)와 같은 수라
// 그 상수를 함께 쓴다(remake-4-scopes를 통합 가지에 합칠 때 하나로 모음 — 수는 그대로라 그림도 그대로).
// 동군연합 폴더의 먹(설계 4-1 · 4-6 #6 A — 상국이 동군연합인 소속 폴더 · 성격이 동군연합인 그릇 폴더)도 같은 스위치다 — 값은 [LidLook.folderFill] ·
// [LidLook.folderEdge], 판단은 host_folders.dart `HostFolders.inked`.

/// 뚜껑 꼬리표 · 동군연합 폴더의 값 — 먹 값은 옛 값(목업 값)이고 그릴 때 그림판 먹 단계([CanvasInk])로 낸다.
abstract final class LidLook {
  /// 네 귀 모따기 — 그릇 그림의 상자([ScopeLook.boxCham] 6)와 같은 값(정수 상수를 실수로).
  static const cham = ScopeLook.boxCham * 1.0;

  /// 칠 먹 6 · 테 먹 30 · 밑선 먹 12(목업 container closed의 k(.06) · k(.3) · k(.12) → 단계 4 · 25 · 12) — 그릇 그림의 접힌 상자
  /// ([ScopeLook.closedFill] · [ScopeLook.closedEdge] · [ScopeLook.boxRule])와 같은 값을 함께 쓴다.
  static const fill = ScopeLook.closedFill, edge = ScopeLook.closedEdge, rule = ScopeLook.boxRule;

  /// 머리 이름 먹 85(목업 접힌 그릇 이름 k(.85)).
  static const name = CanvasInk.k85;

  /// 동군연합 소속 폴더(깊이 0)의 칠 먹 3.5 · 테 먹 20 — 목업 w-common.js의 색 없는 폴더 k(.035) · k(.2)(→ 단계 4 · 25).
  /// 칠은 그릇 폴더 칠과 같이 먹 알파, 테는 불투명 회색. 탭 · 이름표 시대 탭은 몸통과 같은 칠 · 테를 따라간다.
  static const folderFill = .035, folderEdge = .20;
}

/// 뚜껑 판단(배치 · form만 보는 순수한 셈 — 그림판 상태와 무관).
abstract final class LidTags {
  /// form 종류 번호([BandForm.types]의 차례): 15 나라 · 16 동군연합 · 17 동맹.
  static const typeRealm = 15, typeUnion = 16, typeLeague = 17;

  /// 띠 [band](form [form])를 뚜껑으로 그리는가 — 동맹은 늘(제 소속 폴더가 펼쳐 있는 동안만 빼고 — [folderOpenOf]), 나라 · 동군연합은 구성원이 없을 때만.
  /// 스위치 `lid`가 꺼지면 거짓.
  static bool isLid(SceneLayout layout, int form, int band) {
    if (!PaintPick.lid || form == 0) return false;
    final type = BandForm.typeOf(form);
    if (type == typeLeague) return !folderOpenOf(layout, band);
    if (type == typeRealm || type == typeUnion) return !hostsOf(layout).contains(band);
    return false;
  }

  /// 띠 [band]를 상국으로 삼는 소속 폴더가 지금 펼쳐 있는가 — 그 띠의 소속 펼치기 변형이 켜졌고 쌓기가 그 폴더를 두었다
  /// (조감 · 집합 보기 판 · 스위치 `folder` 끔 · 접힌 그릇 안이면 폴더가 없어 거짓 — host_folders.dart `holdsPart`와 같은 판단).
  /// 보기 상태(펼침)를 따르므로 배치마다 기억하지 않는다 — 켠 변형은 몇 개뿐이다.
  static bool folderOpenOf(SceneLayout layout, int band) {
    if (band == 0) return false;
    for (final v in layout.variantsOn) {
      if (v.kind == VariantInfo.kindHost && v.band == band && layout.scopeOnOf(v.key) != null) return true;
    }
    return false;
  }

  /// 구성원이 있는 띠 — 그 띠를 상국(band)으로 삼는 소속 펼치기 변형([VariantInfo.kindHost])이 배치에 있는 띠. 배치마다 한 번만 센다.
  static Set<int> hostsOf(SceneLayout layout) =>
      _hosts[layout] ??= {for (final v in layout.variants) if (v.kind == VariantInfo.kindHost && v.band != 0) v.band};

  static final _hosts = Expando<Set<int>>('구성원이 있는 띠');
}

/// 띠 층의 뚜껑 그리기(bands.dart의 띠 · 머리 길이 부른다).
extension _LidPaint on BandLayer {
  /// 이 장면에서 띠를 뚜껑으로 그리는가 — 조감 · 바탕 문화 · 문화 띠는 아니다(꼬리표가 아님). 알약은 부르는 쪽(꼬리표 끝이 있는 길)이 거른다.
  bool _lidOf(PaintContext c, int look, int form, int band) =>
      PaintPick.lid && !c.layout.bird && look & BandLook.under == 0 && BandLook.kindOf(look) != BandKind.culture && LidTags.isLid(c.layout, form, band);

  /// 뚜껑 꼬리표 하나 — 띠 상자([l] ~ [r] · [top] ~ 두 장 꼬리표의 아랫변)에 모따기 칠 · 테 · 밑선. 누름 · 디버그 · 고른 테는 두 장 꼬리표와 같은 길.
  /// 띠의 값(look · 띠마다 나르는 값)은 타일 [t]의 [i]째 띠에서 상자 셈([_tagBox])이 읽는다.
  void _paintLid(PaintContext c, Tile t, int i, int row, RowGeo geo, int id, int form, _Fade fade, TagEnd tagEnd, double l, double top, double r, double b,
      bool openL, bool openR, bool fuzzyS, bool fuzzyE, double anchor) {
    // 띠 상자 — 두 장 꼬리표([_paintTwoPiece])와 한 셈(색줄 끝 · 몸통 아랫변 · 칸이 있는가 — 디버그 기록도 같은 글).
    var stripB = b, bodyB = b, body = false, hasCells = false;
    final two = geo.bodyTop >= 0;
    if (two) {
      final box = _tagBox(c, t, i, row, geo, b);
      (stripB, bodyB, hasCells) = (box.stripB, box.bodyB, box.hasCells);
      body = bodyB > stripB + .5;
    }
    final bottom = two ? (body ? bodyB : stripB) : b;
    final w = r - l, h = bottom - top;
    final shutL = openL || fuzzyS, shutR = openR || fuzzyE;
    final cap = math.min(w / 2, h / 2);
    final kl = shutL ? 0.0 : math.min(LidLook.cham, cap), kr = shutR ? 0.0 : math.min(LidLook.cham, cap);

    // 고른 테 — 예전 길([_ringOf]) · 왼쪽 귀는 뚜껑의 모따기(오른쪽은 그 길이 직각만 안다).
    if (_em.look.picked && fade.base > .99) _ringOf(c, id, row, l, top, r, bottom, kl, kl > 0, openL, openR, tagEnd, b - top);

    if (!c.hide.contains('bandFill')) {
      _lidFill(c, l, top, r, bottom, kl, kr, CanvasInk.gray(LidLook.fill), fade);
      if (_hotCoal != null) _coalLit(c, id, l, top, r, body ? stripB : bottom, fade.base);
      // 밑선 — 이름 색줄의 아랫변 금 자리(색줄 끝 − 1) · 테 안쪽(잘린 쪽은 끝까지). 두 끝은 두 장 꼬리표의 몸통 안 가로 금과 같은 셈([_innerSpan] —
      // 맞닿음(꼴 off가 아니면 · 감독 결정 2026-10-25 '모든 가로세로 구분선은 맞닿게')이면 테 열 바로 옆 정수 열까지 · 꼴 off면 예전 소수 셈 그대로).
      // 그 줄을 [innerRows]에 적어 할거기 경계 파선이 건너뛰고 대립 파선 테가 T자를 닫는다(꼴 off면 적지 않음 — 구분선 갈래와 합칠 때 더함).
      if (body) {
        final (inL, inR) = BandLayer._innerSpan(l, r, shutL, openR);
        _innerOf = PaintPick.rows == FloorRule.off ? -1 : id;
        _hLine(c, inL, inR, stripB - 1, CanvasInk.gray(LidLook.rule), EdgeStroke.solid, fade, anchor);
        _innerOf = -1;
      }
    }
    final matched = _em.look.filtered && (_em.look.bands?.contains(id) ?? false);
    final ink = CanvasInk.gray(LidLook.edge);
    final edge = matched ? BandLayer._warn : (id == (hotBand ?? c.scene.hoverBand) ? mixOklab(ink, Look.ink, .82) : ink);
    final stroke = TagLook.rivalOf(form) ? TagLook.rivalStroke : EdgeStroke.solid;
    if (!c.hide.contains('bandEdge')) {
      // 대립 파선 테는 밑선의 줄을 함께 넘겨 T자를 닫는다([_dashTees] — 맞닿음일 때만 적힌 줄 · 두 장 꼬리표와 같은 길).
      _edges.add(_EdgeJob(l, top, r, bottom, kl, kr, kl, kr, fade, edge, stroke, openL, openR, anchor,
          chamL: kl > 0, chamR: kr > 0, rows: stroke.dash > 0 ? innerRows[id] : null, teeL: !shutL));
    }
    _hits.add(_HitBox(l, top, r, bottom, id, row, false));
    c.stats.shapes++;
    c.debug?.bands.add(DebugBand(id, ui.Rect.fromLTRB(l, top, r, bottom), kl > 0, kr > 0, fuzzyS, fuzzyE));
    c.debug?.note(
      '띠',
      two
          ? '$id 한 장 색줄=${(stripB - top).round()} 몸통=${body ? (bodyB - stripB).round() : 0} 칸=$hasCells'
          : '$id 종류=${BandLook.kindOf(t.bandLook[i])} 반지름=${kl.round()}/${kr.round()} 뚜껑 ${stroke.name}',
    );
    c.debug?.note('뚜껑', '$id ${l.toStringAsFixed(1)},${top.toStringAsFixed(1)},${w.toStringAsFixed(1)},${h.toStringAsFixed(1)} 귀=${kl.round()}/${kr.round()}'
        ' 밑선=${body ? (stripB - 1).toStringAsFixed(1) : '-'} ${stroke.name}');
  }

  /// 뚜껑의 칠 — 네 귀 모따기(조각 [BandSprites.chamFill]의 네 사분면) + 네모. 옅은 끝 · 조명은 [_band]가 꼭짓점 색으로 번지게 한다.
  /// 띠 칠([_fill]의 paper 길)과 같이 아래의 연도 세로줄을 가리는 종이다(리메이크 4단계 세로줄 얹기 · 4단계 마지막 합치기): 흐림 · 옅은 끝으로 반투명이 된
  /// 칠은 그 자리 바탕색과 섞은 불투명 색으로 칠하고(네모 — [_band] paper), 반투명이 된 귀는 귀 칸 가운데의 바탕색과 섞어 밑 조각([_underSprites])으로,
  /// 끝이 px 사이에 선 기둥에는 밑 종이([BandLayer._edgePaper])를 깐다. 처음부터 불투명한 귀(흐림 없음)는 예전 묶음 그대로(바이트 같음).
  void _lidFill(PaintContext c, double l, double t, double r, double b, double kl, double kr, int fill, _Fade fade) {
    void corner(double k, BandCorner where, double left, double top, double x) {
      final argb = withAlpha(fill, fade.alphaAt(x));
      if ((argb >>> 24) != 0xff) {
        _underSprites.add(BandSprites.chamFill(k), where, left, top, c.grounds.over(argb, x, top + k / 2), k);
      } else {
        sprites.add(BandSprites.chamFill(k), where, left, top, argb, k);
      }
    }

    BandLayer._edgePaper(c, l, t + kl, b - kl, left: true);
    BandLayer._edgePaper(c, r, t + kr, b - kr, left: false);
    if (kl > 0) {
      corner(kl, BandCorner.topLeft, l, t, l + kl / 2);
      corner(kl, BandCorner.bottomLeft, l, b - kl, l + kl / 2);
      _band(c, l, t + kl, l + kl, b - kl, fill, fade, paper: true);
    }
    if (kr > 0) {
      corner(kr, BandCorner.topRight, r - kr, t, r - kr / 2);
      corner(kr, BandCorner.bottomRight, r - kr, b - kr, r - kr / 2);
      _band(c, r - kr, t + kr, r, b - kr, fill, fade, paper: true);
    }
    _band(c, l + kl, t, r - kr, b, fill, fade, paper: true);
  }
}
