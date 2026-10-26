import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/scene/glyph_ranges.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/row_labels.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_memory.dart';
import 'package:archive_prototype/ui/detail_format3.dart';
import 'package:archive_prototype/ui/detail_people.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/filter_sheet_body.dart';
import 'package:archive_prototype/ui/names_display.dart';
import 'package:archive_prototype/ui/shell_keys.dart' show slotNotice;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 원어 병기 · 글꼴(10건 3 · 9 — 감독 선택 D2 · 갈래 D2)의 새 앱 몫 검사.
// 자료는 test/fixtures/names-display.json(지금 내보내기 모듈로 지은 가상 세계 — 웹 검사 scripts/names-display-check.mjs와 같은 이름)이고,
// 글 · 차례 · 값은 웹(js/viewer.js namesHeadHTML · namesRestHTML · namesLineHTML · timeline.js fitName)의 것을 기대한다.
// 모두 가상 이름(고증 아님).

final _fixture = jsonDecode(File('test/fixtures/names-display.json').readAsStringSync()) as Map<String, dynamic>;

/// 고정 자료의 항목 기록 하나(엔진 entity 답의 json을 푼 것).
Map<String, dynamic> record(String uid) {
  for (final e in _fixture['entities'] as List) {
    if (e['uid'] == uid) return (jsonDecode(e['json'] as String) as Map).cast<String, dynamic>();
  }
  throw StateError('고정 자료에 없음: $uid');
}

/// 고정 자료의 정권 줄 후보(이름으로).
Map<String, dynamic> rowLabel(String name) =>
    ((_fixture['rowLabels'] as List).firstWhere((l) => l['name'] == name) as Map).cast<String, dynamic>();

final fsi = String.fromCharCode(0x2068), pdi = String.fromCharCode(0x2069);
final _byeol = String.fromCharCodes([0xf1a00, 0xf1a01, 0xf1a02, 0xf1a03]);

/// 확인용 가상 문자 글꼴(사설 영역 U+F1A00~F1A0B 열두 자 — 웹 검사 names-display-check.mjs의 FONT_TTF와 같은 파일).
const _mockFont =
    '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';

/// 아주 작은 장면 하나(그리기 층은 쓰지 않는다 — 상세 창 · 필터 시트 · 이어 붙이기만 본다).
TimelineScene makeScene({List<Map<String, dynamic>> packs = const [{'id': 1, 'name': '확인용 가상 세계', 'events': 3, 'key': 'd2-names'}]}) {
  Map<String, dynamic> row(int id) => {
    'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
    'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
  };
  final controller = TimelineController()
    ..resize(1920, 500)
    ..setExtent(-1000000, 1000000)
    ..setContentHeight(284);
  return TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson({
      'packs': packs,
      'tracks': [
        {'id': 1, 'pack': 1, 'ord': 0, 'name': '가상 세계', 'rows': [row(0), row(1)]},
      ],
      'epochs': const [],
    }),
    fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
}

/// 부품을 하나씩 띄운다(상세 창 폭 380).
Future<AppBus> show(WidgetTester tester, List<Widget> Function(AppBus bus) children, {AppBus? bus}) async {
  final scene = makeScene();
  final b = bus ?? AppBus(ask: (q) async => const {}, controller: scene.controller, scene: scene);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Ui.bg,
        body: SizedBox(
          width: Ui.detailWidth,
          child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children(b))),
        ),
      ),
    ),
  );
  return b;
}

/// 화면의 글(Text · RichText) 차례대로 — 격리 문자를 뺀 것.
List<String> texts(WidgetTester tester) => [
  for (final r in tester.widgetList<RichText>(find.byType(RichText))) detailPlain(r.text.toPlainText()),
];

/// 그 글을 그린 Text의 모양.
TextStyle? styleOf(WidgetTester tester, String text) {
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    if (t.data != null && detailPlain(t.data!) == text) return t.style;
  }
  return null;
}

/// 그 글에 걸린 풍선 글.
String? tipOf(WidgetTester tester, String text) {
  for (final t in tester.widgetList<Tooltip>(find.byType(Tooltip))) {
    final child = t.child;
    if (child is Text && child.data != null && detailPlain(child.data!) == text) return t.message;
  }
  return null;
}

void main() {
  setUp(ScriptFonts.instance.resetForTest);

  group('판정 표 — 웹 core.js의 범위와 같은 답', () {
    test('글자 범위 글 · 글꼴이 덮는 범위 · 한글 글꼴', () {
      expect(parseRange('U+F1A00-F1A0B'), (0xf1a00, 0xf1a0b));
      expect(parseRange('u+4e00'), (0x4e00, 0x4e00));
      expect(parseRange('U+AC00–D7A3'), (0xac00, 0xd7a3));
      expect(parseRange('nope'), isNull);
      expect(parseRange('U+20-10'), isNull, reason: '거꾸로 된 범위');
      expect(fontRanges(ranges: ['U+F1A00-F1A0B', 'bad', 'U+F1A0C']), [(0xf1a00, 0xf1a0c)], reason: '이어진 범위는 합치고 꼴이 틀린 것은 뺀다');
      expect(fontRanges(scripts: ['Hani']), [(0x4e00, 0x9fff)], reason: 'ranges가 없으면 문자 꼬리표의 기본 범위');
      expect(fontRanges(scripts: ['Qaaa']), isEmpty, reason: '가상 문자는 ranges로만');
      expect(coversHangul(fontRanges(scripts: ['Hang'])), isTrue);
      expect(coversHangul(fontRanges(ranges: ['U+AC00-AC10'])), isFalse);
    });

    test('띠 표에는 그림판이 그릴 수 있는 범위만 — 아랍 글꼴 팩이어도 띠에는 아랍을 넣지 않는다', () {
      final arab = packExtras([fontRanges(scripts: ['Arab'])]);
      expect(inRanges(arab.window, 0x642), isTrue);
      expect(inRanges(arab.band, 0x642), isFalse);
      final virtual = packExtras([fontRanges(ranges: ['U+F1A00-F1A0B'])]);
      expect(inRanges(virtual.band, 0xf1a01), isTrue, reason: '가상 문자(사설 영역)는 그림판이 한 글자씩 그린다');
      // 미리 실려 온 '내장 표에 없는 글자'를 팩의 범위로 다시 본다.
      expect(stillMissing([0xf1a00, 0x2546e], virtual.window), [0x2546e]);
      expect(missingScriptName([0xf1a00]), '가상 문자');
      expect(missingScriptName([0x2546e]), '한자 확장 글자');
      expect(missingScriptName([0x1100]), '옛한글');
      expect(missingScriptName([0x642]), '아랍 문자');
      expect(missingScriptName([0x301]), '결합 부호');
      expect(missingScriptName([0x10330]), '이 문자');
      expect(missingScriptName(const []), '');
    });

    test('고정 자료: 내보내기가 실은 없는 글자 목록(mw · mb)이 웹 판정과 같다', () {
      expect(codePoints(record('d2-names/byeol')['x_nameHead']['first']['mw']), [0xf1a00, 0xf1a01, 0xf1a02, 0xf1a03]);
      expect(codePoints(record('d2-names/rock')['x_nameHead']['first']['mw']), [0x2546e], reason: '보통 한자는 창 표에 있고 확장 B 글자만');
      expect(record('d2-names/moon')['x_nameHead']['first']['mw'], isNull, reason: '아랍 문자는 창 표에 있다');
      expect(codePoints((rowLabel('달 왕국')['orig'] as List).first['mb']), [0x642, 0x645, 0x631], reason: '아랍 문자는 띠 표에 없다');
      expect((rowLabel('해온국')['orig'] as List).length, 1, reason: '첫 원어를 띠에 그릴 수 있으면 로마자 후보는 싣지 않는다');
      expect(rowLabel('قمر')['orig'], isNull, reason: '이름 목록이 없는 띠는 열쇠째 없다');
    });
  });

  group('보는 사람 설정', () {
    test('기본 · 모르는 값 · 적용 체크 · 저장 꼴(웹 ht.ui.names · fonts.screen)', () {
      expect(NamesUi.fromJson(null), const NamesUi());
      expect(NamesUi.fromJson({'orig': 'tab'}).orig, 'detail', reason: '모르는 값은 기본');
      final u = NamesUi.fromJson({'orig': 'band', 'kinds': {'person': false}, 'screen': 'font:sand'});
      expect((u.orig, u.polity, u.person, u.place, u.screen), ('band', true, false, true, 'font:sand'));
      expect(u.shown(NameKind.person), isFalse);
      expect(u.shown(null), isTrue, reason: '사건 제목의 다른 이름은 적용 체크 밖');
      expect(u.band, isTrue);
      expect(u.copyWith(polity: false).band, isFalse, reason: "왼쪽 칸은 적용 '나라'일 때만");
      expect(const NamesUi(orig: 'none').shown(null), isFalse);
      expect(u.toJson(), {'orig': 'band', 'kinds': {'polity': true, 'person': false, 'place': true}, 'screen': 'font:sand'});
      expect(NamesUi.fromJson(u.toJson()), u);
      expect(u.copyWith(noScreen: true).screen, isNull);
    });

    test('이름 정보: 켜진 자료집에 이름 목록이나 글꼴이 있을 때만 무리가 보인다', () {
      final info = NamesInfo.fromJson({
        'packs': [2],
        'fonts': [
          {'uid': 'font:byeol', 'pack': 3, 'id': 'byeol', 'family': '별바다 글씨', 'license': '확인용', 'ranges': ['U+F1A00-F1A0B']},
          {'uid': 'font:sand', 'pack': 3, 'id': 'sand', 'family': '모래 고딕', 'license': '확인용', 'scripts': ['Hang']},
        ],
      });
      expect(info.visible([1]), isFalse);
      expect(info.visible([1, 2]), isTrue);
      expect(info.visible([3]), isTrue, reason: '글꼴만 있는 자료집도');
      expect(info.fontsOn([1, 2]), isEmpty);
      expect([for (final f in info.fontsOn([3])) (f.uid, f.hangul)], [('font:byeol', false), ('font:sand', true)]);
      expect(const NamesInfo().visible([1]), isFalse, reason: '옛 자료 처리부 · 옛 저장소');
    });
  });

  group('상세 창 머리 — 제목 아래 두 줄 · 딱지 없음 · 다른 이름 칸', () {
    for (final surname in [true, false]) {
      testWidgets('${surname ? '성씨' : '계보 전용 인물'} 실제 창: 제목 바로 아래 머리 · 설명 위 나머지 · 적용 체크', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1920, 1080);
        addTearDown(tester.view.reset);
        final scene = makeScene();
        final bus = AppBus(ask: (q) async => const {}, controller: scene.controller, scene: scene);
        final x = record(surname ? 'surname:sn-sea' : 'd2-names/f-wave');
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: Ui.detailWidth, height: 1000,
          child: surname ? SurnameDetail.of(bus: bus, entity: x) : LineageFigureDetail.of(bus: bus, entity: x),
        ))));
        await tester.pumpAndSettle();
        final orig = surname ? '海' : '波', roman = surname ? 'Bada' : 'Mulgyeol', other = surname ? '大海' : '小波';
        expect(texts(tester), containsAllInOrder([x['name'], orig, roman, '다른 이름 1', other, x['description']]));
        expect(tester.getBottomLeft(find.byType(DetailTitle)).dy, lessThanOrEqualTo(tester.getTopLeft(find.byType(NamesHead)).dy + 1));
        expect(tester.getBottomLeft(find.byType(NamesRest)).dy, lessThanOrEqualTo(tester.getTopLeft(find.byType(DetailDesc)).dy));
        expect(texts(tester).where((t) => t.startsWith('$orig (원어') || t.startsWith('$roman (로마자')), isEmpty);
        bus.slot(slotNames).value = surname ? const NamesUi(person: false) : const NamesUi(polity: false);
        await tester.pumpAndSettle();
        expect(texts(tester), containsAll([orig, roman, other]));
        bus.slot(slotNames).value = surname ? const NamesUi(polity: false) : const NamesUi(person: false);
        await tester.pumpAndSettle();
        expect(texts(tester).where([orig, roman, other].contains), isEmpty);
        bus.slot(slotNames).value = const NamesUi(orig: 'none');
        await tester.pumpAndSettle();
        expect(texts(tester).where([orig, roman, other].contains), isEmpty);
      });
    }

    testWidgets('해온국: 원어 19px · 로마자 13px, 언어 · 종류는 풍선에만, 머리에 오르지 않은 이름만 칸에', (tester) async {
      final x = record('d2-names/haeon');
      await show(tester, (bus) => [
        NamesHead(bus: bus, head: x['x_nameHead'], old: x['x_names'], kind: NameKind.polity),
        NamesRest(bus: bus, head: x['x_nameHead'], kind: NameKind.polity),
      ]);
      expect(texts(tester), ['海溫國', 'Haeon-guk', '다른 이름 2', '옛 이름', '溫羅', '1420년 ~ 1449년', '약칭', '海溫', '']);
      final orig = styleOf(tester, '海溫國')!, roman = styleOf(tester, 'Haeon-guk')!;
      expect((orig.fontSize, orig.fontWeight, orig.height, orig.color), (19.0, FontWeight.w400, 1.35, Ui.text2));
      expect((roman.fontSize, roman.height, roman.color), (13.0, 1.4, Ui.text2));
      // 딱지 없음(감독 "한문, 로마자 등의 표기는 X") — 언어 이름 · 종류는 올렸을 때의 풍선에만.
      expect(find.text('한문'), findsNothing);
      expect(tipOf(tester, '海溫國'), '원어 · 한문');
      expect(tipOf(tester, 'Haeon-guk'), '로마자 · 한국어 로마자');
      expect(tipOf(tester, '溫羅'), '옛 이름 · 한문 · 1420년 ~ 1449년');
      // 방향 격리: 이름 글은 U+2068 … U+2069.
      final raw = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList();
      expect(raw, contains('$fsi海溫國$pdi'));
      // 자리: 원어 줄은 그림만 1px 올리고(css 위 −1px) 원어 · 로마자 사이 2px, 로마자 아래 9px(−1 보정 포함).
      final o = tester.getRect(find.text('$fsi海溫國$pdi')), r = tester.getRect(find.text('${fsi}Haeon-guk$pdi'));
      expect(o.top, -1);
      expect(r.top - o.bottom, closeTo(3, .01));
      // 언어가 표준 꼬리표면 그 언어로(lzh) — 가상 언어(x-)는 주지 않는다.
      expect(tester.widget<Text>(find.text('$fsi海溫國$pdi')).locale, const Locale('lzh'));
    });

    testWidgets('그릴 수 없는 원어는 글 대신 딱지 — 가상 문자 · 한자 확장 글자(로마자 줄은 그대로)', (tester) async {
      final byeol = record('d2-names/byeol'), rock = record('d2-names/rock');
      await show(tester, (bus) => [
        NamesHead(bus: bus, head: byeol['x_nameHead'], kind: NameKind.polity),
        NamesHead(bus: bus, head: rock['x_nameHead'], kind: NameKind.polity),
      ]);
      expect(texts(tester), ['원어 — 가상 문자 · 글꼴 없음', 'Yelna Oru', '원어 — 한자 확장 글자 · 글꼴 없음', 'Dolsaem']);
      expect(find.byType(NamesNoFontChip), findsNWidgets(2));
      expect(texts(tester).join(), isNot(contains(_byeol)));
      expect(find.byTooltip('이 원어의 문자가 화면 글꼴에 없습니다 — 글꼴 팩을 넣으면 보입니다'), findsNWidgets(2));
    });

    testWidgets('아랍 원어는 창 표에 있어 그대로(방향 격리) · 이름이 하나뿐이면 칸 없음', (tester) async {
      final moon = record('d2-names/moon');
      await show(tester, (bus) => [
        NamesHead(bus: bus, head: moon['x_nameHead'], kind: NameKind.polity),
        NamesRest(bus: bus, head: moon['x_nameHead'], kind: NameKind.polity),
      ]);
      expect(texts(tester), ['قمر', 'Qamar']);
      expect(tester.widget<Text>(find.text('$fsiقمر$pdi')).locale, const Locale('ar'));
    });

    testWidgets('글꼴 팩을 실으면 그 글꼴이 덮는 가상 문자 원어가 글로 보인다', (tester) async {
      final byeol = record('d2-names/byeol');
      await tester.runAsync(() => ScriptFonts.instance.load('font:byeol', base64Decode(_mockFont)));
      final font = FontEntry(uid: 'font:byeol', pack: 1, family: '별바다 글씨', ranges: const ['U+F1A00-F1A0B']);
      expect(ScriptFonts.instance.refresh([font]), isTrue);
      expect(sceneFallbackNow, [...sceneFontFallback, 'HT 글꼴 font:byeol'], reason: '대체 글꼴 목록 끝에(화면 글꼴에 없는 글자만 채움)');
      await show(tester, (bus) => [NamesHead(bus: bus, head: byeol['x_nameHead'], kind: NameKind.polity)]);
      expect(texts(tester), [_byeol, 'Yelna Oru']);
      expect(find.byType(NamesNoFontChip), findsNothing);
      expect(styleOf(tester, _byeol)!.fontFamilyFallback, contains('HT 글꼴 font:byeol'));
      // 돌샘국의 확장 B 글자는 이 팩이 덮지 않는다.
      expect(NameItem.of(record('d2-names/rock')['x_nameHead']['first'])!.missing(ScriptFonts.instance.windowExtra), [0x2546e]);
    });

    testWidgets('표기 설정: 없음 · 적용 체크를 끈 종류는 이름 줄이 모두 빠진다(형식 3 이전 모습)', (tester) async {
      final x = record('d2-names/haeon'), f = record('d2-names/f-sol');
      final bus = await show(tester, (bus) => [
        NamesHead(bus: bus, head: x['x_nameHead'], kind: NameKind.polity),
        NamesRest(bus: bus, head: x['x_nameHead'], kind: NameKind.polity),
        NamesHead(bus: bus, head: f['x_nameHead'], kind: NameKind.person),
      ]);
      expect(texts(tester), contains('松光'));
      bus.slot(slotNames).value = const NamesUi(polity: false);
      await tester.pump();
      expect(texts(tester), ['松光', 'Solbit'], reason: "'나라'를 끄면 나라 이름만 빠지고 인물은 그대로");
      bus.slot(slotNames).value = const NamesUi(orig: 'none');
      await tester.pump();
      expect(texts(tester), isEmpty);
    });

    testWidgets('미리 푼 머리가 없는 옛 저장소는 x_names(F1 꼴)를 예전 줄로', (tester) async {
      final x = record('d2-names/haeon');
      await show(tester, (bus) => [
        NamesHead(bus: bus, old: x['x_names'], kind: NameKind.polity),
        NamesRest(bus: bus, kind: NameKind.polity),
      ]);
      expect(texts(tester), ['海溫國 (원어 · 한문) · Haeon-guk (로마자 · 한국어 로마자)', '그 밖의 이름: 溫羅 (옛 이름 · 한문 · 1420년 ~ 1449년) · 海溫 (약칭 · 한문)']);
    });

    testWidgets('이름이 없는 기록은 아무것도 그리지 않는다(자리도 없음)', (tester) async {
      await show(tester, (bus) => [
        const SizedBox(height: 10),
        NamesHead(bus: bus, kind: NameKind.polity),
        NamesRest(bus: bus, kind: NameKind.polity),
        NamesPlace(bus: bus, place: null, lead: '장소'),
        const SizedBox(height: 10),
      ]);
      expect(texts(tester), isEmpty);
      expect(tester.getSize(find.byType(Column).first).height, 20);
    });
  });

  group('딸린 한 줄 — 지명 · 성씨', () {
    testWidgets('사건 장소 · 도읍 지명 · 가문의 성: "앞말 — 원어 · 로마자"(딱지 없음)', (tester) async {
      final ev = record('d2-names/ev-move'), haeon = record('d2-names/haeon'), house = record('house:h-sea');
      final bus = await show(tester, (bus) => [
        NamesPlace(bus: bus, place: ev['x_place'], lead: '장소'),
        NamesPlace(bus: bus, place: haeon['x_cellPlaces']['capital:0'], lead: '지명'),
        NamesLine(bus: bus, lead: const [DetailBit('성 바다 — ')], head: house['x_surnameHead'], old: house['x_surname']['names'], kind: NameKind.polity),
      ]);
      // 이름은 줄 안의 조각(풍선 · 딱지를 달 수 있게 — 줄 글에서는 U+FFFC 자리)이고 차례는 웹 줄과 같다.
      const o = '\uFFFC';
      expect(texts(tester), ['장소 바닷골 — $o · $o', '海谷', 'Badatgol', '지명 바닷골 — $o · $o', '海谷', 'Badatgol', '성 바다 — $o · $o · 다른 이름 $o (옛 이름)', '海', 'Bada', '大海']);
      // '지명'을 끄면 장소 줄은 이름만, 도읍의 '지명' 줄은 위 구역이 없어 서지 않는다(웹 placeHTML).
      bus.slot(slotNames).value = const NamesUi(place: false);
      await tester.pump();
      expect(texts(tester), ['장소 바닷골', '성 바다 — $o · $o · 다른 이름 $o (옛 이름)', '海', 'Bada', '大海']);
    });
  });

  // 리메이크 2부(목업 서고): 왼쪽 칸의 줄은 작은 꼬리표 그림 + 띠 이름(보는 범위의 띠를 ' · '로 이음)뿐이다 —
  // 예전의 셋째 조각(원어 · 이름 뒤 4px)과 연도 조각은 그리지 않는다('원어: 왼쪽 칸에도'를 켜도). 원어 고르기(RowLabel.origFor)는 그대로 본다.
  group('왼쪽 줄 이름 칸 — 이름만(리메이크 2부) · 원어 고르기', () {
    test('원어 · 연도 없이 이름 하나 — 원어를 왼쪽 칸에도 켜도 같다', () async {
      final at = tileOrigin(9, 1);
      Map<String, dynamic> label(String name, String years, List<Map<String, dynamic>> orig) =>
          {'period': 'p-$name', 'track': 0, 'row': 0, 'kind': 0, 'name': name, 'years': years, 'color': 0xa8c7b8, 'start': at, 'end': at + 100000, 'orig': orig};
      Future<List<DebugLabel>> paintOne(Map<String, dynamic> one, {bool band = true, List<GlyphRange> extra = const []}) async {
        final (scene, painter) = _gutterScene({0: [one]});
        SceneNames.of(scene)
          ..origBand = band
          ..bandExtra = extra;
        await _settle(scene, painter);
        return [for (final l in painter.debugLabels) if (l.kind.startsWith('row')) l];
      }

      for (final band in [true, false]) {
        final got = await paintOne(label('해온', '1420–', [{'text': '海溫國'}]), band: band);
        expect(got.where((l) => l.kind == 'rowName').single.text, '해온', reason: '원어 왼쪽 칸 $band');
        expect(got.where((l) => l.kind == 'rowOrig' || l.kind == 'rowYears'), isEmpty, reason: '원어 · 연도 조각은 없다(원어 왼쪽 칸 $band)');
      }
    });

    test('띠 표로 그릴 수 없는 원어는 로마자로 — 글꼴 팩이 덮으면(띠에 그릴 수 있는 문자만) 원어로', () {
      String origOf(String name, {List<GlyphRange> extra = const []}) => RowLabel.fromJson(rowLabel(name)).origFor(extra);

      expect(origOf('달 왕국'), 'Qamar', reason: '아랍 문자는 띠 표에 없다(그림판이 이어 쓰지 못함)');
      expect(origOf('달 왕국', extra: packExtras([fontRanges(scripts: ['Arab'])]).band), 'Qamar', reason: '아랍 글꼴 팩이어도 띠에는');
      expect(origOf('별바다', extra: packExtras([fontRanges(ranges: ['U+F1A00-F1A0B'])]).band), _byeol);
      expect(origOf('돌샘국'), 'Dolsaem');
      // 팩이 없으면 별바다는 로마자 후보.
      expect(origOf('별바다'), 'Yelna Oru');
    });

    test('줄 이름 후보의 원어 고르기(RowLabel.origFor)', () {
      final l = RowLabel.fromJson({'name': '달 왕국', 'orig': [{'text': 'قمر', 'mb': [0x642, 0x645, 0x631]}, {'text': 'Qamar'}]});
      expect(l.origFor(const []), 'Qamar');
      expect(RowLabel.fromJson({'name': '해온국'}).orig, isEmpty);
      expect(RowLabel.fromJson({'name': '해온국'}).origFor(const []), '');
    });
  });

  group('필터 시트 — 표기 무리', () {
    testWidgets('이름 목록이 있는 자료집이 켜져 있을 때만 · 원어 고르기 · 적용 체크 · 글꼴은 한글 글꼴만 고른다', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scene = makeScene();
      final bus = AppBus(ask: (q) async => const {}, controller: scene.controller, scene: scene);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 1080, child: FilterSheetBody(bus: bus))))));
      await tester.pumpAndSettle();
      expect(find.text('표기'), findsNothing, reason: '이름 목록 · 글꼴이 없는 자료는 무리가 숨는다(지금 시트 그대로)');

      bus.slot(slotNamesInfo).value = NamesInfo.fromJson({'packs': [1]});
      await tester.pumpAndSettle();
      expect(find.text('표기'), findsOneWidget);
      expect(find.text('원어: 상세 창만'), findsOneWidget);
      expect(find.text('적용'), findsOneWidget);
      expect(find.text('나라'), findsOneWidget);
      expect(find.text('인물'), findsNWidgets(2), reason: "'띠 안'의 인물 단 체크와 같은 글 — 표기 무리의 것은 뒤에");
      expect(find.text('지명'), findsOneWidget);
      expect(find.textContaining('글꼴:'), findsNothing, reason: '글꼴이 없으면 글꼴 고르기도 없다');

      await tester.tap(find.text('인물').last);
      await tester.pump();
      expect(NamesUi.of(bus).person, isFalse);
      await tester.tap(find.text('원어: 상세 창만'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('원어: 왼쪽 칸에도').last);
      await tester.pumpAndSettle();
      expect(NamesUi.of(bus).orig, 'band');

      bus.slot(slotNamesInfo).value = NamesInfo.fromJson({
        'packs': [1],
        'fonts': [
          {'uid': 'font:byeol', 'pack': 1, 'family': '별바다 글씨', 'license': '확인용', 'ranges': ['U+F1A00-F1A0B']},
          {'uid': 'font:sand', 'pack': 1, 'family': '모래 고딕', 'license': 'OFL', 'scripts': ['Hang']},
        ],
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('글꼴: 기본'));
      await tester.pumpAndSettle();
      expect(find.text('글꼴: 별바다 글씨 (없는 글자에만)').last, findsOneWidget);
      // 펼친 목록의 줄마다 '팩 이름 · 라이선스' 풍선(웹 <option title>과 같은 글)
      expect(tipOf(tester, '글꼴: 별바다 글씨 (없는 글자에만)'), '확인용 가상 세계 · 라이선스 확인용 — 한글이 없는 글꼴이라 화면 글꼴로는 쓰지 않고, 화면 글꼴에 없는 글자에만 씁니다');
      expect(tipOf(tester, '글꼴: 모래 고딕'), '확인용 가상 세계 · 라이선스 OFL');
      await tester.tap(find.text('글꼴: 별바다 글씨 (없는 글자에만)').last);
      await tester.pumpAndSettle();
      expect(NamesUi.of(bus).screen, isNull, reason: '한글이 없는 글꼴은 화면 글꼴로 고를 수 없다');
      if (find.text('글꼴: 모래 고딕').evaluate().isEmpty) {
        await tester.tap(find.text('글꼴: 기본'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('글꼴: 모래 고딕').last);
      await tester.pumpAndSettle();
      expect(NamesUi.of(bus).screen, 'font:sand');
      expect(bus.slot(slotNotice).value, '화면 글꼴을 골랐습니다 — 앱을 다시 켜면 바뀝니다');
    });
  });

  group('이어 붙이기 — 이름 정보 · 글꼴 팩 · 왼쪽 칸 · 기억', () {
    test('이름 정보를 묻고, 켜진 자료집의 글꼴을 실어 판정 범위에 더하고, 설정은 고를 때만 적는다', () async {
      final asked = <Map<String, dynamic>>[];
      final scene = makeScene();
      addTearDown(scene.dispose);
      final bus = AppBus(
        ask: (q) async {
          asked.add(q);
          if (q['op'] == 'names_info') {
            return {'packs': [1], 'fonts': [{'uid': 'font:byeol', 'pack': 1, 'family': '별바다 글씨', 'license': '확인용', 'ranges': ['U+F1A00-F1A0B']}, {'uid': 'font:gone', 'pack': 1, 'family': '사라진 글씨'}]};
          }
          if (q['op'] == 'font_data') {
            return {'fonts': [{'uid': 'font:byeol', 'family': '별바다 글씨', 'mime': 'font/ttf', 'data': _mockFont}], 'missing': [{'uid': 'font:gone', 'why': '원본 없이 넣은 DLC라 글꼴 파일을 꺼낼 수 없습니다'}]};
          }
          return const {};
        },
        controller: scene.controller,
        scene: scene,
      );
      final glue = NamesGlue(bus)..start();
      addTearDown(glue.dispose);
      for (int i = 0; i < 20 && ScriptFonts.instance.windowExtra.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(NamesInfo.of(bus).visible([1]), isTrue);
      expect(asked.map((q) => q['op']), ['names_info', 'font_data']);
      expect(asked.last['uids'], ['font:byeol', 'font:gone']);
      expect(ScriptFonts.instance.isLoaded('font:byeol'), isTrue);
      expect(ScriptFonts.instance.failed['font:gone'], '원본 없이 넣은 DLC라 글꼴 파일을 꺼낼 수 없습니다');
      expect(inRanges(ScriptFonts.instance.windowExtra, 0xf1a00), isTrue);
      expect(SceneNames.of(scene).bandExtra, ScriptFonts.instance.bandExtra, reason: '띠에 더할 범위를 장면에 옮긴다');
      expect(SceneNames.of(scene).origBand, isFalse, reason: '기본은 상세 창만');

      // 기억: 적힌 것이 없으면 싣지 않고 · 고른 뒤에만 적는다.
      final dir = await Directory.systemTemp.createTemp('names-memory');
      addTearDown(() => dir.delete(recursive: true));
      final memory = await AppMemory.open(folder: dir, delay: Duration.zero);
      glue.attachMemory(memory);
      expect(memory.parts.containsKey(slotNames), isFalse);
      NamesGlue.set(bus, const NamesUi(orig: 'band'));
      expect(SceneNames.of(scene).origBand, isTrue);
      expect(memory.parts[slotNames], {'orig': 'band', 'kinds': {'polity': true, 'person': true, 'place': true}});
      await memory.flush();
      expect((await readSavedNamesUi(folder: dir)).orig, 'band', reason: '다음에 켤 때 화면 글꼴보다 먼저 읽는다');
    });

    test('화면 글꼴: 앱을 켤 때 한글을 덮는 글꼴만 싣고 맨 앞에 — 고르지 않았거나 한글이 없으면 그대로', () async {
      Future<Map<String, dynamic>> ask(Map<String, dynamic> q) async {
        if (q['op'] == 'names_info') {
          return {'packs': [], 'fonts': [{'uid': 'font:sand', 'pack': 2, 'family': '모래 고딕', 'scripts': ['Hang']}, {'uid': 'font:byeol', 'pack': 2, 'family': '별바다 글씨', 'ranges': ['U+F1A00-F1A0B']}]};
        }
        return {'fonts': [for (final uid in q['uids'] as List) {'uid': uid, 'family': '?', 'mime': 'font/ttf', 'data': _mockFont}], 'missing': []};
      }

      expect(await applySavedScreenFont(ask, saved: const NamesUi()), isFalse);
      expect((sceneFamilyNow, sceneFallbackNow), (sceneFontFamily, sceneFontFallback));
      expect(await applySavedScreenFont(ask, saved: const NamesUi(screen: 'font:byeol')), isFalse, reason: '한글이 없는 글꼴');
      expect(sceneFamilyNow, sceneFontFamily);
      expect(await applySavedScreenFont(ask, saved: const NamesUi(screen: 'font:sand')), isTrue);
      expect(sceneFamilyNow, 'HT 글꼴 font:sand');
      expect(sceneFallbackNow, [sceneFontFamily, ...sceneFontFallback]);
    });
  });
}

// ── 왼쪽 칸 검사용 작은 장면 — 왼쪽 칸 240(리메이크 2부) · 줄 하나 · 분류 색 점 없음 ──

(TimelineScene, TimelinePainter) _gutterScene(Map<int, List<Map<String, dynamic>>> labels) {
  final m = 1000000.0;
  final ppm = 32 / bucketMinutes(9);
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(1000);
  final origin = tileOrigin(9, 1).toDouble();
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '확인용 가상 세계', 'events': 0}],
      'tracks': [
        {
          'id': 1, 'pack': 1, 'ord': 0, 'name': '가상 세계', 'color': 0x9fb4c7, 'dynasty': 0, 'leader': 1, 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
          'rows': [
            {'id': 0, 'height': 126, 'band_top': 19, 'band_h': 107, 'dyn_top': -1, 'lead_top': 23, 'cab_top': 46, 'text_top': 66, 'text_lines': 1,
             'rail_top': 108, 'organ_top': -1, 'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': [], 'fig': 0, 'fig_wide': 0, 'dep': 0, 'zones': 0, 'hem': 0},
          ],
          'groups': [],
        },
      ],
      'epochs': [],
    })..reduceMotion = true,
    fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
    ask: (query) async {
      if (query['op'] == 'rows_near') return {'near': [0], 'far': [0]};
      if (query['op'] != 'row_labels') return {};
      return {
        'labels': [
          for (final r in (query['rows'] as List).cast<int>()) {'row': r, 'items': labels[r] ?? const <Map<String, dynamic>>[]},
        ],
      };
    },
  );
  scene.applyLayoutToView();
  controller.resize(1920, 1080);
  controller.showRange(origin, origin + (1920 - scene.layout.gutterWidth) / ppm);
  return (scene, TimelinePainter(scene)..debug = true);
}

Future<void> _settle(TimelineScene scene, TimelinePainter painter) async {
  void paint() {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    recorder.endRecording().dispose();
  }

  for (int i = 0; i < 40; i++) {
    paint();
    await pumpEventQueue();
    scene.tick(16);
  }
  paint();
}
