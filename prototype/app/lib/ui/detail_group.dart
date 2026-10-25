import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shell/look.dart';
import 'app_bus.dart';
import 'date_text.dart';
import 'detail_format3.dart';
import 'detail_item.dart' show certaintyNames, namedOf;
import 'detail_shell.dart';
import 'names_display.dart';
import 'doc_window.dart' show DocChips;
import 'group_tree.dart' show GroupTreeButton, GroupTreeLayer, groupTreeHolder;

// ════════════════════════════════════════════════════════════════════════════════════════════
//  단체 창과 제도 창 (형식 버전 3 — 설계 `docs/설계-10건/A-아카이브-이음.md` 4-2절 A1-c 2걸음)
//
//  묶음이 나오는 차례는 지금 연표의 `groupDetailHTML`(js/viewer.js:1706) ·
//  `institutionDetailHTML`(js/viewer.js:1776) 그대로이고, **비어 있는 묶음은 아예 그리지 않는다.**
//  단체 · 제도는 연표에 제 줄이 없어 가문 창처럼 **고르지 않고(pick: false) 세로 닻도 걸지 않는다(lane: false)**
//  — 창을 열어도 연표가 흐려지거나 조명이 켜지지 않는다(웹 DETAIL_KINDS의 group · institution).
//  아래 단추 `🎯 이 시기로`만 그 나라 줄로 데려간다(웹 `timeline.focusOn` — 기간의 2.2배 · 그 나라의 줄).
//
//  ── 쓰는 법 ───────────────────────────────────────────────────────────────────────────────
//    registerGroupDetail();                // 앱을 세울 때 한 번(app_glue.dart의 registerDetailKinds)
//    …  DetailHost(bus: bus)               // 나머지는 뼈대가 한다(갈래 'group' · 'institution')
//
//  ── 이 창이 항목 기록에서 읽는 것(계약 초안 6-9 다 = 설계 부록 가-6 · 내보내기가 미리 풀어 둔 `x_…`) ──
//    단체: x_names · x_type · x_span · x_within · x_members · x_power · x_from · x_into · x_people ·
//          x_event · x_warnings · x_docs · x_groupTree | x_treeAt(단체 계보 창 — 설계 D5 결정 4 A · ui/group_tree.dart)
//          (본문: name · track · color · start/end/endY(+At) · …Unknown ·
//          certainty · startRange/endRange(+At) · description · note · debate · alternatives · packName · wiki · event)
//    제도: x_names · x_theme · x_polity · x_spans · x_same · x_warnings · x_docs
//          (본문: track · color · family · start · endY · description · packName · wiki)
//    `x_`가 없는 옛 기록이면 본문의 같은 뜻 칸(typeName · themeName · polityName …)으로 머리만 선다.
//
//  ── 앱 틀이 채워 주어야 하는 곳 ─────────────────────────────────────────────────────────────
//    bus.slot('tracks') = {'sample-gr-west': {'name': '서쪽 들', 'color': 0xb6c398}, …}  (머리의 트랙 배지)
//    bus.slot('doc')    ← `📄 문서` · 트랙 배지를 누르면 그 열쇠(uid · `track:<id>`)
//    `{"op":"ids_of"}`  ← `🎯 이 시기로`가 그 나라 띠의 줄을 묻는다(답이 없으면 줄 없이 기간만 옮긴다)
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 갈래 `group`(단체)과 `institution`(제도)을 이 파일이 맡는다.
void registerGroupDetail() {
  DetailHost.register('group', GroupDetail.new);
  DetailHost.register('institution', InstitutionDetail.new);
}

/// 앞선 단체 · 뒤를 이은 단체의 갈래(지금 연표 `HT.GROUP_HOWS`) — `howName`이 없을 때만 쓴다.
const groupHowNames = {'split': '갈라짐', 'merge': '합쳐짐', 'rename': '이름 바꿈'};

/// 한 해(분) — 1970년 기준 평균 해의 길이(365.25일).
const _yearMinutes = 525960.0;

// ────────────────────────────────────────────────────────────────────────────────────────────
//  0. 두 창이 함께 쓰는 것
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 그 나라 띠의 줄 — `{"op":"ids_of"}`로 묻는다. 모르면 null(줄 없이 기간만 옮긴다).
Future<int?> detailRowOf(AppBus bus, String uid) async {
  if (uid.isEmpty) return null;
  try {
    final answer = await bus.ask({
      'op': 'ids_of',
      'uids': [uid],
    });
    final bands = answer['bands'];
    if (bands is List) {
      for (final b in bands) {
        if (b is Map && b['uid'] == uid && b['row'] is num) return (b['row'] as num).toInt();
      }
    }
  } catch (_) {
    // ids_of를 모르는 자료 처리부 — 줄 없이 간다.
  }
  return null;
}

/// `🎯 이 시기로`가 갈 구간 — 지금 연표 `timeline.focusOn` 그대로: 기간이 있으면 그 2.2배(해 단위면 30년보다 좁게는
/// 가지 않는다), 한 점이면 지금 보는 폭을 정밀도의 문턱(해 30~160년 · 달 2~5년 · 날 두 달~반년 · 시각 사흘~열흘) 안으로.
({double lo, double hi}) detailFocusRange(double lo, double hi, {String? startAt, double? viewSpan}) {
  final len = hi - lo;
  final prec = (startAt ?? '').trim().isEmpty ? DatePrec.year : precOfAt(startAt);
  final (minYears, maxYears) = switch (prec) {
    DatePrec.month => (2.0, 5.0),
    DatePrec.day => (60 / 365.25, .5),
    DatePrec.hour || DatePrec.minute => (3 / 365.25, 10 / 365.25),
    DatePrec.year => (30.0, 160.0),
  };
  final span = len > 0
      ? math.max(len * 2.2, math.min(minYears, 30) * _yearMinutes)
      : (viewSpan ?? minYears * _yearMinutes).clamp(minYears * _yearMinutes, maxYears * _yearMinutes).toDouble();
  final c = lo + len / 2;
  return (lo: c - span / 2, hi: c + span / 2);
}

/// 머리의 트랙 배지 — 누르면 그 트랙의 문서(웹 `data-doc="track:…"`). 트랙 표에 없으면 배지를 두지 않는다.
List<Widget> _trackBadge(DetailContext ctx, String track) {
  final named = namedOf(ctx.bus, 'tracks', track);
  if (named == null) return const [];
  return [DetailBadge(named.name, color: named.color, onTap: () => ctx.slot('doc').value = 'track:$track')];
}

/// `.succ-cap` — 묶음 안의 작은 머리말(기본 상세 · 가문 창의 것과 같은 모양).
Widget _cap(String text, [String? small]) => Padding(
  padding: const EdgeInsets.only(top: 8, bottom: 2),
  child: Text.rich(
    TextSpan(
      text: text,
      children: [if (small != null && small.isNotEmpty) TextSpan(text: ' $small', style: const TextStyle(fontWeight: FontWeight.w400, color: Ui.text3))],
    ),
    style: const TextStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w600, color: Ui.text2),
  ),
);

/// `.kid-list` 한 줄 — `[기간(굵게 · 60px부터)][이름 <small>메모</small> <i>안내</i>]`.
/// 집권 기간 · 제도 칸처럼 이름 뒤에 작은 글 · 기울인 글이 붙는 줄.
class DetailKidRichRow extends StatelessWidget {
  const DetailKidRichRow({super.key, required this.when, required this.bits, this.onTap});
  final String when;
  final List<DetailBit> bits;
  final VoidCallback? onTap;

  /// 이 줄의 글 — 웹 `<b>기간</b><span>…</span>`의 글 그대로(사이 띄어쓰기 없음).
  String get text => '$when${bits.map((b) => b.shown).join()}';

  @override
  Widget build(BuildContext context) => DetailPressable(
    onTap: onTap,
    semantics: bits.map((b) => b.text).join(),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 60),
          child: Text(when, style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()])),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                for (final b in bits)
                  switch (b.kind) {
                    // `<small>` — 13px의 1/1.2.
                    DetailBitKind.small => TextSpan(text: b.text, style: const TextStyle(fontSize: 11, color: Ui.text3)),
                    DetailBitKind.italic => TextSpan(text: b.text, style: const TextStyle(fontStyle: FontStyle.italic, color: Ui.text2)),
                    DetailBitKind.bold => TextSpan(text: b.text, style: const TextStyle(fontWeight: FontWeight.w700)),
                    _ => TextSpan(text: b.shown),
                  },
              ],
            ),
            style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text),
          ),
        ),
      ],
    ),
  );
}

/// `.tr-role` — 이름 뒤의 역할 알약(구성 나라의 `맹주` 따위).
class _RolePill extends StatelessWidget {
  const _RolePill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(color: Ui.accentSoft, borderRadius: BorderRadius.circular(999)),
    child: Text(text, style: const TextStyle(fontSize: 11, height: 1.6, color: Ui.text2)),
  );
}

/// 한 칸의 구간(`span` [lo, hi] 분)으로 데려가는 탭 — 지도자 칸 · 구성원 줄과 같은 길(그 해의 시작 한 해).
VoidCallback? _goSpan(DetailContext ctx, Object? span) {
  final s = detailSpanOf(span);
  if (s == null) return null;
  return () => ctx.goTo(s.lo, minutesOfT(tOfMinutes(s.lo) + 1));
}

/// 다른 견해(본문 `alternatives`) — 기본 상세와 같은 상자(첫 줄은 이 연표가 쓰는 연대).
List<Widget> _alternatives(DetailContext ctx, String when, double? start) {
  final alts = detailList(ctx.json, 'alternatives');
  if (alts.isEmpty) return const [];
  void goYear(double t) => ctx.goTo(minutesOfT(t), minutesOfT(t + 1));
  return [
    DetailBox(
      title: '다른 견해',
      children: [
        DetailAltList([
          DetailAltRow(when: when, why: '이 연표가 쓰는 연대', main: true, onTap: start == null ? null : () => goYear(start)),
          for (final a in alts)
            DetailAltRow(
              when: rangeText(start: detailNum(a, 'start')?.toDouble(), end: detailNum(a, 'end')?.toDouble()),
              why: detailString(a, 'label'),
              note: detailString(a, 'note').isEmpty ? null : detailString(a, 'note'),
              onTap: detailNum(a, 'start') == null ? null : () => goYear(detailNum(a, 'start')!.toDouble()),
            ),
        ]),
      ],
    ),
  ];
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  1. 단체 창 — 웹 groupDetailHTML
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 단체 창: 이름 · 원어 · 종류 · 기간 · 있던 나라 · 집권 기간 · 앞선/뒤를 이은 단체 · 구성원 · 연합의 구성 나라 ·
/// 맺은 사건 · 확인할 것 · 하위 문서 · 다른 견해 · 쟁점 · 제공.
class GroupDetail extends StatelessWidget {
  const GroupDetail(this.ctx, {super.key});
  final DetailContext ctx;

  Map<String, dynamic> get x => ctx.json;

  double? get _start => detailNum(x, 'start')?.toDouble();
  double? get _end => (detailNum(x, 'end') ?? detailNum(x, 'endY'))?.toDouble();
  bool get _startUnknown => x['startUnknown'] == true;
  bool get _endUnknown => x['endUnknown'] == true;
  String get _type => detailString(x, 'x_type').isNotEmpty ? detailString(x, 'x_type') : detailString(x, 'typeName');

  /// 기간 줄 — 웹 `HT.formatRange(g)`.
  String get _when {
    final startAt = detailString(x, 'startAt'), endAt = detailString(x, 'endAt');
    return rangeText(
      start: _start,
      startAt: startAt.isEmpty ? null : startAt,
      end: _end,
      endAt: endAt.isEmpty ? null : endAt,
      startUnknown: _startUnknown,
      endUnknown: _endUnknown,
    );
  }

  @override
  Widget build(BuildContext context) => DetailShell(
    onClose: ctx.close,
    badges: [
      ..._trackBadge(ctx, detailString(x, 'track')),
      DetailBadge('단체', color: detailColor(x['color'])),
      if (_type.isNotEmpty) DetailBadge(_type),
      if (detailString(x, 'certainty').isNotEmpty && detailString(x, 'certainty') != 'accepted')
        DetailBadge('${certaintyNames[detailString(x, 'certainty')] ?? detailString(x, 'certainty')} 연대', color: DetailUi.warn),
      if (_startUnknown || _endUnknown) const DetailBadge('연도 미정', color: DetailUi.warn),
    ],
    body: [
      DetailTitle(detailString(x, 'name')),
      // 원어 머리 두 줄 · '다른 이름' 칸(10건 3 · 감독 결정 D2-1 A — 웹 namesHeadHTML · namesRestHTML(g.names, 'polity')).
      NamesHead(bus: ctx.bus, head: x['x_nameHead'], old: x['x_names'], kind: NameKind.polity),
      DetailWhen(_when),
      ..._rangeNotes(),
      ..._within(),
      NamesRest(bus: ctx.bus, head: x['x_nameHead'], kind: NameKind.polity),
      DetailDesc(detailString(x, 'description').isNotEmpty ? detailString(x, 'description') : detailString(x, 'note')),
      ..._power(),
      ..._branches(),
      ..._people(),
      ..._members(),
      ..._event(),
      ...detailWarnBox(x['x_warnings']),
      DocChips(bus: ctx.bus, uid: ctx.uid, json: x),
      ..._alternatives(ctx, _when, _start),
      if (detailString(x, 'debate').isNotEmpty) DetailBox(title: '쟁점', children: [DetailDesc(detailString(x, 'debate'), small: true)]),
      DetailDefs([
        DetailDef('제공', Text(detailString(x, 'packName'))),
        if (detailString(x, 'note').isNotEmpty && detailString(x, 'description').isNotEmpty) DetailDef('메모', Text(detailString(x, 'note'))),
      ]),
    ],
    foot: [
      DetailSmallButton('이 시기로', icon: LineGlyph.locate, onTap: focus),
      // 단체 계보 창(웹 단체 창의 `단체 계보` 단추 — 이 단체를 고른 채로 그 나라의 나무). 계보 창 층이 붙어 있을 때만 선다.
      if (groupTreeHolder(x, ctx.uid) != null && GroupTreeLayer.mountedOn(ctx.bus)) GroupTreeButton(uid: groupTreeHolder(x, ctx.uid)!, group: ctx.uid, bus: ctx.bus),
      if (detailString(x, 'wiki').isNotEmpty) DetailSmallButton('문서', icon: LineGlyph.file, onTap: () => ctx.slot('doc').value = ctx.uid),
    ],
  );

  /// 연대 폭 — `시작 — 이르면 …, 늦으면 …`(본문 `startRange` · `endRange`는 해 좌표).
  List<Widget> _rangeNotes() => [
    for (final pair in const [('시작', 'startRange'), ('끝', 'endRange')])
      if (x[pair.$2] is List && (x[pair.$2] as List).length >= 2 && (x[pair.$2] as List)[0] is num && (x[pair.$2] as List)[1] is num)
        DetailRangeNote(
          rangeNote(
            pair.$1,
            ((x[pair.$2] as List)[0] as num).toDouble(),
            ((x[pair.$2] as List)[1] as num).toDouble(),
            loAt: _atOf('${pair.$2}At', 0),
            hiAt: _atOf('${pair.$2}At', 1),
          ),
        ),
  ];

  String? _atOf(String key, int i) {
    final v = x[key];
    return v is List && v.length > i && v[i] is String && (v[i] as String).isNotEmpty ? v[i] as String : null;
  }

  /// `있던 나라 [나라 칩] 기간 …`(기간은 적었거나 미정일 때만).
  List<Widget> _within() {
    final rows = detailList(x, 'x_within');
    if (rows.isEmpty) return const [];
    return [
      DetailChipLine(
        label: '있던 나라',
        children: [
          for (final r in rows) ...[
            detailPolityChip(r, ctx.open),
            if (detailString(r, 'when').isNotEmpty) DetailChipLine.small(detailString(r, 'when')),
          ],
        ],
      ),
    ];
  }

  /// 집권 기간 — 누르면 그 시기로. 끝을 비운 칸은 `끝은 다음 칸 · 단체의 끝까지`.
  List<Widget> _power() {
    final rows = detailList(x, 'x_power');
    if (rows.isEmpty) return const [];
    return [
      DetailBox(
        title: '집권 기간',
        small: '${rows.length}',
        children: [
          DetailKidList([
            for (final c in rows)
              DetailKidRichRow(
                when: detailString(c, 'when'),
                bits: [
                  DetailBit(detailString(c, 'name')),
                  if (detailString(c, 'note').isNotEmpty) ...[const DetailBit(' '), DetailBit.small(detailString(c, 'note'))],
                  if ((c['endAuto'] == 1 || c['endAuto'] == true) && !(c['endUnknown'] == 1 || c['endUnknown'] == true)) ...[
                    const DetailBit(' '),
                    const DetailBit.italic('끝은 다음 칸 · 단체의 끝까지'),
                  ],
                ],
                onTap: _goSpan(ctx, c['span']),
              ),
          ]),
        ],
      ),
    ];
  }

  /// 갈래 — 앞선 단체 · 뒤를 이은 단체(칩 뒤의 작은 글은 `갈라짐 · 메모`).
  List<Widget> _branches() {
    final from = detailList(x, 'x_from'), into = detailList(x, 'x_into');
    if (from.isEmpty && into.isEmpty) return const [];
    String small(Map<String, dynamic> f) {
      final how = detailString(f, 'howName').isNotEmpty ? detailString(f, 'howName') : (groupHowNames[detailString(f, 'how')] ?? '');
      return [how, detailString(f, 'note')].where((s) => s.isNotEmpty).join(' · ');
    }

    return [
      DetailBox(
        title: '갈래',
        children: [
          if (from.isNotEmpty) ...[
            _cap('앞선 단체', '${from.length}'),
            DetailChipRow([for (final f in from) detailGroupChip(f, ctx.open, small: small(f))], top: 0),
          ],
          if (into.isNotEmpty) ...[
            _cap('뒤를 이은 단체', '${into.length}'),
            DetailChipRow([for (final f in into) detailGroupChip(f, ctx.open, small: small(f))], top: 0),
          ],
        ],
      ),
    ];
  }

  /// 구성원 칩 하나(사람 고리 + `role` · `color`): 인물이면 이름 + 역할(작게) → 인물 창,
  /// 인물 없는 지도자 칸이면 이름 + 나라(작게) → 그 칸 창, 찾지 못한 이름은 누를 수 없는 칩.
  Widget _memberChip(Map<String, dynamic> p) {
    final uid = detailString(p, 'uid'), ref = detailString(p, 'ref');
    final color = p['color'] == null ? null : detailColor(p['color']);
    if (uid.isNotEmpty && ref.isNotEmpty) {
      return DetailDotChip(detailString(p, 'name'), small: detailString(p, 'polity'), color: color, onTap: () => ctx.open(uid, cell: ref));
    }
    if (uid.isNotEmpty) {
      return DetailDotChip(detailString(p, 'name'), small: detailString(p, 'role'), color: color, onTap: () => ctx.open(uid, kind: 'figure'));
    }
    return DetailDotChip(detailString(p, 'name'));
  }

  List<Widget> _people() {
    final rows = detailList(x, 'x_people');
    if (rows.isEmpty) return const [];
    return [
      DetailBox(
        title: '구성원',
        small: '${rows.length}',
        children: [
          DetailChipRow([for (final p in rows) _memberChip(p)], top: 0),
        ],
      ),
    ];
  }

  /// 연합의 구성 나라 — `[나라 칩][역할 알약][다른 트랙이면 트랙][기간][· 메모]`.
  List<Widget> _members() {
    final rows = detailList(x, 'x_members');
    if (rows.isEmpty) return const [];
    Widget small(String t) => Text(t, style: const TextStyle(fontSize: 11, height: 1.5, color: Ui.text3));
    return [
      DetailBox(
        title: '구성 나라',
        small: '${rows.length}',
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  detailPolityChip(r, ctx.open),
                  if (detailString(r, 'role').isNotEmpty) _RolePill(detailString(r, 'role')),
                  if (detailString(r, 'track').isNotEmpty) small(detailString(r, 'track')),
                  if (detailString(r, 'when').isNotEmpty) small(detailString(r, 'when')),
                  if (detailString(r, 'note').isNotEmpty) small('· ${detailString(r, 'note')}'),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  /// `맺은 사건 〈제목〉 기간` — 찾지 못했으면 적힌 글 + `(연표에서 찾지 못함)`.
  List<Widget> _event() {
    final ev = x['x_event'];
    if (ev is Map && '${ev['uid'] ?? ''}'.isNotEmpty) {
      final e = ev.cast<String, dynamic>();
      return [
        DetailLine([
          const DetailBit('맺은 사건 '),
          DetailBit.link(detailString(e, 'title'), () => ctx.open(detailString(e, 'uid'))),
          if (detailString(e, 'when').isNotEmpty) ...[const DetailBit(' '), DetailBit.small(detailString(e, 'when'))],
        ], style: DetailLineStyle.note),
      ];
    }
    final raw = detailString(x, 'event');
    if (raw.isEmpty) return const [];
    return [
      DetailLine([DetailBit('맺은 사건 $raw '), const DetailBit.small('(연표에서 찾지 못함)')], style: DetailLineStyle.note),
    ];
  }

  /// 그 나라 줄의 기간으로(있던 나라 → 구성 나라의 첫 나라).
  Future<void> focus() async {
    final span = detailSpanOf(x['x_span']) ?? _bodySpan();
    if (span == null) return;
    String polity = '';
    for (final r in [...detailList(x, 'x_within'), ...detailList(x, 'x_members')]) {
      if (detailString(r, 'uid').isNotEmpty) {
        polity = detailString(r, 'uid');
        break;
      }
    }
    final row = await detailRowOf(ctx.bus, polity);
    final at = detailString(x, 'startAt');
    final r = detailFocusRange(span.lo, span.hi, startAt: at.isEmpty ? null : at, viewSpan: ctx.bus.controller.view.span);
    ctx.goTo(r.lo, r.hi, row: row);
  }

  ({double lo, double hi})? _bodySpan() {
    final s = _start;
    if (s == null) return null;
    final e = (detailNum(x, 'endY') ?? detailNum(x, 'end'))?.toDouble() ?? s;
    return (lo: minutesOfT(s), hi: minutesOfT(e));
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  2. 제도 창 — 웹 institutionDetailHTML
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 제도 창: `주제 〈나라〉` · 원어 · 기간 · 나라 · 칸 목록(온 곳) · 같은 갈래의 다른 나라 · 확인할 것 · 하위 문서 · 제공.
class InstitutionDetail extends StatelessWidget {
  const InstitutionDetail(this.ctx, {super.key});
  final DetailContext ctx;

  Map<String, dynamic> get x => ctx.json;

  Map<String, dynamic> _map(String key) {
    final v = x[key];
    return v is Map ? v.cast<String, dynamic>() : const {};
  }

  String get _themeName => detailString(_map('x_theme'), 'name').isNotEmpty ? detailString(_map('x_theme'), 'name') : detailString(x, 'themeName');
  Color get _themeColor => detailColor(_map('x_theme')['color'] ?? x['themeColor']);
  String get _polityName => detailString(_map('x_polity'), 'name').isNotEmpty ? detailString(_map('x_polity'), 'name') : detailString(x, 'polityName');
  String get _family => detailString(x, 'family');

  @override
  Widget build(BuildContext context) {
    final polity = _map('x_polity');
    return DetailShell(
      onClose: ctx.close,
      badges: [
        if (detailString(x, 'track').isNotEmpty) ..._trackBadge(ctx, detailString(x, 'track')),
        DetailBadge('제도', color: detailColor(x['color'])),
        DetailBadge(_themeName, color: _themeColor),
        if (_family.isNotEmpty) DetailBadge(_family, color: detailColor(x['color'])),
      ],
      body: [
        DetailTitle(_themeName, small: _polityName),
        NamesHead(bus: ctx.bus, head: x['x_nameHead'], old: x['x_names'], kind: NameKind.polity),
        DetailWhen(rangeText(start: detailNum(x, 'start')?.toDouble(), end: detailNum(x, 'endY')?.toDouble())),
        DetailChipLine(
          label: '나라',
          children: [
            detailPolityChip({'uid': detailString(polity, 'uid'), 'name': _polityName, 'color': polity['color']}, ctx.open),
            if (_family.isNotEmpty) DetailChipLine.small('· 갈래 $_family'),
          ],
        ),
        NamesRest(bus: ctx.bus, head: x['x_nameHead'], kind: NameKind.polity),
        DetailDesc(detailString(x, 'description')),
        _spans(),
        ..._same(),
        ...detailWarnBox(x['x_warnings']),
        DocChips(bus: ctx.bus, uid: ctx.uid, json: x),
        DetailDefs([DetailDef('제공', Text(detailString(x, 'packName')))]),
      ],
      foot: [
        DetailSmallButton('이 시기로', icon: LineGlyph.locate, onTap: focus),
        if (detailString(x, 'wiki').isNotEmpty) DetailSmallButton('문서', icon: LineGlyph.file, onTap: () => ctx.slot('doc').value = ctx.uid),
      ],
    );
  }

  /// 칸의 온 곳 글 — `나라 «그 나라의 칸»`(지금 연표 `fromRefText`). `polity`가 없으면 `name`이 나라 이름이다.
  static String fromText(Map<String, dynamic> f) {
    final polity = detailString(f, 'polity');
    if (polity.isEmpty) return detailString(f, 'name');
    final span = detailString(f, 'name');
    return '$polity${span.isNotEmpty ? ' «$span»' : ''}';
  }

  /// 칸 목록 — `[기간][이름 <small>메모</small> <i>← 온 곳에서 옴</i> <i>경계는 짐작</i>]` · 그 아래 `온 곳` 나라 칩.
  Widget _spans() {
    final rows = detailList(x, 'x_spans');
    final sources = <String, Map<String, dynamic>>{};
    for (final sp in rows) {
      final f = sp['from'];
      if (f is! Map) continue;
      final from = f.cast<String, dynamic>();
      final uid = detailString(from, 'uid');
      if (uid.isEmpty || sources.containsKey(uid)) continue;
      final name = detailString(from, 'polity').isNotEmpty ? detailString(from, 'polity') : detailString(from, 'name');
      sources[uid] = {'uid': uid, 'name': name, 'color': from['color']};
    }
    return DetailBox(
      title: '칸',
      small: '${rows.length}',
      children: [
        DetailKidList([
          for (final sp in rows)
            DetailKidRichRow(
              when: detailString(sp, 'when'),
              bits: [
                DetailBit(detailString(sp, 'name')),
                if (detailString(sp, 'note').isNotEmpty) ...[const DetailBit(' '), DetailBit.small(detailString(sp, 'note'))],
                if (sp['from'] is Map) ...[const DetailBit(' '), DetailBit.italic('← ${fromText((sp['from'] as Map).cast<String, dynamic>())}에서 옴')],
                if (sp['guess'] == 1 || sp['guess'] == true) ...[const DetailBit(' '), const DetailBit.italic('경계는 짐작')],
              ],
              onTap: _goSpan(ctx, sp['span']),
            ),
        ]),
        if (sources.isNotEmpty) ...[
          _cap('온 곳'),
          DetailChipRow([for (final p in sources.values) detailPolityChip(p, ctx.open)], top: 0),
        ],
      ],
    );
  }

  /// 같은 갈래의 다른 나라 — 칩은 `나라 기간`(작게), 누르면 그 나라의 제도 창.
  List<Widget> _same() {
    final rows = detailList(x, 'x_same');
    if (rows.isEmpty) return const [];
    return [
      DetailBox(
        title: '같은 갈래의 다른 나라',
        small: '${rows.length}',
        children: [
          DetailChipRow([
            for (final q in rows)
              DetailDotChip(
                detailString(q, 'polity').isNotEmpty ? detailString(q, 'polity') : detailString(q, 'name'),
                small: detailString(q, 'when').isEmpty ? null : detailString(q, 'when'),
                color: detailColor(q['color']),
                onTap: detailString(q, 'uid').isEmpty ? null : () => ctx.open(detailString(q, 'uid'), kind: 'institution'),
              ),
          ], top: 0),
        ],
      ),
    ];
  }

  /// 그 나라 줄의 칸 전체 기간으로.
  Future<void> focus() async {
    double? lo, hi;
    for (final sp in detailList(x, 'x_spans')) {
      final s = detailSpanOf(sp['span']);
      if (s == null) continue;
      lo = lo == null ? s.lo : math.min(lo, s.lo);
      hi = hi == null ? s.hi : math.max(hi, s.hi);
    }
    if (lo == null || hi == null) {
      final start = detailNum(x, 'start')?.toDouble();
      if (start == null) return;
      lo = minutesOfT(start);
      hi = minutesOfT((detailNum(x, 'endY') ?? start).toDouble());
    }
    final row = await detailRowOf(ctx.bus, detailString(_map('x_polity'), 'uid'));
    final r = detailFocusRange(lo, hi, viewSpan: ctx.bus.controller.view.span);
    ctx.goTo(r.lo, r.hi, row: row);
  }
}
