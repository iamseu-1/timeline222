import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/detail_format3.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 형식 3의 상세 창 공용 부품(설계 `docs/설계-10건/A-아카이브-이음.md` 4-2 A1-c 1걸음).
// 기록은 손으로 쓴 `x_…`(같은 문서 부록 가-6의 꼴)이고, 글은 지금 연표(js/viewer.js)가 만드는 글 그대로를 기대한다.
// 이름은 모두 가상이다(솔나라 · 푸른 벼랑 · 갈마 …).

final fsi = String.fromCharCode(0x2068), pdi = String.fromCharCode(0x2069);

/// 부품 하나를 띄운다.
Future<void> show(WidgetTester tester, List<Widget> children) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Ui.bg,
        body: SizedBox(
          width: Ui.detailWidth,
          child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
        ),
      ),
    ),
  );
}

/// 화면의 글 한 줄들(RichText) — 차례대로, 격리 문자까지.
List<String> lines(WidgetTester tester) => [
  for (final r in tester.widgetList<RichText>(find.byType(RichText))) r.text.toPlainText(),
];

/// 화면에 선 [DetailLine]의 글(격리 문자를 뺀 것) — 차례대로.
List<String> detailLines(WidgetTester tester) => [
  for (final l in tester.widgetList<DetailLine>(find.byType(DetailLine))) detailPlain(l.text),
];

/// 글 안의 누르는 이름을 찾아 누른다(TextSpan의 recognizer).
void tapSpan(WidgetTester tester, String text) {
  for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
    var done = false;
    r.text.visitChildren((span) {
      if (span is TextSpan && span.text == text && span.recognizer is TapGestureRecognizer) {
        (span.recognizer! as TapGestureRecognizer).onTap!();
        done = true;
        return false;
      }
      return true;
    });
    if (done) return;
  }
  fail('누르는 이름 "$text"을(를) 찾지 못했다');
}

/// 글 안의 그 조각(TextSpan).
TextSpan spanOf(WidgetTester tester, String text) {
  TextSpan? hit;
  for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
    r.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) {
        hit = span;
        return false;
      }
      return true;
    });
    if (hit != null) return hit!;
  }
  throw StateError('조각 "$text" 없음');
}

/// 열린 창을 적어 두는 [DetailOpen].
class Opened {
  final calls = <(String, String, String?)>[];
  void open(String uid, {String kind = '', String? cell}) => calls.add((uid, kind, cell));
}

/// 원어 줄의 견본 — 솔나라(가상).
const solNames = {
  'main': [
    {'text': 'Solnara', 'lang': 'ko-Latn', 'tag': '로마자 · 한국어 로마자'},
    {'text': 'لومين', 'lang': 'ar', 'tag': '원어 · 아랍어'},
    {'text': '솔누리', 'lang': 'x-moon', 'tag': '원어 · x-moon'},
    {'text': '솔'},
  ],
  'other': [
    {'text': '松國', 'lang': 'zh-Hant', 'tag': '한자 · 중국어 번체'},
    {'text': '옛 솔골', 'tag': '옛 이름 · 기원전 300년 ~ 기원전 120년'},
  ],
};

void main() {
  group('원어 줄', () {
    testWidgets('원어 · 로마자 · 종류 없는 이름이 한 줄, 나머지는 `그 밖의 이름:` 줄', (tester) async {
      await show(tester, detailNamesLines(solNames));
      expect(detailLines(tester), [
        'Solnara (로마자 · 한국어 로마자) · لومين (원어 · 아랍어) · 솔누리 (원어 · x-moon) · 솔',
        '그 밖의 이름: 松國 (한자 · 중국어 번체) · 옛 솔골 (옛 이름 · 기원전 300년 ~ 기원전 120년)',
      ]);
    });

    testWidgets('이름마다 격리 문자(U+2068 … U+2069)로 감싼다 — 오른쪽에서 왼쪽 글이 섞여도 그 이름만 방향을 바꾼다', (tester) async {
      await show(tester, detailNamesLines(solNames));
      final first = lines(tester).first;
      expect(first, contains('$fsiلومين$pdi'));
      expect(first, startsWith('${fsi}Solnara$pdi'));
      // 꼬리표(작은 글)는 격리 밖에 있다.
      expect(first, contains('$pdi (원어 · 아랍어)'));
      // 격리 문자의 짝이 맞는다.
      expect(fsi.allMatches(first).length, 4);
      expect(pdi.allMatches(first).length, 4);
    });

    testWidgets('표준 꼬리표는 글의 언어(locale)로, `x-` 꼬리표와 꼬리표 없는 이름은 언어를 주지 않는다', (tester) async {
      await show(tester, detailNamesLines(solNames));
      expect(spanOf(tester, '$fsiلومين$pdi').locale, const Locale('ar'));
      expect(spanOf(tester, '${fsi}Solnara$pdi').locale, const Locale.fromSubtags(languageCode: 'ko', scriptCode: 'Latn'));
      expect(spanOf(tester, '$fsi松國$pdi').locale, const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'));
      expect(spanOf(tester, '$fsi솔누리$pdi').locale, isNull);
      expect(spanOf(tester, '$fsi솔$pdi').locale, isNull);
    });

    test('언어 꼬리표 읽기', () {
      expect(detailLocaleOf('ko'), const Locale('ko'));
      expect(detailLocaleOf('en-GB'), const Locale.fromSubtags(languageCode: 'en', countryCode: 'GB'));
      expect(detailLocaleOf('zh-hant-tw'), const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'));
      expect(detailLocaleOf('grc'), const Locale('grc'));
      expect(detailLocaleOf('x-moon'), isNull);
      expect(detailLocaleOf('X-Moon-Old'), isNull);
      expect(detailLocaleOf('한국어'), isNull, reason: '꼴이 틀린 꼬리표는 언어를 주지 않는다');
      expect(detailLocaleOf(''), isNull);
      expect(detailLocaleOf(null), isNull);
    });

    testWidgets('앞말은 첫 줄 앞에 — 원어가 없으면 둘째 줄 앞에', (tester) async {
      await show(tester, [
        ...detailNamesLines(solNames, lead: const [DetailBit('성 솔 — ')]),
        ...detailNamesLines(const {
          'other': [
            {'text': '솔씨', 'tag': '옛 이름'},
          ],
        }, lead: const [DetailBit('성 솔 — ')]),
      ]);
      final all = detailLines(tester);
      expect(all[0], startsWith('성 솔 — Solnara'));
      expect(all[1], startsWith('그 밖의 이름: '));
      expect(all[2], '성 솔 — 그 밖의 이름: 솔씨 (옛 이름)');
    });

    testWidgets('빈 값이면 위젯이 없다', (tester) async {
      expect(detailNamesLines(null), isEmpty);
      expect(detailNamesLines(const {}), isEmpty);
      expect(detailNamesLines(const {'main': [], 'other': []}), isEmpty);
      expect(
        detailNamesLines(const {
          'main': [
            {'text': ''},
          ],
        }),
        isEmpty,
        reason: '글이 빈 이름은 없는 것',
      );
      expect(detailNamesLines('글자'), isEmpty);
      await show(tester, [const DetailNamesLine(null)]);
      expect(find.byType(RichText), findsNothing);
      expect(find.byType(DetailLine), findsNothing);
    });
  });

  group('사람 고리 · 혈연 줄', () {
    const here = 'sol/p-sol';

    testWidgets('같은 나라의 칸은 이름만, 다른 나라의 칸은 `나라 이름`, 인물은 이름 — 누르면 그 창', (tester) async {
      final o = Opened();
      await show(tester, [
        DetailPersonRing(const {'name': '솔 바람', 'uid': here, 'ref': 'leader:2', 'polity': '솔나라'}, open: o.open, here: here, lead: const [DetailBit('사람: ')]),
        DetailPersonRing(const {'name': '갈마 해', 'uid': 'gal/p-gal', 'ref': 'leader:0', 'polity': '갈마국'}, open: o.open, here: here),
        DetailPersonRing(const {'name': '솔 바람', 'uid': 'sol/f-baram'}, open: o.open, here: here),
        DetailPersonRing(const {'name': '미상', 'unknown': 1}, open: o.open, here: here),
        DetailPersonRing(const {'name': '나루 볕', 'missing': 1}, open: o.open, here: here),
        DetailPersonRing(const {'name': '이름만'}, open: o.open),
      ]);
      expect(detailLines(tester), ['사람: 솔 바람', '갈마국 갈마 해', '솔 바람', '미상', '나루 볕 (찾지 못한 이름)', '이름만']);

      tapSpan(tester, '갈마국 갈마 해');
      expect(o.calls.last, ('gal/p-gal', '', 'leader:0'));
      // 같은 글('솔 바람')이 칸과 인물 두 번 — 첫째는 칸.
      final spans = <TextSpan>[];
      for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
        r.text.visitChildren((s) {
          if (s is TextSpan && s.text == '솔 바람') spans.add(s);
          return true;
        });
      }
      expect(spans, hasLength(2));
      (spans[0].recognizer! as TapGestureRecognizer).onTap!();
      expect(o.calls.last, (here, '', 'leader:2'));
      (spans[1].recognizer! as TapGestureRecognizer).onTap!();
      expect(o.calls.last, ('sol/f-baram', 'figure', null));
      // 미상 · 못 찾은 이름은 누르지 않는다.
      expect(spanOf(tester, '미상').recognizer, isNull);
      expect(spanOf(tester, '나루 볕').recognizer, isNull);
    });

    testWidgets('혈연 줄 — 부모 · 조상 / 배우자 / 자식 · 후손의 차례와 글', (tester) async {
      final o = Opened();
      await show(
        tester,
        detailKinLines(
          const {
            'parents': [
              {'name': '솔 바위', 'uid': here, 'ref': 'leader:1', 'polity': '솔나라', 'as': '부', 'certainty': 'estimated'},
              {'name': '나루 달', 'uid': 'sol/f-dal', 'as': '모'},
              {'name': '솔 첫샘', 'missing': 1, 'as': '3대 조상', 'note': '족보에만'},
            ],
            'spouses': [
              {'name': '갈마 이슬', 'uid': 'gal/p-gal', 'ref': 'leader:4', 'polity': '갈마국', 'when': '기원전 210년 ~ 기원전 190년'},
            ],
            'children': [
              {'name': '솔 새벽', 'uid': here, 'ref': 'leader:3', 'polity': '솔나라'},
              {'name': '솔 들', 'uid': 'sol/f-deul', 'as': '양자'},
            ],
          },
          open: o.open,
          here: here,
        ),
      );
      expect(detailLines(tester), [
        '부모 · 조상: 부 솔 바위 추정 · 모 나루 달 · 3대 조상 솔 첫샘 (찾지 못한 이름) 족보에만',
        '배우자: 갈마국 갈마 이슬 기원전 210년 ~ 기원전 190년',
        '자식 · 후손: 솔 새벽 · 솔 들 양자',
      ]);
      tapSpan(tester, '솔 새벽');
      expect(o.calls.last, (here, '', 'leader:3'));
    });

    testWidgets('속한 단체 줄 — 단체의 구성원으로 적힌 곳(누르면 단체 창)', (tester) async {
      final o = Opened();
      await show(
        tester,
        detailPersonGroupsLines(const {
          'groups': [
            {'uid': 'sol/gr-east', 'name': '동녘파'},
            {'uid': 'sol/gr-water', 'name': '물길회'},
          ],
        }, open: o.open),
      );
      expect(detailLines(tester), ['속한 단체: 동녘파 · 물길회']);
      tapSpan(tester, '물길회');
      expect(o.calls.last, ('sol/gr-water', 'group', null));
      expect(detailPersonGroupsLines(const {'parents': []}, open: o.open), isEmpty);
      expect(detailPersonGroupsLines(null, open: o.open), isEmpty);
    });

    test('혈연이 없으면 줄이 없다', () {
      expect(detailKinLines(null, open: Opened().open), isEmpty);
      expect(detailKinLines(const {'parents': [], 'spouses': []}, open: Opened().open), isEmpty);
    });
  });

  group('지명 줄', () {
    testWidgets('원어가 있으면 원어 줄 꼴로 — 위 구역은 `… 에 속함`(작게)', (tester) async {
      await show(tester, [
        ...detailPlaceLines(const {
          'name': '푸른 벼랑',
          'uid': 'place:pl-bluecliff',
          'up': ['청해', '솔 땅'],
          'names': {
            'main': [
              {'text': 'Pureun Byeorang', 'lang': 'ko-Latn', 'tag': '로마자 · 한국어 로마자'},
            ],
            'other': [
              {'text': '靑崖', 'tag': '한자'},
            ],
          },
        }, lead: '지명'),
      ]);
      expect(detailLines(tester), [
        '지명 푸른 벼랑 청해에 속함 — Pureun Byeorang (로마자 · 한국어 로마자)',
        '그 밖의 이름: 靑崖 (한자)',
      ]);
    });

    testWidgets('원어가 없으면 — 사건의 `장소`는 늘, 도읍 칸의 `지명`은 위 구역이 있을 때만', (tester) async {
      await show(tester, [
        ...detailPlaceLines(const {'name': '갈대 나루'}, lead: '장소'),
        ...detailPlaceLines(const {'name': '갈대 나루'}, lead: '지명'),
        ...detailPlaceLines(const {
          'name': '갈대 나루',
          'up': [
            {'uid': 'place:pl-reed', 'name': '갈대 고을'},
          ],
        }, lead: '지명'),
      ]);
      expect(detailLines(tester), ['장소 갈대 나루', '지명 갈대 나루 갈대 고을에 속함']);
    });

    test('지명이 없으면 줄이 없다', () {
      expect(detailPlaceLines(null, lead: '장소'), isEmpty);
      expect(detailPlaceLines(const {'name': ''}, lead: '장소'), isEmpty);
      expect(detailPlaceLines(const {'name': '갈대 나루'}, lead: '지명'), isEmpty);
    });
  });

  group('법 · 선거', () {
    testWidgets('법 양식 — 머리의 고침 종류 · 조항 수, 법 이름, 조항, 메모', (tester) async {
      await show(tester, [
        const DetailLawBlock({
          'name': '솔나라 물길법',
          'act': 'amend',
          'actName': '개정',
          'articles': [
            {'no': '제1조', 'text': '물길은 모두의 것이다.'},
            '제2조 물길을 막은 자는 벌한다.',
          ],
          'note': '가뭄 뒤에 고쳤다.',
        }),
        const DetailLawBlock({'name': '이름만 적은 법'}),
      ]);
      final boxes = tester.widgetList<DetailBox>(find.byType(DetailBox)).toList();
      expect(boxes.map((b) => '${b.title} ${b.small}'), ['법 개정 · 조항 2개', '법 제정 · 개정 · 폐지를 적지 않음']);
      expect(find.text('제1조 물길은 모두의 것이다.'), findsOneWidget);
      expect(find.text('제2조 물길을 막은 자는 벌한다.'), findsOneWidget);
      expect(find.text('가뭄 뒤에 고쳤다.'), findsOneWidget);
      expect(detailLines(tester), ['솔나라 물길법', '이름만 적은 법']);
    });

    testWidgets('선거 표의 열 차례 — 누구 · 득표 · 의석 · 당선(있는 열만)', (tester) async {
      await show(tester, [
        const DetailElectionTable({
          'office': '물길 지기',
          'results': [
            {'who': '솔 바람', 'votes': 12345, 'seats': 7, 'won': 1},
            {
              'who': {'name': '갈마 해', 'uid': 'sol/f-hae'},
              'votes': 9870.5,
            },
          ],
          'note': '두 번째 투표.',
        }),
      ]);
      final table = tester.widget<Table>(find.byType(Table));
      String cellText(TableRow row, int i) => tester.widget<Text>(find.descendant(of: find.byWidget(row.children[i]), matching: find.byType(Text))).data!;
      expect([for (int i = 0; i < 4; i++) cellText(table.children[0], i)], ['누구', '득표', '의석', '']);
      expect([for (int i = 0; i < 4; i++) cellText(table.children[1], i)], ['솔 바람', '12,345', '7', '당선']);
      expect([for (int i = 0; i < 4; i++) cellText(table.children[2], i)], ['갈마 해', '9,870.5', '', '']);
      // 당선 줄은 굵게.
      expect(tester.widget<Text>(find.text('솔 바람')).style!.fontWeight, FontWeight.w600);
      expect(tester.widget<Text>(find.text('갈마 해')).style!.fontWeight, FontWeight.w400);
      final box = tester.widget<DetailBox>(find.byType(DetailBox));
      expect('${box.title} ${box.small}', '선거 물길 지기');
      expect(find.text('두 번째 투표.'), findsOneWidget);
    });

    testWidgets('의석만 있으면 득표 열이 없다', (tester) async {
      await show(tester, [
        const DetailElectionTable({
          'results': [
            {'who': '솔 바람', 'seats': 3},
          ],
        }),
      ]);
      final table = tester.widget<Table>(find.byType(Table));
      expect(table.children.first.children, hasLength(3));
      expect(DetailElectionTable.headsOf(const [
        {'who': '솔 바람', 'seats': 3},
      ]), ['누구', '의석', '']);
      expect(tester.widget<DetailBox>(find.byType(DetailBox)).small, isNull);
    });

    test('수 글은 세 자리마다 쉼표', () {
      expect(detailNumberText(0), '0');
      expect(detailNumberText(999), '999');
      expect(detailNumberText(1000), '1,000');
      expect(detailNumberText(1234567), '1,234,567');
      expect(detailNumberText(1234.5), '1,234.5');
      expect(detailNumberText(null), '');
    });

    testWidgets('빈 법 · 빈 선거는 묶음이 없다', (tester) async {
      await show(tester, [const DetailLawBlock(null), const DetailLawBlock({}), const DetailElectionTable(null), const DetailElectionTable({})]);
      expect(find.byType(DetailBox), findsNothing);
      expect(detailLensBottom(const {}, Opened().open), isEmpty);
    });
  });

  group('사건 딱지 · 사건 아래 묶음 · 나라의 칩', () {
    const event = {
      'title': '물길 나눔',
      'themeRefs': [
        {'ref': 'law', 'id': 'law', 'name': '법률', 'color': '#bba395', 'auto': false},
        {'ref': '물길', 'id': 'theme-x', 'name': '물길', 'color': '#a0bcc5', 'auto': true},
      ],
      'x_law': {'name': '솔나라 물길법', 'act': 'enact', 'actName': '제정'},
      'x_election': {
        'results': [
          {'who': '솔 바람', 'won': 1},
        ],
      },
      'x_groups': [
        {'uid': 'sol/gr-water', 'name': '물길회', 'color': '#a0bcc5', 'typeName': '세력'},
        {'name': '찾지 못한 모임'},
      ],
    };

    testWidgets('딱지 차례 — 주제 → 법 · 고침 종류 → 선거', (tester) async {
      await show(tester, [Wrap(children: detailLensBadges(event))]);
      expect(tester.widgetList<DetailBadge>(find.byType(DetailBadge)).map((b) => b.text), ['법률', '물길', '법 · 제정', '선거']);
      expect(tester.widgetList<DetailBadge>(find.byType(DetailBadge)).first.color, const Color(0xffbba395));
      expect(detailLensBadges(const {'title': '보통 사건'}), isEmpty);
    });

    testWidgets('사건 아래 — 법 → 선거 → 이 일로 맺은 단체(종류를 작게) · 누르면 단체 창', (tester) async {
      final o = Opened();
      await show(tester, detailLensBottom(event, o.open));
      expect(tester.widgetList<DetailBox>(find.byType(DetailBox)).map((b) => b.title), ['법', '선거', '이 일로 맺은 단체']);
      final chips = tester.widgetList<DetailDotChip>(find.byType(DetailDotChip)).toList();
      expect(chips.map((c) => c.label), ['물길회 세력', '찾지 못한 모임']);
      expect(chips[1].onTap, isNull, reason: '찾지 못한 단체는 누르지 않는다');
      await tester.tap(find.byWidget(chips[0]));
      expect(o.calls.last, ('sol/gr-water', 'group', null));
    });

    testWidgets('나라의 단체 · 제도 칩 — 구성 나라로 든 연합 · 단체 종류 · 갈래', (tester) async {
      final o = Opened();
      await show(
        tester,
        detailPolityLensBoxes(const {
          'x_groupLinks': [
            {'uid': 'sol/gr-east', 'name': '동녘파', 'color': '#d4a39b', 'role': 'within', 'typeName': '붕당·파벌'},
            {'uid': 'sol/gr-league', 'name': '세 물길 연합', 'color': '#9dbea8', 'role': 'member', 'typeName': '연합·동맹'},
          ],
          'x_institutions': [
            {'uid': 'sol/in-tax', 'name': '솔나라 · 조세제도', 'theme': 'tax', 'themeName': '조세제도', 'family': '물길세', 'color': '#d7c18e'},
            {'uid': 'sol/in-sel', 'name': '솔나라 · 선발제도', 'theme': 'selection', 'themeName': '선발제도', 'color': '#9dbea8'},
          ],
        }, o.open),
      );
      final boxes = tester.widgetList<DetailBox>(find.byType(DetailBox)).toList();
      expect(boxes.map((b) => '${b.title} ${b.small}'), ['단체 2', '제도 2']);
      expect(tester.widgetList<DetailDotChip>(find.byType(DetailDotChip)).map((c) => c.label), ['동녘파 붕당·파벌', '세 물길 연합 구성 나라로', '조세제도 물길세', '선발제도']);
      await tester.tap(find.text('조세제도 물길세', findRichText: true));
      expect(o.calls.last, ('sol/in-tax', 'institution', null));
      expect(detailPolityLensBoxes(const {'name': '단체 없는 나라'}, o.open), isEmpty);
    });

    testWidgets('확인할 것 — 노란 상자에 건수', (tester) async {
      await show(tester, detailWarnBox(const ['나라 "솔나라"를 찾지 못했습니다.', '연합인데 구성 나라가 하나뿐입니다.']));
      final box = tester.widget<DetailBox>(find.byType(DetailBox));
      expect('${box.title} ${box.small} ${box.warn}', '확인할 것 2 true');
      expect(find.text('연합인데 구성 나라가 하나뿐입니다.'), findsOneWidget);
      expect(detailWarnBox(null), isEmpty);
      expect(detailWarnBox(const []), isEmpty);
    });
  });
}
