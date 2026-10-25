import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../shell/look.dart';
import 'app_bus.dart';
import '../scene/aux_calendar.dart' show AuxCalendarStore;
import 'date_text.dart';
import 'doc_window.dart' show DocChips;
import 'detail_echo.dart';
import 'detail_format3.dart';
import 'detail_shell.dart';
import 'metro_card.dart' show MetroRequest, metroSlot;
import 'names_display.dart';

// ════════════════════════════════════════════════════════════════════════════════════════════
//  기본 상세(사건 · 시대 · 기관 · 문화 · 왕조)와 조약 상세
//  — 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md` 2-3절의 ㈎ 와 ㈖.
//
//  묶음이 나오는 차례는 지금 연표의 `itemDetailHTML`(js/viewer.js:1881) 그대로이고,
//  **비어 있는 묶음은 아예 그리지 않는다.**
//
//  ── 쓰는 법 ───────────────────────────────────────────────────────────────────────────────
//    registerItemDetail();                 // 앱을 세울 때 한 번 — 갈래 'item'을 이 파일이 맡는다
//    …  DetailHost(bus: bus)               // 나머지는 뼈대가 한다
//
//  ── 이 창이 항목 기록에서 읽는 것(계약 6-9절 · 내보내기가 미리 풀어 둔 `x_…` 칸) ──────────────
//    x_parent · x_children · x_figures · x_partOf · x_scopes · x_hostedScopes · x_dynasties ·
//    x_ruled · x_rulers · x_succ · x_served · x_cellBounds · x_parties · x_related
//    (모두 이름 · uid · `when`(기간 글)까지 풀려 있어 창이 다른 항목을 다시 묻지 않아도 된다)
//
//  ── 앱 틀이 채워 주어야 하는 곳 ─────────────────────────────────────────────────────────────
//    bus.slot('tracks')     = {'mw-coast': {'name': '유리해안', 'color': 0xa0bcc5}, …}
//    bus.slot('categories') = {'war':      {'name': '전쟁',    'color': 0xd4a39b}, …}
//      → 둘 다 `{"op":"layout"}`의 답에 이미 있는 값이다(계약 2절). 비어 있으면 그 배지만 빠진다.
//    bus.slot('doc')        ← 이 창이 `📄 문서`를 누를 때 항목의 uid를 넣는다(문서 창은 이 묶음 밖).
//    bus.slot('metro')      ← `🚇 노선도`를 누를 때 정권의 uid를 넣는다(노선도 카드는 다른 몫).
//    bus.slot('echo')       ← '같은 시기를 타국에도' 스위치의 값(bool) — 왕조 창의 메아리 자리([EchoSlot])가 넣는다.
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 갈래 `item`(그 밖 전부 — 사건 · 시대 · 기관 · 문화 · 왕조 · 조약)을 이 파일이 맡는다.
void registerItemDetail() => DetailHost.register('item', ItemDetail.new);

// ── 이름 표(지금 연표의 js/core.js와 계약 6-1절) ─────────────────────────────────────────────

/// 연대의 확실성.
const certaintyNames = {'certain': '확실', 'accepted': '통설', 'estimated': '추정', 'legend': '전승'};

/// 실재성 — 나라가 '있었는가'(연대가 얼마나 확실한가와는 다른 축).
const historicityNames = {'attested': '실재', 'semi': '반전설', 'legendary': '전설', 'disputed': '실재 논쟁', 'refuted': '부정됨'};
const historicityHints = {
  'attested': '있었음이 기록과 유물로 인정되는 나라 (기본값)',
  'semi': '실재는 인정되나 기록이 전설에 기대는 나라',
  'legendary': '전승·신화에만 전하는 나라',
  'disputed': '있었는지를 두고 학계가 갈리는 나라',
  'refuted': '한때 인정되었으나 고고학·사료 비판으로 부정된 나라',
};

/// 정권의 종류(계약 6-1절의 종류 번호 차례 그대로).
const polityKindNames = {
  'state': '국가', 'tributary': '조공·책봉국', 'fief': '봉국·제후국', 'dominion': '자치령', 'warlord': '군벌·할거 세력',
  'vassal': '종속국', 'protectorate': '보호국', 'satellite': '위성국', 'puppet': '괴뢰국', 'mandate': '위임·신탁 통치령',
  'colony': '식민지·속령', 'occupied': '점령지·군정', 'federation': '연맹', 'org': '조직체', 'era': '시대 이름',
  'client': '복속 세력·부용', 'frontier': '기미·번부·토사', 'prefecture': '직할령·군현', // 묶음 3 · 3번(2026-09-22)
  'exile': '망명 정부', 'movement': '부흥·저항 세력', 'culture': '문화', 'overlay': '기관', 'dynasty': '왕조',
};

/// 종류의 짧은 이름(`HT.POLITY_KINDS`의 short) — 소속 · 다스린 나라 · 구성 정권 목록의 구분 칸에 쓴다(감독 건의 2026-10-16 "구분 칸은 최대한 좁게").
/// 긴 이름은 칸에 올리면 풍선으로 뜬다.
const polityKindShort = {
  'state': '국가', 'tributary': '조공', 'fief': '봉국', 'dominion': '자치', 'warlord': '군벌',
  'vassal': '종속', 'protectorate': '보호', 'satellite': '위성', 'puppet': '괴뢰', 'mandate': '위임',
  'colony': '식민', 'occupied': '점령', 'federation': '연맹', 'org': '조직', 'era': '시대',
  'client': '복속', 'frontier': '기미', 'prefecture': '군현',
  'exile': '망명', 'movement': '세력', 'culture': '문화', 'overlay': '기관', 'dynasty': '왕조',
};
final _kindIdByName = {for (final e in polityKindNames.entries) e.value: e.key};

/// 저장소가 실은 종류 이름(`조공·책봉국`)을 짧은 이름(`조공`)으로 — 모르는 글(민족 이름 따위)은 그대로.
String kindShortOf(String name) => polityKindShort[_kindIdByName[name]] ?? name;

const treatyTypeNames = {
  'peace': '강화', 'armistice': '휴전', 'alliance': '동맹', 'nonaggression': '불가침', 'trade': '통상',
  'border': '국경', 'cession': '할양·병합', 'protectorate': '보호', 'investiture': '책봉·조공', 'marriage': '혼인', 'other': '기타',
};
const treatyEndNames = {'expired': '기한 만료', 'abrogated': '폐기', 'superseded': '새 조약으로 대체', 'fulfilled': '이행 완료', 'annulled': '무효'};
const articleTagNames = {
  'territory': '영토', 'indemnity': '배상', 'trade': '통상', 'extraterritorial': '치외법권', 'military': '군사', 'recognition': '승인', 'other': '기타',
};
const successionNames = {'direct': '직접', 'indirect': '간접', 'revival': '부흥', 'partial': '부분'};

/// 부분 승계의 정도(`HT.SUCC_DEGREES`) — 선에는 그리지 않고 상세 창의 이름 뒤 옅은 글로 보인다. 저장소가 이름(`degreeName`)을 실으면 그것을, 아니면 번호로 읽는다.
const succDegreeNames = {1: '약', 2: '중', 3: '강'};

/// 지위의 짙기(`HT.RANK_MIX`) — 나라 색에 섞는 비율(%).
const rankMix = [0, 8, 22, 38, 56];

/// 앱 틀이 `bus.slot(slotName)`에 채워 둔 이름표에서 하나를 찾는다.
({String name, Color color})? namedOf(AppBus bus, String slotName, String? id) {
  if (id == null || id.isEmpty) return null;
  final table = bus.slot(slotName).value;
  if (table is! Map) return null;
  final row = table[id];
  if (row is! Map) return null;
  return (name: '${row['name'] ?? id}', color: detailColor(row['color']));
}

// ────────────────────────────────────────────────────────────────────────────────────────────

/// 기본 상세 · 조약 상세.
class ItemDetail extends StatefulWidget {
  const ItemDetail(this.ctx, {super.key});
  final DetailContext ctx;

  /// 가문 배지 옆의 `성 ○ · 본관 ○○` 배지(D1 결정 6 A — 올림 풍선이 없는 **휴대폰**에서만 · 확정 설계 5-2).
  /// 컴퓨터에서는 띠 위 풍선(D1-N3)이 같은 값을 보인다. 검사는 이 값을 켜서 본다.
  static bool surnameBadge = Platform.isAndroid || Platform.isIOS;

  @override
  State<ItemDetail> createState() => _ItemDetailState();
}

class _ItemDetailState extends State<ItemDetail> {
  /// 관점 탭에서 고른 트랙(빈 글이면 기본).
  String _lens = '';

  DetailContext get ctx => widget.ctx;
  Map<String, dynamic> get x => ctx.json;

  // ── 왕조 창의 기간 조명: 다스린 띠마다 그 기간을 밝힌다(지금 연표의 DETAIL_KINDS.dynasty.enter → setSpotlight — 인물 창과 같은 길) ──
  Object? _litSpots;

  @override
  void initState() {
    super.initState();
    _light();
    unawaited(_loadSurname());
  }

  @override
  void didUpdateWidget(ItemDetail old) {
    super.didUpdateWidget(old);
    if (old.ctx.uid != ctx.uid) {
      _light();
      unawaited(_loadSurname());
    }
  }

  /// 휴대폰의 성씨 배지 — 가문 기록의 성(`x_surname`) · 본관(`seat`). 없으면 null.
  ({String text, String uid})? _surname;

  Future<void> _loadSurname() async {
    _surname = null;
    final houseId = detailString(x, 'houseId');
    if (!ItemDetail.surnameBadge || houseId.isEmpty) return;
    final h = await ctx.askEntity('house:$houseId');
    if (!mounted || h == null) return;
    final sn = h['x_surname'] is Map ? (h['x_surname'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final name = detailString(sn, 'name').isNotEmpty ? detailString(sn, 'name') : detailString(h, 'surname');
    if (name.isEmpty) return;
    final seat = detailString(h, 'seat');
    setState(() => _surname = (text: '성 $name${seat.isEmpty ? '' : ' · 본관 $seat'}', uid: detailString(sn, 'uid')));
  }

  @override
  void dispose() {
    final slot = ctx.slot('spots');
    if (_litSpots != null && identical(slot.value, _litSpots)) slot.value = null;
    super.dispose();
  }

  void _light() {
    final slot = ctx.slot('spots');
    final mine = _litSpots != null && identical(slot.value, _litSpots);
    final spots = _itemKind == 'dynasty' ? detailList(x, 'x_spots') : const <Map<String, dynamic>>[];
    if (spots.isEmpty) {
      // 제가 켠 것만 지운다(남이 켠 조명은 건드리지 않는다).
      if (mine) slot.value = null;
      _litSpots = null;
      return;
    }
    _litSpots = spots;
    slot.value = spots;
  }

  // ── 값 꺼내기 ──────────────────────────────────────────────────────────────────────────────

  String get _itemKind {
    final k = detailString(x, 'itemKind');
    if (k.isNotEmpty) return k;
    return ctx.kind.isEmpty ? 'period' : ctx.kind;
  }

  bool get _isEvent => _itemKind == 'event' || _itemKind == 'treaty';
  Map<String, dynamic>? get _treaty {
    final t = x['treaty'];
    return t is Map ? t.cast<String, dynamic>() : null;
  }

  List<Map<String, dynamic>> get _views => detailList(x, 'perspectives');
  Map<String, dynamic>? get _view {
    if (_lens.isEmpty) return null;
    for (final v in _views) {
      if (v['track'] == _lens) return v;
    }
    return null;
  }

  double? get _start => detailNum(x, 'start')?.toDouble();
  double? get _end => detailNum(x, 'end')?.toDouble();
  double? get _endY => detailNum(x, 'endY')?.toDouble();
  bool get _ongoing => x['ongoing'] == true;
  bool get _startUnknown => x['startUnknown'] == true;
  bool get _endUnknown => x['endUnknown'] == true;

  // ── 배지 ──────────────────────────────────────────────────────────────────────────────────

  List<Widget> _badges() {
    final out = <Widget>[];
    final track = namedOf(ctx.bus, 'tracks', detailString(x, 'track'));
    if (track != null) out.add(DetailBadge(track.name, color: track.color));

    final polityUid = detailString(x, 'polityUid');
    if (polityUid.isNotEmpty) {
      out.add(DetailBadge(detailString(x, 'polityName'), color: detailColor(x['polityColor']), onTap: () => ctx.open(polityUid)));
    }
    if (!_isEvent && detailString(x, 'peopleName').isNotEmpty) {
      out.add(DetailBadge(detailString(x, 'peopleName'), color: detailColor(x['peopleColor'])));
    }
    final houseId = detailString(x, 'houseId');
    if (houseId.isNotEmpty) {
      out.add(DetailBadge('${_itemKind == 'period' ? '국성' : '가문'} ${detailString(x, 'houseName')}', color: detailColor(x['houseColor']), onTap: () => ctx.open('house:$houseId')));
      final sn = _surname;
      if (sn != null) out.add(DetailBadge(sn.text, color: detailColor(x['houseColor']), onTap: sn.uid.isEmpty ? null : () => ctx.open(sn.uid, kind: 'surname')));
    }

    if (_isEvent) {
      final cat = namedOf(ctx.bus, 'categories', detailString(x, 'category'));
      if (cat != null) out.add(DetailBadge(cat.name, color: cat.color));
    } else {
      out.add(DetailBadge(_kindBadgeText(), dot: false, color: Ui.text3));
    }

    final treaty = _treaty;
    if (treaty != null) {
      final type = detailString(treaty, 'type');
      out.add(DetailBadge('조약${type.isEmpty ? '' : ' · ${treatyTypeNames[type] ?? type}'}', diamond: true, color: const Color(0xff9dbea8)));
      if (treaty['unequal'] == true) out.add(const DetailBadge('불평등 조약', color: DetailUi.warn));
    }
    // 사건의 주제 · 법 · 선거 딱지(형식 3 — 웹 lensBadgesHTML · 조약 배지 다음).
    if (_isEvent) out.addAll(detailLensBadges(x));

    final hs = detailString(x, 'historicity');
    if (!_isEvent && hs.isNotEmpty && hs != 'attested') {
      out.add(DetailBadge(historicityNames[hs] ?? hs, color: Ui.text3, italic: hs == 'legendary' || hs == 'semi', strike: hs == 'refuted'));
    }
    final cert = detailString(x, 'certainty');
    if (cert.isNotEmpty && cert != 'accepted') out.add(DetailBadge('${certaintyNames[cert] ?? cert} 연대', color: DetailUi.warn));
    if (_startUnknown || _endUnknown) out.add(const DetailBadge('연도 미정', color: DetailUi.warn));
    return out;
  }

  String _kindBadgeText() {
    switch (_itemKind) {
      case 'organ':
        return '기관';
      case 'culture':
        return '문화';
      case 'dynasty':
        return '왕조';
      case 'epoch':
        return '시대 구분';
    }
    final kind = detailString(x, 'polityKind');
    return kind.isEmpty || kind == 'state' ? '시대' : (polityKindNames[kind] ?? '시대');
  }

  // ── 몸통 ──────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => DetailShell(
    onClose: ctx.close,
    badges: _badges(),
    body: [
      ..._lensTabs(),
      // 제목 = 큰 꼬리표 카드(리메이크 2부 · 목업 서고): 그 항목의 색 · 기간은 카드 안에(조약 · 법은 제 날짜 칸이 따로라 카드에 넣지 않음).
      DetailTitle(_shownTitle(), color: x['color'] == null ? null : detailColor(x['color']), when: _treaty == null && _lawTop().isEmpty ? _when().$1 : null),
      // 원어 머리 두 줄 · 사건의 장소(10건 3 · 감독 결정 D2-1 A — 웹 namesHeadHTML(제목 바로 아래) · placeHTML(x.place, '장소') · ui/names_display.dart).
      NamesHead(bus: ctx.bus, head: x['x_nameHead'], old: x['x_names'], kind: _isEvent ? null : NameKind.polity),
      ..._nameNotes(),
      // 법 이름 · 뽑은 자리(감독 선택 D5 결정 7 A — 웹 lensAkaHTML: 다른 이름 줄 다음 · 장소 앞).
      if (_isEvent) ...detailLensAka(x),
      if (_isEvent) NamesPlace(bus: ctx.bus, place: x['x_place'], lead: '장소'),
      // 법(이름이 있는 것)은 기본 기간 줄 자리에 법의 내력(웹 lawTop — 내력에 날짜가 든다). 조약은 조약 날짜 표가 그 자리다.
      ..._treaty != null ? _treatyTop(_treaty!) : (_lawTop().isNotEmpty ? _lawTop() : _whenLine()),
      ..._crumb(),
      ..._uncertainNotes(),
      ..._sharedNote(),
      // 선거의 결과(의석 막대 · 과반 글 · 표) — 설명 위 · '다른 이름' 칸 앞(웹 electionTopHTML).
      if (_isEvent) ...detailElectionTop(x, ctx.open),
      // 머리 두 줄에 오르지 않은 이름 — 설명 바로 위의 '다른 이름 n개' 칸(웹 namesRestHTML).
      NamesRest(bus: ctx.bus, head: x['x_nameHead'], kind: _isEvent ? null : NameKind.polity),
      DetailDesc(_shownDesc()),
      ..._historicityBox(),
      ..._treatyBottom(),
      // 법 양식 · 선거 표 · 이 일로 맺은 단체(형식 3 — 웹 lensBottomHTML).
      if (_isEvent) ...detailLensBottom(x, ctx.open, topsPlaced: true),
      ..._children(),
      ..._relatedFigures(),
      ..._partOf(),
      ..._scopes(),
      // 나라의 단체 · 제도 칩(형식 3 — 웹 periodLensHTML · 대범위 다음 · 왕조 앞).
      if (!_isEvent) ...detailPolityLensBoxes(x, ctx.open),
      ..._dynasties(),
      ..._echoSlot(),
      ..._succession(),
      ..._ranks(),
      ..._phases(),
      ..._cells('지도자', 'leaders', 'leader', '명', leaders: true),
      ..._cells('내각', 'cabinets', 'cabinet', '개'),
      ..._cells('연호', 'eras', 'era', '개'),
      ..._capitals(),
      ..._figures(),
      DocChips(bus: ctx.bus, uid: ctx.uid, json: ctx.json),
      ..._alternatives(),
      ..._debate(),
      ..._tags(),
      _defs(),
    ],
    foot: [
      DetailSmallButton('이 위치로', icon: LineGlyph.locate, onTap: _focus),
      if (detailString(x, 'wiki').isNotEmpty) DetailSmallButton('문서', icon: LineGlyph.file, onTap: () => ctx.slot('doc').value = ctx.uid),
    ],
  );

  String _shownTitle() {
    final view = _view;
    if (view != null && detailString(view, 'title').isNotEmpty) return detailString(view, 'title');
    final title = detailString(x, 'title');
    return title.isNotEmpty ? title : detailString(x, 'name');
  }

  String _shownDesc() {
    final view = _view;
    if (view != null && detailString(view, 'description').isNotEmpty) return detailString(view, 'description');
    return detailString(x, 'description');
  }

  /// 1. 관점 탭 — `기본` + 나라마다.
  List<Widget> _lensTabs() {
    if (_views.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _LensTab('기본', on: _view == null, onTap: () => setState(() => _lens = '')),
            for (final v in _views)
              _LensTab(
                namedOf(ctx.bus, 'tracks', detailString(v, 'track'))?.name ?? detailString(v, 'track'),
                on: _view == v,
                onTap: () => setState(() => _lens = detailString(v, 'track')),
              ),
          ],
        ),
      ),
    ];
  }

  /// 3. `기본 이름: …` 또는 `다른 이름: 〈트랙〉 〈이름〉 · …`.
  List<Widget> _nameNotes() {
    final view = _view;
    final title = detailString(x, 'title');
    if (view != null) {
      final own = detailString(view, 'title');
      if (own.isNotEmpty && own != title) return [DetailAka('기본 이름: $title')];
      return const [];
    }
    final others = [
      for (final v in _views)
        if (detailString(v, 'title').isNotEmpty) '${namedOf(ctx.bus, 'tracks', detailString(v, 'track'))?.name ?? detailString(v, 'track')} ${detailString(v, 'title')}',
    ];
    if (others.isEmpty) return const [];
    return [DetailAka('다른 이름: ${others.join(' · ')}')];
  }

  /// 4. 기간 줄 + 원문 표기 + 그날의 곁들임.
  /// 법의 내력(이 사건이 이름 있는 법이고 내보내기가 내력을 실었을 때만 — 아니면 빈 목록이라 기간 줄이 선다).
  List<Widget> _lawTop() => _isEvent ? detailLawTop(x, ctx.open) : const [];

  /// 기간 줄: 기간 글은 제목 카드 안에 들어가므로 여기에는 날 · 시각 곁들임만(있을 때).
  List<Widget> _whenLine() {
    final sub = _when().$2;
    return sub == null || sub.isEmpty ? const [] : [DetailWhen('', sub: sub)];
  }

  /// 기간 글과 날 · 시각 곁들임(음력 · 일진 · 요일).
  (String, String?) _when() {
    final startAt = detailString(x, 'startAt'), endAt = detailString(x, 'endAt');
    final text = rangeText(
      start: _start,
      startAt: startAt.isEmpty ? null : startAt,
      end: _end ?? (_endY != _start ? _endY : null),
      endAt: endAt.isEmpty ? null : endAt,
      startUnknown: _startUnknown,
      endUnknown: _endUnknown,
      ongoing: _ongoing,
    );
    final prec = _startUnknown ? DatePrec.year : (atFits(startAt, _start) ? precOfAt(startAt) : DatePrec.year);
    final fine = prec == DatePrec.day || prec == DatePrec.hour || prec == DatePrec.minute;
    final sub = fine && _start != null ? '${_end != null || _ongoing ? '시작일 ' : ''}${dayNote(_start!, lunar: AuxCalendarStore.shared?.lunar, withLunar: !isLunarAt(startAt))}' : null;
    return (text, sub);
  }

  /// 5. `〈부모 사건〉 안의 사건` 빵부스러기.
  List<Widget> _crumb() {
    final parentUid = detailString(x, 'parentUid');
    if (parentUid.isEmpty) return const [];
    return [DetailNote('${detailString(x, 'parentTitle')} 안의 사건', onTap: () => ctx.open(parentUid))];
  }

  /// 6. 미정 안내 두 줄 → 연대 폭 두 줄.
  List<Widget> _uncertainNotes() {
    final out = <Widget>[];
    if (_startUnknown) out.add(DetailRangeNote(unknownStartNote(_start, at: detailString(x, 'startAt'))));
    if (_endUnknown) out.add(DetailRangeNote(unknownEndNote(_endY, at: detailString(x, 'endAt'), ongoing: _ongoing)));
    for (final pair in const [('시작', 'startRange'), ('끝', 'endRange')]) {
      final v = x[pair.$2];
      if (v is List && v.length >= 2 && v[0] is num && v[1] is num) {
        out.add(DetailRangeNote(rangeNote(pair.$1, (v[0] as num).toDouble(), (v[1] as num).toDouble())));
      }
    }
    return out;
  }

  /// 7. `…가 함께 겪은 일입니다.`(공동 사건, 조약이 아닐 때).
  List<Widget> _sharedNote() {
    if (_treaty != null) return const [];
    final with_ = detailStrings(x, 'sharedWith');
    if (with_.isEmpty) return const [];
    final names = [detailString(x, 'polityName'), ...with_].where((s) => s.isNotEmpty);
    return [DetailNote('${names.join(' · ')}가 함께 겪은 일입니다.')];
  }

  /// 10. 실재성 상자.
  List<Widget> _historicityBox() {
    final hs = detailString(x, 'historicity');
    final note = detailString(x, 'historicityNote');
    final on = hs.isNotEmpty && hs != 'attested';
    if (_isEvent || (!on && note.isEmpty)) return const [];
    final id = on ? hs : 'attested';
    return [
      DetailBox(
        title: '실재성',
        small: historicityNames[id],
        children: [
          Text(
            '${historicityHints[id]}${on ? ' · 연대의 확실성과는 따로, 나라가 있었는가를 말합니다' : ''}',
            style: const TextStyle(fontSize: 12, height: 1.6, color: Ui.text3),
          ),
          if (note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: DetailDesc(note, small: true)),
        ],
      ),
    ];
  }

  /// 12. 포함된 사건.
  List<Widget> _children() {
    final kids = detailList(x, 'x_children');
    if (kids.isEmpty) return const [];
    return [
      DetailBox(
        title: '포함된 사건',
        small: '${kids.length}',
        children: [
          DetailKidList([
            for (final k in kids) DetailKidRow(year: detailString(k, 'when'), name: detailString(k, 'title'), onTap: () => ctx.open(detailString(k, 'uid'))),
          ]),
        ],
      ),
    ];
  }

  /// 13. 관련 인물(칩 — 찾은 인물만 누를 수 있다).
  List<Widget> _relatedFigures() {
    final refs = detailList(x, 'x_figures');
    if (refs.isEmpty) return const [];
    return [
      DetailBox(
        title: '관련 인물',
        small: '${refs.length}',
        children: [
          DetailChipRow([
            for (final f in refs)
              DetailChip(
                '${detailString(f, 'name')}${detailString(f, 'role').isEmpty ? '' : ' · ${detailString(f, 'role')}'}',
                muted: detailString(f, 'uid').isEmpty,
                onTap: detailString(f, 'uid').isEmpty ? null : () => ctx.open(detailString(f, 'uid'), kind: 'figure'),
              ),
          ], top: 0),
        ],
      ),
    ];
  }

  /// 14. 소속(연맹 구성국 · 종속국의 종주국 · 기관이 얹힌 정권).
  List<Widget> _partOf() {
    final table = x['x_partOf'];
    if (table is! Map) return const [];
    final hosts = detailList(table.cast<String, dynamic>(), 'hosts');
    final members = detailList(table.cast<String, dynamic>(), 'members');
    if (hosts.isEmpty && members.isEmpty) return const [];
    final isOrgan = _itemKind == 'organ';
    final organs = [
      for (final m in members)
        if (m['organ'] == 1 || m['organ'] == true) m,
    ];
    final others = [
      for (final m in members)
        if (!(m['organ'] == 1 || m['organ'] == true)) m,
    ];
    return [
      DetailBox(
        title: isOrgan ? '얹힌 정권' : '소속',
        children: [
          if (hosts.isNotEmpty) ...[
            _cap(isOrgan ? '이 기관이 놓인 주권 정권' : (hosts.length > 1 ? '차례로 예속된 상위 정권' : '상위 정권')),
            DetailSuccList([for (final h in hosts) _relRow(h)]),
          ],
          if (others.isNotEmpty) ...[
            _cap(detailString(x, 'polityKind') == 'federation' ? '구성 정권' : '딸린 정권·조직', '${others.length}개'),
            DetailSuccList([for (final m in others) _relRow(m)]),
          ],
          if (organs.isNotEmpty) ...[
            _cap('위에 놓인 기관', '${organs.length}개'),
            DetailSuccList([for (final m in organs) _relRow(m)]),
          ],
        ],
      ),
    ];
  }

  Widget _relRow(Map<String, dynamic> row) => DetailSuccRow(
    badge: detailString(row, 'kind').isEmpty ? null : kindShortOf(detailString(row, 'kind')),
    badgeHint: detailString(row, 'kind'),
    name: detailString(row, 'name'),
    years: detailString(row, 'when'),
    onTap: () => ctx.open(detailString(row, 'uid')),
  );

  /// 15. 대범위 — 든 대범위와 상징적 본국으로 받든 대범위(각 줄에 모아 보기 스위치).
  List<Widget> _scopes() {
    final out = <Widget>[];
    for (final pair in const [('대범위', 'x_scopes', '이 정권이 든 대범위'), ('상징적 본국으로 받든 대범위', 'x_hostedScopes', '이 정권을 본국으로 받드는 대범위')]) {
      final list = detailList(x, pair.$2);
      if (list.isEmpty) continue;
      out.add(
        DetailBox(
          title: pair.$1,
          small: pair.$3,
          children: [
            DetailSuccList([
              for (final s in list)
                DetailSuccRow(
                  badge: detailString(s, 'label').isEmpty ? null : detailString(s, 'label'),
                  name: detailString(s, 'name'),
                  onTap: () => ctx.open(detailString(s, 'uid'), kind: 'scope'),
                ),
            ]),
          ],
        ),
      );
    }
    return out;
  }

  /// 16. 왕조 — 나라면 다스린 왕조 목록, 왕조면 다스린 나라 · 가문 · 지도자 목록.
  List<Widget> _dynasties() {
    final out = <Widget>[];
    final mine = detailList(x, 'x_dynasties');
    if (mine.isNotEmpty) {
      out.add(
        DetailBox(
          title: '왕조',
          small: '${mine.length}',
          children: [
            DetailSuccList([
              for (final d in mine)
                DetailSuccRow(badge: '왕조', name: detailString(d, 'name'), years: detailString(d, 'when'), onTap: () => ctx.open(detailString(d, 'uid'))),
            ]),
          ],
        ),
      );
    }
    final ruled = detailList(x, 'x_ruled');
    if (ruled.isNotEmpty) {
      out.add(
        DetailBox(
          title: '다스린 나라',
          small: '${ruled.length}',
          children: [
            DetailSuccList([
              for (final r in ruled)
                DetailSuccRow(
                  badge: detailString(r, 'kind').isEmpty ? null : kindShortOf(detailString(r, 'kind')),
                  badgeHint: detailString(r, 'kind'),
                  name: detailString(r, 'name'),
                  years: detailString(r, 'when'),
                  onTap: () => ctx.open(detailString(r, 'uid')),
                ),
            ]),
          ],
        ),
      );
    }
    final rulers = detailList(x, 'x_rulers');
    if (rulers.isNotEmpty) {
      out.add(
        DetailBox(
          title: '지도자',
          small: '${rulers.length}',
          children: [
            DetailKidList([
              for (final r in rulers)
                DetailKidRow(
                  year: detailString(r, 'when'),
                  name: detailString(r, 'label'),
                  onTap: () => ctx.open(detailString(r, 'uid'), cell: detailString(r, 'ref')),
                ),
            ]),
          ],
        ),
      );
    }
    return out;
  }

  /// 17. 왕조이고 다스린 나라가 있으면 메아리 자리(스위치와 '같은 시기 타국' 묶음).
  /// 왕조 창은 `always`가 아니다 — 스위치를 켰을 때만 강조를 걸고 그 강조를 사건 배치에 쓰지 않는다(명세 3-4).
  List<Widget> _echoSlot() {
    if (_itemKind != 'dynasty' || detailList(x, 'x_ruled').isEmpty) return const [];
    return [
      EchoSlot(
        bus: ctx.bus,
        spots: detailList(x, 'x_spots'),
        always: false,
        color: detailColor(x['color'], Ui.text3),
        onOpen: ctx.open,
      ),
    ];
  }

  /// 18. 승계 — 이어받은 나라 / 이어간 나라.
  List<Widget> _succession() {
    if (_itemKind == 'dynasty') return const [];
    final table = x['x_succ'];
    if (table is! Map) return const [];
    final pre = detailList(table.cast<String, dynamic>(), 'pre');
    final post = detailList(table.cast<String, dynamic>(), 'post');
    if (pre.isEmpty && post.isEmpty) return const [];
    return [
      DetailBox(
        title: '승계',
        small: detailString(x, 'peopleName').isEmpty ? null : detailString(x, 'peopleName'),
        children: [
          if (pre.isNotEmpty) ...[_cap('이어받은 나라'), DetailSuccList([for (final e in pre) _succRow(e)])],
          if (post.isNotEmpty) ...[_cap('이어간 나라'), DetailSuccList([for (final e in post) _succRow(e)])],
        ],
      ),
    ];
  }

  Widget _succRow(Map<String, dynamic> e) {
    final type = detailString(e, 'type');
    final style = switch (type) {
      'direct' => SuccBadge.direct,
      'indirect' => SuccBadge.indirect,
      'revival' => SuccBadge.revival,
      'partial' => SuccBadge.partial,
      _ => SuccBadge.plain,
    };
    final bits = <String>[
      if (type == 'partial') '정도 ${detailString(e, 'degreeName').isNotEmpty ? detailString(e, 'degreeName') : (succDegreeNames[(detailNum(e, 'degree') ?? 2).toInt()] ?? '중')}',
      ...detailStrings(e, 'parts'),
      if (detailString(e, 'join').isNotEmpty) '${detailString(e, 'join')} 합류',
    ];
    return DetailSuccRow(
      badge: successionNames[type] ?? type,
      badgeStyle: style,
      name: detailString(e, 'name'),
      trailing: bits.isEmpty ? null : bits.join(' · '),
      years: detailString(e, 'when'),
      onTap: () => ctx.open(detailString(e, 'uid')),
    );
  }

  /// 19. 지위 목록(기간 · 짙기 견본 · 이름 · ▲승격 / ▼격하).
  List<Widget> _ranks() {
    final list = detailList(x, 'rankSpans');
    if (list.isEmpty) return const [];
    final base = detailColor(x['color']);
    return [
      DetailBox(
        title: '지위',
        small: '${list.length}',
        children: [
          DetailCellList(single: true, [
            for (int i = 0; i < list.length; i++)
              DetailCellTile(
                year: _cellWhen(list[i]),
                name: detailString(list[i], 'name'),
                swatch: _rankSwatch(base, (detailNum(list[i], 'level') ?? 0).toInt()),
                mark: _rankMove(list, i),
                markColor: _rankMoveUp(list, i) ? DetailUi.ok : DetailUi.warn,
                onTap: () => ctx.open(ctx.uid, cell: 'rank:$i'),
              ),
          ]),
        ],
      ),
    ];
  }

  Color _rankSwatch(Color base, int level) {
    final t = rankMix[level.clamp(0, rankMix.length - 1)] / 100;
    return Color.lerp(Ui.bg, base, t)!;
  }

  bool _rankMoveUp(List<Map<String, dynamic>> list, int i) =>
      i > 0 && (detailNum(list[i], 'level') ?? 0) > (detailNum(list[i - 1], 'level') ?? 0);

  String? _rankMove(List<Map<String, dynamic>> list, int i) {
    if (i == 0) return null;
    final now = detailNum(list[i], 'level') ?? 0, before = detailNum(list[i - 1], 'level') ?? 0;
    if (now == before) return null;
    return now > before ? '▲승격' : '▼격하';
  }

  /// 20. 시기 구분(학계) — 체계별.
  List<Widget> _phases() {
    final schemes = detailList(x, 'phaseSchemes');
    if (schemes.isEmpty) return const [];
    var count = 0;
    for (final s in schemes) {
      count += detailList(s, 'spans').length;
    }
    return [
      DetailBox(
        title: '시기 구분(학계)',
        small: '${schemes.length > 1 ? '체계 ${schemes.length} · ' : ''}시기 $count',
        children: [
          for (final s in schemes) ...[
            if (schemes.length > 1) _cap(detailString(s, 'scheme'), detailString(s, 'note').isEmpty ? null : detailString(s, 'note')),
            DetailCellList(single: true, [
              for (final span in detailList(s, 'spans'))
                DetailCellTile(
                  year: _cellWhen(span),
                  name: detailString(span, 'name'),
                  onTap: () => ctx.open(ctx.uid, cell: 'phase:${(detailNum(span, 'ci') ?? 0).toInt()}'),
                ),
            ]),
          ],
        ],
      ),
    ];
  }

  /// 21. 지도자 · 내각 · 연호 목록.
  List<Widget> _cells(String title, String key, String ref, String unit, {bool leaders = false}) {
    final list = detailList(x, key);
    if (list.isEmpty) return const [];
    return [
      DetailBox(
        title: title,
        small: '${list.length}',
        // 지도자가 둘 이상이면 승계표(D1 결정 1 A — 같은 창이 나라 상세 → 승계표로 바뀐다 · 확정 설계 3-1).
        action: leaders && list.length >= 2 && _itemKind == 'period' ? DetailSmallButton('승계표', onTap: () => ctx.open(ctx.uid, cell: successionCell)) : null,
        children: [
          DetailCellList(leaders: leaders, [
            for (int i = 0; i < list.length; i++)
              DetailCellTile(
                year: _cellWhen(list[i]),
                name: detailString(list[i], 'name'),
                sub: leaders ? _leaderSub(list[i]) : null,
                leaders: leaders,
                onTap: () => ctx.open(ctx.uid, cell: '$ref:$i'),
              ),
          ]),
        ],
      ),
    ];
  }

  String? _leaderSub(Map<String, dynamic> c) {
    final bits = [
      if (detailNum(c, 'ordinal') != null) '제${(detailNum(c, 'ordinal') ?? 0).toInt()}대' else if (c['ordinalUnknown'] == true) '대수 미상',
      if (detailString(c, 'title').isNotEmpty) detailString(c, 'title'),
      if (detailString(c, 'rank').isNotEmpty) detailString(c, 'rank'),
    ];
    return bits.isEmpty ? null : bits.join(' · ');
  }

  /// 21. 도읍(머리에 `🚇 노선도` 단추).
  List<Widget> _capitals() {
    final list = detailList(x, 'capitals');
    if (list.isEmpty) return const [];
    final cities = <String>{}, secondary = <String>{};
    for (final c in list) {
      cities.add(detailString(c, 'city'));
      if (detailString(c, 'role') == 'secondary') secondary.add(detailString(c, 'city'));
    }
    return [
      DetailBox(
        title: '도읍',
        small: '${cities.length}${secondary.isEmpty ? '' : ' · 배도 ${secondary.length}'}',
        // 지금 연표의 `js/viewer.js` 2298은 `showMetro(uid, <그 정권의 줄>, true)` — **고정으로** 연다(다른 항목을 골라도 닫히지 않는다).
        action: DetailSmallButton('노선도', icon: LineGlyph.route, onTap: () => ctx.slot(metroSlot).value = MetroRequest(ctx.uid, pinned: true)),
        children: [
          DetailCellList([
            for (int i = 0; i < list.length; i++)
              DetailCellTile(
                year: _cellWhen(list[i]),
                name: detailString(list[i], 'name').isEmpty ? detailString(list[i], 'city') : detailString(list[i], 'name'),
                sub: _capitalRole(list[i]),
                onTap: () => ctx.open(ctx.uid, cell: 'capital:$i'),
              ),
          ]),
        ],
      ),
    ];
  }

  String? _capitalRole(Map<String, dynamic> c) {
    const roles = {'main': '주요 도읍', 'secondary': '배도', 'temporary': '임시 도읍', 'exile': '망명지'};
    final bits = [
      if (roles[detailString(c, 'role')] != null) roles[detailString(c, 'role')]!,
      if (detailString(c, 'group').isNotEmpty) detailString(c, 'group'),
    ];
    return bits.isEmpty ? null : bits.join(' · ');
  }

  /// 22. 인물 목록(이 띠에서 섬긴 사람들).
  List<Widget> _figures() {
    final list = detailList(x, 'x_served');
    if (list.isEmpty) return const [];
    return [
      DetailBox(
        title: '인물',
        small: '${list.length}',
        children: [
          DetailSuccList([
            for (final f in list)
              DetailSuccRow(
                badge: detailString(f, 'role').isEmpty ? null : detailString(f, 'role'),
                name: detailString(f, 'name'),
                trailing: detailString(f, 'office').isEmpty ? null : detailString(f, 'office'),
                years: detailString(f, 'when'),
                onTap: () => ctx.open(detailString(f, 'uid'), kind: 'figure'),
              ),
          ]),
        ],
      ),
    ];
  }

  /// 24. 다른 견해 — 첫 줄은 이 연표가 쓰는 연대.
  List<Widget> _alternatives() {
    final alts = detailList(x, 'alternatives');
    if (alts.isEmpty) return const [];
    return [
      DetailBox(
        title: '다른 견해',
        children: [
          DetailAltList([
            DetailAltRow(
              when: rangeText(start: _start, end: _end, startUnknown: _startUnknown, endUnknown: _endUnknown, ongoing: _ongoing),
              why: '이 연표가 쓰는 연대',
              main: true,
              onTap: _start == null ? null : () => _goToYear(_start!),
            ),
            for (final a in alts)
              DetailAltRow(
                when: rangeText(start: detailNum(a, 'start')?.toDouble(), end: detailNum(a, 'end')?.toDouble()),
                why: detailString(a, 'label'),
                note: detailString(a, 'note').isEmpty ? null : detailString(a, 'note'),
                onTap: detailNum(a, 'start') == null ? null : () => _goToYear(detailNum(a, 'start')!.toDouble()),
              ),
          ]),
        ],
      ),
    ];
  }

  /// 25. 쟁점.
  List<Widget> _debate() {
    final debate = detailString(x, 'debate');
    if (debate.isEmpty) return const [];
    return [
      DetailBox(title: '쟁점', children: [DetailDesc(debate, small: true)]),
    ];
  }

  /// 26. 태그.
  List<Widget> _tags() {
    final tags = detailStrings(x, 'tags');
    if (tags.isEmpty) return const [];
    return [DetailTags([for (final t in tags) '#$t'])];
  }

  /// 27. dl — 제공 · 중요도 · 메모 · 출처.
  Widget _defs() {
    final importance = (detailNum(x, 'importance') ?? 2).toInt().clamp(1, 3);
    return DetailDefs([
      DetailDef('제공', Text(detailString(x, 'packName'))),
      if (_isEvent) DetailDef('중요도', Text('${'★' * importance}${'☆' * (3 - importance)}')),
      if (detailString(x, 'note').isNotEmpty) DetailDef('메모', Text(detailString(x, 'note'))),
      if (detailString(x, 'source').isNotEmpty) DetailDef('출처', Text(detailString(x, 'source'))),
    ]);
  }

  // ── 조약 (명세 2-3 ㈖) ────────────────────────────────────────────────────────────────────

  /// 기간 줄 자리: 정식 명칭 → 당사국 → 날짜 진행 표.
  List<Widget> _treatyTop(Map<String, dynamic> t) => [
    if (detailString(t, 'formal').isNotEmpty) DetailAka('정식 명칭 ${detailString(t, 'formal')}'),
    ..._treatyParties(),
    _treatyDates(t),
  ];

  /// 편이 정확히 둘이고 모두 편을 적었으면 좌우 두 칸(가운데 파선), 아니면 세로 목록.
  List<Widget> _treatyParties() {
    final parties = detailList(x, 'x_parties');
    if (parties.isEmpty) return const [];
    final sides = <int>{};
    var allSided = true;
    for (final p in parties) {
      final s = detailNum(p, 'side');
      if (s == null) {
        allSided = false;
      } else {
        sides.add(s.toInt());
      }
    }
    final twoSides = allSided && sides.length == 2;
    final ordered = sides.toList()..sort();
    return [
      DetailBox(
        title: '당사국',
        small: '${parties.length}',
        children: [
          if (twoSides)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < ordered.length; i++) ...[
                    if (i > 0) const _SideDivider(),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _cap('편 ${ordered[i]}'),
                          for (final p in parties)
                            if (detailNum(p, 'side')?.toInt() == ordered[i]) _partyCard(p),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            )
          else ...[
            for (final side in [...ordered, if (!allSided) null]) ...[
              if (sides.isNotEmpty) _cap(side == null ? '편을 적지 않은 당사국' : '편 $side'),
              for (final p in parties)
                if (detailNum(p, 'side')?.toInt() == side) _partyCard(p),
            ],
          ],
        ],
      ),
    ];
  }

  Widget _partyCard(Map<String, dynamic> p) {
    final uid = detailString(p, 'uid');
    final signers = detailList(p, 'signers');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DetailChip(detailString(p, 'name'), color: detailColor(p['color']).withAlpha(66), muted: uid.isEmpty, onTap: uid.isEmpty ? null : () => ctx.open(uid)),
              if (detailString(p, 'role').isNotEmpty) Text(detailString(p, 'role'), style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text3)),
            ],
          ),
          for (final s in signers)
            DetailPressable(
              onTap: detailString(s, 'uid').isEmpty ? null : () => ctx.open(detailString(s, 'uid'), kind: 'figure'),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              radius: 6,
              semantics: detailString(s, 'name'),
              child: Text.rich(
                TextSpan(
                  text: detailString(s, 'name'),
                  children: [if (detailString(s, 'title').isNotEmpty) TextSpan(text: ' — ${detailString(s, 'title')}', style: const TextStyle(fontSize: 11, color: Ui.text3))],
                ),
                style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text),
              ),
            ),
        ],
      ),
    );
  }

  /// 체결 → 비준 → 발효 → 실효. 줄마다 `[낱말][날짜][사이 간격]`.
  Widget _treatyDates(Map<String, dynamic> t) {
    final rows = <({String word, double? at, String? atText, String text, String? note, String? sub})>[];
    final startAt = detailString(x, 'startAt');
    final prec = _startUnknown ? DatePrec.year : (atFits(startAt, _start) ? precOfAt(startAt) : DatePrec.year);
    final fine = prec == DatePrec.day || prec == DatePrec.hour || prec == DatePrec.minute;
    rows.add((
      word: '체결',
      at: _startUnknown ? null : _start,
      atText: startAt.isEmpty ? null : startAt,
      text: _startUnknown ? '미정' : whenText(_start, at: startAt),
      note: null,
      sub: fine && _start != null ? dayNote(_start!, lunar: AuxCalendarStore.shared?.lunar, withLunar: !isLunarAt(startAt)) : null,
    ));
    for (final step in const [('비준', 'ratified', 'ratifiedAt'), ('발효', 'effective', 'effectiveAt')]) {
      final v = detailNum(t, step.$2)?.toDouble();
      if (v == null) continue;
      final at = detailString(t, step.$3);
      rows.add((word: step.$1, at: v, atText: at.isEmpty ? null : at, text: whenText(v, at: at), note: null, sub: null));
    }
    final reason = treatyEndNames[detailString(t, 'endReason')];
    final endAt = detailString(x, 'endAt');
    if (_ongoing) {
      rows.add((word: '실효', at: null, atText: null, text: '아직 유효 (현재까지)', note: null, sub: null));
    } else if (_endUnknown) {
      rows.add((word: '실효', at: null, atText: null, text: '미정', note: reason, sub: null));
    } else if (_end != null) {
      rows.add((word: '실효', at: _end, atText: endAt.isEmpty ? null : endAt, text: whenText(_end, at: endAt), note: reason, sub: null));
    } else if (reason != null) {
      rows.add((word: '실효', at: null, atText: null, text: '날짜를 적지 않음', note: reason, sub: null));
    }

    return DetailBox(
      title: '날짜',
      children: [
        for (int i = 0; i < rows.length; i++)
          DetailPressable(
            onTap: rows[i].at == null ? null : () => _goToYear(rows[i].at!),
            semantics: '${rows[i].word} ${rows[i].text}',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(width: 34, child: Text(rows[i].word, style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w600, color: Ui.text))),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: rows[i].text,
                          children: [if (rows[i].note != null) TextSpan(text: ' ${rows[i].note!}', style: const TextStyle(fontSize: 12, color: Ui.text3, fontStyle: FontStyle.italic))],
                        ),
                        style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text),
                      ),
                      if (rows[i].sub != null) Text(rows[i].sub!, style: const TextStyle(fontSize: 11.5, height: 1.5, color: Ui.text3)),
                    ],
                  ),
                ),
                if (i > 0 && rows[i - 1].at != null && rows[i].at != null)
                  Text(
                    gapText(rows[i - 1].at!, rows[i].at!, aAt: rows[i - 1].atText, bAt: rows[i].atText),
                    style: const TextStyle(fontSize: 11, height: 1.5, color: Ui.text3),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// 설명 다음: 조항 · 관련. 조약이 아닌 사건은 '이 일을 끝낸 조약'만.
  List<Widget> _treatyBottom() {
    final t = _treaty;
    if (t == null) return _isEvent ? _treatyRelated(null) : const [];
    return [..._treatyArticles(t), ..._treatyRelated(t)];
  }

  List<Widget> _treatyArticles(Map<String, dynamic> t) {
    final list = detailList(t, 'articles');
    if (list.isEmpty) return const [];
    return [
      DetailBox(
        title: '조항',
        small: '${list.length}',
        children: [for (final a in list) _Article(a)],
      ),
    ];
  }

  /// 끝낸 전쟁 · 대체한 옛 조약 · 대체한 새 조약 · 끝낸 조약 · 장소 · 언어.
  List<Widget> _treatyRelated(Map<String, dynamic>? t) {
    final related = detailList(x, 'x_related');
    final place = t == null ? '' : detailString(t, 'place');
    final languages = t == null ? const <String>[] : detailStrings(t, 'languages');
    if (related.isEmpty && place.isEmpty && languages.isEmpty) return const [];
    return [
      DetailBox(
        title: t != null ? '관련' : '조약',
        children: [
          if (related.isNotEmpty)
            DetailSuccList([
              for (final r in related)
                DetailSuccRow(
                  badge: detailString(r, 'tag'),
                  name: detailString(r, 'title').isEmpty ? detailString(r, 'name') : detailString(r, 'title'),
                  years: detailString(r, 'when'),
                  onTap: detailString(r, 'uid').isEmpty ? null : () => ctx.open(detailString(r, 'uid')),
                ),
            ]),
          if (place.isNotEmpty || languages.isNotEmpty)
            DetailDefs([
              if (place.isNotEmpty) DetailDef('장소', Text(place)),
              if (languages.isNotEmpty) DetailDef('언어', Text(languages.join(' · '))),
            ]),
        ],
      ),
    ];
  }

  // ── 거드는 것 ──────────────────────────────────────────────────────────────────────────────

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

  /// 칸 하나의 기간 글 — 끝을 비운 칸은 풀어 둔 끝(`endY`)으로.
  String _cellWhen(Map<String, dynamic> c) {
    final start = detailNum(c, 'start')?.toDouble();
    final end = (detailNum(c, 'end') ?? detailNum(c, 'endY'))?.toDouble();
    return rangeText(
      start: start,
      startAt: detailString(c, 'startAt').isEmpty ? null : detailString(c, 'startAt'),
      end: end,
      endAt: detailString(c, 'endAt').isEmpty ? null : detailString(c, 'endAt'),
      startUnknown: c['startUnknown'] == true,
      endUnknown: c['endUnknown'] == true,
    );
  }

  /// 🎯 이 위치로 — 이 항목이 통틀어 차지하는 범위(이설 · 연대 폭까지)로.
  void _focus() {
    final lo = (detailNum(x, 'spanMin') ?? detailNum(x, 'start'))?.toDouble();
    final hi = (detailNum(x, 'spanMax') ?? detailNum(x, 'endY') ?? detailNum(x, 'end') ?? lo)?.toDouble();
    if (lo == null || hi == null) return;
    ctx.goTo(minutesOfT(lo), minutesOfT(hi == lo ? lo + 1 : hi), ring: ctx.uid);
  }

  /// 다른 견해 · 조약의 날짜 줄 — 그 해로 데려간다.
  void _goToYear(double t) => ctx.goTo(minutesOfT(t), minutesOfT(t + 1), ring: ctx.uid);
}

/// 관점 탭 한 개.
class _LensTab extends StatelessWidget {
  const _LensTab(this.text, {required this.on, required this.onTap});
  final String text;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DetailPressable(
    onTap: onTap,
    radius: 8,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    background: on ? Ui.accentSoft : Ui.surface2,
    semantics: text,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12.5, height: 1.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? Ui.accent : Ui.text2),
    ),
  );
}

/// 당사국 좌우 두 칸 사이의 파선.
class _SideDivider extends StatelessWidget {
  const _SideDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: CustomPaint(size: const Size(1, double.infinity), painter: _DashPainter()),
  );
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Ui.lineStrong
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 6) {
      canvas.drawLine(Offset(0.5, y), Offset(0.5, (y + 3).clamp(0, size.height)), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}

/// 조항 한 줄 — 제목이 없고 본문이 60자 이하면 접지 않는다.
class _Article extends StatefulWidget {
  const _Article(this.article);
  final Map<String, dynamic> article;

  @override
  State<_Article> createState() => _ArticleState();
}

class _ArticleState extends State<_Article> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    final text = detailString(a, 'text'), title = detailString(a, 'title'), no = detailString(a, 'no');
    final tag = articleTagNames[detailString(a, 'tag')];
    final folds = text.isNotEmpty && (title.isNotEmpty || text.length > 60);
    final head = title.isNotEmpty ? title : (folds && text.length > 36 ? '${text.substring(0, 36)}…' : text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DetailPressable(
          onTap: folds ? () => setState(() => _open = !_open) : null,
          radius: 6,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          semantics: head,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (no.isNotEmpty) ...[
                Text(no, style: const TextStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w700, color: Ui.text2)),
                const SizedBox(width: 6),
              ],
              Expanded(child: Text(head, style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text))),
              if (tag != null) ...[
                const SizedBox(width: 6),
                Text(tag, style: const TextStyle(fontSize: 11, height: 1.5, color: Ui.text3)),
              ],
            ],
          ),
        ),
        if (folds && _open)
          Container(
            margin: const EdgeInsets.fromLTRB(6, 2, 6, 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: const BoxDecoration(border: Border(left: BorderSide(color: Ui.lineStrong, width: 2))),
            child: DetailDesc(text, small: true),
          ),
      ],
    );
  }
}
