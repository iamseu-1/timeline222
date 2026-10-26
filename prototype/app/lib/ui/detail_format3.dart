import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'dart:math' as math;

import '../scene/aux_calendar.dart' show AuxCalendarStore;
import '../scene/color_mix.dart';
import '../shell/look.dart';
import 'date_text.dart';
import 'detail_shell.dart';
import 'group_tree.dart' show GroupTreeButton, GroupTreeLayer;

// ════════════════════════════════════════════════════════════════════════════════════════════
//  형식 3의 상세 창 공용 부품 — 원어 줄 · 사람 고리 · 혈연 줄 · 지명 줄 · 법 · 선거 · 단체/제도 칩
//  (설계 `docs/설계-10건/A-아카이브-이음.md` 4-2절 A1-c 1걸음 · 계약 초안 6-9 다 = 같은 문서 부록 가-6)
//
//  글 · 차례는 지금 연표(js/viewer.js)의 것 그대로다:
//    namesHTML(678줄) · personLink · kinLinesHTML(696줄) · placeHTML(736줄) ·
//    lensBadgesHTML · lensBottomHTML(1830줄) · periodLensHTML · groupChipHTML · polityChipHTML.
//  새 앱은 모델을 갖지 않으므로 이 파일은 **내보내기가 넣을 때 한 번 풀어 둔 `x_…`**만 읽는다
//  (글은 웹이 만든 글 그대로 — 계약 6-9 가의 약속 4). 열쇠가 없으면 그 줄은 아예 서지 않는다.
//
//  ── 쓰는 법(있던 창에 새 줄을 넣는 묶음 A1-d · 단체/제도 창 detail_group.dart) ─────────────────
//    ...detailNamesLines(x['x_names'])                              원어 줄(머리 이름 아래 · 그 밖의 이름)
//    ...detailNamesLines(sn['names'], lead: [DetailBit('성 솔 — ')]) 앞말을 붙인 원어 줄
//    DetailPersonRing(고리, open: ctx.open, here: ctx.uid, lead: [...])  사람 고리 한 줄
//    ...detailKinLines(x_persons['leader:3'], open: ctx.open, here: ctx.uid)   부모 · 배우자 · 자식 줄
//    ...detailPersonGroupsLines(x_persons['leader:3'], open: ctx.open)        `속한 단체:` 줄(혈연 줄 다음)
//    ...detailPlaceLines(x['x_place'], lead: '장소')               지명 줄(사건 '장소' · 도읍 칸 '지명')
//    ...detailLensBadges(x)                                         사건 머리의 주제 · 법 · 선거 딱지
//    ...detailLensBottom(x, ctx.open)                               조항 · 관련 · 이 일로 맺은 단체(아래 셋을 아직 제자리에 부르지 않으면 그것도 맨 앞에)
//    ...detailLensAka(x)                                           법 이름 · 뽑은 자리(제목 바로 아래 — 설계 D5 결정 7 A · 9절)
//    ...detailLawTop(x, ctx.open)                                  법의 내력(기본 기간 줄 자리 — 비면 기간 줄을 둔다)
//    ...detailElectionTop(x, ctx.open)                             선거 결과 · 의석 막대(설명 바로 위)
//       → 셋을 제자리에 부르면 아래는 detailLensBottom(x, ctx.open, topsPlaced: true)
//    ...detailPolityLensBoxes(x, ctx.open)                          나라의 '단체' · '제도' 칩 묶음
//
//  ── 글 한 줄 ────────────────────────────────────────────────────────────────────────────────
//    웹의 `<p class="aka">` 한 줄에는 보통 글 · `<small>` · `<b>` · `<i>` · 누르는 이름(`.linky`) ·
//    원어(`<bdi lang>`)가 섞인다. 여기서는 그 조각을 [DetailBit]로 적고 [DetailLine]이 글 하나(Text.rich)로 그린다
//    — 조각 사이 띄어쓰기까지 웹의 글(textContent)과 같게 둔다. 원어는 U+2068(FSI) … U+2069(PDI)로 감싸
//    오른쪽에서 왼쪽으로 쓰는 글자가 섞여도 그 이름만 방향을 바꾼다(웹 `<bdi>`). 글을 견줄 때는
//    [detailPlain]으로 그 두 글자를 뺀다.
//    누르는 이름은 `detail_people.dart`의 `_LinkyLine`과 같은 모양(12px · `--accent` · 밑줄)이다.
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 다른 항목 · 칸의 창을 연다 — [DetailContext.open]을 그대로 넘긴다(`ctx.open`).
typedef DetailOpen = void Function(String uid, {String kind, String? cell});

/// 원어를 웹 `<bdi>`처럼 감싼다 — U+2068(FSI) … U+2069(PDI).
String detailIsolate(String text) => '\u2068$text\u2069';

/// 글에서 격리 문자(U+2068 · U+2069)를 뺀다 — 웹의 글과 견줄 때.
String detailPlain(String text) => text.replaceAll('\u2068', '').replaceAll('\u2069', '');

final _langTag = RegExp(r'^(?:[a-z]{2,8}(?:-[a-z0-9]{1,8})*|x(?:-[a-z0-9]{1,8})+)$', caseSensitive: false);

/// 언어 꼬리표 → 글의 언어(지금 연표 `HT.isLangTag`와 같은 꼴만). `x-`로 시작하는 가상 언어 · 꼴이 틀린 것은 null.
Locale? detailLocaleOf(String? tag) {
  final t = (tag ?? '').trim();
  if (t.isEmpty || !_langTag.hasMatch(t)) return null;
  final parts = t.split('-');
  if (parts.first.toLowerCase() == 'x') return null;
  String? script, region;
  for (final p in parts.skip(1)) {
    if (script == null && region == null && p.length == 4 && RegExp(r'^[a-zA-Z]{4}$').hasMatch(p)) {
      script = '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}';
    } else if (region == null && (RegExp(r'^[a-zA-Z]{2}$').hasMatch(p) || RegExp(r'^\d{3}$').hasMatch(p))) {
      region = p.toUpperCase();
    }
  }
  return Locale.fromSubtags(languageCode: parts.first.toLowerCase(), scriptCode: script, countryCode: region);
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  1. 값 꺼내기 — 기록의 `x_…`는 빈 것을 싣지 않으므로(약속 2) 없으면 빈 값
// ────────────────────────────────────────────────────────────────────────────────────────────

Map<String, dynamic>? _map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

List<Map<String, dynamic>> _maps(Object? v) => [
  if (v is List)
    for (final one in v)
      if (one is Map) one.cast<String, dynamic>(),
];

String _s(Map<String, dynamic>? m, String key) {
  final v = m?[key];
  return v is String ? v : (v == null ? '' : '$v');
}

/// `1` · `true` 모두 참(약속: 참인 깃발은 `1`).
bool _on(Map<String, dynamic>? m, String key) {
  final v = m?[key];
  return v == true || v == 1;
}

/// 구간 `[lo, hi]`(분) — 없거나 꼴이 틀리면 null.
({double lo, double hi})? detailSpanOf(Object? v) {
  if (v is List && v.length >= 2 && v[0] is num && v[1] is num) return (lo: (v[0] as num).toDouble(), hi: (v[1] as num).toDouble());
  return null;
}

/// 연대의 확실성 이름(지금 연표 `HT.certaintyName`) — 혈연 줄의 `certainty`가 id로 와도 글로.
const _certaintyNames = {'certain': '확실', 'accepted': '통설', 'estimated': '추정', 'legend': '전승', 'disputed': '논쟁'};

/// 법의 고침 종류(지금 연표 `HT.LAW_ACTS`) — `actName`이 없을 때만 쓴다.
const _lawActNames = {'enact': '제정', 'amend': '개정', 'repeal': '폐지'};

// ────────────────────────────────────────────────────────────────────────────────────────────
//  2. 글 한 줄 — 조각([DetailBit])을 글 하나로
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 조각의 갈래 — 보통 글 · `<small>` · 누르는 이름(`.linky`) · `<b>` · `<i>` · 원어(`<bdi lang>`).
enum DetailBitKind { plain, small, link, bold, italic, name }

/// 글 한 줄 안의 조각 하나.
@immutable
class DetailBit {
  const DetailBit(this.text) : kind = DetailBitKind.plain, onTap = null, lang = null;
  const DetailBit.small(this.text) : kind = DetailBitKind.small, onTap = null, lang = null;

  /// 누르는 이름. [onTap]이 null이면 보통 글로 그린다(웹도 갈 곳이 없으면 글만 둔다).
  const DetailBit.link(this.text, this.onTap) : kind = DetailBitKind.link, lang = null;
  const DetailBit.bold(this.text) : kind = DetailBitKind.bold, onTap = null, lang = null;
  const DetailBit.italic(this.text) : kind = DetailBitKind.italic, onTap = null, lang = null;

  /// 원어 하나 — 격리 문자로 감싸고, 표준 언어 꼬리표면 그 언어로 쓴다.
  const DetailBit.name(this.text, {this.lang}) : kind = DetailBitKind.name, onTap = null;

  final String text;
  final DetailBitKind kind;
  final VoidCallback? onTap;
  final String? lang;

  /// 그려지는 글(원어는 격리 문자까지).
  String get shown => kind == DetailBitKind.name ? detailIsolate(text) : text;
}

/// 조각 묶음을 `sep`으로 잇는다(` · ` 따위).
List<DetailBit> detailJoin(Iterable<List<DetailBit>> parts, [String sep = ' · ']) {
  final out = <DetailBit>[];
  for (final p in parts) {
    if (p.isEmpty) continue;
    if (out.isNotEmpty) out.add(DetailBit(sep));
    out.addAll(p);
  }
  return out;
}

/// 글 한 줄의 모양.
/// [aka]는 `.aka`(12px · `--text-3` · 아래 8 — 원어 줄 · 혈연 줄 · 지명 줄),
/// [note]는 `.people-note`(13px · `--text-2` · 안의 작은 글 12px — 있던 나라 · 맺은 사건).
enum DetailLineStyle { aka, note }

/// 조각을 글 하나로 그리는 한 줄. 누르는 이름은 같은 글 안의 밑줄 친 이름이다.
class DetailLine extends StatefulWidget {
  const DetailLine(this.bits, {super.key, this.style = DetailLineStyle.aka});
  final List<DetailBit> bits;
  final DetailLineStyle style;

  /// 이 줄의 글 — 격리 문자까지(그려지는 글 그대로).
  String get text => bits.map((b) => b.shown).join();

  @override
  State<DetailLine> createState() => _DetailLineState();
}

class _DetailLineState extends State<DetailLine> {
  /// 누르는 이름마다 하나 — 다시 그릴 때는 차례대로 다시 쓰고, 창이 닫힐 때 놓는다.
  final _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _tap(int i, VoidCallback onTap) {
    while (_taps.length <= i) {
      _taps.add(TapGestureRecognizer());
    }
    return _taps[i]..onTap = onTap;
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.style == DetailLineStyle.note;
    final base = note ? const TextStyle(fontSize: 13, height: 1.5, color: Ui.text2) : const TextStyle(fontSize: 12, height: 1.5, color: Ui.text3);
    // `<small>`: `.people-note small`은 12px · `--text-3`, 그 밖은 브라우저 기본(글자 크기의 1/1.2).
    final small = note ? const TextStyle(fontSize: 12, color: Ui.text3) : const TextStyle(fontSize: 10);
    var taps = 0;
    final spans = <InlineSpan>[];
    for (final b in widget.bits) {
      switch (b.kind) {
        case DetailBitKind.plain:
          spans.add(TextSpan(text: b.text));
        case DetailBitKind.small:
          spans.add(TextSpan(text: b.text, style: small));
        case DetailBitKind.bold:
          spans.add(TextSpan(text: b.text, style: const TextStyle(fontWeight: FontWeight.w700)));
        case DetailBitKind.italic:
          spans.add(TextSpan(text: b.text, style: const TextStyle(fontStyle: FontStyle.italic)));
        case DetailBitKind.name:
          spans.add(TextSpan(text: detailIsolate(b.text), locale: detailLocaleOf(b.lang)));
        case DetailBitKind.link:
          if (b.onTap == null) {
            spans.add(TextSpan(text: b.text));
          } else {
            spans.add(
              TextSpan(
                text: b.text,
                style: const TextStyle(color: Ui.accent, decoration: TextDecoration.underline, decorationColor: Ui.accent),
                recognizer: _tap(taps++, b.onTap!),
                mouseCursor: SystemMouseCursors.click,
                semanticsLabel: b.text,
              ),
            );
          }
      }
    }
    return Padding(
      padding: EdgeInsets.only(bottom: note ? 10 : 8),
      child: Text.rich(TextSpan(children: spans), style: base),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  3. 원어 줄 — 웹 `namesHTML(list, lead)`
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 이름 하나 — `<bdi lang>글</bdi>` + 꼬리표가 있으면 ` <small>(꼬리표)</small>`.
List<DetailBit> detailNameBits(Map<String, dynamic> n) {
  final tag = _s(n, 'tag');
  final lang = _s(n, 'lang');
  return [
    DetailBit.name(_s(n, 'text'), lang: lang.isEmpty ? null : lang),
    if (tag.isNotEmpty) ...[const DetailBit(' '), DetailBit.small('($tag)')],
  ];
}

/// 원어 줄(`x_names` = `{main:[{text, lang?, tag}], other:[…]}`).
/// 한 줄은 `main`(원어 · 로마자 · 종류 없는 이름), 다음 줄은 `그 밖의 이름: …`(한자음 · 옛 이름 · 약칭 …).
/// [lead]는 첫 줄 앞에 붙는 말(`성 솔 — ` · `지명 푸른 벼랑 — `) — `main`이 없으면 둘째 줄 앞에 붙는다.
class DetailNamesLine extends StatelessWidget {
  const DetailNamesLine(this.xNames, {super.key, this.lead = const []});
  final Object? xNames;
  final List<DetailBit> lead;

  List<Map<String, dynamic>> _of(String key) => [
    for (final n in _maps(_map(xNames)?[key]))
      if (_s(n, 'text').isNotEmpty) n,
  ];

  /// 서는 줄들(없으면 빈 목록).
  List<List<DetailBit>> get lines {
    final main = _of('main'), other = _of('other');
    return [
      if (main.isNotEmpty) [...lead, ...detailJoin(main.map(detailNameBits))],
      if (other.isNotEmpty) [if (main.isEmpty) ...lead, const DetailBit('그 밖의 이름: '), ...detailJoin(other.map(detailNameBits))],
    ];
  }

  bool get isEmpty => lines.isEmpty;

  @override
  Widget build(BuildContext context) {
    final all = lines;
    if (all.isEmpty) return const SizedBox.shrink();
    if (all.length == 1) return DetailLine(all.first);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [for (final l in all) DetailLine(l)]);
  }
}

/// 원어 줄을 몸통에 넣을 때 — 이름이 없으면 위젯을 아예 넣지 않는다(명세 2-3: 비어 있으면 그 묶음은 없다).
List<Widget> detailNamesLines(Object? xNames, {List<DetailBit> lead = const []}) {
  final w = DetailNamesLine(xNames, lead: lead);
  return w.isEmpty ? const [] : [w];
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  4. 사람 고리 · 혈연 줄 — 웹 `personLink(n, here)` · `kinLinesHTML(n, here)`
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 사람 고리 하나(`{name, uid?, ref?, polity?, missing?:1, unknown?:1}`).
/// - 칸(`uid` = 정권 · `ref`): 지금 보는 나라([here])의 칸이면 이름만, 다른 나라면 `나라 이름 지도자 이름` — 누르면 그 칸 창.
/// - 인물(`uid`만): 이름 — 누르면 인물 창.
/// - `unknown`: `미상`. 못 찾은 이름은 글만, `missing`이면 ` (찾지 못한 이름)`을 작게.
class DetailPersonRing extends StatelessWidget {
  const DetailPersonRing(this.ring, {super.key, required this.open, this.here, this.lead = const []});
  final Map<String, dynamic>? ring;
  final DetailOpen open;
  final String? here;

  /// 고리 앞에 붙는 말(`사람: ` 따위).
  final List<DetailBit> lead;

  /// 고리 하나의 조각.
  static List<DetailBit> bitsOf(Map<String, dynamic>? ring, {required DetailOpen open, String? here}) {
    if (ring == null) return const [];
    if (_on(ring, 'unknown')) return const [DetailBit('미상')];
    final name = _s(ring, 'name'), uid = _s(ring, 'uid'), ref = _s(ring, 'ref');
    if (uid.isNotEmpty && ref.isNotEmpty) {
      final polity = _s(ring, 'polity');
      final text = uid == here || polity.isEmpty ? name : '$polity $name';
      return [DetailBit.link(text, () => open(uid, cell: ref))];
    }
    if (uid.isNotEmpty) return [DetailBit.link(name, () => open(uid, kind: 'figure'))];
    return [
      DetailBit(name),
      if (_on(ring, 'missing')) ...[const DetailBit(' '), const DetailBit.small('(찾지 못한 이름)')],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bits = bitsOf(ring, open: open, here: here);
    if (bits.isEmpty) return const SizedBox.shrink();
    return DetailLine([...lead, ...bits]);
  }
}

/// 혈연 줄 — `부모 · 조상: …` / `배우자: …` / `자식 · 후손: …`(있는 것만, 이 차례).
/// [person]은 `x_persons["leader:3"]` · `x_person`처럼 `parents` · `spouses` · `children`을 가진 표다.
/// 혈연 줄 하나는 사람 고리 + `as`(관계 글 — 부모 줄은 이름 앞에, 자식 줄은 이름 뒤에 작게) ·
/// `certainty`(작게) · `note`(작게) · 배우자 줄의 `when`(함께한 기간 — 작게).
List<Widget> detailKinLines(Object? person, {required DetailOpen open, String? here}) {
  final p = _map(person);
  if (p == null) return const [];
  List<DetailBit> ring(Map<String, dynamic> e) => DetailPersonRing.bitsOf(e, open: open, here: here);
  List<DetailBit> small(String text) => text.isEmpty ? const [] : [const DetailBit(' '), DetailBit.small(text)];

  final parents = [
    for (final e in _maps(p['parents']))
      [
        DetailBit('${_s(e, 'as').isEmpty ? '부모' : _s(e, 'as')} '),
        ...ring(e),
        ...small(_certaintyNames[_s(e, 'certainty')] ?? _s(e, 'certainty')),
        ...small(_s(e, 'note')),
      ],
  ];
  final spouses = [
    for (final e in _maps(p['spouses'])) [...ring(e), ...small(_s(e, 'when'))],
  ];
  final kids = [
    for (final e in _maps(p['children'])) [...ring(e), ...small(_s(e, 'as'))],
  ];
  return [
    if (parents.isNotEmpty) DetailLine([const DetailBit('부모 · 조상: '), ...detailJoin(parents)]),
    if (spouses.isNotEmpty) DetailLine([const DetailBit('배우자: '), ...detailJoin(spouses)]),
    if (kids.isNotEmpty) DetailLine([const DetailBit('자식 · 후손: '), ...detailJoin(kids)]),
  ];
}

/// 사람 자리가 속한 단체 한 줄(웹 `personGroupsHTML` — 형식 3 잇기 a: 단체의 구성원으로 적힌 곳) —
/// `속한 단체: 〈단체〉 · …`(누르면 단체 창). [person]은 혈연 줄과 같은 표이고 그 `groups` = `[{uid, name}]`이다.
/// 지도자 칸 창은 혈연 줄 다음, 인물 창은 혈연 줄 다음에 둔다.
List<Widget> detailPersonGroupsLines(Object? person, {required DetailOpen open}) {
  final list = [
    for (final g in _maps(_map(person)?['groups']))
      if (_s(g, 'name').isNotEmpty) g,
  ];
  if (list.isEmpty) return const [];
  return [
    DetailLine([
      const DetailBit('속한 단체: '),
      ...detailJoin([
        for (final g in list)
          [DetailBit.link(_s(g, 'name'), _s(g, 'uid').isEmpty ? null : () => open(_s(g, 'uid'), kind: 'group'))],
      ]),
    ]),
  ];
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  5. 지명 줄 — 웹 `placeHTML(ref, lead)`
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 지명 줄(`{name, uid?, up?:[위 구역 이름…], names?: 이름 줄}` — `up`의 맨 앞이 바로 위 구역).
/// [lead]는 사건이면 `장소`, 도읍 칸이면 `지명`.
/// - 원어가 있으면 원어 줄 꼴로 `〈lead〉 〈이름〉 (위 구역에 속함) — 원어 · …`.
/// - 원어가 없으면 위 구역이 있거나 `장소`일 때만 `〈lead〉 〈이름〉 (위 구역에 속함)` 한 줄.
class DetailPlaceLine extends StatelessWidget {
  const DetailPlaceLine(this.place, {super.key, required this.lead});
  final Object? place;
  final String lead;

  /// 바로 위 구역의 이름(없으면 빈 글).
  static String upOf(Map<String, dynamic> p) {
    final up = p['up'];
    if (up is String) return up;
    if (up is List && up.isNotEmpty) {
      final first = up.first;
      if (first is String) return first;
      if (first is Map) return '${first['name'] ?? ''}';
    }
    return '';
  }

  List<Widget> get lines {
    final p = _map(place);
    if (p == null || _s(p, 'name').isEmpty) return const [];
    final up = upOf(p);
    final head = [
      DetailBit('$lead ${_s(p, 'name')}'),
      if (up.isNotEmpty) ...[const DetailBit(' '), DetailBit.small('$up에 속함')],
    ];
    final names = DetailNamesLine(p['names'], lead: [...head, const DetailBit(' — ')]);
    if (!names.isEmpty) return [names];
    return up.isNotEmpty || lead != '지명' ? [DetailLine(head)] : const [];
  }

  @override
  Widget build(BuildContext context) {
    final all = lines;
    if (all.isEmpty) return const SizedBox.shrink();
    return all.single;
  }
}

/// 지명 줄을 몸통에 넣을 때(없으면 빈 목록).
List<Widget> detailPlaceLines(Object? place, {required String lead}) => DetailPlaceLine(place, lead: lead).lines;

// ────────────────────────────────────────────────────────────────────────────────────────────
//  6. 법 양식 · 선거 표 — 웹 `lensBottomHTML`
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 법 양식(`x_law` = `{name, act?, actName?, articles?:[{no?,title?,text?} 또는 글], note?}`).
/// 머리 `법 (제정 · 조항 n개)` → 법 이름 → 조항(한 줄씩) → 메모.
class DetailLawBlock extends StatelessWidget {
  const DetailLawBlock(this.law, {super.key});
  final Object? law;

  /// 조항 하나의 글 — 글이면 그대로, 표면 `no · title · text`를 띄어 이은 것(지금 연표 `HT.readLaw`).
  static String articleText(Object? a) {
    if (a is String) return a.trim();
    if (a is num) return '$a';
    final m = _map(a);
    if (m == null) return '';
    return [_s(m, 'no'), _s(m, 'title'), _s(m, 'text')].map((s) => s.trim()).where((s) => s.isNotEmpty).join(' ');
  }

  /// 고침 종류의 이름(없으면 빈 글).
  static String actOf(Map<String, dynamic> law) {
    final name = _s(law, 'actName');
    if (name.isNotEmpty) return name;
    final act = _s(law, 'act');
    return _lawActNames[act] ?? act;
  }

  @override
  Widget build(BuildContext context) {
    final l = _map(law);
    if (l == null || l.isEmpty) return const SizedBox.shrink();
    final act = actOf(l);
    final articles = [
      for (final a in (l['articles'] is List ? l['articles'] as List : const []))
        if (articleText(a).isNotEmpty) articleText(a),
    ];
    return DetailBox(
      title: '법',
      small: '${act.isNotEmpty ? act : '제정 · 개정 · 폐지를 적지 않음'}${articles.isNotEmpty ? ' · 조항 ${articles.length}개' : ''}',
      children: [
        if (_s(l, 'name').isNotEmpty) DetailLine([DetailBit(_s(l, 'name'))]),
        if (articles.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < articles.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(articles[i], style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text)),
                  ),
                ),
            ],
          ),
        if (_s(l, 'note').isNotEmpty) DetailDesc(_s(l, 'note'), small: true),
      ],
    );
  }
}

/// 수 글 — 세 자리마다 쉼표(지금 연표 `Number(n).toLocaleString('ko-KR')`, 소수는 셋째 자리까지).
String detailNumberText(Object? n) {
  if (n is! num) return n is String ? n : '';
  final neg = n < 0;
  final abs = n.abs();
  final fixed = abs == abs.roundToDouble() ? abs.round().toString() : abs.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  final dot = fixed.indexOf('.');
  final whole = dot < 0 ? fixed : fixed.substring(0, dot);
  final frac = dot < 0 ? '' : fixed.substring(dot);
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${neg ? '-' : ''}$grouped$frac';
}

/// 선거 표(`x_election` = `{office?, results:[{who: 사람 고리 또는 글, votes?, seats?, won?:1}], note?}`).
/// 열 차례: `누구` → `득표`(한 줄이라도 있으면) → `의석`(한 줄이라도 있으면) → 당선 표시. 당선 줄은 굵게.
class DetailElectionTable extends StatelessWidget {
  const DetailElectionTable(this.election, {super.key});
  final Object? election;

  /// 누구의 글 — 사람 고리면 그 이름(웹은 적힌 이름을 글로만 둔다).
  static String whoOf(Object? who) {
    if (who is String) return who;
    final m = _map(who);
    return m == null ? (who == null ? '' : '$who') : _s(m, 'name');
  }

  /// 표의 머리 칸 — 검사가 열 차례를 본다.
  static List<String> headsOf(List<Map<String, dynamic>> rows) => [
    '누구',
    if (rows.any((r) => r['votes'] != null)) '득표',
    if (rows.any((r) => r['seats'] != null)) '의석',
    '',
  ];

  @override
  Widget build(BuildContext context) {
    final e = _map(election);
    if (e == null || e.isEmpty) return const SizedBox.shrink();
    final rows = _maps(e['results']);
    final votes = rows.any((r) => r['votes'] != null), seats = rows.any((r) => r['seats'] != null);
    const th = TextStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w500, color: Ui.text3);
    const figures = [FontFeature.tabularFigures()];
    Widget head(String t, {bool right = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(t, style: th, textAlign: right ? TextAlign.right : TextAlign.left),
    );
    Widget cell(String t, {bool right = false, bool won = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(
        t,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: TextStyle(fontSize: 13, height: 1.5, color: Ui.text, fontWeight: won ? FontWeight.w600 : FontWeight.w400, fontFeatures: right ? figures : null),
      ),
    );
    final cols = 2 + (votes ? 1 : 0) + (seats ? 1 : 0);
    return DetailBox(
      title: '선거',
      small: _s(e, 'office').isEmpty ? null : _s(e, 'office'),
      children: [
        if (rows.isNotEmpty)
          Table(
            columnWidths: {0: const FlexColumnWidth(), for (int i = 1; i < cols; i++) i: const IntrinsicColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: [
              TableRow(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Ui.line))),
                children: [head('누구'), if (votes) head('득표', right: true), if (seats) head('의석', right: true), head('')],
              ),
              for (final r in rows)
                TableRow(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Ui.line.withValues(alpha: Ui.line.a * .6)))),
                  children: [
                    cell(whoOf(r['who']), won: _on(r, 'won')),
                    if (votes) cell(detailNumberText(r['votes']), right: true, won: _on(r, 'won')),
                    if (seats) cell(detailNumberText(r['seats']), right: true, won: _on(r, 'won')),
                    cell(_on(r, 'won') ? '당선' : '', won: _on(r, 'won')),
                  ],
                ),
            ],
          ),
        if (_s(e, 'note').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: DetailDesc(_s(e, 'note'), small: true)),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  7. 단체 · 제도 · 나라 칩 — 웹 `.chip`(앞의 9px 색 점) · `groupChipHTML` · `polityChipHTML`
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 색 점 칩 — 높이 28 · 둥근 999 · 12.5px/500 · 앞의 9px 점이 그 항목의 색(`--c`).
/// [small]은 이름 뒤의 작은 글(`<small>` — 단체 종류 · 갈래). [onTap]이 없으면 찾지 못한 이름의 칩(`is-off` — 옅은 글).
class DetailDotChip extends StatefulWidget {
  const DetailDotChip(this.text, {super.key, this.small, this.color, this.onTap});
  final String text;
  final String? small;
  final Color? color;
  final VoidCallback? onTap;

  /// 칩의 글(검사 · 웹 대조) — 웹의 `이름 작은 글`.
  String get label => small == null || small!.isEmpty ? text : '$text $small';

  @override
  State<DetailDotChip> createState() => _DetailDotChipState();
}

class _DetailDotChipState extends State<DetailDotChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    final ink = on ? Ui.text : Ui.text3;
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Ui.ease,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: on && _hover ? Color.alphaBlend(Ui.accentSoft, Ui.surface2) : Ui.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: on ? (widget.color ?? Ui.text3) : Ui.text3, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(
                text: widget.text,
                children: [
                  if (widget.small != null && widget.small!.isNotEmpty) ...[
                    const TextSpan(text: ' '),
                    // `<small>` — 칩 글자(12.5px)의 1/1.2.
                    TextSpan(text: widget.small, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w400)),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w500, color: ink),
            ),
          ),
        ],
      ),
    );
    if (!on) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(button: true, label: widget.label, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: body)),
    );
  }
}

/// 단체 칩 — 누르면 단체 창. `uid`가 없으면 찾지 못한 단체(누를 수 없음). [small]은 이름 뒤의 작은 글.
DetailDotChip detailGroupChip(Map<String, dynamic> g, DetailOpen open, {String? small}) {
  final uid = _s(g, 'uid');
  return DetailDotChip(
    _s(g, 'name'),
    small: small,
    color: detailColor(g['color']),
    onTap: uid.isEmpty ? null : () => open(uid, kind: 'group'),
  );
}

/// 나라 칩 — 누르면 그 나라. `uid`가 없으면 연표에서 찾지 못한 나라(누를 수 없음).
DetailDotChip detailPolityChip(Map<String, dynamic> r, DetailOpen open) {
  final uid = _s(r, 'uid');
  return DetailDotChip(_s(r, 'name'), color: detailColor(r['color']), onTap: uid.isEmpty ? null : () => open(uid));
}

/// 제도 칩 — `주제 이름` + 갈래(작게). 누르면 제도 창.
DetailDotChip detailInstitutionChip(Map<String, dynamic> i, DetailOpen open) {
  final uid = _s(i, 'uid');
  final family = _s(i, 'family');
  final theme = _s(i, 'themeName');
  return DetailDotChip(
    theme.isNotEmpty ? theme : _s(i, 'name'),
    small: family.isEmpty ? null : family,
    color: detailColor(i['color']),
    onTap: uid.isEmpty ? null : () => open(uid, kind: 'institution'),
  );
}

/// 칩이 섞인 `.people-note` 한 줄(`있던 나라 [칩] 작은 글 [칩] …` · `나라 [칩] · 갈래 …`).
/// [children]은 칩과 [DetailChipLine.small]을 차례대로 둔다.
class DetailChipLine extends StatelessWidget {
  const DetailChipLine({super.key, required this.label, required this.children});
  final String label;
  final List<Widget> children;

  /// 줄 안의 작은 글(`.people-note small` — 12px · `--text-3`).
  static Widget small(String text) => Text(text, style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text3));

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [Text(label, style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text2)), ...children],
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  8. 있던 창에 넣는 묶음 — 사건 딱지 · 사건 아래 묶음 · 나라의 칩 묶음
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 사건 머리의 딱지(웹 `lensBadgesHTML`): 주제(본문 `themeRefs` — `{ref,id,name,color,auto}`) → `법 · 제정` → `선거 · 뽑은 자리`.
/// 법 · 선거 딱지는 조약 딱지와 같은 마름모(법률 · 선거제도 주제 색 — 설계 D5 결정 7 A). 조약 배지 다음에 둔다.
List<Widget> detailLensBadges(Map<String, dynamic> json) {
  final law = _map(json['x_law']), election = _map(json['x_election']);
  final act = law == null ? '' : DetailLawBlock.actOf(law);
  final office = _s(election, 'office');
  return [
    for (final t in _maps(json['themeRefs']))
      if (_s(t, 'name').isNotEmpty) DetailBadge(_s(t, 'name'), color: detailColor(t['color'])),
    if (law != null && law.isNotEmpty) DetailBadge('법${act.isNotEmpty ? ' · $act' : ''}', diamond: true, color: detailLawColor),
    if (election != null) DetailBadge('선거${office.isNotEmpty ? ' · $office' : ''}', diamond: true, color: detailVoteColor),
  ];
}

/// `이 일로 맺은 단체` 묶음(`x_groups` = `[{uid,name,color,typeName}]`) — 칩 뒤의 작은 글은 단체 종류.
List<Widget> detailEventGroupsBox(Map<String, dynamic> json, DetailOpen open) {
  final list = _maps(json['x_groups']);
  if (list.isEmpty) return const [];
  return [
    DetailBox(
      title: '이 일로 맺은 단체',
      children: [
        DetailChipRow([for (final g in list) detailGroupChip(g, open, small: _s(g, 'typeName'))], top: 0),
      ],
    ),
  ];
}

/// 사건 아래의 묶음(웹 `lensBottomHTML`) — 조항 → 관련(그때의 법률 · 앞 고침) → 관련(그때의 선거 방식 · 앞 · 다음 선거) → 이 일로 맺은 단체.
/// 조약 아래 묶음 다음에 둔다. [topsPlaced]가 거짓이면(기본 상세가 [detailLensAka] · [detailLawTop] · [detailElectionTop]을 제자리에 아직 부르지 않음)
/// 법 이름 · 법의 내력 · 결과를 이 묶음 맨 앞에 둔다. 법의 내력 · 의석 막대를 미리 풀지 않은 옛 저장소면 앞 판의 법 양식 · 선거 표.
List<Widget> detailLensBottom(Map<String, dynamic> json, DetailOpen open, {bool topsPlaced = false}) {
  final law = _map(json['x_law']), election = _map(json['x_election']);
  final hasLaw = law != null && law.isNotEmpty, hasVote = election != null && election.isNotEmpty;
  final lawNew = hasLaw && _lawFresh(json), voteNew = election != null && _voteFresh(json);
  return [
    if (!topsPlaced && (lawNew || voteNew)) ...detailLensAka(json),
    if (!topsPlaced && lawNew) ...detailLawTop(json, open),
    if (!topsPlaced && voteNew) ...detailElectionTop(json, open),
    if (hasLaw) lawNew ? DetailLawArticles(json) : DetailLawBlock(law),
    if (lawNew) ...detailLensRelated(json['x_lawRelated'], open),
    if (hasVote && !voteNew) DetailElectionTable(election),
    if (voteNew) ...detailLensRelated(json['x_voteRelated'], open),
    ...detailEventGroupsBox(json, open),
  ];
}

/// 나라의 `단체` · `제도` 칩 묶음(웹 `periodLensHTML`).
/// - `x_groupLinks` = `[{uid,name,color,role:'within'|'member',typeName?}]` — 작은 글은 구성 나라로 든 연합이면
///   `구성 나라로`, 아니면 단체 종류(`small`을 글로 실었으면 그 글).
/// - `x_institutions` = `[{uid,name,theme,themeName,family?,color,title?}]` — 주제 차례.
List<Widget> detailPolityLensBoxes(Map<String, dynamic> json, DetailOpen open) {
  final links = _maps(json['x_groupLinks']);
  final insts = _maps(json['x_institutions']);
  String linkSmall(Map<String, dynamic> l) {
    final small = l['small'];
    if (small is String && small.isNotEmpty) return small;
    return _s(l, 'role') == 'member' ? '구성 나라로' : _s(l, 'typeName');
  }

  return [
    if (links.isNotEmpty)
      DetailBox(
        title: '단체',
        small: '${links.length}',
        // 단체 계보 창을 여는 단추(설계 D5 결정 4 A — 웹 periodLensHTML의 `.sub-act`). 이 나라의 나무(x_groupTree)가 있고 계보 창이 붙어 있을 때만 선다.
        action: json['x_groupTree'] is Map && GroupTreeLayer.anyMounted ? GroupTreeButton(uid: _s(json, 'uid')) : null,
        children: [
          DetailChipRow([for (final l in links) detailGroupChip(l, open, small: linkSmall(l))], top: 0),
        ],
      ),
    if (insts.isNotEmpty)
      DetailBox(
        title: '제도',
        small: '${insts.length}',
        children: [
          DetailChipRow([for (final i in insts) detailInstitutionChip(i, open)], top: 0),
        ],
      ),
  ];
}

/// `확인할 것` 묶음(웹 `lensWarnHTML` — 노란 상자 · 글머리 목록).
List<Widget> detailWarnBox(Object? warnings) {
  final list = [
    if (warnings is List)
      for (final w in warnings)
        if (w != null && '$w'.isNotEmpty) '$w',
  ];
  if (list.isEmpty) return const [];
  return [
    DetailBox(
      title: '확인할 것',
      small: '${list.length}',
      warn: true,
      children: [
        for (final w in list)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  ', style: TextStyle(fontSize: 12.5, height: 1.5, color: Ui.text2)),
                Expanded(child: Text(w, style: const TextStyle(fontSize: 12.5, height: 1.5, color: Ui.text2))),
              ],
            ),
          ),
      ],
    ),
  ];
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  9. 법의 내력 · 선거 결과(의석 막대) · 조항 · 관련 — 설계 D5 결정 7 A '조약문 양식 빌림'
//     (docs/설계-10건/7-8-단체와-렌즈.md 9-2 · 웹 js/viewer.js lensAkaHTML · lawTopHTML · electionTopHTML · lensBottomHTML · css/viewer.css 끝 절)
//
//  내보내기(prototype/scripts/export/entities.mjs groupWindowRefs)가 미리 푼 값만 읽는다:
//    x_lawHistory { n, orig?, rows:[{word, when, here?, at?(분), uid?, title?, note?, gap?}] } — 법의 내력(같은 나라 · 같은 법 이름)
//    x_lawArts [{no?, title?, text}] — 조항(머리 번호를 뗀 것) · x_lawRelated · x_voteRelated [{tag, uid, text, when?}] — 관련
//    x_vote { by:'seats'|'votes'|'', total, cap?, linked?, rows:[{who, color, uid?, votes?, seats?, won?, part?}] } — 결과
//  이 값이 없는 옛 저장소에서는 앞 판의 [DetailLawBlock] · [DetailElectionTable]이 그대로 선다.
//
//  웹의 자리: 법 이름 · 뽑은 자리 = 제목 바로 아래 한 줄([detailLensAka]) · 법의 내력 = 기본 기간 줄 자리([detailLawTop]) ·
//  결과 = 설명 바로 위([detailElectionTop]) · 조항 · 관련 · 이 일로 맺은 단체 = 아래([detailLensBottom]).
//  기본 상세(detail_item.dart)가 앞의 셋을 제자리에 부르면 `detailLensBottom(…, topsPlaced: true)`로 아래 몫만 받는다.
//  셋을 아직 부르지 않으면(topsPlaced: false — 지금) 법의 내력 · 결과도 아래 묶음 맨 앞에 선다(빠지는 것 없이).
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 법 · 선거 딱지의 색(웹 css `.badge.is-law` · `.badge.is-vote`) — 법률 · 선거제도 주제의 색.
const detailLawColor = Color(0xffbba395), detailVoteColor = Color(0xffa0bcc5);

/// css `--paper-ink`(글자의 먹) — 의석 막대 · 모임 네모의 테두리를 이 색과 섞는다. HistoryArchive 통일(B안) 뒤로 검은 잉크(`Ui.ink`의 값 — 전에는 옛 먹 #1b1a19).
const _paperInk = 0xff000000;

/// 두 색 섞기(css `color-mix(in srgb, a t, b)`).
Color _mixS(Color a, Color b, double t) => Color(mixSrgb(a.toARGB32(), b.toARGB32(), t));

/// css `color-mix(in oklab, c t, var(--paper-ink))`.
Color _inkO(Color c, double t) => Color(mixOklab(c.toARGB32(), _paperInk, t));

/// 법 이름 · 선거의 뽑은 자리 — 제목 바로 아래 `.aka` 한 줄씩(웹 lensAkaHTML).
List<Widget> detailLensAka(Map<String, dynamic> json) {
  final law = _map(json['x_law']), election = _map(json['x_election']);
  return [
    if (_s(law, 'name').isNotEmpty) DetailAka('법 이름 ${_s(law, 'name')}'),
    if (_s(election, 'office').isNotEmpty) DetailAka('뽑은 자리 ${_s(election, 'office')}'),
  ];
}

/// 법의 내력 — 기본 기간 줄 자리(웹 lawTopHTML). 내력이 없으면(법 이름이 없는 법 · 조약 · 법이 아닌 사건) 빈 목록 — 부르는 쪽이 기간 줄을 둔다.
List<Widget> detailLawTop(Map<String, dynamic> json, DetailOpen open) => _map(json['x_lawHistory']) == null ? const [] : [DetailLawHistory(json, open: open)];

/// 선거 결과 — 설명 바로 위(웹 electionTopHTML). `x_vote`가 없는 옛 저장소면 빈 목록(아래 묶음의 옛 선거 표가 선다).
/// 결과를 적지 않은 선거는 메모가 있을 때만 `결과 (적지 않음)` 상자.
List<Widget> detailElectionTop(Map<String, dynamic> json, DetailOpen open) {
  final vote = _map(json['x_vote']);
  if (vote == null) return const [];
  final note = _s(_map(json['x_election']), 'note');
  if (_maps(vote['rows']).isEmpty) {
    return note.isEmpty ? const [] : [DetailBox(title: '결과', small: '적지 않음', children: [DetailDesc(note, small: true)])];
  }
  return [DetailVoteBox(vote, note: note, open: open)];
}

/// 이 사건의 법 · 선거를 새 내보내기(법의 내력 · 의석 막대를 미리 푼 판)가 실었는가 — 아니면 앞 판의 법 양식 · 선거 표를 둔다.
bool _lawFresh(Map<String, dynamic> json) => json.containsKey('x_lawHistory') || json.containsKey('x_lawArts') || json.containsKey('x_lawRelated');
bool _voteFresh(Map<String, dynamic> json) => json.containsKey('x_vote');

/// 법의 내력 표 — 조약 날짜 진행 표(`.tr-steps`) 꼴: 줄마다 `[고침 종류][날짜 · 이 사건/사건 이름/뜻][사이 간격]`.
/// 이 사건 줄은 강조 테두리 + `이 사건`(날까지 적었으면 음력 · 일진 · 요일 · 원문 표기를 곁들임) · 누르면 그때로,
/// 다른 사건 줄은 누르면 그 사건 창, `폐지 — 기록 없음` 줄은 누를 수 없다.
class DetailLawHistory extends StatelessWidget {
  const DetailLawHistory(this.json, {super.key, required this.open});
  final Map<String, dynamic> json;
  final DetailOpen open;

  Map<String, dynamic> get _h => _map(json['x_lawHistory']) ?? const {};

  /// 이 사건 줄의 곁들임 — 날까지 적었으면 그날(웹 dayNote), 원문 표기가 다르면 `원문 표기 …`.
  String get sub {
    final start = json['start'] is num ? (json['start'] as num).toDouble() : null;
    final startAt = _s(json, 'startAt');
    final unknown = json['startUnknown'] == true;
    final prec = unknown || start == null ? DatePrec.year : (atFits(startAt, start) ? precOfAt(startAt) : DatePrec.year);
    final fine = prec == DatePrec.day || prec == DatePrec.hour || prec == DatePrec.minute;
    return [
      if (fine) dayNote(start!, lunar: AuxCalendarStore.shared?.lunar, withLunar: !isLunarAt(startAt)),
      if (_s(_h, 'orig').isNotEmpty) '원문 표기 ${_s(_h, 'orig')}',
    ].join(' · ');
  }

  /// 줄마다의 글(검사 · 웹 대조) — 웹 textContent 그대로(`제정760년 이 사건` · `개정830년 새 법을 고침70년 뒤`).
  List<String> get rowTexts => [
    for (final r in _maps(_h['rows']))
      '${_s(r, 'word')}${_s(r, 'when')}${_on(r, 'here') ? ' 이 사건' : _s(r, 'title').isNotEmpty ? ' ${_s(r, 'title')}' : _s(r, 'note').isNotEmpty ? ' ${_s(r, 'note')}' : ''}${_s(r, 'gap')}',
  ];

  @override
  Widget build(BuildContext context) {
    final rows = _maps(_h['rows']);
    final n = (_h['n'] is num) ? (_h['n'] as num).toInt() : rows.where((r) => _s(r, 'word') != '폐지' || _s(r, 'when') != '기록 없음').length;
    final hereSub = sub;
    return DetailBox(
      title: '법의 내력',
      small: n > 1 ? '$n' : null,
      children: [
        for (int i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
            child: _LawStep(rows[i], sub: _on(rows[i], 'here') ? hereSub : '', onTap: _tapOf(context, rows[i])),
          ),
      ],
    );
  }

  VoidCallback? _tapOf(BuildContext context, Map<String, dynamic> r) {
    final uid = _s(r, 'uid');
    if (!_on(r, 'here')) return uid.isEmpty ? null : () => open(uid);
    final at = r['at'];
    if (at is! num) return null;
    // 이 사건 줄 — 그때로(웹 data-year: 그해 한 해 · 도착 고리는 이 사건). 창을 띄운 뼈대(DetailHost)의 길로 간다.
    final host = context.findAncestorWidgetOfExactType<DetailHost>();
    if (host == null) return null;
    final lo = at.toDouble();
    return () => host.bus.goTo(lo, minutesOfT(tOfMinutes(lo) + 1), ring: _s(json, 'uid').isEmpty ? null : _s(json, 'uid'));
  }
}

/// 법의 내력 한 줄 — `.tr-steps` 의 button · .tr-step(패딩 4/6 · 둥근 6 · 틈 10).
class _LawStep extends StatelessWidget {
  const _LawStep(this.r, {required this.sub, this.onTap});
  final Map<String, dynamic> r;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final here = _on(r, 'here');
    final tail = here ? '이 사건' : (_s(r, 'title').isNotEmpty ? _s(r, 'title') : _s(r, 'note'));
    final gap = _s(r, 'gap');
    Widget row = DetailPressable(
      onTap: onTap,
      radius: 6,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      semantics: '${_s(r, 'word')} ${_s(r, 'when')}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          // `.tr-steps b` — 12px · `--text-3` · 굵게 · 30px부터.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 30),
            child: Text(_s(r, 'word'), style: const TextStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w700, color: Ui.text3)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    text: _s(r, 'when'),
                    children: [
                      // `span i` — 기울이지 않은 11.5px · `--text-3`(이 사건은 `--accent`).
                      if (tail.isNotEmpty) TextSpan(text: ' $tail', style: TextStyle(fontSize: 11.5, color: here ? Ui.accent : Ui.text3)),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text),
                ),
                if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 11.5, height: 1.5, color: Ui.text3)),
              ],
            ),
          ),
          if (gap.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(gap, style: const TextStyle(fontSize: 11, height: 1.5, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ],
      ),
    );
    if (here) {
      // `li.is-now` — 이 사건의 줄: 안쪽 1.5px 잉크 선(고른 것은 색이 아니라 잉크 선으로 — DLC 관리 창의 고른 카드와 같은 붓).
      row = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Ui.controlRadius),
          border: Border.all(color: Ui.ink, width: 1.5),
        ),
        child: row,
      );
    }
    return row;
  }
}

/// 선거 결과 — 의석 막대 하나 · 과반 글 · 결과 표(웹 electionTopHTML · `.el-box`).
/// 막대 조각 · 모임 이름이 단체를 가리키면(같은 이름의 단체) 누르면 단체 창.
class DetailVoteBox extends StatelessWidget {
  const DetailVoteBox(this.vote, {super.key, this.note = '', required this.open});
  final Map<String, dynamic> vote;
  final String note;
  final DetailOpen open;

  List<Map<String, dynamic>> get rows => _maps(vote['rows']);
  String get by => _s(vote, 'by');
  double get total => vote['total'] is num ? (vote['total'] as num).toDouble() : 0;

  /// 머리의 작은 글 — `의석 80` · `득표 30,190` · `3곳`(+ ` · 누르면 그 모임`).
  String get small =>
      '${by == 'seats' ? '의석 ${detailNumberText(vote['total'])}' : by == 'votes' ? '득표 ${detailNumberText(vote['total'])}' : '${rows.length}곳'}${_on(vote, 'linked') ? ' · 누르면 그 모임' : ''}';

  /// 막대의 조각(값이 있는 모임만 — 적은 차례).
  List<Map<String, dynamic>> get segments => [
    for (final r in rows)
      if (r[by] is num && (r[by] as num) > 0) r,
  ];

  @override
  Widget build(BuildContext context) {
    final votes = rows.any((r) => r['votes'] != null), seats = rows.any((r) => r['seats'] != null);
    return DetailBox(
      title: '결과',
      small: small,
      children: [
        if (total > 0 && segments.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: DetailSeatBar(segments, by: by, open: open)),
        if (_s(vote, 'cap').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Transform.translate(offset: const Offset(0, -2), child: Text(_s(vote, 'cap'), style: const TextStyle(fontSize: 11.5, height: 1.5, color: Ui.text3))),
          ),
        Padding(padding: const EdgeInsets.only(top: 2), child: _VoteTable(rows, votes: votes, seats: seats, open: open)),
        if (note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: DetailDesc(note, small: true)),
      ],
    );
  }
}

/// 의석 막대 — 높이 16 · 사이 2 · 조각마다 모임 색 70% 칠 + 그 색의 짙은 1px 테두리 · 둥근 4 · 가장 좁아도 3px(css `.el-bar` · `.el-seg`).
/// 폭은 css flex(값만큼 나눔 · 3px보다 좁은 조각은 3px로 묶고 나머지를 다시 나눔)와 같다.
class DetailSeatBar extends StatelessWidget {
  const DetailSeatBar(this.segments, {super.key, required this.by, required this.open});
  final List<Map<String, dynamic>> segments;
  final String by;
  final DetailOpen open;

  static const height = 16.0, gap = 2.0, least = 3.0;

  /// 조각의 폭 — 전체 폭 [width]에서 사이를 뺀 것을 값만큼(3px보다 좁은 조각은 3px).
  static List<double> widthsOf(List<double> values, double width) {
    final n = values.length;
    if (n == 0) return const [];
    final room = math.max(0.0, width - gap * (n - 1));
    final frozen = List<bool>.filled(n, false);
    final out = List<double>.filled(n, 0);
    for (var pass = 0; pass < n; pass++) {
      final sum = [for (int i = 0; i < n; i++) if (!frozen[i]) values[i]].fold(0.0, (a, b) => a + b);
      final left = room - least * frozen.where((f) => f).length;
      var changed = false;
      for (int i = 0; i < n; i++) {
        if (frozen[i]) continue;
        final w = sum <= 0 ? 0.0 : left * values[i] / sum;
        if (w < least) {
          frozen[i] = true;
          changed = true;
        }
      }
      if (!changed) {
        for (int i = 0; i < n; i++) {
          out[i] = frozen[i] ? least : (sum <= 0 ? 0.0 : left * values[i] / sum);
        }
        return out;
      }
    }
    return List<double>.filled(n, least);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final values = [for (final r in segments) (r[by] as num).toDouble()];
      final widths = widthsOf(values, box.maxWidth);
      return SizedBox(
        height: height,
        child: Row(
          children: [
            for (int i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              _SeatSegment(segments[i], width: widths[i], open: open),
            ],
          ],
        ),
      );
    },
  );
}

class _SeatSegment extends StatefulWidget {
  const _SeatSegment(this.r, {required this.width, required this.open});
  final Map<String, dynamic> r;
  final double width;
  final DetailOpen open;

  @override
  State<_SeatSegment> createState() => _SeatSegmentState();
}

class _SeatSegmentState extends State<_SeatSegment> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = detailColor(widget.r['color']);
    final uid = _s(widget.r, 'uid');
    final fill = _mixS(c, Ui.surface, .70);
    Widget body = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Ui.ease,
      width: widget.width,
      height: DetailSeatBar.height,
      decoration: BoxDecoration(
        // 올리면 css `filter: brightness(.95)`.
        color: _hover ? Color.lerp(fill, const Color(0xff000000), .05) : fill,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _inkO(c, .75), width: 1),
      ),
    );
    final label = '${_s(widget.r, 'part')}${uid.isEmpty ? '' : ' — 단체 창'}';
    body = Tooltip(message: label, waitDuration: const Duration(milliseconds: 400), child: body);
    if (uid.isEmpty) return Semantics(label: label, child: body);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(button: true, label: label, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => widget.open(uid, kind: 'group'), child: body)),
    );
  }
}

/// 결과 표 — `누구`(모임 색 네모 · 이름 · `당선` 딱지) · `득표` · `의석`(있는 열만) · 당선 줄은 굵게(css `.el-table`).
class _VoteTable extends StatelessWidget {
  const _VoteTable(this.rows, {required this.votes, required this.seats, required this.open});
  final List<Map<String, dynamic>> rows;
  final bool votes, seats;
  final DetailOpen open;

  @override
  Widget build(BuildContext context) {
    const th = TextStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w500, color: Ui.text3);
    const figures = [FontFeature.tabularFigures()];
    Widget head(String t, {bool right = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(t, style: th, textAlign: right ? TextAlign.right : TextAlign.left),
    );
    Widget num(String t, bool won) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(t, textAlign: TextAlign.right, style: TextStyle(fontSize: 13, height: 1.5, color: Ui.text, fontWeight: won ? FontWeight.w600 : FontWeight.w400, fontFeatures: figures)),
    );
    final cols = 1 + (votes ? 1 : 0) + (seats ? 1 : 0);
    return Table(
      columnWidths: {0: const FlexColumnWidth(), for (int i = 1; i < cols; i++) i: const IntrinsicColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Ui.line))),
          children: [head('누구'), if (votes) head('득표', right: true), if (seats) head('의석', right: true)],
        ),
        for (final r in rows)
          TableRow(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Ui.line.withValues(alpha: Ui.line.a * .6)))),
            children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: _VoteWho(r, open: open)),
              if (votes) num(r['votes'] == null ? '—' : detailNumberText(r['votes']), _on(r, 'won')),
              if (seats) num(r['seats'] == null ? '—' : '${detailNumberText(r['seats'])}석', _on(r, 'won')),
            ],
          ),
      ],
    );
  }
}

/// `.el-who` — 모임 색 네모(10px · 둥근 3) · 이름(단체면 `.linky`) · `당선` 딱지.
class _VoteWho extends StatelessWidget {
  const _VoteWho(this.r, {required this.open});
  final Map<String, dynamic> r;
  final DetailOpen open;

  @override
  Widget build(BuildContext context) {
    final c = detailColor(r['color']);
    final won = _on(r, 'won');
    final uid = _s(r, 'uid');
    final who = DetailElectionTable.whoOf(r['who']);
    final style = TextStyle(fontSize: 13, height: 1.5, color: Ui.text, fontWeight: won ? FontWeight.w600 : FontWeight.w400);
    Widget name = Text(who, style: style);
    if (uid.isNotEmpty) {
      name = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          label: who,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => open(uid, kind: 'group'),
            child: Text(who, style: style.copyWith(color: Ui.accent, decoration: TextDecoration.underline, decorationColor: Ui.accent)),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 7,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: _mixS(c, Ui.surface, .70), borderRadius: BorderRadius.circular(3), border: Border.all(color: _inkO(c, .75), width: 1)),
        ),
        name,
        if (won)
          Container(
            // '당선' — 딱지 꼴(칠 없이 1px 선 · 둥근 4 · 굵은 잉크 글 — 상태는 색 없이 잉크와 굵기로).
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(Ui.innerRadius), border: Border.all(color: Ui.line)),
            child: const Text('당선', style: TextStyle(fontSize: 11, height: 1.5, fontWeight: FontWeight.w600, color: Ui.ink)),
          ),
      ],
    );
  }
}

/// 조항 — 이 사건에 적은 조항(머리 번호를 뗀 조약 조항 꼴 · 개정 · 폐지면 줄마다 그 딱지) + 법 메모(웹 lensBottomHTML의 `.tr-articles`).
class DetailLawArticles extends StatelessWidget {
  const DetailLawArticles(this.json, {super.key});
  final Map<String, dynamic> json;

  @override
  Widget build(BuildContext context) {
    final law = _map(json['x_law']) ?? const {};
    final arts = _maps(json['x_lawArts']);
    final act = _s(law, 'act');
    final tag = act == 'amend' || act == 'repeal' ? DetailLawBlock.actOf(law) : '';
    if (arts.isEmpty) {
      // 조항 없이 메모만 있거나 내력을 셀 수 없는 법(이름 없음) — `법 (고침 종류)` 상자. 이름이 있고 메모도 없으면 내력이 다 말하므로 없음.
      if (_s(law, 'note').isEmpty && _s(law, 'name').isNotEmpty) return const SizedBox.shrink();
      return DetailBox(
        title: '법',
        small: DetailLawBlock.actOf(law).isNotEmpty ? DetailLawBlock.actOf(law) : '제정 · 개정 · 폐지를 적지 않음',
        children: [if (_s(law, 'note').isNotEmpty) DetailDesc(_s(law, 'note'), small: true)],
      );
    }
    return DetailBox(
      title: '조항',
      small: '${arts.length}',
      children: [
        for (int i = 0; i < arts.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (_s(arts[i], 'no').isNotEmpty) ...[
                    Text(_s(arts[i], 'no'), style: const TextStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w700, color: Ui.text3)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      [if (_s(arts[i], 'title').isNotEmpty) '(${_s(arts[i], 'title')})', _s(arts[i], 'text')].where((s) => s.isNotEmpty).join(' '),
                      style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text),
                    ),
                  ),
                  if (tag.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      // 조항의 고침 딱지(제정 · 개정 · 폐지) — 알약이 아니라 딱지 꼴(둥근 4 · 1px 선).
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Ui.innerRadius),
                        border: Border.all(color: Ui.line),
                      ),
                      child: Text(tag, style: const TextStyle(fontSize: 10.5, height: 1.5, color: Ui.text2)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (_s(law, 'note').isNotEmpty) DetailDesc(_s(law, 'note'), small: true),
      ],
    );
  }
}

/// `관련` 상자 — 조약의 '관련'과 같은 줄(`[딱지][글][기간]` · 누르면 그 항목). 그때의 법률 · 앞 고침 / 그때의 선거 방식 · 앞 · 다음 선거.
List<Widget> detailLensRelated(Object? related, DetailOpen open) {
  final rows = _maps(related);
  if (rows.isEmpty) return const [];
  return [
    DetailBox(
      title: '관련',
      children: [
        DetailSuccList([
          for (final r in rows)
            DetailSuccRow(
              badge: _s(r, 'tag'),
              name: _s(r, 'text'),
              years: _s(r, 'when').isEmpty ? null : _s(r, 'when'),
              onTap: _s(r, 'uid').isEmpty
                  ? null
                  : () => open(_s(r, 'uid'), kind: _s(r, 'tag').startsWith('그때의') ? 'institution' : ''),
            ),
        ]),
      ],
    ),
  ];
}
