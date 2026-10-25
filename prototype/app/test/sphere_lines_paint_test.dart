import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/aux_calendar.dart' show YearCycle;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/gutter.dart';
import 'package:archive_prototype/scene/paint/sphere_lines.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/ruler.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/sphere_rows.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:flutter_test/flutter_test.dart';

import 'load_app_fonts.dart';
import 'support/fold_rows.dart';
import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 문화권 머리 단 밑 줄의 그림(리메이크 4단계 과제 3 걸음 2 — scene/paint/sphere_lines.dart).
// 기준은 메이커 서고 미리보기 js/timeline.js `_drawSphereRows` · css `.tl-srow` · `.tl-srow-cy` · `.tl-srow-lab`:
//   시대 칩 높이 14(둥근 3 · 테 먹 30 · 글 8.5 · 안 여백 4 · 줄임) · 주기 줄 13(칸마다 왼쪽 금 · 가운데 글) · 줄 자리는 그림판 왼쪽 ~ 오른쪽 끝 − 20 ·
//   줄 이름표는 왼쪽 칸 오른쪽 끝에서 12 앞에 오른쪽 맞춤.
// 사람 띠(과제 4 걸음 1 — `_drawSphereRows` 2205 ~ 2213줄 · css `.tl-person`): 주기 줄 밑에 줄마다 16 · 흰 종이 · 테 먹 50 · 둥근 끝 8 ·
//   구멍(테 안 왼쪽 6) · 이름 10 굵게(테 안 왼쪽 15) 뒤 6에 때 글 · 60 아래면 때 글 없이 · 40 아래면 구멍만(테 안 왼쪽 4) · 최소 폭 14.
// 앞 묶음은 그릴 것의 셈(plan — 글자 폭은 글자 수 × 크기 × .9의 가짜 자)으로 자리를 보고, 뒤 묶음은 실제 그리개로 장면 하나를 그려 왼쪽 칸 층을 본다.

/// 가상 팩 f4-sphere의 문화권 줄(test/fixtures/f4-sphere-layout4.json).
Map<String, SphereRows> fixtureRows() {
  final json = jsonDecode(File('test/fixtures/f4-sphere-layout4.json').readAsStringSync()) as Map<String, dynamic>;
  return collectSphereRows([for (final x in json['sphereLines'] as List) SphereLine.fromJson(x as Map)]);
}

/// 가상 팩 f4-crowns의 사람 띠(test/fixtures/f4-crowns-layout4.json — 은 하림 · 왕관 여섯).
Map<String, SphereRows> crownsRows() {
  final json = jsonDecode(File('test/fixtures/f4-crowns-layout4.json').readAsStringSync()) as Map<String, dynamic>;
  return collectSphereRows([for (final x in json['sphereLines'] as List) SphereLine.fromJson(x as Map)]);
}

/// 초원(steppe)의 사람 띠 한 줄 — [from] ~ [to]해, 왕관 둘.
SphereLine person(String name, double from, double to) => SphereLine(
  SphereLine.person, 'steppe', minuteOfYear(from).round(), minuteOfYear(to).round(), name,
  uid: 'fig-$name', data: '[{"uid":"a","cell":0},{"uid":"b","cell":1}]',
);

/// 가짜 글자 폭: 글자 수 × 크기 × .9(한글 한 자가 크기의 .9쯤).
double? fakeWidth(String text, TextLook look) => text.runes.length * look.size * .9;

const left = 240.0, w = 1920.0, right = w - 20;

/// 해 [from] ~ [to]가 그림판(왼쪽 240 ~ 1920)에 보이는 셈 — 줄 영역 위 100 · 상자 아랫변 [bottom].
SphereLinesPlan planOf(SphereRows rows, double from, double to, {double bottom = 100 + 27, double? Function(String, TextLook) widthOf = fakeWidth}) {
  final lo = minuteOfYear(from), hi = minuteOfYear(to);
  final ppm = (w - left) / (hi - lo);
  return SphereLinesPaint.plan(
    rows, top: 100, bottom: bottom, left: left, right: right,
    xOf: (m) => left + (m - lo) * ppm, loMinute: lo, hiMinute: hi, ppm: ppm, widthOf: widthOf,
  );
}

double xYear(double from, double to, num year) => left + (minuteOfYear(year.toDouble()) - minuteOfYear(from)) * (w - left) / (minuteOfYear(to) - minuteOfYear(from));

void main() {
  group('그릴 것의 셈', () {
    test('시대 칩: 시작 · 끝 해 자리(정수 px) · 줄 위 · 안 여백 4 뒤의 글 — 줄 이름표 "시대"는 왼쪽 칸 오른쪽 끝에서 12 앞', () {
      final p = planOf(fixtureRows()['ember-basin']!, -20, 1420);
      expect(p.epochTop, 100);
      expect(p.chips, hasLength(2));
      final first = p.chips[0], second = p.chips[1];
      expect(first.x0, xYear(-20, 1420, 1).roundToDouble());
      expect(first.x1, second.x0, reason: '두 시대가 맞닿는다(788년)');
      expect(second.x1, closeTo(xYear(-20, 1420, 1031), 1));
      expect([first.top, second.top], [100, 100]);
      expect([first.text, second.text], ['등불 왕국 시대', '아홉 불씨 시대']);
      expect(first.textX, first.x0 + 5);
      expect(p.labels.first, ('시대', left - 12 - fakeWidth('시대', SphereLinesLook.label)!, 100.0));
    });

    test('시대 칩이 그림판 왼쪽 앞에서 시작하면 왼쪽 끝에 붙고, 줄 자리 오른쪽 끝(− 20)을 넘으면 거기서 잘린다(오른쪽 열림)', () {
      final p = planOf(fixtureRows()['ember-basin']!, 500, 900);
      expect(p.chips.first.x0, left);
      expect(p.chips.first.openRight, isFalse);
      expect(p.chips.last.x1, right);
      expect(p.chips.last.openRight, isTrue);
    });

    test('글이 칩 밖으로 나가지 않는다 — 넘치면 끝을 "…"로, "…"도 안 들면 글 없이', () {
      for (final (from, to) in [(-20.0, 1420.0), (-20.0, 9000.0), (-20.0, 30000.0), (-20.0, 60000.0), (500.0, 900.0)]) {
        final p = planOf(fixtureRows()['ember-basin']!, from, to);
        for (final c in p.chips) {
          if (c.text.isEmpty) continue;
          final tw = fakeWidth(c.text, SphereLinesLook.chip)!;
          expect(c.textX, greaterThanOrEqualTo(c.x0 + 1), reason: '$from ~ $to · $c');
          expect(c.textX + tw, lessThanOrEqualTo(c.x1 - 1), reason: '$from ~ $to · $c');
        }
      }
      // 아주 넓게(해 3만 — 첫 시대 칩 44px · 글 들 폭 34): 첫 시대 칩은 줄임표로.
      final narrow = planOf(fixtureRows()['ember-basin']!, -20, 30000);
      expect(narrow.chips.first.text, endsWith('…'));
      expect('등불 왕국 시대'.startsWith(narrow.chips.first.text.replaceAll('…', '').trimRight()), isTrue);
    });

    test('이름 돌림 — 해 한 칸이 9px 이상이면 해마다 칸(첫 이름이 바퀴의 첫 칸) · 16px 아래면 글 없음', () {
      // 280 ~ 420년: 1680px에 140해 → 해 한 칸 12px.
      final p = planOf(fixtureRows()['ember-basin']!, 280, 420);
      expect(p.cycleTop, 114, reason: '시대 줄 14 아래');
      expect(p.labels.map((l) => l.$1), ['시대', '불씨해']);
      expect(p.labels.last.$3, 114);
      expect(p.cells.length, inInclusiveRange(138, 141), reason: '280 ~ 418년(419년부터는 줄 자리 오른쪽 끝 − 20 밖)');
      final c280 = p.cells.firstWhere((c) => c.x0 == xYear(280, 420, 280).roundToDouble());
      expect(c280.first, isTrue, reason: '(280 − 1) % 9 = 0 — 바퀴의 첫 이름');
      expect(c280.x1, xYear(280, 420, 281).roundToDouble());
      expect(p.cells.where((c) => c.first).length, inInclusiveRange(15, 17));
      expect(p.cells.every((c) => c.text.isEmpty), isTrue, reason: '12px < 16px — 글 없음');
      // 300 ~ 350년: 해 한 칸 33.6px — 이름이 칸 가운데에.
      final near = planOf(fixtureRows()['ember-basin']!, 300, 350);
      final named = near.cells.where((c) => c.text.isNotEmpty).toList();
      expect(named.length, greaterThan(40));
      final c307 = near.cells.firstWhere((c) => c.x0 == xYear(300, 350, 307).roundToDouble());
      expect((c307.text, c307.first), ('한낮', true), reason: '(307 − 1) % 9 = 0');
      final c308 = near.cells.firstWhere((c) => c.x0 == xYear(300, 350, 308).roundToDouble());
      expect((c308.text, c308.first), ('별', false));
      for (final c in named) {
        final tw = fakeWidth(c.text, c.first ? SphereLinesLook.first : SphereLinesLook.cell)!;
        expect(c.textX, greaterThanOrEqualTo(c.x0 + 1));
        expect(c.textX + tw, lessThanOrEqualTo(c.x1 + .001));
        expect(c.textX - (c.x0 + 1), closeTo(c.x1 - (c.textX + tw), .001), reason: '가운데');
        expect(c.textX, greaterThanOrEqualTo(left));
        expect(c.textX + tw, lessThanOrEqualTo(right));
      }
    });

    test('이름 돌림 — 해 한 칸이 좁으면 한 바퀴(9해)가 한 칸: "첫 이름 해" → "첫 이름" → 빈 칸(모두 첫 이름 칸)', () {
      // −20 ~ 1420년: 해 한 칸 1.17px · 바퀴 칸 10.5px — 글 없음.
      final wide = planOf(fixtureRows()['ember-basin']!, -20, 1420);
      expect(wide.cells.every((c) => c.first && c.text.isEmpty), isTrue);
      expect(wide.cells.length, inInclusiveRange(158, 161), reason: '기원전 27년(천문 해 −26)부터 9해마다 · 줄 자리 오른쪽 끝 − 20 밖은 뺌');
      // 0 ~ 400년: 해 한 칸 4.2px · 바퀴 칸 37.8px — '한낮'(14.4) + 6은 들고, 해 글이 붙으면 '한낮 1'(28.8) + 8만 들고 '한낮 10'(36) + 8부터는 안 든다.
      final mid = planOf(fixtureRows()['ember-basin']!, 0, 400);
      final inner = mid.cells.where((c) => c.x0 > left && c.x1 < right).toList();
      expect(inner.map((c) => c.text).toSet(), {'한낮 1', '한낮'});
      expect(inner.where((c) => c.text == '한낮').length, greaterThan(30));
      // 0 ~ 250년: 해 한 칸 6.7px · 바퀴 칸 60.5px — '한낮 10'(25.2) + 8이 든다.
      final roomy = planOf(fixtureRows()['ember-basin']!, 1, 250);
      final c10 = roomy.cells.firstWhere((c) => c.x0 == xYear(1, 250, 10).roundToDouble());
      expect(c10.text, '한낮 10');
      // 가장자리 칸은 보이는 몫만(왼쪽 끝에 붙음 — 금도 거기에).
      expect(roomy.cells.first.x0, left);
    });

    test('연호 눈금 — step(10)해마다 칸 · 40px 이상이면 "연호 n년"(n = 해 − 원년)', () {
      final p = planOf(fixtureRows()['frost-ridge']!, 280, 420);
      expect(p.labels.map((l) => l.$1), ['시대', '빙원력']);
      expect(p.cells.first.x0, xYear(280, 420, 280).roundToDouble());
      expect(p.cells.first.text, '빙원 -20년');
      expect(p.cells[2].text, '빙원 0년');
      expect(p.cells.every((c) => c.first), isTrue);
      expect(p.cells.length, 14, reason: '280 ~ 410년(420년은 줄 자리 밖)');
      // −20 ~ 1420년: 칸 11.7px — 글 없음.
      expect(planOf(fixtureRows()['frost-ridge']!, -20, 1420).cells.every((c) => c.text.isEmpty), isTrue);
    });

    // 검토 지적(2026-10-25): 순번 · 바퀴 · '연호 n년'을 해 좌표(0년이 빈 자리)의 차이로 세면 기원전과 기원후 사이에서 한 해 어긋난다.
    // 계약의 이름 돌림은 최상위 yearCycle과 같은 읽기(js/core.js `HT.cycleIndex` — 천문 해)이고 날짜 칸 사용자 순환(aux_calendar.dart `YearCycle`)도 그렇게 센다.
    test('0을 건널 때도 천문 해로 센다 — 이름 돌림의 순번 · 바퀴 칸(n해를 덮음) · "연호 n년"이 날짜 칸의 사용자 순환과 같다', () {
      SphereRows cycleRows(String data) => collectSphereRows([SphereLine.fromJson({'kind': 3, 'sphere': 'steppe', 'data': data})])['steppe']!;
      String nameAt(SphereLinesPlan p, double from, double to, int year) => p.cells.firstWhere((c) => c.x0 == xYear(from, to, year).roundToDouble()).text;
      // 이름 둘 · 기준 해 1: 기원전 1년과 기원후 1년은 다른 이름 — 0을 건너도 번갈아 간다.
      final two = planOf(cycleRows('{"names":["홀","짝"],"start":1}'), -10, 10);
      expect([for (final y in [-3, -2, -1, 1, 2, 3]) nameAt(two, -10, 10, y)], ['짝', '홀', '짝', '홀', '짝', '홀'], reason: '기원전 1년 = 천문 해 0 → (0 − 1) % 2 = 1');
      const same = YearCycle(names: ['홀', '짝'], start: 1);
      expect([for (final y in [-3, -2, -1, 1, 2, 3]) same.name(y)], ['짝', '홀', '짝', '홀', '짝', '홀'], reason: '날짜 칸의 사용자 순환과 같은 이름');
      // 육십 이름 · 기준 해 4(육십갑자 자리): 첫 이름(바퀴의 첫 칸)은 기원전 57년(천문 해 −56)이다 — 해 좌표로 세면 기원전 56년으로 1년 늦게 선다.
      final sixty = [for (int i = 0; i < 60; i++) '이$i'];
      final p60 = planOf(cycleRows('{"names":${jsonEncode(sixty)},"start":4}'), -70, -40);
      final firstCell = p60.cells.firstWhere((c) => c.first);
      expect(firstCell.x0, xYear(-70, -40, -57).roundToDouble());
      final cycle = YearCycle(names: sixty, start: 4);
      for (final c in p60.cells.where((c) => c.text.isNotEmpty)) {
        final y = [for (int y = -70; y <= -40; y++) if (y != 0) y].firstWhere((y) => xYear(-70, -40, y).roundToDouble() == c.x0);
        expect(c.text, cycle.name(y), reason: '기원전 ${-y}년 — 날짜 칸의 사용자 순환과 같은 이름');
      }
      // 바퀴 칸: 이름 아홉 · 기준 해 1 — 0을 건너는 바퀴는 기원전 9년(천문 해 −8) ~ 기원후 1년, 아홉 해를 덮는다.
      final wide = planOf(fixtureRows()['ember-basin']!, -20, 1420);
      expect(wide.cells.any((c) => c.x0 == xYear(-20, 1420, -9).roundToDouble() && c.x1 == xYear(-20, 1420, 1).roundToDouble()), isTrue);
      expect(wide.cells.any((c) => c.x0 == xYear(-20, 1420, -8).roundToDouble()), isFalse, reason: '해 좌표로 세면 기원전 8년에 서서 여덟 해만 덮는다');
      // 연호 눈금: 원년 기원전 10년 · 10해마다 — 기원후 10년은 원년에서 19해(해 좌표의 차이 20이 아님).
      final era = planOf(cycleRows('{"era":"옛","from":-10,"step":10}'), -30, 300);
      expect(nameAt(era, -30, 300, 10), '옛 19년');
      expect(nameAt(era, -30, 300, -10), '옛 0년');
      expect(nameAt(era, -30, 300, -20), '옛 -10년');
    });

    test('상자에 다 들지 않는 줄은 셈하지 않는다(접고 펼 때 상자가 자라는 동안) · 글자 폭을 모르면 기다림', () {
      final rows = fixtureRows()['ember-basin']!;
      final half = planOf(rows, -20, 1420, bottom: 100 + 20);
      expect((half.epochTop, half.cycleTop), (100.0, null));
      expect(half.cells, isEmpty);
      final none = planOf(rows, -20, 1420, bottom: 100 + 10);
      expect((none.epochTop, none.cycleTop, none.chips.length), (null, null, 0));
      final waiting = planOf(rows, -20, 1420, widthOf: (_, _) => null);
      expect(waiting.waiting, isTrue);
      expect(waiting.chips.every((c) => c.text.isEmpty), isTrue);
    });

    test('줄이 없으면 아무것도 셈하지 않는다', () {
      final p = planOf(SphereRows.none, -20, 1420);
      expect((p.epochTop, p.cycleTop, p.personTop, p.chips.length, p.cells.length, p.labels.length, p.persons.length), (null, null, null, 0, 0, 0, 0));
    });
  });

  group('사람 띠의 셈(4단계 과제 4 걸음 1)', () {
    test('정답 자료 f4-crowns — 은 하림 1420 ~ 1455: 띠 자리 · 구멍(테 안 왼쪽 6) · 이름(테 안 왼쪽 15) 뒤 6에 때 글 · 줄 이름표 없음', () {
      final rows = crownsRows()['frost-ridge']!;
      final p = planOf(rows, 1400, 1480, bottom: 100 + 16);
      expect(p.personTop, 100, reason: '시대 · 주기 줄이 없으면 사람 띠가 줄 영역 맨 위');
      expect(p.labels, isEmpty, reason: '사람 띠 줄은 왼쪽 칸 이름표가 없다(미리보기 그대로)');
      final band = p.persons.single;
      expect(band.x0, xYear(1400, 1480, 1420).roundToDouble());
      expect(band.x1, xYear(1400, 1480, 1455).roundToDouble());
      expect((band.top, band.bottom, band.shape, band.openRight), (100.0, 116.0, SpherePersonShape.full, false));
      expect(band.holeX, band.x0 + 7);
      expect(band.hasHole, isTrue);
      expect((band.name, band.when), ('은 하림', '1420 ~ 1455 · 왕관 6'));
      expect(band.nameX, band.x0 + 16);
      expect(band.whenX, band.nameX + fakeWidth('은 하림', SphereLinesLook.personName)! + 6);
      expect(band.person.uid, 'f4-crowns/ps-harim');
      expect(band.person.crowns, hasLength(6));
    });

    test('좁은 띠 세 꼴 — 60 아래면 때 글 없이, 40 아래면 구멍만(테 안 왼쪽 4), 때가 없어도 최소 14 · 글은 드는 만큼 줄임', () {
      // 1000 ~ 1168년: 해 한 칸 10px.
      final rows = collectSphereRows([
        person('넉넉', 1000, 1030), // 300px — 이름 · 때 글
        person('하림', 1040, 1047), // 70px — 넉넉한 꼴 · 글 자리 47에 이름(18) + 6 뒤 때 글은 줄임
        person('빠듯한 이름', 1050, 1057), // 70px — 이름(54) + 6 + '…'도 안 들어 이름을 줄이고 때 글은 없이
        person('좁은 띠 이름', 1060, 1065), // 50px — 좁은 꼴(이름만 · 줄임)
        person('아주 좁음', 1080, 1083), // 30px — 구멍만
        person('한 점', 1100, 1100), // 0해 — 최소 14(구멍만)
      ])['steppe']!;
      final p = planOf(rows, 1000, 1168);
      final by = {for (final b in p.persons) b.person.name: b};
      expect([for (final b in p.persons) b.shape], [SpherePersonShape.full, SpherePersonShape.full, SpherePersonShape.full, SpherePersonShape.narrow, SpherePersonShape.tiny, SpherePersonShape.tiny]);
      expect(p.persons.every((b) => b.person.lane == 0), isTrue);
      expect((by['넉넉']!.name, by['넉넉']!.when), ('넉넉', '1000 ~ 1030 · 왕관 2'));
      expect((by['하림']!.name, by['하림']!.when), ('하림', '1…'));
      expect((by['빠듯한 이름']!.name, by['빠듯한 이름']!.when), ('빠듯한…', ''));
      expect(by['좁은 띠 이름']!.when, '');
      expect(by['좁은 띠 이름']!.name, endsWith('…'));
      for (final name in ['아주 좁음', '한 점']) {
        final b = by[name]!;
        expect((b.name, b.when), ('', ''), reason: name);
        expect(b.holeX, b.x0 + 5, reason: '$name — 구멍은 테 안 왼쪽 4');
        expect(b.hasHole, isTrue);
      }
      expect(by['한 점']!.x1 - by['한 점']!.x0, 14);
    });

    test('글이 띠 밖으로 나가지 않는다 — 여러 넓이 · 오른쪽 끝에서 잘린 띠까지', () {
      final rows = collectSphereRows([
        person('가나다라마바사', 1000, 1030),
        person('은 하림', 1040, 1046),
        person('긴 이름의 임금님', 1050, 1056),
        person('끝까지 가는 사람', 1100, 1300),
      ])['steppe']!;
      var seen = 0;
      for (final (from, to) in [(1000.0, 1168.0), (900.0, 1400.0), (990.0, 1060.0), (1040.0, 1160.0), (0.0, 2000.0), (1080.0, 1110.0)]) {
        final p = planOf(rows, from, to);
        for (final b in p.persons) {
          final inner = b.openRight ? b.x1 : b.x1 - 1 - 6;
          expect(b.x1 - b.x0, greaterThanOrEqualTo(1), reason: '$from ~ $to · $b');
          expect(b.x0, greaterThanOrEqualTo(left));
          expect(b.x1, lessThanOrEqualTo(right));
          if (b.name.isNotEmpty) {
            seen++;
            expect(b.nameX, b.x0 + 16, reason: '$from ~ $to · $b');
            expect(b.nameX + fakeWidth(b.name, SphereLinesLook.personName)!, lessThanOrEqualTo(inner + .001), reason: '$from ~ $to · $b');
          }
          if (b.when.isNotEmpty) {
            expect(b.whenX + fakeWidth(b.when, SphereLinesLook.personWhen)!, lessThanOrEqualTo(inner + .001), reason: '$from ~ $to · $b');
            expect(b.whenX, greaterThanOrEqualTo(b.nameX + fakeWidth(b.name, SphereLinesLook.personName)! + 6 - .001));
          }
          if (b.shape != SpherePersonShape.full) expect(b.when, isEmpty);
          if (b.shape == SpherePersonShape.tiny) expect(b.name, isEmpty);
          if (b.hasHole) expect(b.holeX + 5, lessThanOrEqualTo(b.x1));
        }
      }
      expect(seen, greaterThan(5));
      // 1150 ~ 1200년: 끝까지 가는 사람은 그림판 왼쪽에 붙고 줄 자리 오른쪽 끝(− 20)에서 잘린다(오른쪽 열림).
      final cut = planOf(rows, 1150, 1200).persons.single;
      expect(cut.person.name, '끝까지 가는 사람');
      expect((cut.x0, cut.x1, cut.openRight), (left, right, true));
    });

    test('줄마다 16 아래 · 화면 밖 띠는 없음 · 상자에 다 들지 않는 줄은 셈하지 않음(흐르는 동안) · 시대 · 주기 줄 밑에', () {
      final lines = [person('가', 1000, 1050), person('나', 1030, 1080), person('화면 밖', 1500, 1600)];
      final rows = collectSphereRows(lines)['steppe']!;
      final p = planOf(rows, 1000, 1168, bottom: 100 + 32);
      expect([for (final b in p.persons) (b.person.name, b.top)], [('가', 100.0), ('나', 116.0)]);
      final half = planOf(rows, 1000, 1168, bottom: 100 + 20);
      expect([for (final b in half.persons) b.person.name], ['가'], reason: '둘째 줄(116 ~ 132)은 상자 밖');
      expect(planOf(rows, 1000, 1168, bottom: 100 + 10).persons, isEmpty);
      // 시대 · 주기 줄과 함께: 사람 띠는 시대 14 + 주기 13 아래(127).
      final mixed = collectSphereRows([
        ...lines,
        SphereLine(SphereLine.epoch, 'steppe', minuteOfYear(1000).round(), minuteOfYear(1100).round(), '시대'),
        SphereLine.fromJson({'kind': 3, 'sphere': 'steppe', 'data': '{"era":"연호","from":1000,"step":10}'}),
      ])['steppe']!;
      final m = planOf(mixed, 1000, 1168, bottom: 100 + 14 + 13 + 32);
      expect((m.epochTop, m.cycleTop, m.personTop), (100.0, 114.0, 127.0));
      expect([for (final b in m.persons) b.top], [127.0, 143.0]);
      // 글자 폭을 모르면 기다림(띠 · 구멍은 그대로).
      final waiting = planOf(rows, 1000, 1168, bottom: 100 + 32, widthOf: (_, _) => null);
      expect(waiting.waiting, isTrue);
      expect(waiting.persons, hasLength(2));
      expect(waiting.persons.every((b) => b.name.isEmpty && b.when.isEmpty), isTrue);
    });
  });

  group('왼쪽 칸 층에서 그리기', () {
    setUpAll(loadAppFonts);

    /// 트랙 둘을 등불 분지권(펼침) · 설령 빙원권으로 — f4-sphere의 문화권 줄을 얹고(또는 없이) −20 ~ 1420년을 1920 × 1080으로.
    (TimelineScene, TimelinePainter) make({required bool lines, Set<String> folded = const {}, List<Object?> persons = const [], double height = 1080}) {
      final json = twoTrackLayout();
      (json['tracks'] as List)[0]['sphere'] = 'ember-basin';
      (json['tracks'] as List)[1]['sphere'] = 'frost-ridge';
      json['spheres'] = [
        {'id': 'ember-basin', 'name': '등불 분지권', 'count': 3, 'default': true},
        {'id': 'frost-ridge', 'name': '설령 빙원권', 'count': 2},
      ];
      if (lines) json['sphereLines'] = jsonDecode(File('test/fixtures/f4-sphere-layout4.json').readAsStringSync())['sphereLines'];
      if (persons.isNotEmpty) json['sphereLines'] = [...?json['sphereLines'] as List?, ...persons];
      final layout = SceneLayout.fromJson(json)..reduceMotion = true;
      layout.setViewState(layout.viewState.copyWith(foldedSpheres: folded));
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(1920, height)
        ..setExtent(minuteOfYear(-3000), minuteOfYear(3000))
        ..setContentHeight(layout.totalHeight);
      final scene = TimelineScene(
        controller: controller,
        layout: layout,
        fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
      );
      final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
      controller.showRange(minuteOfYear(-20), minuteOfYear(1420));
      return (scene, painter);
    }

    void paint(TimelinePainter painter) {
      for (int i = 0; i < 50; i++) {
        final recorder = ui.PictureRecorder();
        painter.paint(ui.Canvas(recorder), const ui.Size(1920, 1080));
        recorder.endRecording().dispose();
        if (!painter.text.starved) return;
      }
    }

    List<DebugLabel> of(TimelinePainter p, String kind) => [for (final l in p.debugLabels) if (l.kind == kind) l];

    test('펼친 문화권 둘의 시대 칩 · 주기 줄 이름표 · 시대 이름 — 칩 글은 칩 안, 이름표는 왼쪽 칸 오른쪽 끝에서 12 앞', () {
      final (scene, painter) = make(lines: true, folded: const {});
      paint(painter);
      final v = scene.controller.view;
      final layout = scene.layout;
      expect(of(painter, 'sphereEpoch').map((l) => l.text).toSet(), {'등불 왕국 시대', '아홉 불씨 시대', '칸국기', '제국기'});
      final labels = of(painter, 'sphereLineLabel');
      expect(labels.map((l) => l.text).toList(), ['시대', '불씨해', '시대', '빙원력']);
      for (final l in labels) {
        final tw = painter.text.widthOf(l.text, SphereLinesLook.label)!;
        expect(l.at.dx + tw, closeTo(v.left - 12, .01), reason: '${l.text}의 오른쪽 끝');
      }
      // 칩 글: 시대의 시작 x + 5 ~ 끝 x − 1 안.
      final ends = {for (final r in fixtureRows().values) for (final e in r.epochs) e.name: (e.start, e.end)};
      for (final l in of(painter, 'sphereEpoch')) {
        final (a, b) = ends[l.text]!;
        final tw = painter.text.widthOf(l.text, SphereLinesLook.chip)!;
        expect(l.at.dx, closeTo(v.xOf(a).roundToDouble() + 5, .01), reason: l.text);
        expect(l.at.dx + tw, lessThanOrEqualTo(v.xOf(b).roundToDouble() - 1), reason: l.text);
      }
      // 줄 위: 시대 줄 = 머리 단 위 + 20, 이름표 '시대'의 글줄 위와 같은 줄.
      for (int k = 0; k < 2; k++) {
        final y0 = v.yOf(layout.sphereHeadTop(k)).roundToDouble();
        expect(layout.sphereHeadHeight(k), 49);
        final epoch = labels.where((l) => l.text == '시대').elementAt(k);
        expect(epoch.at.dy, greaterThan(y0 + 20));
        expect(epoch.at.dy, lessThan(y0 + 20 + 14));
        // 상자 전체가 누름 자리 — 밑 줄 위를 눌러도 그 문화권(이름 줄 밖).
        final hit = painter.gutter.hitTest(v.left + 300, y0 + 40);
        expect(hit?.kind, GutterHitKind.sphere);
        expect(hit?.uid, layout.spheres[k].id);
      }
    });

    test('접힌 문화권은 줄을 그리지 않는다(머리 단 20 · 작은 꼬리표 자리) · 줄이 없는 자료는 줄 그림이 하나도 없다', () {
      final (_, folded) = make(lines: true, folded: const {'frost-ridge'});
      paint(folded);
      expect(of(folded, 'sphereLineLabel').map((l) => l.text).toList(), ['시대', '불씨해']);
      expect(of(folded, 'sphereEpoch').map((l) => l.text).toSet(), {'등불 왕국 시대', '아홉 불씨 시대'});
      final (scene, bare) = make(lines: false, folded: const {});
      paint(bare);
      expect(bare.gutter.personBands, isEmpty);
      for (final kind in ['sphereEpoch', 'sphereCycle', 'sphereLineLabel', 'spherePersonName', 'spherePersonWhen']) {
        expect(of(bare, kind), isEmpty, reason: kind);
      }
      expect([scene.layout.sphereHeadHeight(0), scene.layout.sphereHeadHeight(1)], [20, 20]);
    });

    /// 사람 띠 셋: 등불 분지권에 겹치는 둘(두 줄) · 설령 빙원권에 하나 — 문화권 줄(f4-sphere)과 함께.
    List<Object?> threePersons() => [
      for (final (name, sphere, from, to) in [('불씨 임금', 'ember-basin', 300.0, 700.0), ('겹친 임금', 'ember-basin', 500.0, 900.0), ('눈 임금', 'frost-ridge', 100.0, 400.0)])
        {
          'kind': 1, 'sphere': sphere, 'start': minuteOfYear(from).round(), 'end': minuteOfYear(to).round(), 'name': name, 'uid': 'fig-$name',
          'data': '[{"uid":"band-a","cell":0},{"uid":"band-b","cell":3}]',
        },
    ];

    test('사람 띠(과제 4 걸음 1): 시대 · 주기 줄 밑에 줄마다 16 — 이름 · 때 글은 띠 안, 그린 자리(문화권 · 줄 · x 범위 · 인물 uid · 왕관)를 층이 남김 · 띠를 누르면 그 사람(과제 4 걸음 3)', () {
      final (scene, painter) = make(lines: true, folded: const {}, persons: threePersons());
      paint(painter);
      final v = scene.controller.view;
      final layout = scene.layout;
      // 등불 분지권: 20 + 14 + 13 + 16 × 2 + 2 = 81 · 설령 빙원권: 20 + 14 + 13 + 16 + 2 = 65.
      expect([layout.sphereHeadHeight(0), layout.sphereHeadHeight(1)], [81, 65]);
      expect(of(painter, 'spherePersonName').map((l) => l.text).toSet(), {'불씨 임금', '겹친 임금', '눈 임금'});
      expect(of(painter, 'spherePersonWhen').map((l) => l.text).toSet(), {'300 ~ 700 · 왕관 2', '500 ~ 900 · 왕관 2', '100 ~ 400 · 왕관 2'});
      final drawn = painter.gutter.personBands;
      expect([for (final d in drawn) (d.sphere, d.band.person.name, d.band.person.lane)], [(0, '불씨 임금', 0), (0, '겹친 임금', 1), (1, '눈 임금', 0)]);
      for (final d in drawn) {
        final b = d.band, p = b.person;
        final y0 = v.yOf(layout.sphereHeadTop(d.sphere)).roundToDouble();
        expect(b.top, y0 + 20 + 27 + p.lane * 16, reason: '${p.name} — 시대 14 · 주기 13 밑에 줄마다 16');
        expect(b.x0, v.xOf(p.start).roundToDouble());
        expect(b.x1, v.xOf(p.end).roundToDouble());
        expect(p.uid, 'fig-${p.name}');
        expect(p.crowns, [(uid: 'band-a', cell: 0), (uid: 'band-b', cell: 3)]);
        // 글은 띠 안(테 안 왼쪽 15 뒤 ~ 테 안 오른쪽 6 앞) · 띠의 위아래 안.
        final name = of(painter, 'spherePersonName').firstWhere((l) => l.text == p.name);
        final when = of(painter, 'spherePersonWhen').firstWhere((l) => l.text == b.when);
        final nw = painter.text.widthOf(p.name, SphereLinesLook.personName)!, ww = painter.text.widthOf(b.when, SphereLinesLook.personWhen)!;
        expect(name.at.dx, b.x0 + 16);
        expect(when.at.dx, closeTo(b.x0 + 16 + nw + 6, .01));
        expect(when.at.dx + ww, lessThanOrEqualTo(b.x1 - 7));
        for (final l in [name, when]) {
          expect(l.at.dy, greaterThan(b.top));
          expect(l.at.dy + 10, lessThan(b.bottom));
        }
        // 사람 띠 위를 누르면 그 사람의 창(과제 4 걸음 3 — 걸음 1에서는 그 문화권 접기였다) · 띠 오른쪽 밖은 그대로 문화권.
        final hit = painter.gutter.hitTest((b.x0 + b.x1) / 2, b.top + 8);
        expect((hit?.kind, hit?.uid), (GutterHitKind.person, p.uid));
        expect(painter.gutter.hitTest(b.x1 + 10, b.top + 8)?.kind, GutterHitKind.sphere);
      }
      // 사람 띠 밑에 트랙(머리 단 상자 끝 + 4).
      expect(layout.trackTop(0), layout.sphereHeadTop(0) + 81 + 4);
    });

    test('접힌 문화권의 사람 띠는 그리지 않고 남기지도 않는다 · 사람 띠만 있는 문화권은 사람 띠가 줄 영역 맨 위', () {
      final (_, folded) = make(lines: true, folded: const {'ember-basin'}, persons: threePersons());
      paint(folded);
      expect(of(folded, 'spherePersonName').map((l) => l.text).toList(), ['눈 임금']);
      expect([for (final d in folded.gutter.personBands) d.sphere], [1]);
      final (scene, only) = make(lines: false, folded: const {}, persons: threePersons());
      paint(only);
      final v = scene.controller.view;
      expect([scene.layout.sphereHeadHeight(0), scene.layout.sphereHeadHeight(1)], [20 + 32 + 2, 20 + 16 + 2]);
      for (final d in only.gutter.personBands) {
        expect(d.band.top, v.yOf(scene.layout.sphereHeadTop(d.sphere)).roundToDouble() + 20 + d.band.person.lane * 16);
      }
      expect(of(only, 'sphereLineLabel'), isEmpty, reason: '사람 띠 줄은 이름표가 없다');
    });

    test('머리 단 고정(과제 3 걸음 4): 내려 보면 등불 분지권 상자가 그림판 위에 붙어 줄 · 사람 띠를 그리고, 그 밑 줄 이름보다 누름을 먼저 받고, 끝이 다가오면 밀려 올라간다', () {
      // 창 높이 150 — 등불 분지권: 머리 단 0 · 상자 81 · 트랙 1 85 ~ 210 · 설령 빙원권 머리 단 216.
      final (scene, painter) = make(lines: true, folded: const {}, persons: threePersons(), height: 150);
      paint(painter);
      final v = scene.controller.view, layout = scene.layout;
      final head = v.head;
      expect(painter.gutter.stuckBottom, head, reason: '처음(내려 보지 않음)은 붙은 머리 단이 없다');
      scene.controller.scrollTo(60);
      paint(painter);
      expect(v.top, 60);
      expect(layout.sphereHeadBox(0, v), (top: head, height: 81.0, stuck: true));
      expect(painter.gutter.stuckBottom, head + 80);
      // 붙은 상자 안의 사람 띠 · 줄 이름표는 그림판 위에서 센 자리.
      final bands = [for (final d in painter.gutter.personBands) if (d.sphere == 0) d.band];
      expect([for (final b in bands) b.top], [head + 20 + 27, head + 20 + 27 + 16]);
      final epochLabel = of(painter, 'sphereLineLabel').lastWhere((l) => l.text == '시대'); // 붙은 머리 단이 맨 뒤 걸음
      expect(epochLabel.at.dy, inInclusiveRange(head + 20, head + 20 + 14));
      // 붙은 머리 단은 왼쪽 칸 층의 맨 뒤 걸음 — 이름이 다른 문화권 머리 단(설령 빙원권)보다 뒤에 그려진다(그 밑을 지나는 줄 이름 글자를 덮음).
      final names = [for (final l in painter.debugLabels) if (l.kind == 'sphereName') l.text];
      expect(names, ['설령 빙원권', '등불 분지권']);
      // 누름: 상자 밑을 지나는 줄 이름(트랙 1의 첫 줄 — 몸통 89 → 화면 head + 29)보다 머리 단이 먼저 · 그림판 몫도 머리 단.
      final under = head + 89 - 60 + 4;
      expect(painter.gutter.hitTest(GutLook.rowX + 20, under)?.kind, GutterHitKind.sphere);
      expect(painter.gutter.hitTest(v.left + 300, head + 40)?.uid, 'ember-basin');
      // 상자 아래(줄 이름 자리)는 그대로 줄 이름.
      expect(painter.gutter.hitTest(GutLook.rowX + 20, head + 81 + 50)?.kind, isNot(GutterHitKind.sphere));
      // 더 내려 보면 문화권 끝(210 → 화면 head + 30)에 상자 아랫변이 닿은 채 밀려 올라간다 — 설령 빙원권 머리 단은 그 6 아래 제자리.
      scene.controller.scrollTo(180);
      paint(painter);
      expect(layout.sphereHeadBox(0, v), (top: head + 30 - 81, height: 81.0, stuck: true));
      expect(layout.sphereHeadBox(1, v), (top: head + 36, height: 65.0, stuck: false));
      expect(painter.gutter.stuckBottom, head + 30 - 1);
    });

    test('줄 없는 문화권은 내려 봐도 붙지 않는다 — 왼쪽 칸 그림 걸음이 4단계 전과 같다(붙은 머리 단 걸음 없음)', () {
      final (scene, painter) = make(lines: false, folded: const {}, height: 150);
      paint(painter);
      final v = scene.controller.view;
      scene.controller.scrollTo(60);
      paint(painter);
      expect(v.top, 60);
      expect(scene.layout.sphereHeadBox(0, v)?.stuck, isFalse);
      expect(painter.gutter.stuckBottom, v.head);
      expect([for (final l in painter.debugLabels) if (l.kind == 'sphereName') l.text], ['설령 빙원권'], reason: '등불 분지권 머리 단은 화면 위로 지나갔다');
    });
  });
}
