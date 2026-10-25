import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scene/fonts.dart';
import '../scene/layout.dart';
import '../scene/scene.dart';
import '../shell/look.dart';
import '../shell/motion_controls.dart';
import '../shell/motion_widgets.dart';
import '../motion.dart';
import '../shell/parts.dart';
import 'dlc_add.dart' show DlcHidden, DlcJob, DlcRoute, dlcNoOriginalOffText, dlcRoute, dlcRouteRefusal, dlcScreenOnlyNote;
import 'dlc_layout_import.dart' show DlcPackFacts;

// DLC 관리 창 — 지금 연표의 `🧩 DLC 관리`(js/viewer.js:3011~ · css/viewer.css:660~709 · docs/구상-메이커-팩 2-5)를 옮긴 것.
//
// 3단계의 몫은 **설치된 DLC를 자유롭게 켜고 끄는 것**이었고, 4단계 1걸음(`docs/설계-아카이브-4단계-1걸음-DLC-앱-안에서.md`)에서
// **파일에서 더하기 · 삭제**가 앱 안으로 들어왔다(뒷일은 `ui/dlc_add.dart`의 [DlcJob] · 바꿔 넣기와 뼈대 다시 읽기는 앱 틀):
//   · `📂 파일에서 더하기…`(위 칸)와 고른 카드의 `DLC 삭제`(자세히 · 기본팩도 — 2026-10-16). 도는 동안 위 칸에 진행 · 까닭이 보인다([DlcJob.status]).
//   · 켜고 끄기(2026-10-16 감독 건의 "숨기면 연표 자체에서 등장하지 않게"): 끈 DLC를 **저장소에서 뺀다**([DlcManagerBody.onToggle] — 엔진 `remove_pack`,
//     원본은 저장소의 보관함 · 켜면 `add_pack`으로 다시 — 계획 P4 과제 10b) — 화면에서만 가리면 날짜 칸의 시대 · 검색 · 필터 · 판 …에 끈 DLC가 남았다.
//     끈 DLC의 카드는 `DLC/hidden.json`의 값([DlcHidden])으로 그린다.
//   · 마지막 하나도 끌 수 있다 — 다 끄면 연표가 비고, 그 자리의 안내([dlcEmptyText])는 창을 띄운 쪽이 [DlcManager.onChanged]로 받아 세운다.
//     (2단계의 창은 "줄이 하나도 남지 않는 조합은 만들지 않는다"고 막아, DLC가 하나뿐인 저장소에서는 스위치가 아예 눌리지 않았다.)
//   · 백업 단추는 아직 없다. 화면에 보이는 말은 모두 `DLC`다(지금 연표 그대로). 코드의 이름 · 측정 구간 이름의 '자료집'은 그대로 둔다.
//
// 카드에 적는 값은 모두 자료 처리부가 준 것이다(`{"op":"layout"}`의 `packs` · `tracks`) — 이 저장소에는
// 지은이 · 설명 · 태그 · 분류 · 표지 그림이 없으므로 **만들어 넣지 않는다**(있는 값만 적는다).
// 판(version)과 `원본 없음`(예전 메이커 배치로만 든 DLC — A2 5-4 · 5-6)은 `{"op":"layout"}`의 `packs[]`에서 온다([DlcPackFacts]):
// 앱 틀이 뼈대를 읽을 때마다 [DlcJob.packFacts]를 채우고(이 창이 떠 있는 동안에도 따라온다), 검사는 [DlcManager.packFacts]로 준다. 옛 저장소는 없어 예전 카드 그대로다.

/// 기본팩(동아시아사 기본팩)의 글자 id. 기본팩도 끄고 뺄 수 있다(2026-10-16 감독 건의) — 카드의 '기본팩' 표시와 삭제 확인 글만 다르다.
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

/// 카드 모눈의 칸 수 — css의 `repeat(auto-fill, minmax(220px, 1fr))`와 같은 셈(칸 사이 12px).
/// 지금 연표의 1배 실측(모눈 760px)에서 3칸 · 칸 폭 245.33px이 나온다.
int dlcGridColumns(double width, {double min = _cardMin, double gap = _gridGap}) {
  if (!width.isFinite || width <= min) return 1;
  return math.max(1, ((width + gap) / (min + gap)).floor());
}

const _cardMin = 220.0, _gridGap = 12.0, _detailWidth = 360.0, _wrapGap = 16.0;

/// 켜 둔 DLC 가운데 트랙을 가진 것이 하나도 없으면 참 — 연표 자리에 [dlcEmptyText]를 세울 때.
/// (트랙 없이 남의 줄에 사건만 덧붙이는 DLC는 혼자 켜져 있어도 연표가 빈다 — 지금 연표의 `model.tracks.length`와 같은 잣대.)
/// 집합 보기의 판 트랙은 세지 않는다(판을 켰을 때만 서는 합성 트랙이다).
bool dlcTimelineEmpty(SceneLayout layout) {
  for (int i = 0; i < layout.tracks.length; i++) {
    if (!layout.isBoardTrack(i) && layout.isPackEnabled(layout.tracks[i].pack)) return false;
  }
  return true;
}

/// 그 카드의 켜기([on]) · 끄기 · 삭제([remove])가 갈 길(계획 P4 과제 10b — [dlcRoute]를 카드 하나로): 엔진(add_pack · remove_pack — 휴대폰도) ·
/// 화면에서만(엔진이 빼지 못하는 바탕 · 원본 없이 든 DLC의 끄기 · 글자 id 없는 옛 저장소) · 없음(바탕 빼기) — 판정 R43.
/// 원본 없이 든 DLC(카드의 [DlcCardInfo.original] 거짓 — 메이커 배치로만 넣은 것)를 엔진이 빼면 남길 원본이 없어 지워지므로 끄기는 화면에서만(고침 1회차 I-1).
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

/// 카드를 화면에서만 켜고 끈 까닭의 알림 — 엔진이 빼지 못하는 바탕(저장소의 첫 DLC · 글자 id 없는 옛 저장소)이면 바탕의 알림([dlcScreenOnlyNote])이
/// 먼저다(원본 없는 바탕도 — 10b 고침 재검토), 바탕이 아닌데 원본 없이 든 DLC를 끄면 그 DLC 이름과 함께 그 알림([dlcNoOriginalOffText]).
String dlcScreenNote(DlcCardInfo card, SceneLayout layout, {required DlcHidden hidden, bool on = false}) {
  if (on || card.original || card.key.isEmpty) return dlcScreenOnlyNote;
  final base = dlcRoute(packKeys: [for (final p in layout.packs) p.key], hidden: hidden, baseKey: dlcBaseKey, offKeys: [card.key]) != DlcRoute.engine;
  return base ? dlcScreenOnlyNote : dlcNoOriginalOffText(card.name);
}

/// 창이 카드로 그리는 DLC 하나. 값은 모두 `{"op":"layout"}`가 준 것이다.
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

  /// 저장소에 들어 있는가. 거짓이면 꺼 두어 저장소에서 뺀 DLC다(카드는 `DLC/hidden.json`의 값 — [DlcCardInfo.hiddenOf]) · [id]는 음수.
  final bool stored;
  final String name;

  /// DLC의 판(`meta.pack_info`의 `version` — 모르면 빈 글이고 카드에 적지 않는다).
  final String version;

  /// 원본 팩을 저장소에 품었는가. 거짓이면 카드에 `원본 없음`(예전 메이커의 아카이브 배치로만 들어와 .htpack이 없다 — 5-4).
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

  /// 카드의 '담긴 것' 한 줄 — 지금 연표의 설치 알림("사건 N개, 시대 M개")과 `.pk-meta`(담긴 것) 자리.
  /// 제 트랙이 없어도 남의 트랙에 얹은 것이 있으면 `얹은 트랙 n개`로 적는다 — 둘 다 없을 때만 `트랙 없음`.
  String get contents {
    final parts = ['사건 ${formatCount(events)}건', if (periods > 0) '시대 ${formatCount(periods)}개'];
    if (tracks.isNotEmpty) parts.add('트랙 ${tracks.length}개 · 줄 $rows개');
    if (shared.isNotEmpty) parts.add('얹은 트랙 ${shared.length}개');
    if (tracks.isEmpty && shared.isEmpty) parts.add('트랙 없음');
    return parts.join(' · ');
  }

  /// 트랙 이름을 이어 붙인 글(없으면 빈 글) — 카드의 소개 자리(`.pk-sum`)에 적는다. 얹은 트랙도 든다.
  String get trackNames => [...tracks, ...shared].map((t) => t.name).join(' · ');

  /// 끈 목록(`DLC/hidden.json`)에 적을 카드 — 끄면 저장소에서 빠지므로 그 뒤의 카드는 이 값으로 그린다([DlcCardInfo.hiddenOf]의 거꾸로 · add-dlc.mjs의
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

  /// [facts]는 글자 id마다의 판 · 원본(없으면 판은 빈 글 · 원본은 있음 — 예전 카드 그대로).
  /// [hidden]의 끈 DLC 가운데 저장소에 없는 것은 그 카드 값으로 뒤에 붙인다(꺼 둔 기본팩은 맨 앞).
  /// [kept]: 저장소의 보관함(`{"op":"kept_packs"}` — 꺼 둔 DLC의 원본) — 끈 목록에 카드가 없는 것도(끈 목록 쓰기가 실패했거나 깨짐) 이름 · 판만으로 카드를
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

  /// 꺼 두어 저장소에서 뺀 DLC의 카드 — 도구가 끌 때 떠 둔 값(`{name, version, events, periods, tracks:[{key,name,color,rows}], shared:[{key,name,color,owner}]}`).
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

/// DLC 관리 창을 띄운다. 나타남 200 · 사라짐 160(`docs/움직임-원칙.md`).
/// [onChanged]는 켜고 끌 때마다 새 조합으로 불린다 — 창을 띄운 쪽이 연표 자리의 안내를 세우고 기억에 적는다.
/// [onAddFiles]가 있으면 위 칸에 `📂 파일에서 더하기…` 단추가, [onRemove]가 있으면 고른 카드의 자세히에 `DLC 삭제`가 선다
/// (앱 틀이 파일 고르기 · 엔진의 고쳐 쓰기 · 뼈대 다시 읽기를 맡는다 — 4단계 1걸음 · 계획 P4 과제 10b). [job]은 그 뒷일의 상태(위 칸에 진행 · 까닭을 보인다).
/// 넣기 · 지우기 · 끄기 · 켜기는 휴대폰도 컴퓨터도 엔진 하나로 된다([dlcCardRoute]) — 엔진이 빼지 못하는 바탕(저장소의 첫 DLC)은 삭제 단추가 서지 않고
/// 켜고 끄기는 화면에서만(판정 R43).
/// [packFacts]는 카드의 판 · `원본 없음`(글자 id마다 — 앱 틀은 [DlcJob.packFacts]를 채우므로 검사만 준다).
/// [onToggle]이 있으면 스위치 · 모두 켜기/끄기가 그것을 부른다 — 앱 틀이 끈 DLC를 **저장소에서 뺀다**(원본은 보관함 — 숨긴 DLC가 연표 어디에도 남지 않게).
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
  Color get barrierColor => Ui.ink20; // 창 뒤는 흐림 없이 ink20 깔개(css의 dialog::backdrop)

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

/// DLC 관리 창(머리 · 알맹이). 검사는 이것을 바로 띄운다.
class DlcManager extends StatelessWidget {
  const DlcManager({super.key, required this.scene, this.onChanged, this.onAddFiles, this.onRemove, this.onToggle, this.job, this.packFacts});
  final TimelineScene scene;
  final Future<void> Function()? onAddFiles;
  final Future<void> Function(DlcCardInfo card)? onRemove;
  final Future<void> Function(List<DlcCardInfo> cards, bool on)? onToggle;
  final DlcJob? job;

  /// 카드의 판 · `원본 없음`(글자 id마다). 없으면 예전 카드 그대로.
  final Map<String, DlcPackFacts>? packFacts;

  /// 켜고 끈 뒤의 조합. 비어 있으면 연표가 빈 것이다([dlcTimelineEmpty]).
  final void Function(Set<int> packs)? onChanged;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // 지금 연표의 `#dlcDialog`: width min(1180px, 100vw − 24) · max-height 100dvh − 32.
    final width = math.min(1180.0, media.size.width - 24);
    final height = math.max(240.0, media.size.height - 32);
    return Center(
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback, fontSize: 14, height: 1.5, color: Ui.text, decoration: TextDecoration.none),
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
          child: Focus(
            autofocus: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Ui.surface,
                borderRadius: BorderRadius.circular(Ui.menuRadius),
                // css: 그림자 없이 0 0 0 1px var(--line)
                boxShadow: Ui.shadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Ui.menuRadius),
                child: SizedBox(
                  width: width,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: height),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // `.dlg-head` — 18/22/12 · 제목 19px 700.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
                          child: Row(
                            children: [
                              const Expanded(child: Text('DLC 관리', style: TextStyle(fontFamily: Ui.title, fontFamilyFallback: Ui.titleFallback, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -.38, color: Ui.text))),
                              ShellButton(
                                tooltip: '닫기',
                                width: 32,
                                padding: EdgeInsets.zero,
                                onPressed: () => Navigator.of(context).maybePop(),
                                child: const Text('✕', style: TextStyle(fontSize: 15)),
                              ),
                            ],
                          ),
                        ),
                        Flexible(child: DlcManagerBody(scene: scene, onChanged: onChanged, onAddFiles: onAddFiles, onRemove: onRemove, onToggle: onToggle, job: job, packFacts: packFacts)),
                      ],
                    ),
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

/// 창의 알맹이 — 위 칸(찾기 · 모두 켜기/끄기) · 카드 모눈 + 자세히 · 아래 줄. 작은 자리에도 그대로 들어간다.
class DlcManagerBody extends StatefulWidget {
  const DlcManagerBody({super.key, required this.scene, this.onChanged, this.onAddFiles, this.onRemove, this.onToggle, this.job, this.packFacts});
  final TimelineScene scene;
  final void Function(Set<int> packs)? onChanged;
  final Future<void> Function()? onAddFiles;
  final Future<void> Function(DlcCardInfo card)? onRemove;
  final Future<void> Function(List<DlcCardInfo> cards, bool on)? onToggle;
  final DlcJob? job;
  final Map<String, DlcPackFacts>? packFacts;

  @override
  State<DlcManagerBody> createState() => DlcManagerBodyState();
}

class DlcManagerBodyState extends State<DlcManagerBody> {
  final _find = TextEditingController();
  final _scroll = ScrollController();

  /// 고른 카드(자세히에 나오는 것). 이 창에서만 기억한다 — 지금 연표의 `dlcUi.sel`.
  int _selected = -1;

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

  /// 카드 — 판 · 원본은 준 값 위에 지금 뼈대의 값([DlcJob.packFacts] — 앱 틀이 뼈대를 읽을 때마다 채운다)을 덮는다.
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

  /// 삭제 단추가 서는가 — 엔진(remove_pack)으로 뺄 수 있을 때(엔진이 빼지 못하는 바탕은 서지 않는다).
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
      // 화면에서만인 까닭 — 카드마다(바탕이면 바탕의 알림 · 원본 없이 든 DLC를 끄면 그 알림) 한 번씩.
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

  /// `.dlg-body` — 8/22/18. 위 칸(찾기 · 모두 켜기/끄기) · 카드 모눈 + 자세히 · 아래 줄.
  @override
  Widget build(BuildContext context) {
    final cards = _cards;
    final shown = [
      for (final card in cards)
        if (card.matches(_find.text)) card,
    ];
    // 고른 것이 없거나 사라졌으면 보이는 첫 카드를 고른다 — 지금 연표의 `dlcMainHTML`과 같은 길.
    final selected = cards.any((c) => c.id == _selected) ? _selected : (shown.isNotEmpty ? shown.first.id : (cards.isNotEmpty ? cards.first.id : -1));
    final allOn = cards.every(_isOn);
    final allOff = !cards.any(_isOn);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _top(cards, allOn: allOn, allOff: allOff),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              controller: _scroll,
              child: LayoutBuilder(
                builder: (context, box) {
                  // css: `.pk-wrap`은 모눈 + 자세히(360). 좁으면 자세히를 접고 모눈만 둔다(css의 900px 갈림길과 같은 뜻).
                  final wide = box.maxWidth >= 700;
                  final gridWidth = wide ? box.maxWidth - _detailWidth - _wrapGap : box.maxWidth;
                  final grid = _grid(shown, gridWidth, selected);
                  if (!wide) return grid;
                  final picked = cards.where((c) => c.id == selected).firstOrNull;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: gridWidth, child: grid),
                      const SizedBox(width: _wrapGap),
                      SizedBox(
                        key: const Key('dlc-detail'),
                        width: _detailWidth,
                        child: picked == null
                            ? const SizedBox.shrink()
                            : _DlcDetail(
                                card: picked,
                                on: _isOn(picked),
                                onRemove: !_canRemove(picked) ? null : () => _remove(picked),
                                removing: widget.job != null && widget.job!.running && widget.job!.removingKey == picked.key,
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          _foot(cards),
        ],
      ),
    );
  }

  /// `.pk-top` — 찾기 칸(240×30) · 뒷일의 상태(도는 중 · 실패의 까닭) · 오른쪽에 파일에서 더하기 · 모두 켜기 · 모두 끄기. (분류 거르기 · 백업은 아직 없다.)
  Widget _top(List<DlcCardInfo> cards, {required bool allOn, required bool allOff}) {
    final job = widget.job;
    final busy = job?.running ?? false;
    return Row(
      children: [
        _FindField(controller: _find, onChanged: (_) => setState(() {})),
        if (job != null && (job.running || job.failed)) ...[
          const SizedBox(width: 12),
          if (job.running) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Ui.accent)),
          if (job.running) const SizedBox(width: 8),
          Expanded(
            child: Text(
              job.status,
              key: const ValueKey('dlc-job-status'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: job.failed ? Ui.ink : Ui.text2),
            ),
          ),
        ] else if (job != null && job.notes.isNotEmpty) ...[
          // 끝난 뒤에 남긴 알림(배치 더하기 — `판을 확인할 수 없습니다` · `원본 없음`). 다음 일을 시작하면 사라진다.
          const SizedBox(width: 12),
          Expanded(
            child: Tooltip(
              message: job.notes.join('\n'),
              child: Text(
                job.notes.join(' · '),
                key: const ValueKey('dlc-job-notes'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: Ui.text3),
              ),
            ),
          ),
        ] else
          const Spacer(),
        // 파일에서 더하기(4단계 1걸음 · 계획 P4 과제 10b · 11c): 메이커가 저장한 DLC 파일(.htpack)을 골라 더한다 — 앱 틀이 엔진으로 맡는다. 도는 동안은 잠근다.
        if (widget.onAddFiles != null) ...[
          const SizedBox(width: 8),
          _SmallButton(key: const ValueKey('dlc-add-files'), label: '파일에서 더하기', onPressed: busy ? null : () => widget.onAddFiles!()),
        ],
        const SizedBox(width: 8),
        _SmallButton(label: '모두 켜기', onPressed: cards.isEmpty || allOn || busy ? null : () => _setAll(cards, true)),
        const SizedBox(width: 8),
        _SmallButton(label: '모두 끄기', onPressed: cards.isEmpty || allOff || busy ? null : () => _setAll(cards, false)),
      ],
    );
  }

  Widget _grid(List<DlcCardInfo> shown, double width, int selected) {
    if (shown.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('맞는 DLC가 없습니다.', style: TextStyle(fontSize: 12.5, color: Ui.text3)),
      );
    }
    final columns = dlcGridColumns(width);
    final cardWidth = (width - _gridGap * (columns - 1)) / columns;
    return Wrap(
      spacing: _gridGap,
      runSpacing: _gridGap,
      children: [
        for (final card in shown)
          SizedBox(
            key: ValueKey('dlc-card-${card.id}'),
            width: cardWidth,
            child: _DlcCard(
              card: card,
              on: _isOn(card),
              selected: card.id == selected,
              onPick: () => setState(() => _selected = card.id),
              onToggle: (on) => _set(card, on),
            ),
          ),
      ],
    );
  }

  /// `.pk-foot` — 켜 둔 DLC 수 · 불러오는 차례. (지금 연표의 '파일을 끌어다 놓으면 설치됩니다'는 이 단계에 없다.)
  Widget _foot(List<DlcCardInfo> cards) {
    final on = [
      for (final card in cards)
        if (_isOn(card)) card,
    ];
    final order = on.map((c) => c.name).join(' → ');
    final empty = dlcTimelineEmpty(_layout);
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.only(top: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Ui.line))),
      child: Text(
        '켜 둔 DLC ${on.length}개 · 불러오는 차례: ${order.isEmpty ? '없음' : order}${empty ? ' — $dlcEmptyText' : ''}',
        style: const TextStyle(fontSize: 12.5, color: Ui.text3),
      ),
    );
  }
}

/// `.pk-find` — 240×30 · 둥근 9 · 바탕 surface-2. 회색 예시 글자는 두지 않는다.
class _FindField extends StatelessWidget {
  const _FindField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    height: 30,
    child: Semantics(
      label: '이름으로 찾기',
      textField: true,
      child: Tooltip(
        message: '이름으로 찾기',
        child: TextField(
          controller: controller,
          maxLines: 1,
          textAlignVertical: TextAlignVertical.center,
          cursorColor: Ui.ink,
          style: const TextStyle(fontSize: 14, height: 1.5, color: Ui.text),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Ui.paper,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(Ui.controlRadius), borderSide: const BorderSide(color: Ui.ink20)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Ui.controlRadius), borderSide: const BorderSide(color: Ui.ink20)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Ui.controlRadius), borderSide: const BorderSide(color: Ui.ink)),
          ),
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

/// `.btn.btn-sm` — 높이 32 · 둥근 6 · 13px/600 · 채움 없이 ink20 선(올리면 ink8).
class _SmallButton extends StatefulWidget {
  const _SmallButton({super.key, required this.label, this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  State<_SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<_SmallButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final off = widget.onPressed == null;
    return MouseRegion(
      cursor: off ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        enabled: !off,
        label: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Opacity(
            opacity: off ? .45 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Ui.ease,
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: !off && _hover ? Ui.ink8 : null,
                borderRadius: BorderRadius.circular(Ui.controlRadius),
              ),
              foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(Ui.controlRadius), border: Border.all(color: Ui.ink20)),
              child: Text(widget.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Ui.text)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 표지 카드 한 장 — `.pk-card`(둥근 14 · 바탕 surface · 테두리 1px line · 손을 올리면 120ms로 떠오름).
class _DlcCard extends StatefulWidget {
  const _DlcCard({required this.card, required this.on, required this.selected, required this.onPick, required this.onToggle});
  final DlcCardInfo card;
  final bool on, selected;
  final VoidCallback onPick;
  final ValueChanged<bool> onToggle;

  @override
  State<_DlcCard> createState() => _DlcCardState();
}

class _DlcCardState extends State<_DlcCard> {
  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: '${card.name} — 누르면 자세히',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPick,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Ui.ease,
            decoration: BoxDecoration(
              color: Ui.surface,
              borderRadius: BorderRadius.circular(Ui.menuRadius),
              // 카드는 선으로만: 고른 카드는 ink 선 1.5, 나머지는 ink20 선 1.
              boxShadow: [if (widget.selected) const BoxShadow(color: Ui.accent, spreadRadius: 1.5) else const BoxShadow(color: Ui.line, spreadRadius: 1)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Ui.menuRadius),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // `.pk-cover` — 16:9. 꺼진 카드의 표지는 흐리다(css의 grayscale(.85) opacity(.5) 자리).
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Opacity(opacity: widget.on ? 1 : .5, child: CustomPaint(painter: DlcCoverPainter(card: card, gray: !widget.on))),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 24,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    text: card.name,
                                    children: [
                                      // 판(아는 것만) — 지금 연표 카드의 `.ver`처럼 이름 뒤에 작게.
                                      if (card.version.isNotEmpty) TextSpan(text: '  v${card.version}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: Ui.text3)),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Ui.text),
                                ),
                              ),
                              const SizedBox(width: 6),
                              DlcSwitch(value: widget.on, onChanged: widget.onToggle, label: card.name),
                            ],
                          ),
                        ),
                        if (card.trackNames.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(card.trackNames, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, height: 1.5, color: Ui.text2)),
                        ],
                        const SizedBox(height: 5),
                        Text(card.contents, style: const TextStyle(fontSize: 11.5, height: 1.5, color: Ui.text3)),
                        if (!card.original) ...[
                          const SizedBox(height: 6),
                          const Align(alignment: Alignment.centerLeft, child: DlcNoOriginalTag()),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 고른 DLC의 자세히 — `.pk-detail`(폭 360 · 둥근 16 · 바탕 surface). 저장소에 있는 값만 적고, 아래에 `DLC 삭제`가 선다(기본팩도).
class _DlcDetail extends StatelessWidget {
  const _DlcDetail({required this.card, required this.on, this.onRemove, this.removing = false});
  final DlcCardInfo card;
  final bool on;

  /// 삭제 단추(없으면 서지 않는다 — 도구 없는 실행본 · 글자 id 없는 옛 저장소). [removing]이면 `삭제하는 중…`.
  final VoidCallback? onRemove;
  final bool removing;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Ui.surface,
      borderRadius: BorderRadius.circular(Ui.menuRadius),
      boxShadow: const [BoxShadow(color: Ui.line, spreadRadius: 1)],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(Ui.menuRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: CustomPaint(painter: DlcCoverPainter(card: card, gray: !on))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(card.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -.17, color: Ui.text)),
                const SizedBox(height: 8),
                const _DetailHead('담긴 것'),
                Text(card.contents, style: const TextStyle(fontSize: 13, height: 1.6, color: Ui.text2)),
                if (card.version.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const _DetailHead('판'),
                  Text('v${card.version}', style: const TextStyle(fontSize: 13, height: 1.6, color: Ui.text2)),
                ],
                if (!card.original) ...[
                  const SizedBox(height: 8),
                  const _DetailHead('원본'),
                  const Text(
                    dlcNoOriginalText,
                    key: ValueKey('dlc-no-original'),
                    style: TextStyle(fontSize: 13, height: 1.6, color: Ui.text2),
                  ),
                ],
                const SizedBox(height: 8),
                const _DetailHead('트랙'),
                if (card.tracks.isEmpty && card.shared.isEmpty)
                  const Text('트랙 없음 — 다른 DLC의 줄에 사건만 덧붙입니다.', style: TextStyle(fontSize: 13, height: 1.6, color: Ui.text2))
                else ...[
                  for (final track in card.tracks)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: Color(0xff000000 | track.color), borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 6),
                          Expanded(child: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.6, color: Ui.text2))),
                          Text('줄 ${track.rowCount}개', style: const TextStyle(fontSize: 11.5, height: 1.6, color: Ui.text3)),
                        ],
                      ),
                    ),
                  // 남의 트랙에 얹은 것(같은 id의 트랙은 먼저 켠 DLC의 것으로 합쳐진다) — 어느 DLC의 트랙인지 함께 적는다.
                  for (final track in card.shared)
                    Padding(
                      key: ValueKey('dlc-shared-${track.id}'),
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(border: Border.all(color: Color(0xff000000 | track.color), width: 1.5), borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 6),
                          Expanded(child: Text('${track.name}에 얹음', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.6, color: Ui.text2))),
                          Text(card.owners[track.id] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, height: 1.6, color: Ui.text3)),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Text('${card.stored ? '번호: ${card.id}' : '저장소에서 뺌'}${on ? '' : ' · 꺼 둠'}${card.key.isEmpty ? '' : ' · ${card.key}'}', style: const TextStyle(fontSize: 11.5, height: 1.6, color: Ui.text3)),
                if (onRemove != null || removing) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _SmallButton(key: const ValueKey('dlc-remove'), label: removing ? '삭제하는 중…' : 'DLC 삭제', onPressed: removing ? null : onRemove),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// 기본팩을 삭제할 때의 확인 글(바탕이 아닌 자리의 기본팩 — 바탕은 지울 수 없다) — 기본팩은 파일이 아니라 도구 폴더에 들어 있어, 되살리는 길을 함께 적는다.
const dlcBaseRemoveText = "기본팩이 연표에서 빠집니다. 다시 넣으려면 '파일에서 더하기'로 도구 폴더의 east-asia.htpack(도구\\prototype\\results\\compat)을 고르세요.";

/// 휴대폰에서 기본팩을 삭제할 때의 확인 글 — 휴대폰에는 도구 폴더가 없다(등불 바탕 APK에 사용자가 넣은 동아시아 DLC — 판정 R60 I-1).
const dlcBaseRemovePhoneText = "기본팩이 연표에서 빠집니다. 다시 넣으려면 기본팩의 .htpack을 '파일에서 더하기'로 고르세요.";

/// 원본이 없는 DLC의 자세히 글(5-4 다) — 저장소에 그 DLC의 .htpack이 없어 엔진이 다시 셈하지 못한다(넣기 · 빼기가 거절된다 · 끄기는 화면에서만).
const dlcNoOriginalText = "원본 없음 — 예전 메이커 배치로만 들어와 이 DLC의 .htpack이 저장소에 없습니다. 이 DLC의 .htpack을 '파일에서 더하기'로 넣어 주세요.";

/// 카드의 `원본 없음` 딱지 — 둥근 6 · 11px · 따스한 붉은 글(실패 글과 같은 #b5533c)을 옅은 바탕에.
class DlcNoOriginalTag extends StatelessWidget {
  const DlcNoOriginalTag({super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: "이 DLC의 .htpack을 '파일에서 더하기'로 넣어 주세요",
    child: Container(
      key: const ValueKey('dlc-tag-no-original'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: const Color(0x1fb5533c), borderRadius: BorderRadius.circular(6)),
      child: const Text('원본 없음', style: TextStyle(fontSize: 11, height: 1.5, fontWeight: FontWeight.w600, color: Color(0xffb5533c))),
    ),
  );
}

/// `.pk-detail h4` — 11.5px 700 · text-3.
class _DetailHead extends StatelessWidget {
  const _DetailHead(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.5, color: Ui.text3)),
  );
}

/// 자료집 켬끔도 공통 42×24 토글을 쓴다.
class DlcSwitch extends StatelessWidget {
  const DlcSwitch({super.key, required this.value, required this.onChanged, required this.label});
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  static const on = Ui.ink;

  @override
  Widget build(BuildContext context) => Semantics(label: label, child: MotionToggle(value: value, onChanged: onChanged, hint: value ? '끄기' : '켜기'));
}

/// 표지 그림 — 저장소에 표지가 없으므로 지금 연표의 자동 표지(`HT.autoCover`)처럼 **있는 값으로** 그린다:
/// 트랙마다 가는 둥근 막대 하나(제 색 · 길이는 그 트랙의 줄 수) · 일곱 줄까지 · 세로 가운데.
/// 트랙이 없는 DLC(남의 줄에 사건만 덧붙이는 것)는 지금 연표와 같이 옅은 줄무늬.
class DlcCoverPainter extends CustomPainter {
  const DlcCoverPainter({required this.card, this.gray = false});
  final DlcCardInfo card;
  final bool gray;

  /// 표지 바탕 — css의 `.pk-cover` 배경(바탕 위 잉크 4% — `--paper-2`).
  static const paper = Color(0xfff5f5f5), stripe = Color(0xffcccccc);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    // 지금 연표의 자동 표지는 320×180을 셈으로 잡는다 — 칸 크기가 달라도 같은 그림이 되게 그 자리로 재 옮긴다.
    final k = w / 320, pad = 18 * k;
    final tracks = (card.tracks.isNotEmpty ? card.tracks : card.shared).take(7).toList();
    if (tracks.isEmpty) {
      for (int i = 0; i < 5; i++) {
        final rect = Rect.fromLTWH(28 * k + i * 16 * k, (34 + i * 24) * (h / 180), w - 56 * k - i * 32 * k, 13 * (h / 180));
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(6.5 * k)), Paint()..color = stripe.withValues(alpha: .95 - i * .16));
      }
      return;
    }
    final most = tracks.fold<int>(1, (a, t) => math.max(a, t.rowCount));
    final rowHeight = math.min(26 * (h / 180), (h - pad * 2) / math.max(3, tracks.length));
    final top = (h - rowHeight * tracks.length) / 2;
    for (int i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final length = (w - pad * 2) * (.35 + .65 * (track.rowCount / most));
      final rect = Rect.fromLTWH(pad, top + i * rowHeight + rowHeight * .14, math.max(8 * k, length), rowHeight * .72);
      final color = Color(0xff000000 | track.color);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rowHeight * .3)),
        Paint()..color = gray ? Color.lerp(color, const Color(0xff666666), .85)! : color,
      );
    }
  }

  @override
  bool shouldRepaint(DlcCoverPainter old) => old.card.id != card.id || old.card.tracks.length != card.tracks.length || old.card.shared.length != card.shared.length || old.gray != gray;
}
