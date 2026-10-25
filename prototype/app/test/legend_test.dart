import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/scene/viewport.dart' show SceneView;
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/shell/sheet_parts.dart';
import 'package:archive_prototype/ui/legend.dart';
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'load_app_fonts.dart';
import 'tools_test.dart' show makeBus, host;

// 범례(리메이크 4단계 틀의 시트와 창 걸음 4 — 감독 고름 G5 #9 다듬기 판의 범례): 서고 폴더 '범례 {줄 수}' 안 두 열의 상자 + 두 열에 걸친 정통성 상자.
// 쓰인 것만 줄 · 4단계 전 줄 글이 하나도 빠지지 않음(옛 줄 글 목록과 견줌) · 정통성 넷 · 두 열 바닥 같음 · 견본 머리 24 · 층 16 · 좁은 폭 한 열 · 닫기 탭.
// 그림: `flutter test --no-pub test/legend_test.dart --dart-define=LG_OUT=<그림 폴더>`면 1920×1080 1배 그림을 적는다(없으면 건너뜀).

const _out = String.fromEnvironment('LG_OUT');

LegendFacts _fixture() => LegendFacts.fromJson(jsonDecode(File('test/fixtures/도구-범례.json').readAsStringSync()) as Map<String, dynamic>);

/// 조건부 줄이 모두 켜진 답(부분 승계 · 합류 · 뒤 장까지 — 견본 답에 더함).
Map<String, dynamic> _everythingJson() {
  final j = jsonDecode(File('test/fixtures/도구-범례.json').readAsStringSync()) as Map<String, dynamic>;
  return {...j, 'has': {...(j['has'] as Map), 'partial': true, 'join': true, 'hostTab': true}};
}

/// 조건부 줄이 모두 켜진 자료(부분 승계 · 합류 · 뒤 장까지).
LegendFacts _everything() {
  final f = _fixture();
  return LegendFacts(kinds: f.kinds, certainty: f.certainty, historicity: f.historicity, has: {...f.has, 'partial': true, 'join': true, 'hostTab': true});
}

/// 4단계 전 범례(`buildLegend` — 커밋 bb8a472의 lib/ui/legend.dart 170 ~ 275줄)의 줄 글을 그대로 옮긴 것. 이 목록의 글이 새 범례에서 하나도 빠지면 안 된다.
List<String> _oldRowTexts(LegendFacts f) {
  final deps = f.kinds.where((k) => k.dep).toList();
  return [
    '통설 연대 (기본)',
    if (f.certainty.contains(2)) '추정 연대 — 옅은 실선 테두리',
    if (f.certainty.contains(3)) '전승 연대 — 빗금',
    if (f.got('range')) '연대 폭이 있는 구간만 무늬',
    if (f.got('unknown')) '연도 미정 — 그쪽 끝이 둥글게 사라짐',
    for (final k in f.kinds)
      if (!k.dep || deps.length == 1)
        k.hint.isEmpty ? k.name : '${k.name} — ${k.hint.split(' — ').last}'
      else if (k == deps.first)
        '종속 갈래 — 옅은 띠 (${deps.map((d) => d.name).join(' · ')}). 누구를 어떻게 섬겼는지는 상국 띠의 이름표로',
    if (f.historicity.contains(1)) '반전설 — 이름 띠를 한 단 옅은 색으로 · 옅은 실선 테 · 탭에 “반전설”',
    if (f.historicity.contains(2)) '전설 — 이름 띠를 두 단 옅은 색으로 · 옅은 실선 테 · 탭 이름이 기울어짐 · 탭에 “전설”',
    if (f.historicity.contains(3)) '실재 논쟁 — 보통 띠 · 탭에 “논쟁”',
    if (f.historicity.contains(4)) '부정됨 — 전설과 같은 옅은 칠을 색 없이 회색으로 · 탭 이름에 취소선 · 이어진 승계선이 옅어짐 · 탭에 “부정”',
    if (f.got('scope')) '대범위를 켜면 구성 정권이 한 가지로 모이고 둘레에 옅은 테두리 — 왼쪽 위 이름표를 누르면 상세, 짙은 세로 구간은 대범위의 기간',
    if (f.got('hollow')) '할거기 — 상징적 본국 띠의 그 기간이 속 빈 모양(이름만 남음) · 띠의 작은 단추로 모아 보기',
    '건국 (채운 둥근 네모, 띠 안쪽)',
    '멸망·종료 (빈 둥근 네모)',
    if (f.got('unknown')) '연도 미정 (점선 동그라미)',
    '직접 승계 — 승계를 선언',
    '간접 승계 — 지역·거시적 승계',
    if (f.got('revival')) '부흥 — 멸망한 나라를 되살리려는 세력 (점선 + 후대 띠 앞의 작은 고리)',
    if (f.got('partial')) '부분 승계 — 나라는 끊겼으나 지배층·백성·영역·제도·문화의 일부가 넘어감. 가는 실선(직접 승계는 굵은 실선) — 정도(약 · 중 · 강)와 이어진 것은 선에 올리거나 상세 창에서',
    if (f.got('join')) '합류 — 이미 있던 나라로 들어간 승계(흡수): 선이 멸망 네모 밑에서 곧게 내려가 그해의 띠 테두리에 닿고, 닿는 자리에 선대 색의 짧은 합류 조각',
    '소속선 — 상위 띠 아래에 접혀 들어간 정권 ↔ 상위 정권 (펼쳤을 때)',
    '동군연합 — 같은 사람이 같은 때 두 나라의 지도자: 겹친 기간의 가운데에서 두 지도자 칸을 꿰는 옅은 줄과 끝의 고리(한쪽이 화면 밖이면 칸 이름 앞의 겹고리)',
    if (f.got('depOut'))
      '상국 띠 아래에 매달린 이름표 — 스스로 다스린 속국: 빈 탭은 조공·책봉 · 봉국 · 자치령 · 복속 세력 · 기미, 칠한 탭은 종속 · 보호 · 위성 (점선 탭은 명목상 소속, 파선 탭은 예속이 아닌 소속). 상국 띠의 ▾ 속국 단추로 접고 편다',
    if (f.got('depIn'))
      '상국 띠 안 맨 아래의 이름표 — 상국이 다스린 속국: 옅은 칸은 괴뢰 · 위임 통치, 짙은 칸은 식민지 · 속령 · 직할령 · 군현, 빗금 칸은 점령지 · 군정. 매달려 있다가 안으로 들어오면 세로 끈으로 이어짐',
    if (f.got('hostTab'))
      '뒤 장 — 속국 띠 뒤에 깔린 상국 빛깔의 종이(관계가 있던 기간만큼 · 띠 위로 살짝 드러남), 관계가 끝나는 쪽의 탭이 상국 이름. 짙기는 예속의 깊이: 옅게 조공·책봉 · 봉국 · 자치령 · 복속 · 기미, 가운데 종속 · 보호 · 위성, 짙게 괴뢰 · 위임 · 식민 · 군현 · 점령 (칠 없는 점선 테는 명목상 · 예속이 아닌 소속)',
    '확실·통설 연대의 사건',
    '추정·전승 연대, 또는 여러 나라가 함께 겪은 사건(속 빈 점)',
    if (f.got('unknown')) '연도 미정 (배치용 연도에 놓임)',
    '기간이 있는 사건 — 양 끝이 실선 세로바인 가는 선',
    '연대가 갈리는 사건 — 점선 실에 꿴 구슬: 채운 구슬 = 통설, 빈 고리 = 다른 견해. 날짜를 정확히 모르는 사건은 범위 없이 점 하나로',
    '기간이 있는 사건의 다른 견해 — 이설의 시작 · 끝에 점선 세로바',
    if (f.got('treaty')) '조약 — 마름모 인장: 제 줄은 채운 마름모, 다른 당사국의 줄은 속 빈 마름모',
    if (f.got('treaty')) '기간이 있는 조약(체결 ~ 실효) — 겹줄 가는 선. 발효가 체결과 다르면 선 위에 작은 마름모 눈금',
    '띠 맨 위: 왕조 칸 · 그 아래 지도자 칸 · 내각 칸. 이어지는 지도자 칸은 같은 왕조끼리 하나의 긴 둥근 칸에 가는 구분선으로. 띠 안 맨 아래는 기관 칸, 띠 아래로 내려오는 작은 탭은 구역 — 둘 다 옅은 빗금(외세의 손길 · 속국 이름표는 민무늬)',
    '맨 위 날짜 칸: 간지 줄 아래 연호 · 도읍 묶음 줄. 한 왕조의 연호, 한 정권의 도읍은 하나의 긴 둥근 칸으로 이어짐(천도 = 가는 구분선, 임시 도읍 = 점선 칸)',
    if (f.got('cats')) '띠 안 사건 분류별 글줄: 한 띠에 분류가 둘 이상이면 분류마다 글줄 하나, 글줄 사이는 옅은 점선. 왼쪽 줄 이름 칸의 색 점이 그 글줄의 분류',
    '조감(띠 밀도 넷째 · V · ↕): 줄이 띠 하나 높이로 — 이름은 띠 안 왼쪽, 사건은 작은 점 · 개수 알약',
    '칸 기간 조명: 띠 안의 지도자·내각·시기·지위 칸, 날짜 칸의 연호·도읍 칸을 누르면 그 칸은 진하게, 띠 안의 그 기간은 옅게 칠해지고 그 칸의 창이 열림',
    if (f.got('cellAlt')) '칸의 다른 견해(이설): 이설이 말하는 경계 해에 칸 높이만 한 옅은 점선(유령 구분선) — 진짜 구분선은 그대로',
    if (f.got('cellFuzzy')) '연대가 모호한 칸(추정 · 전승 · 이르면 ~ 늦으면): 그 구간의 칸 바탕에 띠의 연대 폭과 같은 무늬, 그 구간 안의 경계는 점선',
    if (f.got('phase')) '시기 구분(학계): 띠 안 왕조 칸 아래 · 지도자 칸 위에 체계마다 얇은 줄 하나. 누르면 그 기간이 조명되고 시기 창이 열림',
    if (f.got('rank')) '지위: 지도자 칸 위(시기 구분이 있으면 그 아래)의 얇은 지위 단 — 서열이 높을수록 나라 색이 짙음(맨 왼쪽 견본은 서열 밖)',
    '가문: 필터의 가문을 켜면 지도자 칸 아래쪽에 그 지도자의 가문 색 줄. 가문 창이 열린 동안 그 가문의 칸이 진해짐',
    if (f.got('unknown')) '칸의 미정: 시작이나 끝을 모르면 그쪽 끝이 칸 안에서 옅어지며 사라지고 칸 사이 구분선이 점선이 됨',
    if (f.got('figure')) '인물 단(띠 안, 기간 막대 아래): 그 나라에서 활동한 사람의 활동 막대 — 이름은 들어갈 때만. 고르면 생몰을 잇는 수명선. 막대가 너무 좁으면 “인물 n명” 한 칸',
  ];
}

/// 글을 낱말로 — 문장 부호(— : ( ) , . · “ ” ' ")만 걷고 차례는 그대로. '이름 — 설명'으로 나누며 바뀐 것은 부호뿐이어야 한다.
List<String> _words(String s) => s.replaceAll(RegExp(r'[—:(),.·“”"]'), ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// [needle]이 [hay] 안에 이어진 차례로 있는가.
bool _contains(List<String> hay, List<String> needle) {
  for (var i = 0; i + needle.length <= hay.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length && ok; j++) {
      ok = hay[i + j] == needle[j];
    }
    if (ok) return true;
  }
  return false;
}

List<LegendRow> _rows(List<LegendBox> boxes) => [for (final b in boxes) ...b.rows];

Future<void> _open(WidgetTester tester, {double width = 1920, double height = 1080}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('범례 — 줄', () {
    test('지금 자료에 쓰인 것만 줄이 된다', () {
      final full = _rows(buildLegend(_fixture())).map((r) => r.text).join('\n');
      expect(full, contains('종속 갈래 — 옅은 띠'), reason: '종속 갈래가 여럿이면 한 줄로 묶는다');
      expect(full, contains('조공·책봉국'));
      expect(full, isNot(contains('부분 승계')), reason: '견본 자료에 부분 승계가 없다');
      expect(full, isNot(contains('합류 —')), reason: '견본 자료에 합류가 없다');
      expect(full, contains('영토 밖 — 둥근 끝 · 부흥·저항 세력'), reason: '쓰인 종류의 끝 꼴 — 부흥 · 저항은 둥근 끝(TagLook.endOf)');
      expect(full, isNot(contains('무리 —')), reason: '견본 자료에 복속 세력(직각 끝)이 없다');
      expect(full, isNot(contains('사람 띠')), reason: '배치에 사람 띠 줄이 없으면 없다');
      expect(full, isNot(contains('폴더 —')), reason: '배치에 그릇이 없으면 그릇 줄도 없다');

      const bare = LegendFacts(kinds: [LegendKind(kind: 0, name: '국가', hint: '독립 국가·왕조 (기본값) — 보통 띠')], certainty: [1]);
      final boxes = buildLegend(bare);
      expect(boxes.map((b) => b.title), ['꼬리표', '꼬리표 안', '실 · 받침', '정통성'], reason: '대범위 · 그릇이 쓰이지 않으면 그릇 상자가 없다');
      final groups = [for (final b in boxes) ...b.groups.map((g) => g.title)];
      expect(groups, isNot(contains(startsWith('실재성'))));
      expect(groups, isNot(contains(startsWith('대범위'))));
      final rows = _rows(boxes).map((r) => r.text).join('\n');
      expect(rows, contains('통설 연대 — 기본'));
      expect(rows, contains('국가 — 보통 띠'), reason: '종류의 뜻은 자료가 준 글의 뒷부분만 쓴다');
      for (final gone in ['추정 연대', '연도 미정', '인물 단', '영토 밖', '조약']) {
        expect(rows, isNot(contains(gone)));
      }

      const more = LegendFacts(certainty: [1], persons: true, containers: true, nested: true, has: {'scope': true});
      final shown = _rows(buildLegend(more)).map((r) => r.name).toList();
      expect(shown, containsAll(['사람 띠', '폴더', '상자', '접힌 상자', '대범위']));
      expect(_rows(buildLegend(const LegendFacts(certainty: [1], containers: true))).map((r) => r.name), isNot(contains('상자')), reason: '그릇 안의 그릇이 없으면 상자 줄은 없다');
    });

    test('4단계 전 줄 글이 하나도 빠지지 않는다(이름 — 설명으로 나눠도 낱말 차례는 그대로)', () {
      for (final facts in [_fixture(), _everything(), const LegendFacts(kinds: [LegendKind(kind: 0, name: '국가')], certainty: [1])]) {
        final now = [for (final r in _rows(buildLegend(facts))) _words('${r.name} ${r.desc}')];
        final used = <int>{};
        for (final old in _oldRowTexts(facts)) {
          final want = _words(old);
          final at = [for (var i = 0; i < now.length; i++) if (!used.contains(i) && _contains(now[i], want)) i];
          expect(at, isNotEmpty, reason: '옛 줄 "$old"이 새 범례에 없다');
          used.add(at.first);
        }
      }
    });

    test('정통성 넷은 두 열에 걸친 상자로 늘 있다', () {
      for (final facts in [_fixture(), const LegendFacts()]) {
        final legit = buildLegend(facts).last;
        expect(legit.title, '정통성');
        expect(legit.wide, isTrue);
        expect(legit.rows.map((r) => r.name), ['공동', '섭정', '명목', '주장']);
        expect(legit.rows.map((r) => r.mark), [LegendMark.joint, LegendMark.regent, LegendMark.nominal, LegendMark.claim]);
      }
    });

    test('견본은 그림판 제 크기 — 폭 148 · 머리 24 · 층 16(공동은 두 단)', () {
      expect(LegendLook.sample, 148);
      expect(LegendLook.head, 24);
      expect(LegendLook.floor, 16);
      expect(legendSampleHeight(LegendMark.tag), LegendLook.head);
      expect(legendSampleHeight(LegendMark.floor), LegendLook.head + LegendLook.floor);
      expect(legendSampleHeight(LegendMark.regent), LegendLook.head + LegendLook.floor);
      expect(legendSampleHeight(LegendMark.joint), LegendLook.head + 2 * LegendLook.floor);
    });

    test('폭과 열 — 넉넉하면 두 열 752, 상세 창이 열리면 줄다가 한 열, 860 아래는 숨김, 휴대폰은 한 열', () {
      expect(legendFrame(1920, covered: false), (width: 752.0, two: true, text: 172.0));
      expect(legendFrame(1920, covered: true)?.two, isTrue);
      final shrink = legendFrame(1100, covered: true)!;
      expect(shrink.two, isTrue);
      expect(shrink.width, lessThan(752));
      expect(legendFrame(1000, covered: true), (width: 384.0, two: false, text: 172.0));
      expect(legendFrame(860, covered: true), isNull);
      expect(legendFrame(1920, covered: false, phone: true)?.two, isFalse);
      expect(legendFrame(360, covered: false)?.two, isFalse);
    });

    test('상자는 차례를 지켜 두 열에 — 키 차가 작은 쪽', () {
      final (a, b) = balanceLegendColumns([100, 100, 100, 100]);
      expect(a, [0, 1], reason: '고르면 앞에서 끊는다(목업의 왼쪽 꼬리표 · 꼬리표 안)');
      expect(b, [2, 3]);
      final (l, r) = balanceLegendColumns([900, 1200, 700, 300]);
      expect(l, [0, 2], reason: '한 상자가 크면 짧은 열에 차례로 얹는다');
      expect(r, [1, 3]);
      final (one, none) = balanceLegendColumns([50]);
      expect(one, [0]);
      expect(none, isEmpty);
    });
  });

  group('범례 — 폴더', () {
    testWidgets('열면 폴더 "범례 {줄 수}"와 상자 · 견본이 나오고, 닫기 탭으로 닫힌다', (tester) async {
      await _open(tester);
      final h = makeBus();
      await tester.pumpWidget(host(LegendCard(bus: h.bus), width: 1920, height: 1080));
      expect(find.byType(SheetFolder), findsNothing);

      h.bus.slot(legendSlot).value = true;
      await tester.pumpAndSettle();
      final count = _rows(buildLegend(_fixture())).length;
      final folder = tester.widget<SheetFolder>(find.byType(SheetFolder));
      expect(folder.label, '범례');
      expect(folder.count, '$count');
      expect(find.byType(SheetBox), findsNWidgets(5), reason: '꼬리표 · 꼬리표 안 · 실 · 받침 · 그릇(견본 자료의 대범위 · 할거기) · 정통성');
      for (final t in ['꼬리표', '꼬리표 안', '실 · 받침', '그릇', '정통성']) {
        expect(find.widgetWithText(SheetBox, t), findsWidgets);
      }
      expect(find.text('정권 띠'), findsOneWidget, reason: '앞 범례의 묶음은 상자 안의 작은 묶음 이름으로 남는다');
      expect(find.byType(LegendSample), findsNWidgets(count));
      expect(h.asked.last['op'], 'legend_kinds');

      // 폴더 자리 — 왼쪽 아래 16(흰 둘레 6은 바깥).
      final rect = tester.getRect(find.byType(SheetFolder));
      expect(rect.left, legendMargin);
      expect(rect.bottom, 1080 - legendMargin);
      expect(rect.width, 752);

      await tester.tap(find.bySemanticsLabel('닫기'));
      await tester.pumpAndSettle();
      expect(h.bus.slot(legendSlot).value, false);
      expect(find.byType(SheetFolder), findsNothing);

      runCommand(h.bus, Cmd.legend); // ❔ · L
      await tester.pumpAndSettle();
      expect(find.byType(SheetFolder), findsOneWidget);
    });

    testWidgets('두 열의 바닥이 같다 · 정통성은 두 열 폭 · 견본 머리 24', (tester) async {
      await _open(tester, height: 4000);
      final h = makeBus();
      h.bus.slot(legendSlot).value = true;
      await tester.pumpWidget(host(LegendCard(bus: h.bus), width: 1920, height: 4000));
      await tester.pumpAndSettle();
      final left = tester.getRect(find.byKey(const ValueKey('legend-column-0')));
      final right = tester.getRect(find.byKey(const ValueKey('legend-column-1')));
      expect(left.bottom, right.bottom, reason: '짧은 열은 줄 사이를 고루 늘려 바닥을 맞춘다');
      expect(left.width, right.width);
      final legit = tester.getRect(find.widgetWithText(SheetBox, '정통성'));
      expect(legit.left, left.left);
      expect(legit.right, right.right, reason: '정통성은 두 열에 걸친다');
      expect(legit.top, left.bottom + LegendLook.boxGap);
      // 정통성 둘째 견본의 왼쪽 끝은 오른쪽 열의 견본과 한 줄.
      final samples = find.descendant(of: find.widgetWithText(SheetBox, '정통성'), matching: find.byType(LegendSample));
      expect(samples, findsNWidgets(4));
      expect(tester.getRect(samples.at(1)).left, right.left + 10);
      final tag = find.byWidgetPredicate((w) => w is LegendSample && w.row.name == '다스림');
      expect(tester.getSize(tag), const Size(148, 24));
      final floor = find.byWidgetPredicate((w) => w is LegendSample && w.row.name == '지도자 · 직위 층');
      expect(tester.getSize(floor), const Size(148, 40));
    });

    testWidgets('좁으면 한 열 · 상세 창이 열린 860 아래에서는 숨는다', (tester) async {
      await _open(tester, width: 1000, height: 800);
      final h = makeBus();
      h.bus.slot(legendSlot).value = true;
      await tester.pumpWidget(host(LegendCard(bus: h.bus), width: 1000, height: 800));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('legend-column-1')), findsOneWidget, reason: '1000px 창은 두 열이 든다');

      h.bus.select('moonwake-chronicle/p-coast-0');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('legend-column-1')), findsNothing, reason: '상세 창이 400을 쓰면 한 열');
      expect(tester.getSize(find.byType(SheetFolder)).width, 384);

      tester.view.physicalSize = const Size(820, 800);
      await tester.pumpWidget(host(LegendCard(bus: h.bus), width: 820, height: 800));
      await tester.pumpAndSettle();
      expect(find.byType(SheetFolder), findsNothing, reason: '상세 창이 열린 860px 아래 창에서는 숨는다');
    });

    testWidgets('휴대폰은 한 열', (tester) async {
      await _open(tester);
      SceneView.phone = true;
      addTearDown(() => SceneView.phone = false);
      final h = makeBus();
      h.bus.slot(legendSlot).value = true;
      await tester.pumpWidget(host(LegendCard(bus: h.bus), width: 1100, height: 1000));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('legend-column-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('legend-column-1')), findsNothing);
    });

    testWidgets('열린 폴더의 자리를 슬롯에 적고, 닫으면 지운다', (tester) async {
      await _open(tester);
      final h = makeBus();
      await tester.pumpWidget(host(LegendCard(bus: h.bus), width: 1920, height: 1080));
      h.bus.slot(legendSlot).value = true;
      await tester.pumpAndSettle();
      final spot = h.bus.slot(legendSpotSlot).value as LegendSpot;
      expect(spot.local.left, legendMargin);
      expect(spot.local.width, 752);
      expect(spot.global, tester.getRect(find.byType(SheetFolder)));
      h.bus.slot(legendSlot).value = false;
      await tester.pumpAndSettle();
      expect(h.bus.slot(legendSpotSlot).value, isNull);
    });
  });

  // 1배 그림 둘: 실제 화면(1920 × 1080 — 폴더 안이 넘김)과 온 범례(키 3400 — 넘김 없이 모든 줄).
  for (final (name, height, all) in const [('범례-앱-1920-1배', 1080.0, false), ('범례-앱-온-1배', 3400.0, true)]) {
    testWidgets('1배 그림 $name', (tester) async {
      await tester.runAsync(loadAppFonts);
      await _open(tester, height: height);
      final h = makeBus(legend: all ? _everythingJson() : null);
      h.bus.slot(legendSlot).value = true;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback, scaffoldBackgroundColor: Ui.bg),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: SizedBox(width: 1920, height: height, child: Stack(children: [Positioned.fill(child: LegendCard(bus: h.bus))])),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
      final png = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      final folder = Directory(_out)..createSync(recursive: true);
      File('${folder.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }, skip: _out.isEmpty);
  }
}
