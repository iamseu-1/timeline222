import 'package:flutter/material.dart';

import '../shell/look.dart';
import '../shell/motion_controls.dart';
import 'app_bus.dart';
import 'board_views.dart' show BoardEpochCard;
import 'date_text.dart';
import 'detail_item.dart' show kindShortOf;
import 'detail_shell.dart';
import 'doc_window.dart' show DocChips;

// ════════════════════════════════════════════════════════════════════════════════════════════
//  시대 구분 창 · 대범위 창
//  — 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md` 2-3절의 ㈔ 와 ㈕(지금 연표의 js/viewer.js:974 · 1021).
//
//  묶음이 나오는 차례는 지금 연표 그대로이고, **비어 있는 묶음은 아예 그리지 않는다**(명세 2-3).
//  둘 다 연표에 제 줄이 없는 항목이라 세로 닻을 걸지 않고 조명도 켜지 않는다(명세 2-2의 1 · 2번 갈래 · 9절 ㈐-7)
//  — 그 일은 뼈대(`DetailHost`)가 `detailKinds`의 `lane: false`로 이미 하고 있어 이 파일이 따로 알릴 것은 없다.
//
//  ── 쓰는 법 ───────────────────────────────────────────────────────────────────────────────
//    registerScopeDetail();                // 앱을 세울 때 한 번 — 갈래 'epoch' · 'scope'를 이 파일이 맡는다
//    …  DetailHost(bus: bus)               // 나머지는 뼈대가 한다
//
//    앱 틀에 직접 끼워 넣을 때는 위젯을 바로 세워도 된다(받는 것은 AppBus와 항목 기록뿐):
//      EpochDetail(bus: bus, entity: 항목기록, onClose: …)
//      ScopeDetail(bus: bus, entity: 항목기록, onClose: …)
//    [onClose]를 주지 않으면 ✕는 `bus.clearSelection()`으로 창을 닫는다.
//
//  ── 이 창이 항목 기록에서 읽는 것(계약 6-9절) ────────────────────────────────────────────────
//    시대 구분: name · start · end · startAt · endAt · ongoing · color · track · trackName ·
//               description · note · alternatives · packName · wiki · **x_scopes**(이어진 대범위)
//    대범위:    name · label · start · end · color · track · trackName · rangeFrom · host($ref) ·
//               afterHost · epoch($ref) · nameAuto · startAuto · colorAuto · warnings · default ·
//               description · note · packName · wiki · **x_members**(구성 정권 — `other:1`이면 다른 트랙) ·
//               **x_docs**(하위 문서 칩 — [DocChips]가 읽는다)
//    시대 구분 창에는 하위 문서 묶음을 두지 않는다 — 지금 연표의 `epochDetailHTML`에도 없다(js/viewer.js:974).
//
//  ── 앱 틀이 채워 주어야 하는 곳 ─────────────────────────────────────────────────────────────
//    bus.slot('tracks') = {'mw-coast': {'name': '유리해안', 'color': 0xa0bcc5}, …}
//      → `{"op":"layout"}`의 답에 이미 있는 값(계약 2절). 비어 있으면 항목 기록의 `trackName`으로 적고 색만 옅어진다.
//    bus.slot('scopes')  ← **모아 보기**의 상태 `{대범위 uid: 켬/끔}`. 이 창이 넣고 읽는다.
//                          기록이 없는 대범위는 제 `default` 값이다(지금 연표의 timeline.scopeOn).
//                          앱 틀은 이것을 듣고 줄을 다시 쌓는다(모여드는 움직임).
//    bus.slot('doc')     ← `📄 문서`를 누르면 그 항목의 uid, 머리의 트랙 배지를 누르면 `track:<트랙 id>`.
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 갈래 `epoch`(시대 구분)와 `scope`(대범위)를 이 파일이 맡는다.
void registerScopeDetail() {
  DetailHost.register('epoch', (ctx) => EpochDetail(bus: ctx.bus, entity: ctx.json, onClose: ctx.close));
  DetailHost.register('scope', (ctx) => ScopeDetail(bus: ctx.bus, entity: ctx.json, onClose: ctx.close));
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  모아 보기 — bus.slot('scopes')의 {uid: 켬/끔}
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 지금 켜 둔 대범위 표. 기록이 없는 대범위는 여기에 없다(= 제 `default`).
Map<String, bool> gatheredScopes(AppBus bus) {
  final v = bus.slot('scopes').value;
  if (v is! Map) return const {};
  return {
    for (final e in v.entries)
      if (e.value is bool) '${e.key}': e.value as bool,
  };
}

/// 그 대범위가 모여 있는가 — 기록이 없으면 [byDefault](항목 기록의 `default`).
bool scopeGathered(AppBus bus, String uid, {bool byDefault = false}) => gatheredScopes(bus)[uid] ?? byDefault;

/// 모아 보기를 켜고 끈다(표를 통째로 새로 실어 앱 틀이 한 번만 듣게).
void setScopeGathered(AppBus bus, String uid, bool on) => bus.slot('scopes').value = {...gatheredScopes(bus), uid: on};

// ────────────────────────────────────────────────────────────────────────────────────────────
//  1. 시대 구분 창 (명세 2-3 ㈔)
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 날짜 칸의 시대 구분 칸을 누르면 열리는 창 — 이름 · 기간 · 설명 · 다른 견해 · 이어진 대범위 · 제공.
class EpochDetail extends StatelessWidget {
  const EpochDetail({super.key, required this.bus, required this.entity, this.onClose});

  final AppBus bus;

  /// 항목 기록(`{"op":"entity"}`의 `json`을 푼 것).
  final Map<String, dynamic> entity;

  /// ✕를 눌렀을 때. 주지 않으면 고르기를 비워 창을 닫는다.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Object?>(
    // 모아 보기 스위치가 바뀌면 그 줄만 다시 그린다(창은 그대로 — 명세 9절 ㈐-8).
    valueListenable: bus.slot('scopes'),
    builder: (context, _, _) => DetailShell(
      onClose: onClose ?? bus.clearSelection,
      badges: [
        trackBadge(bus, entity),
        DetailBadge('시대 구분', color: detailColor(entity['color'])),
      ],
      body: [
        DetailTitle(detailString(entity, 'name')),
        DetailWhen(entityRange(entity)),
        DetailDesc(descOf(entity)),
        ...alternativesBox(bus, entity),
        ..._scopes(),
        // 집합 보기(결정 5 A): 이 시대의 나라 — 스위치를 켜면 저장하지 않는 임시 판(판이 없으면 자리도 없다).
        BoardEpochCard(bus: bus, epochUid: detailString(entity, 'uid')),
        DetailDefs([DetailDef('제공', Text(detailString(entity, 'packName')))]),
      ],
      foot: footButtons(bus, entity, '이 시기로'),
    ),
  );

  /// 이어진 대범위 — 이름 칩과 모아 보기 스위치를 한 줄씩.
  List<Widget> _scopes() {
    final list = detailList(entity, 'x_scopes');
    if (list.isEmpty) return const [];
    return [
      DetailBox(
        title: '이어진 대범위',
        children: [
          for (int i = 0; i < list.length; i++) ScopeSwitchRow(bus: bus, scope: list[i], top: i == 0 ? 2 : 6),
        ],
      ),
    ];
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  2. 대범위 창 (명세 2-3 ㈕)
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 대범위 테두리의 이름표 · 칩 · 검색으로 열리는 창 —
/// 이름 · 성격 · 기간 · 모아 보기 · 상징적 본국 · 설명 · 구성 정권 · 이어진 시대 구분 · 확인할 것 · 제공.
class ScopeDetail extends StatelessWidget {
  const ScopeDetail({super.key, required this.bus, required this.entity, this.onClose});

  final AppBus bus;
  final Map<String, dynamic> entity;
  final VoidCallback? onClose;

  String get _uid => detailString(entity, 'uid');
  bool get _afterHost => entity['afterHost'] == true || entity['afterHost'] == 1;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Object?>(
    valueListenable: bus.slot('scopes'),
    builder: (context, _, _) => DetailShell(
      onClose: onClose ?? bus.clearSelection,
      badges: [
        trackBadge(bus, entity),
        DetailBadge('대범위', color: detailColor(entity['color'])),
        // 성격 딱지(`.badge-scope`) — 색 점 없이 옅은 바탕.
        if (detailString(entity, 'label').isNotEmpty) DetailBadge(detailString(entity, 'label'), dot: false, color: Ui.text3),
      ],
      body: [
        DetailTitle(detailString(entity, 'name')),
        DetailWhen(entityRange(entity), sub: _rangeFrom()),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 10),
          child: ScopeSwitch(bus: bus, uid: _uid, color: detailColor(entity['color']), byDefault: entity['default'] == true),
        ),
        ..._host(),
        DetailDesc(descOf(entity)),
        _members(),
        ..._epoch(),
        ..._warnings(),
        // 하위 문서 칩 — 지금 연표의 `scopeDetailHTML`도 '확인할 것' 다음, '제공' 앞에 둔다(js/viewer.js:1043).
        DocChips(bus: bus, uid: _uid, json: entity),
        DetailDefs([
          DetailDef('제공', Text(detailString(entity, 'packName'))),
          // 설명이 따로 있을 때만 메모를 적는다(설명이 없으면 메모가 그 자리에 올라간다).
          if (detailString(entity, 'note').isNotEmpty && detailString(entity, 'description').isNotEmpty) DetailDef('메모', Text(detailString(entity, 'note'))),
        ]),
      ],
      foot: footButtons(bus, entity, '이 시기로'),
    ),
  );

  /// 기간을 어디에서 물려받았는가.
  String? _rangeFrom() {
    switch (detailString(entity, 'rangeFrom')) {
      case 'epoch':
        return '시대 구분의 기간';
      case 'members':
        return '구성 정권의 범위';
    }
    return null;
  }

  /// 상징적 본국 한마디.
  List<Widget> _host() {
    final host = detailRef(entity['host']);
    if (host == null) return const [];
    return [
      LinkNote(
        before: '상징적 본국 ',
        link: host.name,
        onTap: () => bus.select(host.uid),
        small: _afterHost
            ? '(본국이 끝난 뒤의 부흥 — 켜면 본국 줄 아래 · 본국이 끝난 자리의 오른쪽에 모임)'
            : '(이름만 남은 본국 — 그 띠에 할거기 칠 · 켜면 본국 줄 바로 아래에 모임)',
      ),
    ];
  }

  /// 구성 정권 — 이 트랙과 다른 트랙(다른 트랙은 모이지 않는다).
  Widget _members() {
    final all = detailList(entity, 'x_members');
    final own = [
      for (final m in all)
        if (m['other'] != 1 && m['other'] != true) m,
    ];
    final other = [
      for (final m in all)
        if (m['other'] == 1 || m['other'] == true) m,
    ];
    Widget row(Map<String, dynamic> m) => DetailSuccRow(
      badge: detailString(m, 'kind').isEmpty ? null : kindShortOf(detailString(m, 'kind')),
      badgeHint: detailString(m, 'kind'),
      name: detailString(m, 'name'),
      years: detailString(m, 'when'),
      onTap: () => bus.select(detailString(m, 'uid')),
    );
    return DetailBox(
      title: '구성 정권',
      small: '${own.length}',
      children: [
        if (own.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('이 트랙에서 찾은 구성 정권이 없습니다.', style: TextStyle(fontSize: 13, height: 1.5, color: Ui.text3)),
          )
        else
          DetailSuccList([for (final m in own) row(m)]),
        if (other.isNotEmpty) ...[
          const _Cap('다른 트랙 — 모이지 않음'),
          DetailSuccList([for (final m in other) row(m)]),
        ],
      ],
    );
  }

  /// 이어진 시대 구분 한마디.
  List<Widget> _epoch() {
    final epoch = detailRef(entity['epoch']);
    if (epoch == null) return const [];
    final auto = [
      if (entity['nameAuto'] == true) '이름',
      if (entity['startAuto'] == true) '기간',
      if (entity['colorAuto'] == true) '색',
    ];
    return [
      LinkNote(
        before: '시대 구분 ',
        link: epoch.name,
        onTap: () => bus.select(epoch.uid, kind: 'epoch'),
        small: auto.isEmpty ? '(같은 뜻)' : '(같은 뜻 — 비워 둔 ${auto.join(' · ')}을 물려받음)',
      ),
    ];
  }

  /// 확인할 것 — 노란 상자의 글머리 목록.
  List<Widget> _warnings() {
    final list = detailStrings(entity, 'warnings');
    if (list.isEmpty) return const [];
    return [
      DetailBox(
        title: '확인할 것',
        small: '${list.length}',
        warn: true,
        children: [
          for (final w in list)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 18, child: Text('·', style: TextStyle(fontSize: 12.5, height: 1.6, color: Ui.text2))),
                  Expanded(child: Text(w, style: const TextStyle(fontSize: 12.5, height: 1.6, color: Ui.text2))),
                ],
              ),
            ),
        ],
      ),
    ];
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  3. 두 창이 함께 쓰는 조각
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 머리의 트랙 배지 — 트랙이 없는 시대 구분은 `공통`. 누르면 그 트랙의 문서를 연다(`track:<id>`).
DetailBadge trackBadge(AppBus bus, Map<String, dynamic> entity) {
  final id = detailString(entity, 'track');
  if (id.isEmpty) return const DetailBadge('공통');
  final table = bus.slot('tracks').value;
  final row = table is Map ? table[id] : null;
  final name = row is Map && row['name'] != null ? '${row['name']}' : detailString(entity, 'trackName');
  return DetailBadge(
    name.isEmpty ? id : name,
    color: row is Map ? detailColor(row['color']) : Ui.text3,
    onTap: () => bus.slot('doc').value = 'track:$id',
  );
}

/// 항목의 기간 줄 — 지금 연표의 `HT.formatRange`와 같은 규칙.
String entityRange(Map<String, dynamic> entity) => rangeText(
  start: detailNum(entity, 'start')?.toDouble(),
  startAt: detailString(entity, 'startAt').isEmpty ? null : detailString(entity, 'startAt'),
  end: detailNum(entity, 'end')?.toDouble(),
  endAt: detailString(entity, 'endAt').isEmpty ? null : detailString(entity, 'endAt'),
  startUnknown: entity['startUnknown'] == true,
  endUnknown: entity['endUnknown'] == true,
  ongoing: entity['ongoing'] == true,
);

/// 설명 — 없으면 메모를 그 자리에 적는다(지금 연표의 `description || note`).
String descOf(Map<String, dynamic> entity) {
  final desc = detailString(entity, 'description');
  return desc.isNotEmpty ? desc : detailString(entity, 'note');
}

/// 다른 견해 — 첫 줄은 이 연표가 쓰는 연대, 그 아래는 이설마다 연대 · 근거 · 메모.
List<Widget> alternativesBox(AppBus bus, Map<String, dynamic> entity) {
  final alts = detailList(entity, 'alternatives');
  if (alts.isEmpty) return const [];
  final uid = detailString(entity, 'uid');
  void goToYear(double t) => bus.goTo(minutesOfT(t), minutesOfT(t + 1), ring: uid);
  final start = detailNum(entity, 'start')?.toDouble();
  return [
    DetailBox(
      title: '다른 견해',
      children: [
        DetailAltList([
          DetailAltRow(
            when: entityRange(entity),
            why: '이 연표가 쓰는 연대',
            main: true,
            onTap: start == null ? null : () => goToYear(start),
          ),
          for (final a in alts)
            DetailAltRow(
              when: rangeText(start: detailNum(a, 'start')?.toDouble(), end: detailNum(a, 'end')?.toDouble()),
              why: [detailString(a, 'label'), detailString(a, 'source')].where((s) => s.isNotEmpty).join(' · '),
              note: detailString(a, 'note').isEmpty ? null : detailString(a, 'note'),
              onTap: detailNum(a, 'start') == null ? null : () => goToYear(detailNum(a, 'start')!.toDouble()),
            ),
        ]),
      ],
    ),
  ];
}

/// 아래 단추 줄 — `🎯 이 시기로`와 문서가 있을 때의 `📄 문서`.
List<Widget> footButtons(AppBus bus, Map<String, dynamic> entity, String focusText) {
  final uid = detailString(entity, 'uid');
  final start = detailNum(entity, 'start')?.toDouble();
  final end = (detailNum(entity, 'endY') ?? detailNum(entity, 'end') ?? start)?.toDouble();
  return [
    DetailSmallButton(
      focusText,
      icon: LineGlyph.locate,
      onTap: start == null || end == null ? null : () => bus.goTo(minutesOfT(start), minutesOfT(end == start ? start + 1 : end), ring: uid),
    ),
    if (detailString(entity, 'wiki').isNotEmpty) DetailSmallButton('문서', icon: LineGlyph.file, onTap: () => bus.slot('doc').value = uid),
  ];
}

/// 목록 위의 작은 머리말(`.succ-cap`) — 12px · `--text-3`.
class _Cap extends StatelessWidget {
  const _Cap(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 2),
    child: Text(text, style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text3)),
  );
}

/// `.people-note` — 가운데의 이름만 누를 수 있는 한 줄(상징적 본국 · 이어진 시대 구분).
class LinkNote extends StatelessWidget {
  const LinkNote({super.key, required this.before, required this.link, required this.onTap, this.small});

  final String before, link;
  final VoidCallback onTap;

  /// 뒤에 붙는 옅은 한마디.
  final String? small;

  static const style = TextStyle(fontSize: 13, height: 1.5, color: Ui.text2);
  static const linkStyle = TextStyle(fontSize: 13, height: 1.5, color: Ui.accent, decoration: TextDecoration.underline, decorationColor: Ui.accent);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text.rich(
      TextSpan(
        text: before,
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Semantics(
                button: true,
                label: link,
                child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: Text(link, style: linkStyle)),
              ),
            ),
          ),
          if (small != null && small!.isNotEmpty) TextSpan(text: ' ${small!}', style: const TextStyle(fontSize: 12, color: Ui.text3)),
        ],
      ),
      style: style,
    ),
  );
}

/// 대범위 이름 칩 + 모아 보기 스위치 한 줄(`.scope-row`) — 시대 구분 창의 `이어진 대범위`.
class ScopeSwitchRow extends StatelessWidget {
  const ScopeSwitchRow({super.key, required this.bus, required this.scope, this.top = 6});

  final AppBus bus;

  /// 항목 기록의 `x_scopes` 한 줄 — `{uid, name, color, label?, host?}`.
  /// 아직 `default`(기본 켬)가 실려 있지 않아, 기록이 없는 대범위는 여기서 '끔'으로 보인다
  /// (계약 6-9절의 `scopeRow`에 `default`가 더해지면 저절로 맞는다).
  final Map<String, dynamic> scope;
  final double top;

  @override
  Widget build(BuildContext context) {
    final uid = detailString(scope, 'uid');
    final label = detailString(scope, 'label');
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DetailChip(
            label.isEmpty ? detailString(scope, 'name') : '${detailString(scope, 'name')} · $label',
            onTap: () => bus.select(uid, kind: 'scope'),
          ),
          ScopeSwitch(bus: bus, uid: uid, color: detailColor(scope['color']), byDefault: scope['default'] == true),
        ],
      ),
    );
  }
}

/// 모아 보기 스위치(`.scope-switch`) — 높이 28 · 둥근 999 · 28×16 손잡이 · 켜면 제 색 18% 바탕.
/// 켜고 끈 값은 `bus.slot('scopes')`에 `{uid: 켬/끔}`으로 실린다.
class ScopeSwitch extends StatefulWidget {
  const ScopeSwitch({super.key, required this.bus, required this.uid, required this.color, this.byDefault = false});

  final AppBus bus;
  final String uid;

  /// 그 대범위의 색(`--c`).
  final Color color;

  /// 기록이 없을 때의 값(항목 기록의 `default`).
  final bool byDefault;

  @override
  State<ScopeSwitch> createState() => _ScopeSwitchState();
}

class _ScopeSwitchState extends State<ScopeSwitch> {
  @override
  Widget build(BuildContext context) {
    final on = scopeGathered(widget.bus, widget.uid, byDefault: widget.byDefault);
    return Row(mainAxisSize: MainAxisSize.min, children: [MotionToggle(value: on, label: '모아 보기', hint: on ? '모아 보기 끄기' : '모아 보기 켜기', onChanged: (value) => setScopeGathered(widget.bus, widget.uid, value)), const SizedBox(width: 7), Text(on ? '켬' : '끔', style: const TextStyle(fontSize: 11, color: Ui.text3))]);
  }
}
