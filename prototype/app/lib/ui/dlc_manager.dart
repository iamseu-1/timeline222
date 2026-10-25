import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scene/fonts.dart';
import '../scene/layout.dart';
import '../scene/scene.dart';
import '../shell/line_icon.dart';
import '../shell/look.dart';
import '../shell/motion_widgets.dart';
import '../motion.dart';
import '../shell/sheet_look.dart';
import '../shell/sheet_parts.dart';
import 'dlc_add.dart' show DlcHidden, DlcJob, DlcRoute, dlcNoOriginalOffText, dlcRoute, dlcRouteRefusal, dlcScreenOnlyNote;
import 'dlc_layout_import.dart' show DlcPackFacts;

// DLC 관리 창 — 지금 연표의 `🧩 DLC 관리`(js/viewer.js:3011~ · css/viewer.css:660~709 · docs/구상-메이커-팩 2-5)를 옮긴 것.
//
// 3단계의 몫은 **설치된 DLC를 자유롭게 켜고 끄는 것**이었고, 4단계 1걸음(`docs/설계-아카이브-4단계-1걸음-DLC-앱-안에서.md`)에서
// **파일에서 더하기 · 삭제**가 앱 안으로 들어왔다(뒷일은 `ui/dlc_add.dart`의 [DlcJob] · 바꿔 넣기와 뼈대 다시 읽기는 앱 틀):
//   · `파일에서 더하기`(위 칸)와 줄 끝의 `DLC 삭제`(기본팩도 — 2026-10-16). 도는 동안 위 칸에 진행 · 까닭이 보인다([DlcJob.status]).
//   · 켜고 끄기(2026-10-16 감독 건의 "숨기면 연표 자체에서 등장하지 않게"): 끈 DLC를 **저장소에서 뺀다**([DlcManagerBody.onToggle] — 엔진 `remove_pack`,
//     원본은 저장소의 보관함 · 켜면 `add_pack`으로 다시 — 계획 P4 과제 10b) — 화면에서만 가리면 날짜 칸의 시대 · 검색 · 필터 · 판 …에 끈 DLC가 남았다.
//     끈 DLC의 줄은 `DLC/hidden.json`의 값([DlcHidden])으로 그린다.
//   · 마지막 하나도 끌 수 있다 — 다 끄면 연표가 비고, 그 자리의 안내([dlcEmptyText])는 창을 띄운 쪽이 [DlcManager.onChanged]로 받아 세운다.
//     (2단계의 창은 "줄이 하나도 남지 않는 조합은 만들지 않는다"고 막아, DLC가 하나뿐인 저장소에서는 스위치가 아예 눌리지 않았다.)
//   · 백업 단추는 아직 없다. 화면에 보이는 말은 모두 `DLC`다(지금 연표 그대로). 코드의 이름 · 측정 구간 이름의 '자료집'은 그대로 둔다.
//
// 창의 꼴(리메이크 4단계 과제 9 걸음 1 — 감독 고름 G5 #9 다듬기 판 `sm-dlc` · 목업 g-sheet-menu `drawDlc` — git 밖): 카드 모눈을 걷고 서고 폴더로.
//   폴더 'DLC 관리 {수}'(가운데 · 폭 1180 안 · 뒤는 먹 20 깔개 그대로) · 위 칸 = 찾기(흰 종이 칸 · 돋보기) · 파일에서 더하기 · 모두 켜기 · 모두 끄기 |
//   닫기(흰 종이 단추) · 일 진행 줄([DlcJob.status]) 자리는 그대로.
//   왼쪽 상자 '켠 DLC {수}'(뚜껑 오른쪽 '불러오는 차례') = 불러오는 차례대로 **실에 꿴** 꼬리표 줄(차례 번호 · 이름 · 판 · '원본 없음' · 트랙 작은
//   꼬리표(제 트랙 = 제 색 · 얹은 트랙 = 흰 종이 **점선** — 점선은 얹기만) · 담긴 것 · 끄기 · 삭제) / '보관함 · 꺼 둔 DLC {수}' = **실에서 내린**
//   흰 종이 줄(먹 25 실선 · 글 옅게 · 켜기 · 삭제). 오른쪽 상자 '자세히' = 표지(트랙마다 꼬리표 · 길이는 줄 수 — 예전 막대 표지를 갈음) · 이름 17 · 판 ·
//   담긴 것 · (원본) · 트랙 줄(얹은 트랙은 흰 종이 점선 + 주인 DLC) · 번호 · 글자 id. 고른 줄은 고른 테(먹 100 · 1.5). 아래 줄은 켜 둔 수와 불러오는 차례.
//   삭제는 자세히에서 줄 끝으로 옮겼다(지울 수 없는 줄은 그 자리를 비움). 좁은 창 · 휴대폰은 자세히가 목록 밑으로.
//   켜고 끄기의 엔진 길 · 화면에서만 끄는 바탕 알림 · 삭제 확인 · 기본팩 · 다 껐을 때 안내 · 찾기 거르기 · 키보드 · 콜백 이름 · 단추 글은 그대로다.
//
// 줄에 적는 값은 모두 자료 처리부가 준 것이다(`{"op":"layout"}`의 `packs` · `tracks`) — 이 저장소에는
// 지은이 · 설명 · 태그 · 분류 · 표지 그림이 없으므로 **만들어 넣지 않는다**(있는 값만 적는다).
// 판(version)과 `원본 없음`(예전 메이커 배치로만 든 DLC — A2 5-4 · 5-6)은 `{"op":"layout"}`의 `packs[]`에서 온다([DlcPackFacts]):
// 앱 틀이 뼈대를 읽을 때마다 [DlcJob.packFacts]를 채우고(이 창이 떠 있는 동안에도 따라온다), 검사는 [DlcManager.packFacts]로 준다. 옛 저장소는 없어 예전 줄 그대로다.

/// 기본팩(동아시아사 기본팩)의 글자 id. 기본팩도 끄고 뺄 수 있다(2026-10-16 감독 건의) — '기본팩' 표시와 삭제 확인 글만 다르다.
const dlcBaseKey = 'east-asia-base';

/// 다 껐을 때 연표 자리에 서는 안내 — 지금 연표의 `emptyText`(js/viewer.js:207) 그대로.
const dlcEmptyText = '표시할 트랙이 없습니다. 필터나 DLC 설정을 확인하세요.';

/// 세 자리마다 쉼표: 1250000 → 1,250,000
String formatCount(int n) {
  final digits = '$n', out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// 켜 둔 DLC 가운데 트랙을 가진 것이 하나도 없으면 참 — 연표 자리에 [dlcEmptyText]를 세울 때.
/// (트랙 없이 남의 줄에 사건만 덧붙이는 DLC는 혼자 켜져 있어도 연표가 빈다 — 지금 연표의 `model.tracks.length`와 같은 잣대.)
/// 집합 보기의 판 트랙은 세지 않는다(판을 켰을 때만 서는 합성 트랙이다).
bool dlcTimelineEmpty(SceneLayout layout) {
  for (int i = 0; i < layout.tracks.length; i++) {
    if (!layout.isBoardTrack(i) && layout.isPackEnabled(layout.tracks[i].pack)) return false;
  }
  return true;
}

/// 그 DLC의 켜기([on]) · 끄기 · 삭제([remove])가 갈 길(계획 P4 과제 10b — [dlcRoute]를 줄 하나로): 엔진(add_pack · remove_pack — 휴대폰도) ·
/// 화면에서만(엔진이 빼지 못하는 바탕 · 원본 없이 든 DLC의 끄기 · 글자 id 없는 옛 저장소) · 없음(바탕 빼기) — 판정 R43.
/// 원본 없이 든 DLC([DlcCardInfo.original] 거짓 — 메이커 배치로만 넣은 것)를 엔진이 빼면 남길 원본이 없어 지워지므로 끄기는 화면에서만(고침 1회차 I-1).
DlcRoute dlcCardRoute(DlcCardInfo card, SceneLayout layout, {required DlcHidden hidden, bool remove = false, bool on = false}) {
  if (card.key.isEmpty) return remove ? DlcRoute.none : DlcRoute.screen;
  if (!remove && !on && card.stored && !card.original) return DlcRoute.screen;
  return dlcRoute(
    packKeys: [for (final p in layout.packs) p.key],
    hidden: hidden,
    baseKey: dlcBaseKey,
    removeKey: remove ? card.key : null,
    offKeys: !remove && !on ? [card.key] : const [],
    onKeys: !remove && on ? [card.key] : const [],
  );
}

/// DLC를 화면에서만 켜고 끈 까닭의 알림 — 엔진이 빼지 못하는 바탕(저장소의 첫 DLC · 글자 id 없는 옛 저장소)이면 바탕의 알림([dlcScreenOnlyNote])이
/// 먼저다(원본 없는 바탕도 — 10b 고침 재검토), 바탕이 아닌데 원본 없이 든 DLC를 끄면 그 DLC 이름과 함께 그 알림([dlcNoOriginalOffText]).
String dlcScreenNote(DlcCardInfo card, SceneLayout layout, {required DlcHidden hidden, bool on = false}) {
  if (on || card.original || card.key.isEmpty) return dlcScreenOnlyNote;
  final base = dlcRoute(packKeys: [for (final p in layout.packs) p.key], hidden: hidden, baseKey: dlcBaseKey, offKeys: [card.key]) != DlcRoute.engine;
  return base ? dlcScreenOnlyNote : dlcNoOriginalOffText(card.name);
}

/// 창이 줄 하나로 그리는 DLC 하나(예전 이름 그대로 '카드'). 값은 모두 `{"op":"layout"}`가 준 것이다.
class DlcCardInfo {
  const DlcCardInfo({
    required this.id,
    required this.name,
    required this.events,
    required this.tracks,
    this.key = '',
    this.isBase = false,
    this.periods = 0,
    this.shared = const [],
    this.owners = const {},
    this.version = '',
    this.original = true,
    this.stored = true,
  });
  final int id, events;

  /// 저장소에 들어 있는가. 거짓이면 꺼 두어 저장소에서 뺀 DLC다(값은 `DLC/hidden.json`의 것 — [DlcCardInfo.hiddenOf]) · [id]는 음수.
  final bool stored;
  final String name;

  /// DLC의 판(`meta.pack_info`의 `version` — 모르면 빈 글이고 줄에 적지 않는다).
  final String version;

  /// 원본 팩을 저장소에 품었는가. 거짓이면 줄에 `원본 없음`(예전 메이커의 아카이브 배치로만 들어와 .htpack이 없다 — 5-4).
  final bool original;

  /// 이 DLC의 띠(나라 · 시대) 수(`layout.packs[].periods` — 옛 저장소는 0).
  final int periods;

  /// 이 DLC의 띠 · 사건이 얹힌 **남의 트랙**(같은 id의 트랙은 먼저 켠 DLC의 것으로 합쳐진다 — `DLC-형식.md`의 트랙 `id`).
  /// 나라 52개를 기본팩의 한국 트랙에 얹은 DLC는 제 트랙이 없어도 여기 한국이 든다 — "트랙 없음"으로 읽히지 않게(2026-09-22 감독의 실제 DLC).
  final List<TrackInfo> shared;

  /// 얹은 트랙마다 그 트랙을 데려온 DLC의 이름(자세히에 적는다).
  final Map<int, String> owners;

  /// DLC의 글자 id(`layout.packs[].key` — 옛 저장소는 빈 글 · 그때는 뺄 수 없다).
  final String key;

  /// 동아시아 기본팩(글자 id [dlcBaseKey] — 글자 id 없는 옛 저장소는 첫 DLC)인가. 삭제 확인 글이 다르다(되살리는 길을 적는다). 저장소의 바탕(첫 DLC — 빼지
  /// 못하는 자리)과는 다르다: 등불 바탕 저장소에 넣은 동아시아 DLC는 기본팩이지만 바탕이 아니다(판정 R60 I-1 — 길은 [dlcCardRoute]가 가른다).
  final bool isBase;

  /// 이 DLC가 데려오는 트랙(없을 수 있다 — 남의 줄에 사건만 덧붙이는 DLC).
  final List<TrackInfo> tracks;

  int get rows {
    int sum = 0;
    for (final t in tracks) {
      sum += t.rowCount;
    }
    return sum;
  }

  /// '담긴 것' 한 줄 — 지금 연표의 설치 알림("사건 N개, 시대 M개")과 `.pk-meta`(담긴 것) 자리.
  /// 제 트랙이 없어도 남의 트랙에 얹은 것이 있으면 `얹은 트랙 n개`로 적는다 — 둘 다 없을 때만 `트랙 없음`.
  String get contents {
    final parts = ['사건 ${formatCount(events)}건', if (periods > 0) '시대 ${formatCount(periods)}개'];
    if (tracks.isNotEmpty) parts.add('트랙 ${tracks.length}개 · 줄 $rows개');
    if (shared.isNotEmpty) parts.add('얹은 트랙 ${shared.length}개');
    if (tracks.isEmpty && shared.isEmpty) parts.add('트랙 없음');
    return parts.join(' · ');
  }

  /// 트랙 이름을 이어 붙인 글(없으면 빈 글) — 찾기가 함께 본다. 얹은 트랙도 든다.
  String get trackNames => [...tracks, ...shared].map((t) => t.name).join(' · ');

  /// 끈 목록(`DLC/hidden.json`)에 적을 값 — 끄면 저장소에서 빠지므로 그 뒤의 줄은 이 값으로 그린다([DlcCardInfo.hiddenOf]의 거꾸로 · add-dlc.mjs의
  /// `cardsOfStore`와 같은 꼴).
  Map<String, dynamic> get hiddenCard => {
    'name': name,
    'version': version,
    'events': events,
    'periods': periods,
    'tracks': [for (final t in tracks) {'key': t.key, 'name': t.name, 'color': t.color, 'rows': t.rowCount}],
    'shared': [for (final t in shared) {'key': t.key, 'name': t.name, 'color': t.color, 'owner': owners[t.id] ?? ''}],
  };

  /// 이름으로 찾기(대소문자 · 앞뒤 빈칸 무시). 트랙 이름도 함께 본다 — 지금 연표가 이름 · id · 소개 · 태그를 함께 보는 자리.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) || trackNames.toLowerCase().contains(q);
  }

  /// [facts]는 글자 id마다의 판 · 원본(없으면 판은 빈 글 · 원본은 있음 — 예전 값 그대로).
  /// [hidden]의 끈 DLC 가운데 저장소에 없는 것은 그 값으로 뒤에 붙인다(꺼 둔 기본팩은 맨 앞).
  /// [kept]: 저장소의 보관함(`{"op":"kept_packs"}` — 꺼 둔 DLC의 원본) — 끈 목록에 값이 없는 것도(끈 목록 쓰기가 실패했거나 깨짐) 이름 · 판만으로
  /// 세운다(판정 R60 I-3 덤 — 켜거나 지울 길이 보이게).
  static List<DlcCardInfo> of(
    SceneLayout layout, {
    Map<String, DlcPackFacts> facts = const {},
    DlcHidden hidden = DlcHidden.none,
    List<({String id, String name, String version})> kept = const [],
  }) {
    final stored = _stored(layout, facts);
    final have = {for (final c in stored) if (c.key.isNotEmpty) c.key};
    final away = [for (final key in hidden.off.toList()..sort()) if (!have.contains(key) && hidden.cards[key] != null) key];
    final shelved = [
      for (final k in [...kept]..sort((a, b) => a.id.compareTo(b.id)))
        if (k.id.isNotEmpty && !have.contains(k.id) && !away.contains(k.id)) k,
    ];
    final cards = [
      for (final (i, key) in away.indexed) DlcCardInfo.hiddenOf(-1 - i, key, hidden.cards[key]!),
      for (final (i, k) in shelved.indexed) DlcCardInfo.hiddenOf(-1 - away.length - i, k.id, {'name': k.name, 'version': k.version}),
    ];
    return [...cards.where((c) => c.isBase), ...stored, ...cards.where((c) => !c.isBase)];
  }

  /// 꺼 두어 저장소에서 뺀 DLC — 도구가 끌 때 떠 둔 값(`{name, version, events, periods, tracks:[{key,name,color,rows}], shared:[{key,name,color,owner}]}`).
  factory DlcCardInfo.hiddenOf(int id, String key, Map<String, dynamic> m) {
    int n(Object? v) => v is num ? v.toInt() : 0;
    List<Map> list(Object? v) => [if (v is List) for (final t in v) if (t is Map) t];
    final own = list(m['tracks']), shared = list(m['shared']);
    final sharedTracks = [for (final (i, t) in shared.indexed) TrackInfo(-1001 - i, -1, '${t['name'] ?? ''}', 0, 0, color: n(t['color']), key: '${t['key'] ?? ''}')];
    return DlcCardInfo(
      id: id,
      name: '${m['name'] ?? key}',
      events: n(m['events']),
      key: key,
      isBase: key == dlcBaseKey,
      periods: n(m['periods']),
      version: '${m['version'] ?? ''}',
      stored: false,
      tracks: [for (final (i, t) in own.indexed) TrackInfo(-1 - i, id, '${t['name'] ?? ''}', 0, n(t['rows']), color: n(t['color']), key: '${t['key'] ?? ''}')],
      shared: sharedTracks,
      owners: {for (final (i, t) in shared.indexed) sharedTracks[i].id: '${t['owner'] ?? ''}'},
    );
  }

  static List<DlcCardInfo> _stored(SceneLayout layout, Map<String, DlcPackFacts> facts) => [
    for (final pack in layout.packs)
      DlcCardInfo(
        id: pack.id,
        name: pack.name,
        events: pack.events,
        key: pack.key,
        isBase: pack.key.isNotEmpty ? pack.key == dlcBaseKey : pack.id == layout.packs.first.id,
        periods: pack.periods,
        version: facts[pack.key]?.version ?? '',
        original: facts[pack.key]?.original ?? true,
        // 집합 보기의 판 트랙(그 DLC의 판마다 하나)은 '담긴 트랙'이 아니다.
        tracks: [
          for (int i = 0; i < layout.tracks.length; i++)
            if (layout.tracks[i].pack == pack.id && !layout.isBoardTrack(i)) layout.tracks[i],
        ],
        shared: [
          for (int i = 0; i < layout.tracks.length; i++)
            if (layout.tracks[i].pack != pack.id && pack.touches.contains(layout.tracks[i].id) && !layout.isBoardTrack(i)) layout.tracks[i],
        ],
        owners: {
          for (int i = 0; i < layout.tracks.length; i++)
            if (layout.tracks[i].pack != pack.id && pack.touches.contains(layout.tracks[i].id) && !layout.isBoardTrack(i))
              layout.tracks[i].id: _ownerName(layout, layout.tracks[i]),
        },
      ),
  ];

  /// 그 트랙을 데려온 DLC의 이름.
  static String _ownerName(SceneLayout layout, TrackInfo track) {
    for (final p in layout.packs) {
      if (p.id == track.pack) return p.name;
    }
    return '';
  }
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  창
// ════════════════════════════════════════════════════════════════════════════════════════════

/// DLC 관리 창을 띄운다. 나타남 200 · 사라짐 160(`docs/움직임-원칙.md`).
/// [onChanged]는 켜고 끌 때마다 새 조합으로 불린다 — 창을 띄운 쪽이 연표 자리의 안내를 세우고 기억에 적는다.
/// [onAddFiles]가 있으면 위 칸에 `파일에서 더하기` 단추가, [onRemove]가 있으면 줄 끝에 `DLC 삭제`가 선다
/// (앱 틀이 파일 고르기 · 엔진의 고쳐 쓰기 · 뼈대 다시 읽기를 맡는다 — 4단계 1걸음 · 계획 P4 과제 10b). [job]은 그 뒷일의 상태(위 칸에 진행 · 까닭을 보인다).
/// 넣기 · 지우기 · 끄기 · 켜기는 휴대폰도 컴퓨터도 엔진 하나로 된다([dlcCardRoute]) — 엔진이 빼지 못하는 바탕(저장소의 첫 DLC)은 삭제 자리가 비고
/// 켜고 끄기는 화면에서만(판정 R43).
/// [packFacts]는 줄의 판 · `원본 없음`(글자 id마다 — 앱 틀은 [DlcJob.packFacts]를 채우므로 검사만 준다).
/// [onToggle]이 있으면 끄기 · 켜기 · 모두 켜기/끄기가 그것을 부른다 — 앱 틀이 끈 DLC를 **저장소에서 뺀다**(원본은 보관함 — 숨긴 DLC가 연표 어디에도 남지 않게).
/// 없으면(검사 · 측정) 예전처럼 화면에서만 켜고 끈다.
Future<void> showDlcManager(
  BuildContext context,
  TimelineScene scene, {
  void Function(Set<int> packs)? onChanged,
  Future<void> Function()? onAddFiles,
  Future<void> Function(DlcCardInfo card)? onRemove,
  Future<void> Function(List<DlcCardInfo> cards, bool on)? onToggle,
  DlcJob? job,
  Map<String, DlcPackFacts>? packFacts,
}) => Navigator.of(context, rootNavigator: true).push<void>(DlcManagerRoute(scene: scene, onChanged: onChanged, onAddFiles: onAddFiles, onRemove: onRemove, onToggle: onToggle, job: job, packFacts: packFacts));

/// DLC 관리 창의 길 — 나타남 200 · 사라짐 160. (`showGeneralDialog`는 사라지는 길이를 따로 받지 못한다.)
class DlcManagerRoute extends PopupRoute<void> {
  DlcManagerRoute({required this.scene, this.onChanged, this.onAddFiles, this.onRemove, this.onToggle, this.job, this.packFacts});
  final Future<void> Function()? onAddFiles;
  final Future<void> Function(DlcCardInfo card)? onRemove;
  final Future<void> Function(List<DlcCardInfo> cards, bool on)? onToggle;
  final DlcJob? job;
  final Map<String, DlcPackFacts>? packFacts;
  final TimelineScene scene;
  final void Function(Set<int> packs)? onChanged;

  @override
  Duration get transitionDuration => const Duration(milliseconds: Motion.popMs);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: Motion.outMs * 2);

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'DLC 관리 닫기';

  @override
  Color get barrierColor => Ui.ink20; // 창 뒤는 흐림 없이 먹 20 깔개(css의 dialog::backdrop)

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) => MotionPresence(open: animation.status == AnimationStatus.forward || animation.status == AnimationStatus.completed, alignment: Alignment.center, child: child!),
    child: DlcManager(scene: scene, onChanged: onChanged, onAddFiles: onAddFiles, onRemove: onRemove, onToggle: onToggle, job: job, packFacts: packFacts),
  );

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    // 경로의 시간은 수명만 맡고, 움직임은 공통 장의 면 하나가 맡는다.
    return child;
  }
}

/// DLC 관리 창(폴더 'DLC 관리 {수}'). 검사는 이것을 바로 띄운다.
class DlcManager extends StatelessWidget {
  const DlcManager({super.key, required this.scene, this.onChanged, this.onAddFiles, this.onRemove, this.onToggle, this.job, this.packFacts});
  final TimelineScene scene;
  final Future<void> Function()? onAddFiles;
  final Future<void> Function(DlcCardInfo card)? onRemove;
  final Future<void> Function(List<DlcCardInfo> cards, bool on)? onToggle;
  final DlcJob? job;

  /// 줄의 판 · `원본 없음`(글자 id마다). 없으면 예전 줄 그대로.
  final Map<String, DlcPackFacts>? packFacts;

  /// 켜고 끈 뒤의 조합. 비어 있으면 연표가 빈 것이다([dlcTimelineEmpty]).
  final void Function(Set<int> packs)? onChanged;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // 지금 연표의 `#dlcDialog`: width min(1180px, 100vw − 24) · max-height 100dvh − 32.
    final width = math.min(SheetLook.dlcWidth, media.size.width - 24);
    final height = math.max(240.0, media.size.height - 32);
    return Center(
      // 뜬 길 위의 글 · 찾기 칸에도 바탕(Material)을 둔다 — 없으면 Flutter가 글마다 '바탕 없음' 겹밑줄을 긋고 찾기 칸이 서지 못한다(디버그).
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: const TextStyle(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback, fontSize: 14, height: 1.5, color: SheetLook.ink85, decoration: TextDecoration.none),
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
            child: Focus(
              autofocus: true,
              child: SizedBox(
                width: width,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: height),
                  child: DlcManagerBody(
                    scene: scene,
                    onChanged: onChanged,
                    onAddFiles: onAddFiles,
                    onRemove: onRemove,
                    onToggle: onToggle,
                    job: job,
                    packFacts: packFacts,
                    folder: true,
                    onClose: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 창의 알맹이 — 위 칸(찾기 · 단추) · 켠 DLC · 보관함 + 자세히 · 아래 줄. 작은 자리(옛 `PackPanel`)에도 그대로 들어간다.
/// [folder]면 폴더 'DLC 관리 {수}'로 싸고, [onClose]가 있으면 위 칸 오른쪽 끝에 닫기 단추가 선다.
class DlcManagerBody extends StatefulWidget {
  const DlcManagerBody({super.key, required this.scene, this.onChanged, this.onAddFiles, this.onRemove, this.onToggle, this.job, this.packFacts, this.folder = false, this.onClose});
  final TimelineScene scene;
  final void Function(Set<int> packs)? onChanged;
  final Future<void> Function()? onAddFiles;
  final Future<void> Function(DlcCardInfo card)? onRemove;
  final Future<void> Function(List<DlcCardInfo> cards, bool on)? onToggle;
  final DlcJob? job;
  final Map<String, DlcPackFacts>? packFacts;
  final bool folder;
  final VoidCallback? onClose;

  @override
  State<DlcManagerBody> createState() => DlcManagerBodyState();
}

class DlcManagerBodyState extends State<DlcManagerBody> {
  final _find = TextEditingController();
  final _scroll = ScrollController();

  /// 고른 줄(자세히에 나오는 것 — 아직 고르지 않았으면 null). 이 창에서만 기억한다 — 지금 연표의 `dlcUi.sel`.
  /// (-1 같은 표시 값을 쓰지 않는다: 저장소에서 뺀 DLC의 번호가 음수(-1부터)라 아직 고르지 않았는데 그 줄이 골라졌다 — 걸음 5의 실제 앱 그림.)
  int? _selected;

  @override
  void initState() {
    super.initState();
    widget.scene.addListener(_onScene);
    widget.job?.addListener(_onScene);
  }

  @override
  void dispose() {
    widget.scene.removeListener(_onScene);
    widget.job?.removeListener(_onScene);
    _find.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 삭제 — 지금 연표의 `removePack`과 같은 확인 글. 확인하면 앱 틀의 [DlcManagerBody.onRemove]가 끄는 흐름 → 뒤에서 엔진의 고쳐 쓰기(`remove_pack`)를 맡는다.
  Future<void> _remove(DlcCardInfo card) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Ui.surface,
        title: Text('"${card.name}" DLC를 삭제할까요?', style: const TextStyle(fontFamily: Ui.title, fontFamilyFallback: Ui.titleFallback, fontSize: 16, fontWeight: FontWeight.w700, color: Ui.text)),
        content: Text(card.isBase ? ((widget.job?.phone ?? false) ? dlcBaseRemovePhoneText : dlcBaseRemoveText) : '다시 설치하려면 DLC 파일이 필요합니다.', style: const TextStyle(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback, fontSize: 13.5, height: 1.5, color: Ui.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await widget.onRemove?.call(card);
  }

  void _onScene() {
    if (mounted) setState(() {});
  }

  SceneLayout get _layout => widget.scene.layout;

  /// DLC — 판 · 원본은 준 값 위에 지금 뼈대의 값([DlcJob.packFacts] — 앱 틀이 뼈대를 읽을 때마다 채운다)을 덮는다.
  List<DlcCardInfo> get _cards =>
      DlcCardInfo.of(_layout, facts: {...?widget.packFacts, ...?widget.job?.packFacts}, hidden: widget.job?.hidden ?? DlcHidden.none, kept: widget.job?.kept ?? const []);

  /// 켜져 있는가 — 켜고 끄는 중이면 부탁한 쪽([DlcJob.toggling]), 아니면 저장소에 있고 켠 것.
  bool _isOn(DlcCardInfo card) => widget.job?.toggling[card.key] ?? (card.stored && _layout.isPackEnabled(card.id));

  /// 켜고 끄기 · 삭제가 갈 길([dlcCardRoute]) — 앱 틀이 길을 주지 않았으면(검사 · 측정) 화면에서만.
  DlcRoute _route(DlcCardInfo card, {bool on = false, bool remove = false}) {
    if (remove ? widget.onRemove == null : widget.onToggle == null) return remove ? DlcRoute.none : DlcRoute.screen;
    return dlcCardRoute(card, _layout, hidden: widget.job?.hidden ?? DlcHidden.none, remove: remove, on: on);
  }

  /// 저장소에서 켜고 끄는가(앱 틀이 엔진으로 — [DlcManagerBody.onToggle]).
  bool _stores(DlcCardInfo card, bool on) => _route(card, on: on) == DlcRoute.engine;

  /// 삭제 단추가 서는가 — 엔진(remove_pack)으로 뺄 수 있을 때(엔진이 빼지 못하는 바탕은 자리를 비운다).
  bool _canRemove(DlcCardInfo card) => _route(card, remove: true) == DlcRoute.engine;

  /// 켜고 끈다 — **막지 않는다.** 마지막 하나도 끌 수 있고, 다 끄면 연표가 빈다.
  /// 앱 틀이 끈 DLC를 저장소에서 뺀다([DlcManagerBody.onToggle] — 엔진 `remove_pack`의 보관함) — 도는 동안에는 받지 않는다.
  /// 엔진이 빼지 못하는 바탕(저장소의 첫 DLC)과 원본 없이 든 DLC의 끄기는 화면에서만(알림 — [dlcScreenOnlyNote] · [dlcNoOriginalOffText] · 판정 R43 · 고침 1회차).
  void _set(DlcCardInfo card, bool on) {
    final route = _route(card, on: on);
    if (route == DlcRoute.engine) {
      if (!(widget.job?.running ?? false)) widget.onToggle!([card], on);
      return;
    }
    if (route == DlcRoute.none) {
      widget.job?.notice(dlcRouteRefusal());
      return;
    }
    if (!card.stored) return;
    final next = {..._layout.enabledPacks.where((id) => id != card.id), if (on) card.id};
    _apply(next, notes: widget.onToggle == null ? const [] : [dlcScreenNote(card, _layout, hidden: widget.job?.hidden ?? DlcHidden.none, on: on)]);
  }

  void _setAll(List<DlcCardInfo> cards, bool on) {
    final change = [for (final c in cards) if (_isOn(c) != on) c];
    final stores = [for (final c in change) if (_stores(c, on)) c];
    final screenCards = [for (final c in change) if (c.stored && _route(c, on: on) == DlcRoute.screen) c];
    final screen = [for (final c in screenCards) c.id];
    if (stores.isNotEmpty && (widget.job?.running ?? false)) return;
    if (screen.isNotEmpty || stores.isEmpty) {
      final next = widget.onToggle == null
          ? (on ? {for (final p in _layout.packs) p.id} : <int>{})
          : (on ? {..._layout.enabledPacks, ...screen} : _layout.enabledPacks.toSet().difference(screen.toSet()));
      // 화면에서만인 까닭 — DLC마다(바탕이면 바탕의 알림 · 원본 없이 든 DLC를 끄면 그 알림) 한 번씩.
      final notes = widget.onToggle == null ? const <String>[] : {for (final c in screenCards) dlcScreenNote(c, _layout, hidden: widget.job?.hidden ?? DlcHidden.none, on: on)}.toList();
      _apply(next, notes: notes);
    }
    if (stores.isNotEmpty) widget.onToggle!(stores, on);
  }

  /// 화면에서만 켜고 끈다. 앱 틀이 있는데도 화면에서만이면(엔진이 빼지 못하는 바탕 · 원본 없이 든 DLC) 위 칸에 그 사정([notes])을 알린다.
  void _apply(Set<int> next, {List<String> notes = const []}) {
    setState(() => widget.scene.setPacks(next));
    widget.onChanged?.call(next);
    for (final note in notes) {
      widget.job?.notice(note);
    }
  }

  /// 위 칸(28) · 틈 14 · 켠 DLC와 보관함 + 자세히(넘치면 이 칸만 넘김) · 아래 줄.
  @override
  Widget build(BuildContext context) {
    final cards = _cards;
    final shown = [
      for (final card in cards)
        if (card.matches(_find.text)) card,
    ];
    final onShown = [for (final c in shown) if (_isOn(c)) c];
    final offShown = [for (final c in shown) if (!_isOn(c)) c];
    // 불러오는 차례 — 켠 DLC 모두 가운데의 차례(찾기로 걸러도 번호는 그대로).
    final order = <int, int>{};
    for (final c in cards) {
      if (_isOn(c)) order[c.id] = order.length + 1;
    }
    // 고른 것이 없거나 사라졌으면 걸러진 것 가운데 첫 DLC(DLC 차례 — 켜고 꺼서 상자를 옮겨도 자세히가 따라 바뀌지 않게)를 고른다 —
    // 지금 연표의 `dlcMainHTML`과 같은 길.
    final picked = _selected;
    final int? selected = picked != null && cards.any((c) => c.id == picked) ? picked : (shown.isNotEmpty ? shown.first.id : cards.firstOrNull?.id);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _top(cards, allOn: cards.every(_isOn), allOff: !cards.any(_isOn)),
        const SizedBox(height: SheetLook.dlcGap),
        Flexible(
          child: SingleChildScrollView(
            controller: _scroll,
            child: LayoutBuilder(builder: (context, box) => _lists(box, cards, shown, onShown, offShown, order, selected)),
          ),
        ),
        _foot(cards),
      ],
    );
    if (!widget.folder) return Padding(padding: const EdgeInsets.fromLTRB(22, 8, 22, 18), child: body);
    return SheetFolder(
      label: 'DLC 관리',
      count: '${cards.length}',
      padding: const EdgeInsets.fromLTRB(SheetLook.dlcPad, SheetLook.dlcPadTop, SheetLook.dlcPad, SheetLook.dlcPadBottom),
      child: body,
    );
  }

  /// 위 칸 — 찾기(흰 종이 칸 240 · 돋보기) · 뒷일의 상태(도는 중 · 실패의 까닭 · 끝난 뒤의 알림) · 파일에서 더하기 · 모두 켜기 · 모두 끄기 | 닫기.
  /// 폭이 [SheetLook.dlcTwoLines]보다 좁으면 두 줄(찾기 · 닫기 / 상태 · 단추). (분류 거르기 · 백업은 아직 없다.)
  Widget _top(List<DlcCardInfo> cards, {required bool allOn, required bool allOff}) {
    final job = widget.job;
    final busy = job?.running ?? false;
    Widget? status;
    if (job != null && (job.running || job.failed)) {
      status = Row(
        children: [
          if (job.running) ...[
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: SheetLook.ink60)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              job.status,
              key: const ValueKey('dlc-job-status'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sheetText(SheetLook.dlcContents, color: job.failed ? SheetLook.ink85 : SheetLook.ink60),
            ),
          ),
        ],
      );
    } else if (job != null && job.notes.isNotEmpty) {
      // 끝난 뒤에 남긴 알림(배치 더하기 — `판을 확인할 수 없습니다` · `원본 없음` · 화면에서만 끈 까닭). 다음 일을 시작하면 사라진다.
      status = Tooltip(
        message: job.notes.join('\n'),
        child: Text(
          job.notes.join(' · '),
          key: const ValueKey('dlc-job-notes'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: sheetText(SheetLook.dlcContents, color: SheetLook.ink45),
        ),
      );
    }
    const gap = SizedBox(width: SheetLook.dlcButtonGap);
    final buttons = <Widget>[
      // 파일에서 더하기(4단계 1걸음 · 계획 P4 과제 10b · 11c): 메이커가 저장한 DLC 파일(.htpack)을 골라 더한다 — 앱 틀이 엔진으로 맡는다. 도는 동안은 잠근다.
      if (widget.onAddFiles != null) SheetPaperButton(key: const ValueKey('dlc-add-files'), label: '파일에서 더하기', height: SheetLook.dlcTop, onTap: busy ? null : () => widget.onAddFiles!()),
      SheetPaperButton(label: '모두 켜기', height: SheetLook.dlcTop, onTap: cards.isEmpty || allOn || busy ? null : () => _setAll(cards, true)),
      SheetPaperButton(label: '모두 끄기', height: SheetLook.dlcTop, onTap: cards.isEmpty || allOff || busy ? null : () => _setAll(cards, false)),
    ];
    final close = widget.onClose == null ? null : SheetPaperButton(label: '닫기', height: SheetLook.dlcTop, onTap: widget.onClose);
    final find = _FindField(controller: _find, onChanged: (_) => setState(() {}));
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= SheetLook.dlcTwoLines) {
          return SizedBox(
            height: SheetLook.dlcTop,
            child: Row(
              children: [
                SizedBox(width: SheetLook.dlcFind, child: find),
                const SizedBox(width: 12),
                Expanded(child: status ?? const SizedBox.shrink()),
                const SizedBox(width: 12),
                for (var i = 0; i < buttons.length; i++) ...[if (i > 0) gap, buttons[i]],
                if (close != null) ...[
                  // 닫기 앞 가름 금(먹 25 · 위아래 4 들임).
                  const SizedBox(width: SheetLook.dlcGap),
                  const SizedBox(width: 1, height: SheetLook.dlcTop - 8, child: ColoredBox(color: SheetLook.ink25)),
                  const SizedBox(width: SheetLook.dlcGap),
                  close,
                ],
              ],
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: SheetLook.dlcTop,
              child: Row(children: [Expanded(child: find), if (close != null) ...[gap, close]]),
            ),
            const SizedBox(height: 8),
            Wrap(alignment: WrapAlignment.end, spacing: SheetLook.dlcButtonGap, runSpacing: SheetLook.dlcButtonGap, children: buttons),
            if (status != null) ...[const SizedBox(height: 8), SizedBox(height: 16, child: status)],
          ],
        );
      },
    );
  }

  /// 켠 DLC(실에 꿴 줄) · 보관함(실에서 내린 줄) — 넓으면 오른쪽에 자세히(목록과 키를 맞춰 표지가 남는 키를 갖는다), 좁으면 목록 밑에.
  Widget _lists(BoxConstraints box, List<DlcCardInfo> cards, List<DlcCardInfo> shown, List<DlcCardInfo> onShown, List<DlcCardInfo> offShown, Map<int, int> order, int? selected) {
    Widget row(DlcCardInfo card) {
      final job = widget.job;
      final removing = job != null && job.running && job.removingKey == card.key;
      final removable = _canRemove(card);
      return DlcRow(
        key: ValueKey('dlc-card-${card.id}'),
        card: card,
        on: _isOn(card),
        order: order[card.id] ?? 0,
        selected: card.id == selected,
        onPick: () => setState(() => _selected = card.id),
        onToggle: (on) => _set(card, on),
        removeSlot: widget.onRemove != null,
        showRemove: removable || removing,
        removing: removing,
        // 고른 줄의 삭제 단추는 'dlc-remove' — 예전 자세히의 단추와 같은 이름(검사 · 측정이 찾는다).
        removeKey: card.id == selected ? const ValueKey('dlc-remove') : ValueKey('dlc-remove-${card.id}'),
        onRemove: removable && !removing
            ? () {
                setState(() => _selected = card.id);
                _remove(card);
              }
            : null,
      );
    }

    Widget note(String text) => SizedBox(
      height: SheetLook.chip,
      child: Align(alignment: Alignment.centerLeft, child: Text(text, style: sheetText(SheetLook.dlcContents, color: SheetLook.ink45))),
    );

    final onBox = SheetBox(
      label: '켠 DLC',
      count: '${onShown.length}',
      hint: '불러오는 차례',
      child: onShown.isEmpty
          ? note(shown.isEmpty && _find.text.trim().isNotEmpty ? '맞는 DLC가 없습니다.' : '켠 DLC가 없습니다.')
          : SheetThreadColumn(gap: SheetLook.dlcRowGap, children: [for (final c in onShown) row(c)]),
    );
    final list = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        onBox,
        if (offShown.isNotEmpty) ...[
          const SizedBox(height: SheetLook.dlcBoxGap),
          // 보관함 — 원본을 저장소에 둔 꺼 둔 DLC(화면에서만 끈 것도) · 실에 꿰지 않는다.
          SheetBox(
            label: '보관함 · 꺼 둔 DLC',
            count: '${offShown.length}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < offShown.length; i++) ...[if (i > 0) const SizedBox(height: SheetLook.dlcRowGap), row(offShown[i])],
              ],
            ),
          ),
        ],
      ],
    );
    final picked = cards.where((c) => c.id == selected).firstOrNull;
    if (picked == null) return list;
    final wide = box.maxWidth >= SheetLook.dlcWide;
    final detail = DlcDetail(card: picked, on: _isOn(picked), fill: wide);
    if (!wide) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [list, const SizedBox(height: SheetLook.dlcBoxGap), KeyedSubtree(key: const Key('dlc-detail'), child: detail)],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: list),
          const SizedBox(width: SheetLook.dlcColumnGap),
          SizedBox(key: const Key('dlc-detail'), width: SheetLook.dlcDetail, child: detail),
        ],
      ),
    );
  }

  /// 아래 줄 — 금(먹 12) 밑에 켜 둔 DLC 수 · 불러오는 차례. (지금 연표의 '파일을 끌어다 놓으면 설치됩니다'는 이 단계에 없다.)
  Widget _foot(List<DlcCardInfo> cards) {
    final on = [
      for (final card in cards)
        if (_isOn(card)) card,
    ];
    final order = on.map((c) => c.name).join(' → ');
    final empty = dlcTimelineEmpty(_layout);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: SheetLook.dlcGap),
        const SizedBox(height: 1, child: ColoredBox(color: SheetLook.ink12)),
        const SizedBox(height: 6),
        Text(
          '켜 둔 DLC ${on.length}개 · 불러오는 차례: ${order.isEmpty ? '없음' : order}${empty ? ' — $dlcEmptyText' : ''}',
          style: sheetText(SheetLook.dlcContents, color: SheetLook.ink60).copyWith(height: 1.5),
        ),
      ],
    );
  }
}

/// 찾기 칸 — 흰 이름 종이(모따기 3 · 테 먹 45 · 쓰는 동안 먹 85) 안 돋보기 14(왼쪽 10) · 글 13. 회색 예시 글자는 두지 않는다.
class _FindField extends StatefulWidget {
  const _FindField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_FindField> createState() => _FindFieldState();
}

class _FindFieldState extends State<_FindField> {
  final _focus = FocusNode(debugLabel: 'DLC 찾기');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '이름으로 찾기',
    textField: true,
    child: Tooltip(
      message: '이름으로 찾기',
      child: SheetTag(
        shape: SheetShape(chamfer: SheetLook.paperChamfer, stroke: _focus.hasFocus ? SheetLook.ink85 : SheetLook.ink45),
        height: SheetLook.dlcTop,
        child: Row(
          children: [
            const SizedBox(width: SheetLook.dlcFindLead),
            const LineIcon(LineGlyph.search, size: SheetLook.dlcFindIcon, color: SheetLook.ink60),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                maxLines: 1,
                textAlignVertical: TextAlignVertical.center,
                cursorColor: SheetLook.ink85,
                cursorWidth: 1.5,
                style: sheetText(13).copyWith(height: 1.2),
                decoration: const InputDecoration.collapsed(hintText: null),
                onChanged: widget.onChanged,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  줄 · 자세히
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 트랙 꼬리표의 갈래 — 줄의 작은 꼬리표 · 표지 · 자세히의 트랙 줄이 함께 쓴다.
enum DlcTrackMode {
  /// 제 트랙: 제 색 꼬리표(칠 24% · 테 84% + 먹 · 글 = 탭 글).
  own,

  /// 남의 트랙에 얹은 것: 흰 종이 · 그 트랙 색 테 · **점선**(점선은 얹기만) · 글 먹 60.
  shared,

  /// 꺼 둔 DLC의 트랙: 흰 종이 · 먹 25 실선 · 글 먹 45(얹은 트랙이어도 실선).
  off,
}

/// DLC 관리 창의 꼴 — 값이라 검사가 바로 본다.
abstract final class DlcLook {
  /// 줄 꼬리표 50: 흰 종이 · 켠 줄 = 테 먹 45 · 구멍 테 45 / 꺼 둔 줄 = 테 먹 25 · 구멍 테 25(실선). 올리면 칠 먹 4.
  static SheetShape row({required bool on, bool hover = false}) => SheetShape(
    fill: hover ? SheetLook.ink4 : SheetLook.paper,
    stroke: on ? SheetLook.ink45 : SheetLook.ink25,
    hole: true,
    holeStroke: on ? SheetLook.ink45 : SheetLook.ink25,
  );

  static DlcTrackMode modeOf({required bool on, required bool shared}) => !on ? DlcTrackMode.off : (shared ? DlcTrackMode.shared : DlcTrackMode.own);

  static SheetShape _track(Color c, DlcTrackMode mode, {double chamfer = SheetLook.tagChamfer, double hole = SheetLook.holeRadius, required List<double> dash}) => SheetShape(
    chamfer: chamfer,
    fill: mode == DlcTrackMode.own ? SheetLook.tagFill(c) : SheetLook.paper,
    stroke: mode == DlcTrackMode.off ? SheetLook.ink25 : SheetLook.tagEdge(c),
    dash: mode == DlcTrackMode.shared ? dash : null,
    hole: true,
    holeRadius: hole,
    holeStroke: mode == DlcTrackMode.off ? SheetLook.ink25 : SheetLook.ink45,
  );

  /// 줄의 작은 트랙 꼬리표 14(모따기 3 · 구멍 1.5) — 얹은 트랙은 점선 '2 2'.
  static SheetShape mini(Color c, DlcTrackMode mode) => _track(c, mode, chamfer: SheetLook.dlcMiniChamfer, hole: SheetLook.dlcMiniHole, dash: SheetLook.dlcSharedDash);

  /// 표지 · 자세히의 트랙 꼬리표(24 · 22 — 모따기 5 · 구멍 2.5) — 얹은 트랙은 점선 '3 2'.
  static SheetShape track(Color c, DlcTrackMode mode) => _track(c, mode, dash: SheetLook.dlcSharedDashWide);

  /// 트랙 꼬리표의 이름 글 — 제 트랙 = 탭 글(제 색 22% + 먹) · 얹은 트랙 = 먹 60 · 꺼 둠 = 먹 45.
  static Color inkOf(Color c, DlcTrackMode mode) => switch (mode) {
    DlcTrackMode.own => SheetLook.tagInk(c),
    DlcTrackMode.shared => SheetLook.ink60,
    DlcTrackMode.off => SheetLook.ink45,
  };

  /// '원본 없음' 흰 종이(18 · 모따기 3 · 테 먹 25).
  static const badge = SheetShape(chamfer: SheetLook.paperChamfer, stroke: SheetLook.ink25);
}

Color _colorOf(TrackInfo t) => Color(0xff000000 | t.color);

/// DLC 줄 하나 — 꼬리표 50(켠 DLC는 실에 꿰고 보관함은 내려놓음). 첫 줄 = 차례 번호(켠 것만) · 이름 · 판 · '원본 없음' /
/// 둘째 줄 = 트랙 작은 꼬리표(제 트랙 · 얹은 트랙) · 담긴 것 / 오른쪽 = 끄기(켜기) · 삭제(지울 수 없으면 자리만). 누르면 자세히(고른 테).
class DlcRow extends StatefulWidget {
  const DlcRow({
    super.key,
    required this.card,
    required this.on,
    required this.order,
    required this.selected,
    required this.onPick,
    required this.onToggle,
    this.onRemove,
    this.removeSlot = false,
    this.showRemove = false,
    this.removing = false,
    this.removeKey,
  });
  final DlcCardInfo card;
  final bool on, selected;

  /// 불러오는 차례(1부터 — 0이면 적지 않음: 보관함의 줄).
  final int order;
  final VoidCallback onPick;
  final ValueChanged<bool> onToggle;

  /// 삭제 단추의 일(없으면 누를 수 없음 — [removing]).
  final VoidCallback? onRemove;

  /// [removeSlot] — 삭제 자리를 두는가(앱 틀이 삭제 길을 주었을 때) · [showRemove] — 그 자리에 단추가 서는가(엔진이 뺄 수 있을 때 · 지우는 중).
  final bool removeSlot, showRemove, removing;
  final Key? removeKey;

  @override
  State<DlcRow> createState() => _DlcRowState();
}

class _DlcRowState extends State<DlcRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final card = widget.card, on = widget.on, numbered = widget.order > 0;
    final tracks = [for (final t in card.tracks) (t, false), for (final t in card.shared) (t, true)];
    // 첫 줄(가운데 17): 차례 번호 · 이름 · 판은 한 바탕선, '원본 없음'은 가운데.
    final head = Row(
      children: [
        SizedBox(width: numbered ? SheetLook.dlcOrder - (SheetLook.dlcLead - SheetLook.dlcOrder) : SheetLook.dlcLead),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (numbered)
                SizedBox(
                  width: (SheetLook.dlcLead - SheetLook.dlcOrder) * 2,
                  child: Center(heightFactor: 1, child: Text('${widget.order}', maxLines: 1, softWrap: false, style: sheetText(SheetLook.dlcVersion, bold: true, color: SheetLook.ink45))),
                ),
              Flexible(
                child: Text(card.name, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: sheetText(SheetLook.dlcName, bold: true, color: on ? SheetLook.ink85 : SheetLook.ink60)),
              ),
              if (card.version.isNotEmpty) ...[
                const SizedBox(width: SheetLook.dlcVersionGap),
                Text('v${card.version}', maxLines: 1, softWrap: false, style: sheetText(SheetLook.dlcVersion, color: SheetLook.ink45)),
              ],
            ],
          ),
        ),
        if (!card.original) ...[const SizedBox(width: SheetLook.dlcBadgeGap), const DlcNoOriginalTag()],
      ],
    );
    // 둘째 줄(가운데 36): 트랙 작은 꼬리표 · 담긴 것 — 들지 않는 꼬리표는 그리지 않는다(모두는 자세히에).
    final tail = Padding(
      padding: const EdgeInsets.only(left: SheetLook.dlcLead),
      child: SheetFitRun(
        children: [
          for (final (t, shared) in tracks) _MiniTag(track: t, mode: DlcLook.modeOf(on: on, shared: shared)),
          Text(card.contents, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: sheetText(SheetLook.dlcContents, color: on ? SheetLook.ink60 : SheetLook.ink45)),
        ],
      ),
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DlcSwitch(value: on, onChanged: widget.onToggle, label: card.name),
        if (widget.removeSlot) ...[
          const SizedBox(width: SheetLook.dlcButtonGap),
          if (widget.showRemove)
            SheetPaperButton(
              key: widget.removeKey,
              label: widget.removing ? '삭제하는 중…' : 'DLC 삭제',
              semantics: '${card.name} — ${widget.removing ? '삭제하는 중…' : 'DLC 삭제'}',
              quiet: true,
              onTap: widget.onRemove,
            )
          else
            // 엔진이 빼지 못하는 바탕 · 글자 id 없는 옛 저장소 — 자리만 비운다(줄마다 끄기 단추가 한 줄에 서게).
            const Visibility(visible: false, maintainSize: true, maintainAnimation: true, maintainState: true, child: SheetPaperButton(label: 'DLC 삭제', quiet: true)),
        ],
      ],
    );
    final body = SheetTag(
      shape: DlcLook.row(on: on, hover: _hover),
      height: SheetLook.dlcRow,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: SheetLook.dlcLine1 - SheetLook.dlcBadge / 2),
                SizedBox(height: SheetLook.dlcBadge, child: head),
                const SizedBox(height: SheetLook.dlcLine2 - SheetLook.dlcMini / 2 - SheetLook.dlcLine1 - SheetLook.dlcBadge / 2),
                SizedBox(height: SheetLook.dlcMini, child: tail),
              ],
            ),
          ),
          const SizedBox(width: 12),
          buttons,
          const SizedBox(width: SheetLook.dlcButtonRight),
        ],
      ),
    );
    return SheetPickRing(
      on: widget.selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Semantics(
          button: true,
          selected: widget.selected,
          label: '${card.name} — 누르면 자세히',
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onPick, child: body),
        ),
      ),
    );
  }
}

/// 줄의 작은 트랙 꼬리표 — 키 14 · 글 8.5 굵게(앞 10 · 뒤 5).
class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.track, required this.mode});
  final TrackInfo track;
  final DlcTrackMode mode;

  @override
  Widget build(BuildContext context) {
    final c = _colorOf(track);
    return SheetTag(
      shape: DlcLook.mini(c, mode),
      height: SheetLook.dlcMini,
      child: Padding(
        padding: const EdgeInsets.only(left: SheetLook.dlcMiniLead, right: SheetLook.dlcMiniTail),
        child: Center(widthFactor: 1, child: Text(track.name, maxLines: 1, softWrap: false, style: sheetText(SheetLook.dlcMiniText, bold: true, color: DlcLook.inkOf(c, mode)))),
      ),
    );
  }
}

/// 고른 DLC의 자세히 — 상자 '자세히'(폭 352): 표지 · 이름 17 + 판 · 담긴 것 · (원본) · 트랙 · 번호 줄. 저장소에 있는 값만 적는다.
/// [fill]이면 옆 목록과 키를 맞춰(상자가 받은 키) 표지가 남는 키를 갖는다(아래에 빈 자리가 뜨지 않게 — 목업과 같은 셈).
class DlcDetail extends StatelessWidget {
  const DlcDetail({super.key, required this.card, required this.on, this.fill = false});
  final DlcCardInfo card;
  final bool on, fill;

  @override
  Widget build(BuildContext context) {
    final tracks = [for (final t in card.tracks) (t, false), for (final t in card.shared) (t, true)];
    final body = sheetText(SheetLook.dlcBody).copyWith(height: SheetLook.dlcBodyLine / SheetLook.dlcBody);
    final cover = CustomPaint(painter: DlcCoverPainter(card: card, on: on, style: DefaultTextStyle.of(context).style));
    final coverMin = DlcCoverPainter.minHeight(card);
    // 마디: 금(먹 12) → 제목(금에서 가운데 16) → 글(첫 줄 가운데가 금에서 35) · 트랙 줄은 금에서 30.
    List<Widget> section(String title, {double below = 3}) => [
      const SizedBox(height: 1, child: ColoredBox(color: SheetLook.ink12)),
      const SizedBox(height: 16 - SheetLook.dlcSection / 2 - 1),
      Text(title, maxLines: 1, softWrap: false, style: sheetText(SheetLook.dlcSection, bold: true, color: SheetLook.ink60)),
      SizedBox(height: below),
    ];
    return SheetBox(
      label: '자세히',
      fill: fill,
      padding: const EdgeInsets.fromLTRB(SheetLook.dlcDetailPad, SheetLook.dlcDetailTop, SheetLook.dlcDetailPad, SheetLook.dlcDetailPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fill)
            Expanded(child: ConstrainedBox(constraints: BoxConstraints(minHeight: coverMin), child: cover))
          else
            SizedBox(height: coverMin, child: cover),
          const SizedBox(height: SheetLook.dlcCoverBelow),
          SizedBox(
            height: 18,
            child: Align(
              alignment: Alignment.centerLeft,
              // 이름과 판은 한 글(한 바탕선) — 판은 줄에도 따로 선다.
              child: Text.rich(
                TextSpan(
                  text: card.name,
                  children: [if (card.version.isNotEmpty) TextSpan(text: '  v${card.version}', style: sheetText(SheetLook.dlcTitleVersion, color: SheetLook.ink45))],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sheetText(SheetLook.dlcTitle, bold: true),
              ),
            ),
          ),
          const SizedBox(height: SheetLook.dlcTitleBelow),
          ...section('담긴 것'),
          Text(card.contents, style: body),
          if (!card.original) ...[
            const SizedBox(height: SheetLook.dlcSectionGap),
            ...section('원본'),
            Text(dlcNoOriginalText, key: const ValueKey('dlc-no-original'), style: body),
          ],
          const SizedBox(height: SheetLook.dlcSectionGap),
          ...section('트랙', below: 8),
          if (tracks.isEmpty)
            Text('트랙 없음 — 다른 DLC의 줄에 사건만 덧붙입니다.', style: body.copyWith(color: SheetLook.ink60))
          else
            for (final (i, (t, shared)) in tracks.indexed)
              Padding(
                key: shared ? ValueKey('dlc-shared-${t.id}') : null,
                padding: EdgeInsets.only(top: i == 0 ? 0 : SheetLook.dlcTrackGap),
                child: _TrackRow(track: t, mode: DlcLook.modeOf(on: on, shared: shared), owner: shared ? card.owners[t.id] ?? '' : null),
              ),
          const SizedBox(height: 20),
          Text(
            '${card.stored ? '번호 ${card.id}' : '저장소에서 뺌'}${on ? '' : ' · 꺼 둠'}${card.key.isEmpty ? '' : ' · ${card.key}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sheetText(SheetLook.dlcIdText, color: SheetLook.ink45),
          ),
        ],
      ),
    );
  }
}

/// 자세히의 트랙 줄 — 꼬리표 22: 제 트랙 = 제 색 · 이름(탭 글) · 오른쪽 '줄 N개'(이름 글) / 얹은 트랙([owner]가 있음) = 흰 종이 점선 · '〈트랙〉에 얹음' · 오른쪽 주인 DLC.
class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.mode, this.owner});
  final TrackInfo track;
  final DlcTrackMode mode;
  final String? owner;

  @override
  Widget build(BuildContext context) {
    final c = _colorOf(track), shared = owner != null;
    return SheetTag(
      shape: DlcLook.track(c, mode),
      height: SheetLook.dlcTrack,
      child: Padding(
        padding: const EdgeInsets.only(left: SheetLook.dlcTrackLead, right: SheetLook.dlcTrackTail),
        child: Row(
          children: [
            Expanded(
              child: Text(
                shared ? '${track.name}에 얹음' : track.name,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: sheetText(SheetLook.dlcTrackText, bold: true, color: DlcLook.inkOf(c, mode)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              shared ? owner! : '줄 ${track.rowCount}개',
              maxLines: 1,
              softWrap: false,
              style: sheetText(SheetLook.dlcTrackNote, color: mode == DlcTrackMode.own ? SheetLook.nameInk(c) : SheetLook.ink45),
            ),
          ],
        ),
      ),
    );
  }
}

/// 기본팩을 삭제할 때의 확인 글(바탕이 아닌 자리의 기본팩 — 바탕은 지울 수 없다) — 기본팩은 파일이 아니라 도구 폴더에 들어 있어, 되살리는 길을 함께 적는다.
const dlcBaseRemoveText = "기본팩이 연표에서 빠집니다. 다시 넣으려면 '파일에서 더하기'로 도구 폴더의 east-asia.htpack(도구\\prototype\\results\\compat)을 고르세요.";

/// 휴대폰에서 기본팩을 삭제할 때의 확인 글 — 휴대폰에는 도구 폴더가 없다(등불 바탕 APK에 사용자가 넣은 동아시아 DLC — 판정 R60 I-1).
const dlcBaseRemovePhoneText = "기본팩이 연표에서 빠집니다. 다시 넣으려면 기본팩의 .htpack을 '파일에서 더하기'로 고르세요.";

/// 원본이 없는 DLC의 자세히 글(5-4 다) — 저장소에 그 DLC의 .htpack이 없어 엔진이 다시 셈하지 못한다(넣기 · 빼기가 거절된다 · 끄기는 화면에서만).
const dlcNoOriginalText = "원본 없음 — 예전 메이커 배치로만 들어와 이 DLC의 .htpack이 저장소에 없습니다. 이 DLC의 .htpack을 '파일에서 더하기'로 넣어 주세요.";

/// 줄의 `원본 없음` — 흰 종이 18(모따기 3 · 테 먹 25) · 글 11 굵게 먹 60(앞뒤 9) · 풍선은 되찾는 길.
class DlcNoOriginalTag extends StatelessWidget {
  const DlcNoOriginalTag({super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: "이 DLC의 .htpack을 '파일에서 더하기'로 넣어 주세요",
    child: SheetTag(
      key: const ValueKey('dlc-tag-no-original'),
      shape: DlcLook.badge,
      height: SheetLook.dlcBadge,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SheetLook.dlcBadgePad),
        child: Center(widthFactor: 1, child: Text('원본 없음', maxLines: 1, softWrap: false, style: sheetText(SheetLook.dlcBadgeText, bold: true, color: SheetLook.ink60))),
      ),
    ),
  );
}

/// 줄의 켜고 끄기 — 흰 이름 종이 단추 '끄기'(켠 줄) · '켜기'(꺼 둔 줄). 이름은 예전 스위치 그대로([value]가 켜짐 · [onChanged]는 누르면 반대 값).
/// 읽기 글은 '〈DLC 이름〉 끄기'.
class DlcSwitch extends StatelessWidget {
  const DlcSwitch({super.key, required this.value, required this.onChanged, required this.label});
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = value ? '끄기' : '켜기';
    return SheetPaperButton(label: text, semantics: '$label $text', onTap: () => onChanged(!value));
  }
}

/// 표지 — 저장소에 표지가 없으므로 **있는 값으로** 그린다(예전 막대 표지를 갈음): 둥근 4 · 칠 먹 4 · 테 먹 12 안에 트랙마다 꼬리표 24(사이 8 · 넷까지 ·
/// 위아래 가운데 · 왼쪽 18 · 길이 = (폭 − 36) × (.42 + .58 × 줄 수 / 가장 많은 줄 수)) · 이름 9 굵게. 제 트랙 = 제 색 · 얹은 트랙 = 흰 종이 점선 '〈트랙〉에 얹음' ·
/// 꺼 둔 DLC = 흰 종이 · 먹 25. 트랙이 없는 DLC(남의 줄에 사건만 덧붙이는 것)는 빈 표지.
class DlcCoverPainter extends CustomPainter {
  const DlcCoverPainter({required this.card, this.on = true, this.style = const TextStyle()});
  final DlcCardInfo card;
  final bool on;

  /// 글의 바탕 꼴(글꼴 — 창의 [DefaultTextStyle]).
  final TextStyle style;

  /// 표지에 서는 트랙(제 트랙 먼저 · 얹은 트랙 · 넷까지)과 그 갈래.
  static List<(TrackInfo, DlcTrackMode)> tracksOf(DlcCardInfo card, {required bool on}) => [
    for (final t in card.tracks) (t, DlcLook.modeOf(on: on, shared: false)),
    for (final t in card.shared) (t, DlcLook.modeOf(on: on, shared: true)),
  ].take(SheetLook.dlcCoverMax).toList();

  /// 표지의 가장 작은 키 — 꼬리표들 + 위아래 18(트랙이 없으면 72).
  static double minHeight(DlcCardInfo card) {
    final n = math.min(SheetLook.dlcCoverMax, card.tracks.length + card.shared.length);
    return n == 0 ? SheetLook.dlcCoverEmpty : 2 * SheetLook.dlcCoverLead + n * SheetLook.dlcCoverTag + (n - 1) * SheetLook.dlcCoverGap;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final mid = Rect.fromLTWH(.5, .5, w - 1, h - 1);
    const r = SheetLook.dlcCoverRadius;
    canvas.drawRRect(RRect.fromRectAndRadius(mid, const Radius.circular(r)), Paint()..color = SheetLook.ink4);
    // 테는 획이 아니라 고리 칠(sheetTagRing의 까닭).
    canvas.drawDRRect(
      RRect.fromRectAndRadius(mid.inflate(.5), const Radius.circular(r + .5)),
      RRect.fromRectAndRadius(mid.deflate(.5), const Radius.circular(r - .5)),
      Paint()..color = SheetLook.ink12,
    );
    final list = tracksOf(card, on: on);
    if (list.isEmpty) return;
    final most = list.fold<int>(1, (a, e) => math.max(a, e.$1.rowCount));
    const tag = SheetLook.dlcCoverTag, lead = SheetLook.dlcCoverLead;
    var y = ((h - (list.length * tag + (list.length - 1) * SheetLook.dlcCoverGap)) / 2).roundToDouble();
    for (final (t, mode) in list) {
      final c = _colorOf(t);
      final len = math.max(2 * tag, ((w - 2 * lead) * (.42 + .58 * t.rowCount / most)).roundToDouble());
      canvas.save();
      canvas.translate(lead, y);
      DlcLook.track(c, mode).paint(canvas, Size(len, tag));
      final text = TextPainter(
        text: TextSpan(text: mode == DlcTrackMode.shared ? '${t.name}에 얹음' : t.name, style: style.merge(sheetText(SheetLook.dlcCoverText, bold: true, color: DlcLook.inkOf(c, mode)))),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0, len - SheetLook.dlcCoverTextLeft - 6));
      text.paint(canvas, Offset(SheetLook.dlcCoverTextLeft, ((tag - text.height) / 2).roundToDouble()));
      text.dispose();
      canvas.restore();
      y += tag + SheetLook.dlcCoverGap;
    }
  }

  @override
  bool shouldRepaint(DlcCoverPainter old) => old.card != card || old.on != on || old.style != style;
}
