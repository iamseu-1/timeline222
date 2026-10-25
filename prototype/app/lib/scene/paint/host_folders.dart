import 'dart:math' as math;

import '../band_form.dart';
import '../hit_test.dart' show Hit, HitKind;
import '../layout.dart' show SceneLayout, VariantInfo;
import '../tile.dart';
import 'bands.dart' show LidLook, LidTags;
import 'context.dart';
import 'paint_pick.dart';
import 'scopes.dart';

// 소속 폴더(리메이크 4단계 과제 8 걸음 2 · 스위치 folder — 설계 4-6 #6 · 목업 서고 folder): 펼친 상국의 소속을 서고의 폴더로 —
// 상국 띠가 첫 줄이고 그 아래가 소속 줄이다. 예전에는 상국 아래에 소속 줄만 끼워 쌓고 둘레가 없었다.
//
// 쌓기(layout.dart `_hostFolders`)가 켠 소속 펼치기 변형마다 켠 그릇(ScopeOn · uid = 변형 열쇠 `host:<상국 uid>` · 늘 펼침)을 등록해
// 머리 · 발 · 줄 위 틈을 그릇과 같은 길로 붙이고, 이 파일이 그 그릇을 대범위 층의 [ScopeIn] 꼴로 지어 [ScopeLayer.readScopes] 끝에 더한다.
// 그러면 그릇 그림이 그대로 그린다 — 깊이 0은 폴더(어깨 탭 라벨 '상국 이름 n'), 1 이상(그릇 안의 상국 · 포갠 소속)은 상자 —
// 그리고 readScopes를 읽는 매다는 실(openFolders) · 흠 ① 가로대 · 왼쪽 칸 폴더 줄도 함께 따라온다.
// 그릇 네 상태(폴더 탭 누름 번호 1 ~ 5 — 펼침 ↔ 접힘 · 선반 기억에 든 그릇의 가지 접기 뒤집기 5 [ScopeLayer.pressFold] · 오른쪽 클릭 메뉴)에는
// 넣지 않는다(대범위 층이 [SceneLayout.isHostFolder]로 건너뜀).
//
// 걸음 3(마무리): 누름 · 소속선.
//  · 누름 — 어깨 탭 · 상자 뚜껑의 라벨([ScopeLayer.hitHostFolder])과 왼쪽 칸의 폴더 그림 · 이름(GutterHitKind.folder · uid `host:…`)을 누르면
//    소속 펼치기 단추와 같은 맞히기([pressOf] — memberButton · 상국 띠 번호)로 앱 틀에 간다(timeline_view.dart). 앱 틀은 그 단추처럼 소속 펼치기를
//    끄고 켠다 — 폴더는 늘 펼침이라 누르면 소속을 접는다(archive_app.dart는 그대로).
//  · 소속선 — 같은 소속 폴더 안의 상국 → 소속은 긋지 않는다([holdsPart] · links.dart `_planPart`). 매다는 실이 대신한다(설계 4-2 '그릇에 듦 =
//    폴더 안에 매달림'). 소속 폴더가 없으면(조감 · 스위치 folder 끔 · 그 상국을 품은 그릇이 접힘) 예전 그대로다.
//
// 과제 8 걸음 1(스위치 lid): 상국 띠의 form 종류가 동군연합(16)이면 그 폴더(깊이 0)를 먹으로 칠한다([inked] — 설계 4-1 · 4-6 #6 A).
//    성격(구역 23의 label)이 동군연합인 그릇 폴더도 같다(걸음 4 검토 — 설계 4-1의 깊이 0 성격 넷 가운데 동군연합).
//    폴더 첫 줄은 상국 띠의 제 꼬리표 그대로다(새 그림 없음 — 쌓기가 상국 줄을 폴더 첫 줄로 · 실 매듭은 몸통 윗변 · 시험으로 못박음).
//
// 재료는 타일에서 읽는다: 상국 띠(색 — 이름은 변형 이름이 먼저) · 구역 26(소속 펼치기 단추)의 소속 수 n · 폴더 줄 띠들의 양 끝
// (상국 줄은 상국 띠만 — 같은 줄의 다른 띠는 폴더 밖이다). id는 음수(−변형 번호)라 구역 23의 항목 번호와 겹치지 않는다.
// row2는 −1 — 그릇 이름표 시대(구역 53) · 기간 칠(구역 24)이 줄 범위로 짝을 찾을 때 걸리지 않는다.

abstract final class HostFolders {
  /// 소속 폴더 [uid]의 상국 띠 번호 — 켠 소속 펼치기 변형(열쇠 = 폴더 uid)의 band. 소속 폴더가 아니거나 그 변형이 켜지지 않았으면 0.
  static int bandOf(SceneLayout layout, String uid) {
    if (!SceneLayout.isHostFolder(uid)) return 0;
    for (final v in layout.variantsOn) {
      if (v.kind == VariantInfo.kindHost && v.key == uid) return v.band;
    }
    return 0;
  }

  /// 소속 폴더를 누른 것(탭 · 뚜껑의 라벨 · 왼쪽 칸의 폴더 줄)의 맞히기 — 소속 펼치기 단추와 같은 [Hit](memberButton · 상국 띠 번호).
  /// 소속 폴더가 아니면 null(그릇 폴더의 누름은 예전 길 그대로).
  static Hit? pressOf(SceneLayout layout, String uid) {
    final band = bandOf(layout, uid);
    return band == 0 ? null : Hit(HitKind.memberButton, bandId: band);
  }

  /// 상국 띠 [host]의 소속선(구역 22 — 상국 줄 [hostRow] ↔ 소속 줄 [row])이 그 상국의 소속 폴더 안인가 — 그러면 소속선을 긋지 않는다
  /// (매다는 실이 대신 — 설계 4-2). 쌓기가 소속 폴더를 둔 때만 참이다(조감 · 집합 보기 판 · 스위치 folder 끔 · 접힌 그릇 안이면 폴더가 없다).
  static bool holdsPart(SceneLayout layout, int host, int hostRow, int row) {
    if (host == 0) return false;
    for (final v in layout.variantsOn) {
      if (v.kind != VariantInfo.kindHost || v.band != host) continue;
      final folder = layout.scopeOnOf(v.key);
      if (folder != null && folder.rows.contains(hostRow) && folder.rows.contains(row)) return true;
    }
    return false;
  }

  /// 상국 띠가 이 장면에 실려 오지 않았을 때 쓸 색(마지막으로 본 상국 띠의 색) — 배치마다 따로 기억한다.
  static final _colors = Expando<Map<String, int>>();

  /// 상국 띠의 form 종류가 동군연합(16)인 소속 폴더의 uid — 배치마다 따로 기억한다(상국 띠가 실리지 않은 장면에서도 먹 그대로).
  static final _unions = Expando<Set<String>>('동군연합 폴더');

  /// 그릇(구역 23)의 성격 글이 이것이면 동군연합 그릇 — 형식 4 다리(js/core.js `HT.F4.down`)가 시대 객체(트랙 · 구성원이 있어 그릇이 됨)의 `label`을
  /// 그릇의 성격(구역 23 text2의 뒤 · [ScopeIn.label])으로 싣는다(본보기: 시험 자료 nest-scene.f4의 합스부르크 군주국).
  static const unionLabel = '동군연합';

  /// 깊이 0 폴더를 먹으로 칠하는가(과제 8 걸음 1 · 설계 4-1 · 4-6 #6 A '동군연합 폴더는 먹' · 스위치 lid) — 상국이 동군연합인 소속 폴더([uid])와
  /// 성격([label])이 동군연합인 그릇 폴더(과제 8 걸음 4 검토). 칠 · 테만 바뀐다(scopes.dart `_paintFolder` — 값 [LidLook.folderFill] · [LidLook.folderEdge] ·
  /// 탭 · 이름표 시대 탭도 따라감). 기간의 짙은 구간(구역 24)은 그릇 색 그대로다. 스위치를 끄면 상국 · 그릇 색 그대로.
  static bool inked(PaintContext c, String uid, String label) =>
      PaintPick.lid && ((_unions[c.layout]?.contains(uid) ?? false) || label.trim() == unionLabel);

  /// 이 장면의 소속 폴더를 [out]에 더한다(조감이면 없다 — 쌓기도 소속 폴더를 두지 않는다).
  static void addTo(PaintContext c, Map<int, ScopeIn> out) {
    final layout = c.layout;
    if (layout.bird) return;
    for (final s in layout.scopesOn) {
      if (!SceneLayout.isHostFolder(s.uid)) continue;
      VariantInfo? v;
      for (final x in layout.variantsOn) {
        if (x.kind == VariantInfo.kindHost && x.key == s.uid) v = x;
      }
      final hostRow = layout.hostFolderRowOf(s.uid);
      if (v == null || v.band == 0 || hostRow < 0) continue;
      final one = _read(c, v, s.rows, hostRow);
      if (one != null) out[one.id] = one;
    }
  }

  static ScopeIn? _read(PaintContext c, VariantInfo v, Set<int> rows, int hostRow) {
    var lo = double.infinity, hi = double.negativeInfinity;
    int? color;
    var hostName = '';
    var count = 0;
    var union = false;
    for (final d in c.scene.draw) {
      final t = d.tile, origin = t.origin.toDouble();
      for (int i = 0; i < t.bandCount; i++) {
        final row = t.bandRow[i], id = t.bandId[i];
        final host = id == v.band;
        if (!host && (row == hostRow || !rows.contains(row))) continue;
        lo = math.min(lo, origin + t.bandX0[i]);
        hi = math.max(hi, origin + t.bandX1[i]);
        if (host) {
          color ??= t.bandColor[i];
          if (hostName.isEmpty) hostName = t.text(t.bandName[i]);
          if (BandForm.typeOf(t.bandForm[i]) == LidTags.typeUnion) union = true;
        }
      }
      final s = t.section(ScopeMarks.secMemBtn);
      if (count == 0 && s.count > 0) {
        final ref = s.u(Tile.itemRef), a = s.u(Tile.itemA);
        for (int i = 0; i < s.count; i++) {
          if (ref[i] == v.band) count = a[i];
        }
      }
    }
    if (lo > hi) return null;
    final seen = _colors[c.layout] ??= <String, int>{};
    if (color != null) seen[v.key] = color;
    if (union) (_unions[c.layout] ??= <String>{}).add(v.key);
    final track = c.layout.tracks.where((t) => t.id == v.track).firstOrNull;
    final ink = color ?? seen[v.key] ?? track?.color ?? 0xa0bcc5;
    return ScopeIn(-v.id, hostRow, -1, lo, hi, 0, ink, 0, v.name.isNotEmpty ? v.name : hostName, '', count: count, uid: v.key);
  }
}
