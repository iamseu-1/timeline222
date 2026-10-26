import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shell/look.dart';
import 'app_bus.dart';
import 'date_text.dart';
import 'detail_echo.dart';
import 'names_display.dart';
import 'detail_format3.dart';
import 'detail_item.dart' show certaintyNames, namedOf;
import 'detail_shell.dart';
import 'doc_window.dart' show DocChips;
import 'kin/family_window.dart' show FamilyRequest, familySlot;
import 'kin/kin_head.dart' show KinUi, kinDecode, kinPersonTarget, kinRevealIn, kinYear;
import 'kin/kin_record.dart';
import 'person_titles.dart';

// ════════════════════════════════════════════════════════════════════════════════════════════
//  인물 창과 가문 창 — 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md` 2-3절의 ㈒ 와 ㈓.
//
//  묶음이 나오는 차례는 지금 연표의 `figureDetailHTML`(js/viewer.js:1272) ·
//  `houseDetailHTML`(js/viewer.js:1540) 그대로이고, **비어 있는 묶음은 아예 그리지 않는다.**
//
//  ── 쓰는 법 ───────────────────────────────────────────────────────────────────────────────
//    registerPeopleDetail();               // 앱을 세울 때 한 번 — 갈래 'figure' · 'house'를 이 파일이 맡는다
//    …  DetailHost(bus: bus)               // 나머지는 뼈대가 한다
//
//    창 하나만 따로 띄울 때(검사 · 미리 보기)는 [AppBus]와 항목 기록만 주면 된다:
//      FigureDetail.of(bus: bus, entity: 푼_항목_기록)
//      HouseDetail.of(bus: bus, entity: 푼_가문_기록)
//
//  ── 이 창이 항목 기록에서 읽는 것(계약 6-9절 · 내보내기가 미리 풀어 둔 `x_…` 칸) ──────────────
//    인물: x_services · x_events · x_signed · x_leaders · x_rulers · x_spots
//          (본문의 `services`는 그 줄의 이설 · 연대 폭을 적는 작은 상자에만 쓴다 — 차례가 x_services와 같다)
//    가문: x_path · x_branches · x_nations · x_members
//    형식 3(계약 초안 6-9 다): 인물 x_names · x_person(다스린 칸 · 혈연 · 속한 단체), 가문 x_names · x_surname(성의 이름 · 원어).
//          없으면 그 줄이 없고 옛 기록은 지금 그림 그대로다.
//    스키마 4(계약 1-1 · 리메이크 4단계 과제 4 걸음 3 — 사람 창): 인물 x_titles → '칭호' 묶음(객체 · 직위 · 때 · 지위 — 누르면 그 객체의 칸 창).
//          있으면 같은 칸을 두 번 적지 않게 x_person의 '다스린 칸' 줄을 빼고 그 칸 이름은 칭호 줄의 꼬리 글로 옮긴다. 없으면 창은 지금 그대로다.
//    둘 다: x_docs — 하위 문서 칩([DocChips]). 지금 연표도 인물 창은 '같은 시기의 지도자' 다음,
//           가문 창은 '구성원' 다음에 둔다(js/viewer.js:1329 · 1594).
//
//  ── 앱 틀이 채워 주거나 들어야 하는 곳 ───────────────────────────────────────────────────────
//    bus.slot('tracks')  = {'mw-coast': {'name': '유리해안', 'color': 0xa0bcc5}, …}  (기본 상세와 같은 표)
//    bus.slot('spots')   ← 인물 창이 열릴 때 `x_spots`를 [{uid, start, end}](분)로 싣는다 · 닫으면 비운다
//    bus.slot('house')   ← 가문 창이 열릴 때 가문 id를 싣는다(명세 3-5 — 그 가문의 칸만 진해진다) · 닫으면 비운다
//    bus.slot('echo')    ← '같은 시기를 타국에도' 스위치의 값(bool) — 인물 창의 메아리 자리([EchoSlot])가 넣는다
//    bus.slot('doc')     ← `📄 문서`를 누를 때 항목의 uid(문서 창은 이 묶음 밖)
//
//  ── D1(승계표 · 세계표 · 가문 — 확정 설계 3 · 4 · 5-3 · 8-1)이 더한 것 ─────────────────────────
//    가문 창: 다스린 기간 막대(x_eras) · `세계표` 단추(x_kin) · 구성원 상한(x_memberCount) · 가문 조명(x_under · x_spots)
//    성씨 창(갈래 `surname`): 성씨 배지 · 가문 수 · 다스린 나라 수 · 막대 · 가문 칩 — 그 성의 가문 모두를 조명(x_spots)
//    계보 전용 인물 창(갈래 `lineage`): 파 · 부모 · 자식 줄을 뼈대(x_kin)에서 · `세계표에서 보기` · `승계표에서 보기`
//          — 고르지도 흐리게 하지도 않는다(lane · pick 거짓). 생몰을 적지 않았으면 생몰 줄이 없다(비움 ≠ 미상).
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 갈래 `figure`(인물) · `house`(가문) · `lineage`(계보 전용 인물) · `surname`(성씨)을 이 파일이 맡는다.
void registerPeopleDetail() {
  DetailHost.register('figure', FigureDetail.new);
  DetailHost.register('house', HouseDetail.new);
  DetailHost.register('lineage', LineageFigureDetail.new);
  DetailHost.register('surname', SurnameDetail.new);
}

/// 가문 구성원의 역할 딱지(지금 연표의 `HOUSE_ROLES`).
const houseRoleNames = {'period': '국성', 'dynasty': '왕조', 'leader': '지도자', 'cabinet': '내각', 'figure': '인물'};

/// 앱 틀 없이 창 하나만 띄울 때의 [DetailContext] — [AppBus]와 푼 항목 기록만 있으면 된다.
DetailContext peopleContext({
  required AppBus bus,
  required Map<String, dynamic> entity,
  String? uid,
  String kind = '',
  VoidCallback? onClose,
}) {
  final id = uid ?? detailString(entity, 'uid');
  final k = kind.isNotEmpty ? kind : (detailString(entity, 'itemKind').isNotEmpty ? detailString(entity, 'itemKind') : (id.startsWith('house:') ? 'house' : 'figure'));
  return DetailContext(
    bus: bus,
    uid: id,
    kind: k,
    cell: null,
    json: entity,
    branch: pickDetailKind(kind: k, json: entity),
    fresh: true,
    close: onClose ?? bus.clearSelection,
    askEntity: (other) async {
      try {
        final answer = await bus.ask({'op': 'entity', 'uid': other});
        final raw = answer['json'];
        if (raw is Map) return raw.cast<String, dynamic>();
        if (raw is String && raw.isNotEmpty) {
          final v = jsonDecode(raw);
          if (v is Map) return v.cast<String, dynamic>();
        }
      } catch (_) {
        // 못 찾은 항목은 없는 것으로 — 목록 줄이 눌리지 않을 뿐이다.
      }
      return null;
    },
  );
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  1. 인물 창 (명세 2-3 ㈒)
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 인물 상세 — 이름 · 다른 이름 · 생몰(향년) · 활동 · 활동 기록 · 관련 사건 · 서명한 조약 · 같은 시기의 지도자.
class FigureDetail extends StatefulWidget {
  const FigureDetail(this.ctx, {super.key});

  /// 앱 틀 없이 띄울 때 — 받는 것은 [AppBus]와 푼 항목 기록뿐이다.
  FigureDetail.of({required AppBus bus, required Map<String, dynamic> entity, String? uid, VoidCallback? onClose, super.key})
    : ctx = peopleContext(bus: bus, entity: entity, uid: uid, kind: 'figure', onClose: onClose);

  final DetailContext ctx;

  @override
  State<FigureDetail> createState() => _FigureDetailState();
}

class _FigureDetailState extends State<FigureDetail> {
  /// 이 창이 켠 기간 조명 — 닫을 때 제 것만 끈다(다음 창이 이미 켰으면 두고 간다).
  Object? _litSpots;

  DetailContext get ctx => widget.ctx;
  Map<String, dynamic> get x => ctx.json;

  @override
  void initState() {
    super.initState();
    _light();
  }

  @override
  void didUpdateWidget(FigureDetail old) {
    super.didUpdateWidget(old);
    if (old.ctx.uid != ctx.uid) _light();
  }

  @override
  void dispose() {
    final slot = ctx.slot('spots');
    if (identical(slot.value, _litSpots)) slot.value = null;
    super.dispose();
  }

  /// 섬긴 띠마다 그 기간을 밝힌다(명세 2-2의 갈래 `figure` · 3-3).
  void _light() {
    final spots = detailList(x, 'x_spots');
    _litSpots = spots.isEmpty ? null : spots;
    ctx.slot('spots').value = _litSpots;
  }

  // ── 값 꺼내기 ──────────────────────────────────────────────────────────────────────────────

  double? get _start => detailNum(x, 'start')?.toDouble();
  double? get _endY => (detailNum(x, 'endY') ?? detailNum(x, 'end'))?.toDouble();
  double? get _birth => detailNum(x, 'birth')?.toDouble();
  double? get _death => detailNum(x, 'death')?.toDouble();
  bool get _ongoing => x['ongoing'] == true;
  bool get _startUnknown => x['startUnknown'] == true;
  bool get _endUnknown => x['endUnknown'] == true;
  String get _startAt => detailString(x, 'startAt');
  String get _endAt => detailString(x, 'endYAt').isNotEmpty ? detailString(x, 'endYAt') : detailString(x, 'endAt');

  List<Map<String, dynamic>> get _services => detailList(x, 'x_services');

  /// 본문의 활동 기록 — 이설 · 연대 폭이 여기에만 있다(`x_services`와 차례가 같다).
  List<Map<String, dynamic>> get _rawServices => detailList(x, 'services');

  /// 칭호 묶음(스키마 4 `x_titles` — 받은 차례 그대로 · 없거나 꼴이 다르면 빈 목록).
  List<PersonTitle> get _titles => PersonTitles.of(x);

  // ── 배지 ──────────────────────────────────────────────────────────────────────────────────

  List<Widget> _badges() {
    final out = <Widget>[];
    final track = namedOf(ctx.bus, 'tracks', detailString(x, 'track'));
    if (track != null) out.add(DetailBadge(track.name, color: track.color));

    final polityUid = detailString(x, 'polityUid');
    if (polityUid.isNotEmpty) {
      out.add(DetailBadge(detailString(x, 'polityName'), color: detailColor(x['polityColor']), onTap: () => ctx.open(polityUid)));
    }

    final role = detailString(x, 'role');
    out.add(DetailBadge('인물${role.isEmpty ? '' : ' · $role'}', dot: false, color: Ui.text3));

    final houseId = detailString(x, 'houseId');
    final houseName = detailString(x, 'houseName');
    if (houseId.isNotEmpty) {
      out.add(
        DetailBadge(
          houseName.endsWith('가문') ? houseName : '가문 $houseName',
          color: detailColor(x['houseColor']),
          onTap: () => ctx.open('house:$houseId', kind: 'house'),
        ),
      );
    } else if (detailString(x, 'house').isNotEmpty) {
      out.add(DetailBadge('가문 ${detailString(x, 'house')}', color: Ui.text3));
    }
    return out;
  }

  // ── 몸통 ──────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => DetailShell(
    onClose: ctx.close,
    badges: _badges(),
    body: [
      DetailTitle(detailString(x, 'name')),
      // 원어 머리 두 줄(10건 3 · 감독 결정 D2-1 A — 웹 namesHeadHTML(x.names, 'person') · 제목 바로 아래).
      NamesHead(bus: ctx.bus, head: x['x_nameHead'], old: x['x_names'], kind: NameKind.person),
      ..._akaLine(),
      ..._lifeLine(),
      _activeLine(),
      ..._activeUnknown(),
      ..._twins(),
      ..._personLines(),
      NamesRest(bus: ctx.bus, head: x['x_nameHead'], kind: NameKind.person),
      DetailDesc(detailString(x, 'description')),
      ..._titleBox(),
      ..._alternatives(),
      _serviceBox(),
      ..._echoSlot(),
      ..._events(),
      ..._signed(),
      ..._rulers(),
      // 하위 문서 칩은 지금 연표와 같은 자리 — '같은 시기의 지도자' 다음, 꼬리표 앞(js/viewer.js:1329).
      DocChips(bus: ctx.bus, uid: ctx.uid, json: ctx.json),
      ..._tags(),
      _defs(),
    ],
    foot: [
      DetailSmallButton('이 위치로', icon: LineGlyph.locate, onTap: _focus),
      if (detailString(x, 'wiki').isNotEmpty) DetailSmallButton('문서', icon: LineGlyph.file, onTap: () => ctx.slot('doc').value = ctx.uid),
    ],
  );

  /// 2. 다른 이름.
  List<Widget> _akaLine() {
    final aka = detailStrings(x, 'aka');
    if (aka.isEmpty) return const [];
    return [DetailAka('다른 이름: ${aka.join(' · ')}')];
  }

  /// 3. 생몰(향년) — 둘 다 없으면 줄이 없다.
  List<Widget> _lifeLine() {
    final life = _figureLife();
    return life.isEmpty ? const [] : [DetailWhen(life)];
  }

  /// `790년 ~ 906년 (향년 117세)` — 향년은 세는나이(햇수 차 + 1)이고 0~150세 사이일 때만 붙인다.
  String _figureLife() {
    final birth = _birth, death = _death;
    if (birth == null && death == null) return '';
    final b = birth == null ? '' : whenText(birth, at: _atOf('birthAt'));
    final d = death == null ? '' : whenText(death, at: _atOf('deathAt'));
    var age = '';
    if (birth != null && death != null) {
      final yb = civilAt(birth).year, yd = civilAt(death).year;
      final n = yd - yb - (yb < 0 && yd > 0 ? 1 : 0) + 1; // 0년이 없으므로 기원전 → 기원후는 한 해를 뺀다
      if (n > 0 && n < 150) age = ' (향년 $n세)';
    }
    return '$b ~ $d$age'.trim();
  }

  String? _atOf(String key) {
    final at = detailString(x, key);
    return at.isEmpty ? null : at;
  }

  /// 4. `활동 〈기간〉` — 생몰 줄이 있으면 그 아래 작은 글로, 없으면 이 줄이 날짜 줄이 된다.
  Widget _activeLine() {
    final text = '활동 ${_activeRange()}${_guessedNote()}';
    return _figureLife().isEmpty ? DetailWhen(text) : DetailAka(text);
  }

  String _activeRange() => rangeText(
    start: _start,
    startAt: _atOf('startAt'),
    end: _endY,
    endAt: _endAt.isEmpty ? null : _endAt,
    startUnknown: _startUnknown,
    endUnknown: _endUnknown,
    ongoing: _ongoing,
  );

  /// 짐작한 쪽만 밝힌다 — 한쪽 끝만 짐작했으면 적은 쪽 연도까지 짐작처럼 읽히지 않게.
  String _guessedNote() {
    final from = _rawServices.any((s) => s['given'] == true) ? '활동 기록' : '생몰';
    final startAuto = x['startAuto'] == true, endAuto = x['endAuto'] == true;
    if (startAuto && endAuto) return ' ($from에서 짐작)';
    if (startAuto) return ' (시작은 $from에서 짐작)';
    if (endAuto) return ' (끝은 $from에서 짐작)';
    return '';
  }

  /// 5. 활동 시기의 미정 안내 — 모르는 쪽이 연표의 어디에 놓였는지(칸 창과 같은 말).
  List<Widget> _activeUnknown() {
    final notes = [
      if (_startUnknown) cellUnknownStartNote(_start, at: _atOf('startAt')),
      if (_endUnknown) cellUnknownEndNote(_endY, at: _endAt.isEmpty ? null : _endAt),
    ];
    return notes.isEmpty ? const [] : [DetailRangeNote(notes.join(' · '))];
  }

  /// 6. `같은 이름의 지도자: …` — 누르면 그 칸 창.
  List<Widget> _twins() {
    final twins = detailList(x, 'x_leaders');
    if (twins.isEmpty) return const [];
    return [
      _LinkyLine(
        label: '같은 이름의 지도자: ',
        items: [
          for (final t in twins)
            (
              text: '${detailString(t, 'name')} ${detailString(t, 'label')}'.trim(),
              onTap: () => ctx.open(detailString(t, 'uid'), cell: detailString(t, 'ref')),
            ),
        ],
      ),
    ];
  }

  /// 7. 사람 글(형식 3 — 웹 `figurePersonHTML`): 다스린 칸(같은 이름의 지도자에 이미 있는 칸은 뺀다) → 혈연 → 속한 단체.
  /// 칭호 묶음(`x_titles` — [_titleBox])이 있으면 다스린 칸 줄은 없다: 둘 다 모델의 같은 사람 노드에서 모은 칸이고(다스린 칸 = 지도자 칸 ·
  /// 칭호 = 지도자 · 내각 칸 — 내보내기 entities.mjs) 칭호 묶음이 그 칸을 모두 품어, 같은 칸을 두 번 적지 않는다(리메이크 4단계 과제 4 걸음 3).
  List<Widget> _personLines() {
    final p = x['x_person'];
    if (p is! Map) return const [];
    final person = p.cast<String, dynamic>();
    final twins = {for (final t in detailList(x, 'x_leaders')) '${detailString(t, 'uid')}|${detailString(t, 'ref')}'};
    final ruled = [
      if (_titles.isEmpty)
        for (final q in detailList(person, 'ruled'))
          if (!twins.contains('${detailString(q, 'uid')}|${detailString(q, 'ref')}')) q,
    ];
    return [
      if (ruled.isNotEmpty)
        DetailLine([
          const DetailBit('다스린 칸: '),
          ...detailJoin([
            for (final q in ruled)
              [
                DetailBit.link(
                  '${detailString(q, 'name')} ${detailString(q, 'label')}'.trim(),
                  detailString(q, 'uid').isEmpty ? null : () => ctx.open(detailString(q, 'uid'), cell: detailString(q, 'ref')),
                ),
              ],
          ]),
        ]),
      ...detailKinLines(person, open: ctx.open),
      ...detailPersonGroupsLines(person, open: ctx.open),
    ];
  }

  /// 7-1. 칭호 묶음(리메이크 4단계 과제 4 걸음 3 — 사람 창 · 설계 4-3의 묶음 한 꼴): 이 사람이 앉은 지도자 · 내각 칸마다 한 줄 —
  /// 직위(딱지) · 객체 이름(누르면 그 객체의 칸 창 `leader:i` · `cabinet:i`) · 칸 이름과 지위(옅은 꼬리 글) · 때(오른쪽 끝). 차례는 받은 그대로(시작 차례 — 짓는 쪽의 몫).
  /// 메이커 사람 폼의 칭호 묶음(`HT.personTitles` — 객체 · 직위 · 해 · 지위)과 같은 칸이다. 없으면 묶음이 없다.
  /// 칸 이름(`남등왕` 따위)은 x_titles에 없어 빠진 '다스린 칸' 줄(x_person.ruled — 같은 객체 uid · 칸 참조)에서 옮겨 온다 — 줄을 빼도 잃는 글이 없게.
  List<Widget> _titleBox() {
    final list = _titles;
    if (list.isEmpty) return const [];
    final p = x['x_person'];
    final labels = {
      if (p is Map)
        for (final q in detailList(p.cast<String, dynamic>(), 'ruled')) '${detailString(q, 'uid')}|${detailString(q, 'ref')}': detailString(q, 'label'),
    };
    String? tail(PersonTitle t) {
      final parts = [labels['${t.uid}|${t.cellRef}'] ?? '', t.rank].where((s) => s.isNotEmpty).toList();
      return parts.isEmpty ? null : parts.join(' · ');
    }

    return [
      DetailBox(
        title: '칭호',
        small: '${list.length}',
        children: [
          DetailSuccList([
            for (final t in list)
              DetailSuccRow(
                badge: t.office.label.isEmpty ? null : t.office.label,
                name: t.name.isEmpty ? t.uid : t.name,
                trailing: tail(t),
                years: titleWhen(t),
                onTap: t.uid.isEmpty ? null : () => ctx.open(t.uid, cell: t.cellRef),
              ),
          ]),
        ],
      ),
    ];
  }

  /// 8. 다른 견해 — 인물은 생몰과 활동을 따로 적는다.
  List<Widget> _alternatives() {
    final alts = detailList(x, 'alternatives');
    if (alts.isEmpty) return const [];
    final base = _figureBase();
    return [
      DetailBox(
        title: '다른 견해',
        children: [_altList(alts, base, figure: true)],
      ),
    ];
  }

  /// 인물의 통설 연대 — 다른 견해가 비운 칸을 채우는 값(끝은 풀어 둔 활동 끝).
  Map<String, dynamic> _figureBase() => {
    'birth': _birth,
    'birthAt': detailString(x, 'birthAt'),
    'death': _death,
    'deathAt': detailString(x, 'deathAt'),
    'start': _start,
    'startAt': _startAt,
    'end': _endY,
    'endAt': _endAt,
    'ongoing': _ongoing,
    'startUnknown': _startUnknown,
    'endUnknown': _endUnknown,
  };

  /// 9. 활동 기록 — 비어 있어도 까닭 한 줄을 적는다(지금 연표와 같다).
  Widget _serviceBox() {
    final list = _services, raw = _rawServices;
    return DetailBox(
      title: '활동 기록',
      small: '${list.length}',
      children: [
        if (list.isEmpty)
          _cap('그 시기의 같은 트랙 정권을 찾지 못했습니다.')
        else
          DetailSuccList([for (int i = 0; i < list.length; i++) _serviceRow(list[i], i < raw.length ? raw[i] : const {})]),
        for (int i = 0; i < list.length && i < raw.length; i++) ..._serviceAlt(list[i], raw[i]),
      ],
    );
  }

  Widget _serviceRow(Map<String, dynamic> s, Map<String, dynamic> raw) {
    final office = detailString(s, 'office');
    final uid = detailString(s, 'uid');
    final tail = [
      ..._altTag(raw),
      if (detailString(s, 'track').isNotEmpty) detailString(s, 'track'),
      if (detailString(s, 'note').isNotEmpty) detailString(s, 'note'),
      if (s['missing'] == 1 || s['missing'] == true) '연표에서 찾지 못한 정권',
      if (s['auto'] == 1 || s['auto'] == true) '활동 시기로 짐작한 자리',
    ];
    return DetailSuccRow(
      badge: office.isEmpty ? '활동' : office,
      name: detailString(s, 'name'),
      trailing: tail.isEmpty ? null : tail.join(' · '),
      years: detailString(s, 'when'),
      onTap: uid.isEmpty ? null : () => ctx.open(uid),
    );
  }

  /// 그 줄의 이설 · 모호함 작은 상자(`.alt-sub`).
  List<Widget> _serviceAlt(Map<String, dynamic> s, Map<String, dynamic> raw) {
    final alts = detailList(raw, 'alternatives');
    final notes = _uncertainNotes(raw);
    if (alts.isEmpty && notes.isEmpty) return const [];
    final office = detailString(s, 'office');
    final base = <String, dynamic>{
      'start': detailNum(raw, 'from')?.toDouble(),
      'startAt': detailString(raw, 'fromAt'),
      'end': detailNum(raw, 'to')?.toDouble(),
      'endAt': detailString(raw, 'toAt'),
      'startUnknown': raw['fromUnknown'] == true,
      'endUnknown': raw['toUnknown'] == true,
      'ongoing': _ongoing && detailNum(raw, 'to') == detailNum(x, 'endY'),
    };
    return [
      _AltSub(
        title: '${detailString(s, 'name')}${office.isEmpty ? '' : ' $office'} 활동 기록',
        small: alts.isEmpty ? null : '다른 견해 ${alts.length}개',
        notes: notes,
        list: alts.isEmpty ? null : _altList(alts, base),
      ),
    ];
  }

  /// 확실성 · 연대 폭 안내 줄(`uncNotesHTML`).
  List<String> _uncertainNotes(Map<String, dynamic> u) {
    final cert = detailString(u, 'certainty');
    final out = <String>[
      if (cert.isNotEmpty && cert != 'accepted') '연대의 확실성 — ${certaintyNames[cert] ?? cert}',
    ];
    for (final pair in const [('시작', 'startRange'), ('끝', 'endRange')]) {
      final v = u[pair.$2];
      if (v is List && v.length >= 2 && v[0] is num && v[1] is num) {
        out.add(rangeNote(pair.$1, (v[0] as num).toDouble(), (v[1] as num).toDouble()));
      }
    }
    return out;
  }

  /// 목록 줄의 작은 딱지 — `이설 n` · `연대 폭`(확실성이 추정 · 전승이면 그 이름).
  List<String> _altTag(Map<String, dynamic> c) {
    if (c.isEmpty) return const [];
    final n = detailList(c, 'alternatives').length;
    final cert = detailString(c, 'certainty');
    final fuzzy = cert == 'estimated' || cert == 'legend' || c['startRange'] != null || c['endRange'] != null;
    return [
      if (n > 0) '이설 $n',
      if (fuzzy) (cert == 'estimated' || cert == 'legend' ? (certaintyNames[cert] ?? cert) : '연대 폭'),
    ];
  }

  /// 10. 그려지는 활동이 있으면 메아리 자리(스위치와 '같은 시기 타국' 묶음).
  /// 인물 창은 `always`가 아니다 — 스위치를 켰을 때만 강조를 걸고 그 강조를 사건 배치에 쓰지 않는다(명세 3-4).
  List<Widget> _echoSlot() {
    final spots = detailList(x, 'x_spots');
    if (spots.isEmpty) return const [];
    return [
      EchoSlot(
        bus: ctx.bus,
        spots: spots,
        always: false,
        color: detailColor(x['polityColor'], Ui.text3),
        onOpen: ctx.open,
      ),
    ];
  }

  /// 11. 관련 사건.
  List<Widget> _events() {
    final list = detailList(x, 'x_events');
    if (list.isEmpty) return const [];
    return [
      DetailBox(
        title: '관련 사건',
        small: '${list.length}',
        children: [
          DetailYearEvents([
            for (final e in list)
              DetailYearRow(
                color: detailColor(e['color']),
                when: detailString(e, 'when'),
                title: detailString(e, 'title'),
                diamond: e['treaty'] == 1 || e['treaty'] == true,
                onTap: () => ctx.open(detailString(e, 'uid')),
              ),
          ]),
        ],
      ),
    ];
  }

  /// 12. 서명한 조약.
  List<Widget> _signed() {
    final list = detailList(x, 'x_signed');
    if (list.isEmpty) return const [];
    return [
      DetailBox(
        title: '서명한 조약',
        small: '${list.length}',
        children: [
          DetailYearEvents([
            for (final t in list)
              DetailYearRow(
                color: detailColor(t['color']),
                when: detailString(t, 'when'),
                title: detailString(t, 'title'),
                tail: '${detailString(t, 'party')}${detailString(t, 'role').isEmpty ? '' : ' · ${detailString(t, 'role')}'}',
                diamond: true,
                onTap: () => ctx.open(detailString(t, 'uid')),
              ),
          ]),
        ],
      ),
    ];
  }

  /// 13. 같은 시기의 지도자 — 섬긴 기간과 지도자 칸의 `[lo, hi)`가 겹치는 칸.
  List<Widget> _rulers() {
    final list = detailList(x, 'x_rulers');
    if (list.isEmpty) return const [];
    final many = _services.where((s) => detailString(s, 'uid').isNotEmpty).length > 1;
    return [
      DetailBox(
        title: '같은 시기의 지도자',
        small: '${list.length}',
        children: [
          DetailKidList([
            for (final r in list)
              DetailKidRow(
                year: detailString(r, 'when'),
                name: '${detailString(r, 'label')}${many ? ' · ${detailString(r, 'name')}' : ''}',
                onTap: () => ctx.open(detailString(r, 'uid'), cell: detailString(r, 'ref')),
              ),
          ]),
        ],
      ),
    ];
  }

  /// 15. 태그.
  List<Widget> _tags() {
    final tags = detailStrings(x, 'tags');
    if (tags.isEmpty) return const [];
    return [
      DetailTags([for (final t in tags) '#$t']),
    ];
  }

  /// 16. dl — 제공 · 중요도 · 출처.
  Widget _defs() {
    final importance = (detailNum(x, 'importance') ?? 2).toInt().clamp(1, 3);
    return DetailDefs([
      DetailDef('제공', Text(detailString(x, 'packName'))),
      DetailDef('중요도', Text('${'★' * importance}${'☆' * (3 - importance)}')),
      if (detailString(x, 'source').isNotEmpty) DetailDef('출처', Text(detailString(x, 'source'))),
    ]);
  }

  /// 🎯 이 위치로 — 이 인물이 통틀어 차지하는 범위(생몰 · 활동 · 이설).
  void _focus() {
    final lo = (detailNum(x, 'spanMin') ?? detailNum(x, 'birth') ?? detailNum(x, 'start'))?.toDouble();
    final hi = (detailNum(x, 'spanMax') ?? detailNum(x, 'death') ?? detailNum(x, 'endY') ?? lo)?.toDouble();
    if (lo == null || hi == null) return;
    ctx.goTo(minutesOfT(lo), minutesOfT(hi == lo ? lo + 1 : hi), ring: ctx.uid);
  }

  // ── 다른 견해 목록 만들기 ───────────────────────────────────────────────────────────────────

  /// 첫 줄은 이 연표가 쓰는 연대, 그다음은 이설마다 채운 연대(비운 쪽은 통설 값).
  Widget _altList(List<Map<String, dynamic>> alts, Map<String, dynamic> base, {bool figure = false}) {
    final keys = figure ? const ['start', 'end', 'birth', 'death'] : const ['start', 'end'];
    final baseAt = _baseAt(base);
    return DetailAltList([
      DetailAltRow(
        when: _baseWhen(base, figure: figure),
        why: '이 연표가 쓰는 연대',
        main: true,
        onTap: baseAt == null ? null : () => _goToYear(baseAt),
      ),
      for (final a in alts) _altRow(a, base, keys, figure: figure),
    ]);
  }

  double? _baseAt(Map<String, dynamic> base) {
    final start = detailNum(base, 'start')?.toDouble(), end = detailNum(base, 'end')?.toDouble();
    if (base['startUnknown'] != true && start != null) return start;
    if (base['endUnknown'] != true && base['ongoing'] != true && end != null) return end;
    return null;
  }

  String _baseWhen(Map<String, dynamic> base, {required bool figure}) {
    final range = rangeText(
      start: detailNum(base, 'start')?.toDouble(),
      startAt: _nullable(detailString(base, 'startAt')),
      end: detailNum(base, 'end')?.toDouble(),
      endAt: _nullable(detailString(base, 'endAt')),
      startUnknown: base['startUnknown'] == true,
      endUnknown: base['endUnknown'] == true,
      ongoing: base['ongoing'] == true,
    );
    if (!figure) return range;
    final birth = detailNum(base, 'birth')?.toDouble(), death = detailNum(base, 'death')?.toDouble();
    final life = birth == null && death == null
        ? ''
        : '생몰 ${birth == null ? '' : '${whenText(birth, at: _nullable(detailString(base, 'birthAt')))} '}~${death == null ? '' : ' ${whenText(death, at: _nullable(detailString(base, 'deathAt')))}'}';
    return [if (life.isNotEmpty) life, '활동 $range'].join(' · ');
  }

  DetailAltRow _altRow(Map<String, dynamic> a, Map<String, dynamic> base, List<String> keys, {required bool figure}) {
    final f = _AltFill(a, base, keys);
    final why = '${detailString(a, 'label')}${detailString(a, 'source').isEmpty ? '' : ' · ${detailString(a, 'source')}'}';
    final flipped = f.flipped;
    final note = [
      if (detailString(a, 'note').isNotEmpty) detailString(a, 'note'),
      if (flipped) '비운 쪽을 이 연표의 연대로 채우면 앞뒤가 뒤집혀 연표에는 그리지 않습니다',
    ].join(' · ');
    final at = flipped ? null : f.pickedAt;
    return DetailAltRow(
      when: f.dated ? f.text(figure: figure) : '',
      why: why,
      note: note.isEmpty ? null : note,
      onTap: at == null ? null : () => _goToYear(at),
    );
  }

  void _goToYear(double t) => ctx.goTo(minutesOfT(t), minutesOfT(t + 1), ring: ctx.uid);
}

/// 칭호 한 줄의 때(인물 창 '칭호' 묶음): 칸의 시작 · 끝(분)을 창의 해 글로 — `1420년 ~ 1455년`(해 첫날이 아니면 날까지 · 끝이 시작과 같으면 하나).
/// 셈하지 못한 쪽(null — JS의 NaN)은 비우고(`1420년` · `~ 1455년`), 둘 다 없으면 빈 글.
String titleWhen(PersonTitle t) {
  String at(int? minutes) => minutes == null ? '' : whenText(tOfMinutes(minutes.toDouble()));
  final s = at(t.start), e = at(t.end);
  if (s.isEmpty) return e.isEmpty ? '' : '~ $e';
  return e.isEmpty || e == s ? s : '$s ~ $e';
}

/// 이설 하나를 통설 값으로 채운 것(지금 연표의 `HT.altSpan`).
class _AltFill {
  _AltFill(this.alt, this.base, this.keys) {
    for (final k in keys) {
      final mine = alt[k] != null || (k == 'end' && alt['ongoing'] == true);
      own[k] = mine;
      final src = mine ? alt : base;
      value[k] = detailNum(src, k)?.toDouble();
      at[k] = _nullable(detailString(src, '${k}At'));
      if ((k == 'start' || k == 'end') && !mine && base['${k}Unknown'] == true) unknown[k] = true;
    }
    ongoing = alt['ongoing'] == true || (own['end'] != true && base['ongoing'] == true);
    if (ongoing) {
      value['end'] = null;
      at['end'] = null;
    }
  }

  final Map<String, dynamic> alt, base;
  final List<String> keys;
  final own = <String, bool>{}, unknown = <String, bool>{};
  final value = <String, double?>{}, at = <String, String?>{};
  bool ongoing = false;

  /// 날짜가 적힌 이설인가(글만 있는 견해가 아닌가).
  bool get dated =>
      alt['start'] != null || alt['end'] != null || alt['ongoing'] == true || alt['birth'] != null || alt['death'] != null;

  /// 비운 쪽을 통설 값으로 채우면 앞뒤가 뒤집히는가 — 그런 이설은 연표에 그리지 않아 누를 수도 없다.
  bool get flipped {
    for (final pair in const [('start', 'end'), ('birth', 'death')]) {
      if (!keys.contains(pair.$1)) continue;
      if (pair.$2 == 'end' && ongoing) continue;
      if (unknown[pair.$1] == true || unknown[pair.$2] == true) continue;
      final lo = value[pair.$1], hi = value[pair.$2];
      if (lo == null || hi == null) continue;
      final bound = endIn(endY: hi, endAt: at[pair.$2]);
      if (bound != null && bound < lo) return true;
    }
    return false;
  }

  /// 누르면 갈 해 — 이설이 스스로 적은 쪽(없으면 채운 시작).
  double? get pickedAt {
    for (final k in keys) {
      if (own[k] == true && value[k] != null) return value[k];
    }
    return dated ? value['start'] : null;
  }

  String _side(String k) {
    if (unknown[k] == true) return '미정';
    if (k == 'end' && ongoing) return '현재';
    final v = value[k];
    return v == null ? '' : whenText(v, at: at[k]);
  }

  String get _range {
    final hasEnd = ongoing || unknown['end'] == true || (value['end'] != null && value['end'] != value['start']);
    return hasEnd ? '${_side('start')} ~ ${_side('end')}' : _side('start');
  }

  String get _life {
    final b = _side('birth'), d = _side('death');
    return '생몰 ${b.isEmpty ? '' : '$b '}~${d.isEmpty ? '' : ' $d'}';
  }

  /// 목록에 적는 연대 글 — 인물은 생몰과 활동을 따로, 이설이 적은 쪽만.
  String text({required bool figure}) {
    if (!figure) return _range;
    return [
      if (own['birth'] == true || own['death'] == true) _life,
      if (own['start'] == true || own['end'] == true) '활동 $_range',
    ].join(' · ');
  }
}

String? _nullable(String s) => s.isEmpty ? null : s;

// ────────────────────────────────────────────────────────────────────────────────────────────
//  2. 가문 창 (명세 2-3 ㈓)
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 가문 상세 — 성 · 본관 · 시조 · 본가와 분가 · 국성으로 삼은 나라 · 나라별 구성원.
/// **연표를 흐리게 하지 않는다**(갈래 `house`의 `pick: false` · 명세 9절 ㈐-6) — 그 가문의 칸만 진해진다.
class HouseDetail extends StatefulWidget {
  const HouseDetail(this.ctx, {super.key});

  /// 앱 틀 없이 띄울 때 — 받는 것은 [AppBus]와 푼 가문 기록뿐이다.
  HouseDetail.of({required AppBus bus, required Map<String, dynamic> entity, String? uid, VoidCallback? onClose, super.key})
    : ctx = peopleContext(bus: bus, entity: entity, uid: uid, kind: 'house', onClose: onClose);

  final DetailContext ctx;

  @override
  State<HouseDetail> createState() => _HouseDetailState();
}

class _HouseDetailState extends State<HouseDetail> {
  Object? _litHouse, _litSpots;

  DetailContext get ctx => widget.ctx;
  Map<String, dynamic> get x => ctx.json;

  /// 가문의 id — `house:h-coast-0` 에서 앞머리를 뗀 것.
  String get _houseId {
    final id = detailString(x, 'id');
    if (id.isNotEmpty) return id;
    return ctx.uid.startsWith('house:') ? ctx.uid.substring('house:'.length) : ctx.uid;
  }

  @override
  void initState() {
    super.initState();
    _light();
  }

  @override
  void didUpdateWidget(HouseDetail old) {
    super.didUpdateWidget(old);
    if (old.ctx.uid != ctx.uid) _light();
  }

  @override
  void dispose() {
    final slot = ctx.slot('house');
    if (identical(slot.value, _litHouse)) slot.value = null;
    final spots = ctx.slot('spots');
    if (_litSpots != null && identical(spots.value, _litSpots)) spots.value = null;
    super.dispose();
  }

  /// 성씨 사전의 그 성(형식 3 `x_surname` = `{uid?, name, names?}`) — 없으면 빈 표.
  Map<String, dynamic> get _surname {
    final v = x['x_surname'];
    return v is Map ? v.cast<String, dynamic>() : const {};
  }

  /// 성의 이름 — 성을 id로 적었어도 사전의 이름으로(웹 `sn ? sn.name : h.surname`).
  String get _surnameName => detailString(_surname, 'name');

  /// 그 가문의 지도자 · 내각 · 왕조 칸과 인물 막대가 진해진다(명세 3-5).
  /// D1 결정 7 A: 아래 파가 있으면 파까지 함께(`x_under`) · 그 가문이 자리에 있던 기간을 모든 나라의 띠에 조명(`x_spots`).
  void _light() {
    final under = detailStrings(x, 'x_under');
    _litHouse = under.length > 1 ? {'house': _houseId, 'houses': under} : _houseId;
    ctx.slot('house').value = _litHouse;
    final spots = detailList(x, 'x_spots');
    if (spots.isNotEmpty) {
      _litSpots = spots;
      ctx.slot('spots').value = spots;
    }
  }

  /// 세계표 자리(D1-E ④ — `{key, at?, chunk?, n, gens, branches}`). 없으면 null.
  Map<String, dynamic>? get _kin => x['x_kin'] is Map ? (x['x_kin'] as Map).cast<String, dynamic>() : null;

  void _openFamily() {
    final kin = _kin;
    if (kin == null) return;
    final at = detailNum(kin, 'at');
    ctx.slot(familySlot).value = FamilyRequest(kin: detailString(kin, 'key'), house: ctx.uid, at: at == null ? -1 : at.toInt());
  }

  @override
  Widget build(BuildContext context) => DetailShell(
    onClose: ctx.close,
    badges: [
      DetailBadge('가문', color: detailColor(x['color'])),
      if (detailString(x, 'surname').isNotEmpty) DetailBadge('성 ${_surnameName.isNotEmpty ? _surnameName : detailString(x, 'surname')}'),
      if (detailString(x, 'seat').isNotEmpty) DetailBadge('본관 ${detailString(x, 'seat')}'),
    ],
    body: [
      DetailTitle(detailString(x, 'name')),
      // 원어 머리 두 줄 · 성의 원어 한 줄(10건 3 · 감독 결정 D2-1 A — 웹 namesHeadHTML(h.names, 'polity') · namesLineHTML(sn.names, 'polity', '성 X — ')).
      NamesHead(bus: ctx.bus, head: x['x_nameHead'], old: x['x_names'], kind: NameKind.polity),
      if (_surnameName.isNotEmpty) NamesLine(bus: ctx.bus, lead: [DetailBit('성 $_surnameName — ')], head: x['x_surnameHead'], old: _surname['names'], kind: NameKind.polity),
      if (detailString(x, 'founder').isNotEmpty) DetailAka('시조 ${detailString(x, 'founder')}'),
      if (x['auto'] == true) const DetailRangeNote('가문 목록에 없는 이름이라, 적힌 이름 그대로 가문으로 묶었습니다'),
      NamesRest(bus: ctx.bus, head: x['x_nameHead'], kind: NameKind.polity),
      DetailDesc(detailString(x, 'description')),
      // 다스린 기간 막대(D1 결정 7 A — 가문 창 맨 위 상자).
      if (detailList(x, 'x_eras').isNotEmpty)
        DetailBox(
          title: '다스린 기간',
          children: [KinErasBars(rows: detailList(x, 'x_eras'), houseColor: detailColor(x['color']), onRow: (lo, hi) => ctx.goTo(lo, hi))],
        ),
      ..._treeBox(),
      ..._nationBox(),
      _memberBox(),
      // 하위 문서 칩 — 지금 연표의 `houseDetailHTML`도 '구성원' 다음, '제공' 앞에 둔다(js/viewer.js:1594).
      DocChips(bus: ctx.bus, uid: ctx.uid, json: x),
      DetailDefs([
        DetailDef('제공', Text(detailString(x, 'packName').isEmpty ? '가문 목록에 없음' : detailString(x, 'packName'))),
      ]),
    ],
    foot: [
      if (detailString(x, 'wiki').isNotEmpty) DetailSmallButton('문서', icon: LineGlyph.file, onTap: () => ctx.slot('doc').value = ctx.uid),
      if (_kin != null) DetailSmallButton('세계표', onTap: _openFamily),
      DetailSmallButton('닫기', onTap: ctx.close),
    ],
  );

  /// 본가 · 분가 — 본가에서 이 가문까지의 길과 갈라져 나간 분가.
  List<Widget> _treeBox() {
    final path = detailList(x, 'x_path'), branches = detailList(x, 'x_branches');
    if (path.length <= 1 && branches.isEmpty) return const [];
    return [
      DetailBox(
        title: '본가 · 분가',
        children: [
          if (path.length > 1) ...[
            _cap('본가에서 이 가문까지'),
            _PathChips(
              chips: [
                for (final q in path)
                  (
                    text: detailString(q, 'name'),
                    color: detailColor(q['color']),
                    onTap: detailString(q, 'uid') == ctx.uid ? null : () => ctx.open(detailString(q, 'uid'), kind: 'house'),
                  ),
              ],
            ),
          ],
          if (branches.isNotEmpty) ...[
            _cap('갈라져 나간 분가', '${branches.length}개'),
            DetailChipRow([
              for (final q in branches)
                DetailChip(
                  detailString(q, 'name'),
                  color: _chipTint(detailColor(q['color'])),
                  onTap: () => ctx.open(detailString(q, 'uid'), kind: 'house'),
                ),
            ], top: 0),
          ],
        ],
      ),
    ];
  }

  /// 국성으로 삼은 나라.
  List<Widget> _nationBox() {
    final list = detailList(x, 'x_nations');
    if (list.isEmpty) return const [];
    return [
      DetailBox(
        title: '국성 나라',
        small: '${list.length}',
        children: [
          DetailChipRow([
            for (final p in list)
              DetailChip(
                detailString(p, 'name'),
                color: _chipTint(detailColor(p['color'])),
                onTap: () => ctx.open(detailString(p, 'uid')),
              ),
          ], top: 0),
        ],
      ),
    ];
  }

  /// 구성원 — 나라별 묶음. 지도자 · 내각은 누르면 그 시기로, 왕조 · 인물은 상세로.
  Widget _memberBox() {
    final members = detailList(x, 'x_members');
    final groups = _groupByNation(members);
    // 구성원 상한(D1-E ④): 띠 인물이 200을 넘으면 처음 200만 실리고 `x_memberCount`가 전체 수다. 계보 전용 인물은 구성원에 없고 세계표에 있다.
    final shownFigures = members.where((m) => detailString(m, 'role') == 'figure').length;
    final allFigures = (detailNum(x, 'x_memberCount') ?? shownFigures).toInt();
    final more = allFigures - shownFigures;
    final kin = _kin;
    // 계보 전용 인물 수(D1-E ④ 덧붙임 `x_kin.lineage` — 아래 파 포함 · 0이면 없음). 웹 `kinN`과 같은 셈이라 글도 웹 그대로.
    final kinLineage = kin == null ? 0 : (detailNum(kin, 'lineage') ?? 0).toInt();
    return DetailBox(
      title: '구성원',
      small: '${members.length - shownFigures + allFigures}',
      children: [
        if (groups.isEmpty)
          _cap('이 가문을 가리키는 지도자 · 내각 · 왕조 · 인물이 없습니다.')
        else
          for (final g in groups) ...[
            _NationCap(
              name: g.name,
              count: g.list.length,
              onTap: g.uid.isEmpty ? null : () => ctx.open(g.uid),
            ),
            DetailKidList([for (final m in g.list) _memberRow(m)]),
          ],
        if (more > 0) _LinkyLine(label: '', items: [(text: '${_count(more)}명 더 · 세계표', onTap: kin == null ? null : _openFamily)]),
        if (kinLineage > 0) _LinkyLine(label: '계보 전용 인물 ${_count(kinLineage)}명 · ', items: [(text: '세계표에서 보기', onTap: _openFamily)]),
      ],
    );
  }

  /// 만난 차례대로 나라별로 묶고, 나라가 없는 '그 밖'은 맨 끝에 둔다
  /// (구성원은 이미 시작 순이므로 이 차례가 지금 연표의 `order`와 같다).
  List<({String uid, String name, List<Map<String, dynamic>> list})> _groupByNation(List<Map<String, dynamic>> members) {
    final keys = <String>[], names = <String, String>{}, lists = <String, List<Map<String, dynamic>>>{};
    for (final m in members) {
      final uid = detailString(m, 'nation');
      if (!lists.containsKey(uid)) {
        keys.add(uid);
        names[uid] = detailString(m, 'nationName');
        lists[uid] = [];
      }
      lists[uid]!.add(m);
    }
    if (keys.remove('')) keys.add(''); // 나라를 못 찾은 '그 밖'만 맨 끝으로 — 나머지는 만난 차례 그대로
    return [for (final k in keys) (uid: k, name: names[k] ?? '', list: lists[k]!)];
  }

  Widget _memberRow(Map<String, dynamic> m) {
    final role = detailString(m, 'role');
    final cell = role == 'leader' || role == 'cabinet';
    final at = detailNum(m, 'at')?.toDouble();
    final uid = detailString(m, 'uid');
    return _MemberRow(
      when: detailString(m, 'when'),
      name: detailString(m, 'name'),
      role: houseRoleNames[role] ?? '',
      auto: m['auto'] == 1 || m['auto'] == true,
      onTap: cell
          ? (at == null ? null : () => ctx.goTo(at, minutesOfT(tOfMinutes(at) + 1)))
          : (uid.isEmpty ? null : () => ctx.open(uid)),
    );
  }
}

/// 분가 · 나라 칩의 바탕 — 그 색 18%를 `--surface-2`에 섞는다(css의 `color-mix(--c 18%, --surface-2)`).
Color _chipTint(Color c) => Color.alphaBlend(c.withValues(alpha: .18), Ui.surface2);

// ────────────────────────────────────────────────────────────────────────────────────────────
//  3. 이 창에만 쓰는 작은 부품
// ────────────────────────────────────────────────────────────────────────────────────────────

/// `.succ-cap` — 목록 위의 작은 머리말.
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

/// 글 한 줄 안에 든 누를 수 있는 이름들(`.aka` 안의 `.linky`) — `같은 이름의 지도자: …`.
/// 세 자리마다 쉼표(웹 `toLocaleString()` — 1234 → 1,234).
String _count(int n) {
  final digits = '$n', out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

class _LinkyLine extends StatelessWidget {
  const _LinkyLine({required this.label, required this.items});
  final String label;
  final List<({String text, VoidCallback? onTap})> items;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 2, 0, 8),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (label.isNotEmpty) Text(label, style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text3)),
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const Text(' · ', style: TextStyle(fontSize: 12, height: 1.5, color: Ui.text3)),
          _Linky(items[i].text, onTap: items[i].onTap, size: 12),
        ],
      ],
    ),
  );
}

/// `.linky` — 글 안의 밑줄 친 이름 단추.
class _Linky extends StatelessWidget {
  const _Linky(this.text, {this.onTap, this.size = 12.5});
  final String text;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final body = Text(
      text,
      style: TextStyle(
        fontSize: size,
        height: 1.5,
        color: onTap == null ? Ui.text2 : Ui.accent,
        decoration: onTap == null ? null : TextDecoration.underline,
        decorationColor: Ui.accent,
      ),
    );
    if (onTap == null) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(button: true, label: text, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: body)),
    );
  }
}

/// 본가에서 이 가문까지 — 칩을 `›`로 잇고, 제 가문은 테두리만 두른 채 누르지 않는다.
class _PathChips extends StatelessWidget {
  const _PathChips({required this.chips});
  final List<({String text, Color color, VoidCallback? onTap})> chips;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (int i = 0; i < chips.length; i++) ...[
          if (i > 0) const Text('›', style: TextStyle(fontSize: 13, height: 1.5, color: Ui.text3)),
          if (chips[i].onTap == null)
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _chipTint(chips[i].color),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: chips[i].color, width: 1.5),
              ),
              child: Text(chips[i].text, style: const TextStyle(fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w500, color: Ui.text)),
            )
          else
            DetailChip(chips[i].text, color: _chipTint(chips[i].color), onTap: chips[i].onTap),
        ],
      ],
    ),
  );
}

/// 구성원 묶음의 머리 — `[나라 이름][구성원 수]`. 나라가 없는 묶음은 `그 밖`.
class _NationCap extends StatelessWidget {
  const _NationCap({required this.name, required this.count, this.onTap});
  final String name;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        if (onTap == null || name.isEmpty)
          Text(name.isEmpty ? '그 밖' : name, style: const TextStyle(fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w600, color: Ui.text2))
        else
          _Linky(name, onTap: onTap),
        Text('$count', style: const TextStyle(fontSize: 12, height: 1.6, color: Ui.text3)),
      ],
    ),
  );
}

/// 구성원 한 줄 — `[기간 60px][이름][역할 딱지]`. `.kid-list`의 줄에 역할 알약을 더한 것.
class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.when, required this.name, required this.role, this.auto = false, this.onTap});
  final String when, name, role;
  final bool auto;
  final VoidCallback? onTap;

  static const whenStyle = TextStyle(fontSize: 12, height: 1.5, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()]);

  @override
  Widget build(BuildContext context) {
    // 날짜 칸: 예전에는 60px 고정이라 '기원전 19년 ~ 18년' · '18년 ~ 44년'이 칸 안에서 꺾여 '44 / 년'처럼 두 줄이 되었다(감독 건의 2026-10-14 5 · 6번 —
    // 가문 창 구성원). 창 안 날짜 칸과 한 폭(YearColumn — 웹 `--yw`)으로 맞추되 줄 폭의 45%까지.
    final shared = YearColumn.maybeOf(context);
    if (shared != null && when.isNotEmpty) shared.offer(measureText(when, whenStyle, scaler: MediaQuery.textScalerOf(context)) + 1);
    final yw = shared?.value ?? 60.0;
    return DetailPressable(
      onTap: onTap,
      semantics: name,
      child: LayoutBuilder(
        builder: (context, box) {
          final cap = box.maxWidth.isFinite ? box.maxWidth * .45 : yw;
          final width = math.min(yw, cap);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minWidth: width, maxWidth: math.max(width, cap)),
                child: Text(when, style: whenStyle),
              ),
              const SizedBox(width: 10),
              Flexible(child: Text(name, style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text))),
              if (role.isNotEmpty) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(color: Ui.accentSoft, borderRadius: BorderRadius.circular(999)),
                  child: Text(role, style: const TextStyle(fontSize: 10.5, height: 1.6, color: Ui.text2)),
                ),
              ],
              if (auto) ...[
                const SizedBox(width: 4),
                const Text('짐작', style: TextStyle(fontSize: 11, height: 1.5, color: Ui.text3)),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// `.alt-sub` — 목록 한 줄에 딸린 이설 · 모호함 작은 상자(왼쪽에 굵은 선).
class _AltSub extends StatelessWidget {
  const _AltSub({required this.title, this.small, this.notes = const [], this.list});
  final String title;
  final String? small;
  final List<String> notes;
  final Widget? list;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(0, 8, 0, 2),
    padding: const EdgeInsets.fromLTRB(10, 2, 0, 2),
    // css는 파선 테두리지만 Flutter의 Border는 파선을 긋지 못한다 — 같은 뜻을 옅은 경고 색으로 전한다(뼈대의 배지와 같은 맞바꿈).
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: Color.alphaBlend(DetailUi.warn.withValues(alpha: .34), Ui.line), width: 2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _cap(title, small),
        for (final n in notes) DetailRangeNote(n),
        ?list,
      ],
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  4. 다스린 기간 막대 — D1 결정 7 A(가문 창 · 성씨 창 맨 위 · 목업 `.d1-bars`)
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 나라마다 한 줄 — 나라 기간은 나라 색 18% 막대, 그 가문의 칸은 가문 색 칠. 모든 줄이 같은 자를 쓰고 아래에 처음 · 가운데 · 끝 해.
/// 줄은 `x_eras`(`[{uid, name, color, span: [분, 분], cells: [[분, 분], …]}]`) 그대로, 칸마다 다른 색이면 `cellColors`(성씨 창 — 가문마다).
class KinErasBars extends StatelessWidget {
  const KinErasBars({super.key, required this.rows, this.houseColor, this.onRow});

  final List<Map<String, dynamic>> rows;

  /// 칸 칠 색(가문 색). 줄의 칸이 `[분, 분, 색]`이면 그 색이 먼저다.
  final Color? houseColor;

  /// 줄을 누르면 그 나라 기간으로(분).
  final void Function(double lo, double hi)? onRow;

  static (double, double)? _span(Object? v) {
    if (v is List && v.length >= 2 && v[0] is num && v[1] is num) return ((v[0] as num).toDouble(), (v[1] as num).toDouble());
    return null;
  }

  /// 막대 밑 한 줄: 지도자 구간 · '실권' 구간(넷까지 · 넘으면 '외 n'). 웹 `erasHTML`의 `spanText`와 같은 글.
  static String _whenOf(Map<String, dynamic> r, String Function(double) year) {
    // 끝이 열린 구간(적지 않음 · 미정 — `openCells` · `openReal`의 차례)은 '~ 미정': 막대는 나라 끝까지 가도 나라의 끝을 그 가문의 끝처럼 적지 않는다.
    String text(Object? list, Object? open) {
      if (list is! List) return '';
      final spans = [for (final c in list) ?_span(c)];
      final opens = {if (open is List) for (final i in open) if (i is num) i.toInt()};
      final shown = [
        for (final (i, s) in spans.take(4).indexed) opens.contains(i) ? '${year(s.$1)} ~ 미정' : year(s.$1) == year(s.$2) ? year(s.$1) : '${year(s.$1)} ~ ${year(s.$2)}',
      ];
      return shown.join(' · ') + (spans.length > 4 ? ' 외 ${spans.length - 4}' : '');
    }

    final cells = text(r['cells'], r['openCells']), real = text(r['real'], r['openReal']);
    return [cells, if (real.isNotEmpty) '실권 $real'].where((t) => t.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    var lo = double.infinity, hi = -double.infinity;
    for (final r in rows) {
      final s = _span(r['span']);
      if (s == null) continue;
      lo = math.min(lo, s.$1);
      hi = math.max(hi, s.$2);
    }
    if (!lo.isFinite || !hi.isFinite) return const SizedBox.shrink();
    if (hi <= lo) hi = lo + 1;
    String year(double m) => kinYear(civilAt(tOfMinutes(m)).year);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final r in rows)
          if (_span(r['span']) case final s?)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: DetailPressable(
                onTap: onRow == null ? null : () => onRow!(s.$1, s.$2),
                padding: EdgeInsets.zero,
                radius: 5,
                semantics: detailString(r, 'name'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(detailString(r, 'name'), maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Ui.text2)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 14,
                            child: CustomPaint(painter: _ErasPainter(row: r, lo: lo, hi: hi, nation: detailColor(r['color']), house: houseColor ?? Ui.text3)),
                          ),
                        ),
                      ],
                    ),
                    // 그 가문이 실제로 자리에 있던 해(감독 건의 2026-10-14 5번): 막대 밑의 해(아래 줄)는 나라들의 자일 뿐이라
                    // '다스린 기간'이 나라의 기간으로 읽혔다(해씨 기원전 19 ~ 53이 기원전 37 ~ 668로). 웹 `.kv-era-when`과 같은 글.
                    if (_whenOf(r, year) case final text when text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 52, top: 2),
                        child: Text(text, style: const TextStyle(fontSize: 11, height: 1.5, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()])),
                      ),
                  ],
                ),
              ),
            ),
        Row(
          children: [
            const SizedBox(width: 52),
            Expanded(
              child: DefaultTextStyle(
                style: const TextStyle(fontSize: 10.5, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()]),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(year(lo)), Text(year((lo + hi) / 2)), Text(year(hi))]),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ErasPainter extends CustomPainter {
  _ErasPainter({required this.row, required this.lo, required this.hi, required this.nation, required this.house});
  final Map<String, dynamic> row;
  final double lo, hi;
  final Color nation, house;

  @override
  void paint(Canvas canvas, Size size) {
    final span = KinErasBars._span(row['span']);
    if (span == null) return;
    double at(double m) => (m - lo) / (hi - lo) * size.width;
    final a = at(span.$1), b = math.max(at(span.$2), at(span.$1) + 4);
    final track = RRect.fromRectAndRadius(Rect.fromLTRB(a, 0, b, size.height), const Radius.circular(5));
    canvas.drawRRect(track, Paint()..color = KinUi.tint(nation, .18));
    canvas.drawRRect(track.deflate(.5), Paint()
      ..color = KinUi.fade(nation, .45)
      ..style = PaintingStyle.stroke);
    // 지도자 자리의 구간은 가문 색 칠, 내각(실권) 자리의 구간(`real` — 감독 건의 2026-10-14 5번)은 옅은 칠.
    for (final (list, real) in [(row['cells'], false), (row['real'], true)]) {
      if (list is List) _paintCells(canvas, size, list, real, at, a, b);
    }
  }

  void _paintCells(Canvas canvas, Size size, List cells, bool real, double Function(double) at, double a, double b) {
    for (final c in cells) {
      final s = KinErasBars._span(c);
      if (s == null) continue;
      final hc = c is List && c.length > 2 ? detailColor(c[2], house) : house;
      var l = at(s.$1), r = at(s.$2);
      // 아주 짧은 구간도 4px — 막대 끝에 닿으면 안쪽에 붙여 막대 밖으로 나가지 않는다.
      if (r - l < 4) {
        r = l + 4;
        if (r > b) {
          r = b;
          l = b - 4;
        }
      }
      final cell = RRect.fromRectAndRadius(Rect.fromLTRB(l.clamp(a, b), 0, r.clamp(a, b), size.height), const Radius.circular(4));
      canvas.drawRRect(cell, Paint()..color = real ? KinUi.tint(hc, .34, KinUi.paper) : Color.lerp(KinUi.tint(hc, .78, KinUi.paper), const Color(0xff1b1a19), .06)!);
      canvas.drawRRect(cell.deflate(.5), Paint()
        ..color = Color.lerp(hc, const Color(0xff1b1a19), .30)!
        ..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(_ErasPainter old) => old.row != row || old.lo != lo || old.hi != hi || old.nation != nation || old.house != house;
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  5. 성씨 창 — D1 결정 7 A 덧붙임(갈래 `surname` · 목업 `d1-7-sur.png`)
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 성씨 창 — 성씨 배지 · 가문 수 · 다스린 나라 수 · 다스린 기간 막대(가문마다 제 색) · 가문 칩. 그 성의 모든 가문을 같은 칠로 조명한다.
class SurnameDetail extends StatefulWidget {
  const SurnameDetail(this.ctx, {super.key});

  /// 앱 틀 없이 띄울 때.
  SurnameDetail.of({required AppBus bus, required Map<String, dynamic> entity, String? uid, VoidCallback? onClose, super.key})
    : ctx = peopleContext(bus: bus, entity: entity, uid: uid, kind: 'surname', onClose: onClose);

  final DetailContext ctx;

  @override
  State<SurnameDetail> createState() => _SurnameDetailState();
}

class _SurnameDetailState extends State<SurnameDetail> {
  Object? _litHouse, _litSpots;
  List<Map<String, dynamic>> _eras = const [];
  int _nations = 0;

  DetailContext get ctx => widget.ctx;
  Map<String, dynamic> get x => ctx.json;

  /// 그 성의 가문(`x_houses` = `[{uid, name, color}]`).
  List<Map<String, dynamic>> get _houses => detailList(x, 'x_houses');

  @override
  void initState() {
    super.initState();
    _light(const []);
    unawaited(_loadEras());
  }

  @override
  void dispose() {
    final house = ctx.slot('house');
    if (identical(house.value, _litHouse)) house.value = null;
    final spots = ctx.slot('spots');
    if (_litSpots != null && identical(spots.value, _litSpots)) spots.value = null;
    super.dispose();
  }

  /// 그 성의 가문(과 아래 파) 모두를 조명 — 누른 가문은 없다(`{'houses': [...]}`).
  void _light(List<String> under) {
    final ids = <String>{
      for (final h in _houses)
        if (detailString(h, 'uid').startsWith('house:')) detailString(h, 'uid').substring(6),
      ...under,
    };
    _litHouse = ids.isEmpty ? null : {'houses': ids.toList()};
    ctx.slot('house').value = _litHouse;
    final spots = detailList(x, 'x_spots');
    if (spots.isNotEmpty) {
      _litSpots = spots;
      ctx.slot('spots').value = spots;
    }
  }

  /// 가문마다 다스린 기간(`x_eras`)을 받아 나라마다 한 줄로 합친다 — 칸은 가문 색.
  Future<void> _loadEras() async {
    final byNation = <String, Map<String, dynamic>>{};
    final order = <String>[];
    final under = <String>[];
    for (final h in _houses) {
      final rec = await ctx.askEntity(detailString(h, 'uid'));
      if (rec == null) continue;
      under.addAll(detailStrings(rec, 'x_under'));
      final hc = detailString(h, 'color').isNotEmpty ? h['color'] : rec['color'];
      for (final r in detailList(rec, 'x_eras')) {
        final uid = detailString(r, 'uid');
        final row = byNation.putIfAbsent(uid, () {
          order.add(uid);
          return {'uid': uid, 'name': r['name'], 'color': r['color'], 'span': r['span'], 'cells': <Object>[]};
        });
        for (final c in (r['cells'] is List ? r['cells'] as List : const [])) {
          if (c is List && c.length >= 2) (row['cells'] as List).add([c[0], c[1], hc]);
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _eras = [for (final k in order) byNation[k]!];
      _nations = order.length;
    });
    if (under.isNotEmpty) _light(under);
  }

  @override
  Widget build(BuildContext context) => DetailShell(
    onClose: ctx.close,
    badges: [DetailBadge('성씨', color: _houses.isEmpty ? Ui.text3 : detailColor(_houses.first['color']))],
    body: [
      DetailTitle(detailString(x, 'name')),
      NamesHead(bus: ctx.bus, head: x['x_nameHead'], old: x['x_names'], kind: NameKind.polity),
      DetailWhen('가문 ${_houses.length}${_nations > 0 ? ' · 다스린 나라 $_nations' : ''}'),
      NamesRest(bus: ctx.bus, head: x['x_nameHead'], kind: NameKind.polity),
      if (detailString(x, 'description').isNotEmpty) DetailDesc(detailString(x, 'description')),
      if (_eras.isNotEmpty)
        DetailBox(
          title: '다스린 기간',
          children: [KinErasBars(rows: _eras, onRow: (lo, hi) => ctx.goTo(lo, hi))],
        ),
      if (_houses.isNotEmpty)
        DetailBox(
          title: '가문',
          children: [
            DetailChipRow([
              for (final h in _houses)
                _DotChip(
                  text: detailString(h, 'name'),
                  color: detailColor(h['color']),
                  onTap: () => ctx.open(detailString(h, 'uid'), kind: 'house'),
                ),
            ], top: 0),
          ],
        ),
      DocChips(bus: ctx.bus, uid: ctx.uid, json: x),
      DetailDefs([if (detailString(x, 'packName').isNotEmpty) DetailDef('제공', Text(detailString(x, 'packName')))]),
    ],
    foot: [
      if (detailString(x, 'wiki').isNotEmpty) DetailSmallButton('문서', icon: LineGlyph.file, onTap: () => ctx.slot('doc').value = ctx.uid),
      DetailSmallButton('닫기', onTap: ctx.close),
    ],
  );
}

/// 색 점이 붙은 칩(성씨 창의 가문 칩 — 목업 `● 경주 김씨`).
class _DotChip extends StatelessWidget {
  const _DotChip({required this.text, required this.color, this.onTap});
  final String text;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => DetailPressable(
    onTap: onTap,
    radius: 999,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    background: Ui.surface2,
    semantics: text,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w500, color: Ui.text)),
      ],
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  6. 계보 전용 인물 창 — D1(갈래 `lineage` · 확정 설계 2-1 · 9-2 W2 5번 · 8-3 끝)
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 계보 전용 인물 — 띠에 막대가 없는 사람(왕위에 오르지 않은 대군 · 군 · 공주 · 후손). 파 · 부모 · 자식 줄은 뼈대(`x_kin`)에서 읽는다.
/// **연표를 고르거나 흐리게 하지 않는다**(갈래의 lane · pick 거짓 — 조명도 걸지 않음).
class LineageFigureDetail extends StatefulWidget {
  const LineageFigureDetail(this.ctx, {super.key});

  LineageFigureDetail.of({required AppBus bus, required Map<String, dynamic> entity, String? uid, VoidCallback? onClose, super.key})
    : ctx = peopleContext(bus: bus, entity: entity, uid: uid, kind: 'figure', onClose: onClose);

  final DetailContext ctx;

  @override
  State<LineageFigureDetail> createState() => _LineageFigureDetailState();
}

class _LineageFigureDetailState extends State<LineageFigureDetail> {
  KinSkeleton? _skel;
  int _at = -1;

  DetailContext get ctx => widget.ctx;
  Map<String, dynamic> get x => ctx.json;

  ({String key, int at})? get _ref => kinRefOf(x['x_kin']);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<String?> _fetch(String uid) async {
    try {
      final answer = await ctx.bus.ask({'op': 'entity', 'uid': uid});
      final json = answer['json'];
      return json is String && json.isNotEmpty ? json : null;
    } catch (_) {
      return null;
    }
  }

  /// 그 사람이 든 뼈대를 받아(작업자 isolate) 그 사람의 자리를 찾는다. 덩어리에 있으면 덩어리째(`x_kin.chunk`).
  Future<void> _load() async {
    final ref = _ref;
    if (ref == null || ref.at < 0) return;
    final kin = x['x_kin'] as Map;
    final chunk = '${kin['chunk'] ?? ''}';
    try {
      final text = await _fetch(chunk.isNotEmpty ? chunk : ref.key);
      if (text == null) return;
      var s = await kinDecode(text, uid: chunk.isNotEmpty ? chunk : ref.key);
      var at = s.locate(ref.at).at;
      if (at < 0) {
        final got = await kinRevealIn(s, ref.at, _fetch);
        s = got.skel;
        at = got.at;
      }
      if (!mounted || at < 0) return;
      setState(() {
        _skel = s;
        _at = at;
      });
    } catch (_) {
      // 뼈대를 읽지 못하면 그 줄들만 없다.
    }
  }

  void _openKey(String key) {
    final t = kinPersonTarget(key);
    if (t != null) ctx.open(t.uid, cell: t.cell);
  }

  KinBranch? _branch() {
    final s = _skel;
    if (s == null || _at < 0) return null;
    final b = s.branch[_at];
    return b >= 0 && b < s.branches.length ? s.branches[b] : null;
  }

  /// 가장 가까운 지도자 조상(칸 열쇠 `c:<정권>|leader:i`) — `승계표에서 보기`가 데려갈 곳.
  String? _leaderAbove() {
    final s = _skel;
    if (s == null || _at < 0) return null;
    for (var p = s.par[_at]; p >= 0; p = s.par[p]) {
      if (s.keys[p].startsWith('c:')) return s.keys[p];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = _skel;
    final ref = _ref;
    final role = detailString(x, 'role');
    final track = namedOf(ctx.bus, 'tracks', detailString(x, 'track'));
    final branch = _branch();
    final leader = _leaderAbove();
    final leaderT = leader == null ? null : kinPersonTarget(leader);
    return DetailShell(
      onClose: ctx.close,
      badges: [
        if (track != null) DetailBadge(track.name, color: track.color),
        DetailBadge('계보 전용${role.isEmpty ? '' : ' · $role'}', dot: false, color: Ui.text3),
        if (branch != null) DetailBadge(branch.name, color: detailColor(branch.color), onTap: () => ctx.open(branch.uid, kind: 'house')),
      ],
      body: [
        DetailTitle(detailString(x, 'name')),
        NamesHead(bus: ctx.bus, head: x['x_nameHead'], old: x['x_names'], kind: NameKind.person),
        if (detailStrings(x, 'aka').isNotEmpty) DetailAka('다른 이름: ${detailStrings(x, 'aka').join(' · ')}'),
        ..._life(),
        if (s != null && _at >= 0) ..._kinLines(s, _at),
        NamesRest(bus: ctx.bus, head: x['x_nameHead'], kind: NameKind.person),
        DetailDesc(detailString(x, 'description')),
        DocChips(bus: ctx.bus, uid: ctx.uid, json: x),
        if (detailStrings(x, 'tags').isNotEmpty) DetailTags([for (final t in detailStrings(x, 'tags')) '#$t']),
        DetailDefs([
          if (detailString(x, 'packName').isNotEmpty) DetailDef('제공', Text(detailString(x, 'packName'))),
          if (detailString(x, 'source').isNotEmpty) DetailDef('출처', Text(detailString(x, 'source'))),
        ]),
      ],
      foot: [
        if (ref != null) DetailSmallButton('세계표에서 보기', onTap: () => ctx.slot(familySlot).value = FamilyRequest(kin: ref.key, focus: 'f:${ctx.uid}')),
        if (leaderT != null) DetailSmallButton('승계표에서 보기', onTap: () => ctx.open(leaderT.uid, cell: successionCell)),
        if (detailString(x, 'wiki').isNotEmpty) DetailSmallButton('문서', icon: LineGlyph.file, onTap: () => ctx.slot('doc').value = ctx.uid),
        DetailSmallButton('닫기', onTap: ctx.close),
      ],
    );
  }

  /// 생몰 — 적지 않았으면 줄이 없다(비움 ≠ 미상 — '미상'이라 쓰지 않음).
  List<Widget> _life() {
    final birth = detailNum(x, 'birth')?.toDouble(), death = detailNum(x, 'death')?.toDouble();
    if (birth == null && death == null) return const [];
    String? at(String k) => detailString(x, k).isEmpty ? null : detailString(x, k);
    final b = birth == null ? '' : whenText(birth, at: at('birthAt'));
    final d = death == null ? '' : whenText(death, at: at('deathAt'));
    return [DetailWhen('$b ~ $d'.trim())];
  }

  /// 파 · 부모 · 자식 줄(뼈대에서) — 누르면 그 사람의 창.
  List<Widget> _kinLines(KinSkeleton s, int at) {
    List<DetailBit> person(int i, [String note = '']) => [
      if (s.bits[i] & kKinUnknown != 0) const DetailBit('이름 미상') else DetailBit.link(s.name[i], kinPersonTarget(s.keys[i]) == null ? null : () => _openKey(s.keys[i])),
      if (note.isNotEmpty) ...[const DetailBit(' '), DetailBit.small(note)],
    ];
    final parents = <List<DetailBit>>[];
    final p = s.par[at];
    if (p >= 0) {
      final kind = kinEdgeKind(s.edge[at]);
      parents.add(person(p, kind == kKinEdgeAdopted ? '양부' : (kind == kKinEdgeSkip ? '${s.gen[at] - s.gen[p]}대조' : '')));
    }
    for (var e = 0; e + 3 < s.extra.length; e += 4) {
      if (s.extra[e + 1] != at) continue;
      final kind = s.extra[e + 2];
      parents.add(person(s.extra[e], kind == kKinEdgeAdopted ? '양부' : (kind == kKinEdgeSkip ? '${s.extra[e + 3]}대조' : '')));
    }
    final kids = <List<DetailBit>>[];
    var count = 0;
    for (final c in s.children(at)) {
      count++;
      if (kids.length < 30) kids.add(person(c));
    }
    final branch = _branch();
    return [
      if (branch != null) DetailLine([const DetailBit('파: '), DetailBit.link(branch.name, () => ctx.open(branch.uid, kind: 'house'))]),
      if (parents.isNotEmpty) DetailLine([const DetailBit('부모 · 조상: '), ...detailJoin(parents)]),
      if (kids.isNotEmpty) DetailLine([const DetailBit('자식 · 후손: '), ...detailJoin(kids), if (count > kids.length) DetailBit(' 외 ${count - kids.length}명')]),
    ];
  }
}
