import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/scene/aux_calendar.dart' show YearCycle, yearGanji;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/ruler.dart' show minuteOfYear;
import 'package:archive_prototype/scene/sphere_rows.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fold_rows.dart';

// 문화권 머리 단 밑 줄의 순수 모델(리메이크 4단계 과제 3 걸음 1 — scene/sphere_rows.dart).
// 원본은 메이커 서고 미리보기 js/timeline.js `_sphereF4` · js/core.js `HT.f4Preview`의 sphereRows:
//   시대 = kind 2 가운데 시작이나 끝이 있는 것 · 주기 = kind 3의 첫 것(data {names, start, label} · {era, from, step, label}) ·
//   사람 띠 = kind 1(과제 4 걸음 1 — 시작 차례로 줄 나눔 · 앞 사람의 끝 + 2해 ≤ 시작이면 같은 줄) ·
//   높이 = (시대 14) + (주기 13) + 사람 띠 줄 수 × 16 + 2 · 줄이 없으면 0.
// 정답 자료는 test/fixtures/f4-sphere-layout4.json · f4-crowns-layout4.json(가상 팩의 내보내기 — 3단계 과제 8이 굳힌 사본)의 sphereLines.

List<SphereLine> fixtureLines([String pack = 'f4-sphere']) {
  final json = jsonDecode(File('test/fixtures/$pack-layout4.json').readAsStringSync()) as Map<String, dynamic>;
  return [for (final x in json['sphereLines'] as List) SphereLine.fromJson(x as Map)];
}

SphereLine cycleLine(Object? data, {String sphere = 'steppe', String name = ''}) =>
    SphereLine.fromJson({'kind': 3, 'sphere': sphere, 'start': 0, 'end': 0, 'name': name, 'data': data});

/// 사람 띠 한 줄 — [from] ~ [to]해(해 좌표 → 분), 왕관 둘.
SphereLine personLine(String name, double from, double to, {String sphere = 'steppe', String uid = ''}) => SphereLine(
  SphereLine.person, sphere, minuteOfYear(from).round(), minuteOfYear(to).round(), name,
  uid: uid, data: '[{"uid":"a","cell":0},{"uid":"b","cell":1}]',
);

void main() {
  group('정답 자료 f4-sphere', () {
    test('문화권 둘의 시대 · 주기 · 높이(시대 14 + 주기 13 + 2 = 29)', () {
      final rows = collectSphereRows(fixtureLines());
      expect(rows.keys.toSet(), {'ember-basin', 'frost-ridge'});
      final ember = rows['ember-basin']!, frost = rows['frost-ridge']!;
      expect(ember.epochs, [
        const SphereEpochRow('등불 왕국 시대', -1035593280, -621672480, uid: 'f4-sphere/ep-l1', color: 11977624),
        const SphereEpochRow('아홉 불씨 시대', -621672480, -493866720, uid: 'f4-sphere/ep-l2', color: 14332309),
      ]);
      expect(ember.cycle, const SphereCycleRow.names(['한낮', '별', '바람', '쇠', '새벽', '노을', '달', '물', '숲'], 1, '불씨해'));
      expect(ember.cycle!.isNames, isTrue);
      expect(ember.cycle!.title, '불씨해');
      expect(frost.epochs.map((e) => e.name), ['칸국기', '제국기']);
      expect(frost.cycle, const SphereCycleRow.era('빙원', 300, 10, '빙원력'));
      expect(frost.cycle!.isNames, isFalse);
      expect(frost.cycle!.title, '빙원력');
      for (final r in [ember, frost]) {
        expect(r.height, 29);
        expect((r.epochTop, r.cycleTop), (0, 14));
      }
    });

    test('같은 자료를 SceneLayout이 문화권 자리마다 들고 있다 — 모르는 자리는 줄 없음', () {
      final json = twoTrackLayout();
      (json['tracks'] as List)[0]['sphere'] = 'ember-basin';
      (json['tracks'] as List)[1]['sphere'] = 'frost-ridge';
      json['spheres'] = [
        {'id': 'ember-basin', 'name': '등불 분지권', 'count': 3, 'default': true},
        {'id': 'frost-ridge', 'name': '설령 빙원권', 'count': 2},
        {'id': 'dust', 'name': '줄 없는 권', 'count': 0},
      ];
      json['sphereLines'] = jsonDecode(File('test/fixtures/f4-sphere-layout4.json').readAsStringSync())['sphereLines'];
      final l = SceneLayout.fromJson(json)..reduceMotion = true;
      expect(l.sphereRowsOf(0).height, 29);
      expect(l.sphereRowsOf(1).cycle?.era, '빙원');
      expect(l.sphereRowsOf(2).isEmpty, isTrue);
      expect(l.sphereRowsOf(2).height, 0);
      expect(l.sphereRowsOf(-1).isEmpty, isTrue);
      expect(l.sphereRowsOf(9).isEmpty, isTrue);
    });
  });

  group('주기 data의 두 꼴', () {
    test('이름 돌림 {names, start, label} — 이름은 글로, 수는 글로 와도 읽는다', () {
      final c = SphereCycleRow.parse(cycleLine('{"names":["쥐",2,"범"],"start":"4","label":"띠"}'))!;
      expect(c.names, ['쥐', '2', '범']);
      expect((c.start, c.label, c.isNames, c.title), (4, '띠', true, '띠'));
    });

    test('연호 눈금 {era, from, step, label} — step이 1 아래면 1 · label이 비면 연호 이름', () {
      final c = SphereCycleRow.parse(cycleLine({'era': '갑자', 'from': 4.0, 'step': 0}))!;
      expect((c.era, c.from, c.step, c.label, c.isNames, c.title), ('갑자', 4, 1, '', false, '갑자'));
      final d = SphereCycleRow.parse(cycleLine({'era': '빙원', 'from': '300', 'step': '10', 'label': '빙원력'}))!;
      expect((d.from, d.step, d.title), (300, 10, '빙원력'));
    });

    test('label이 비면 줄의 name(내보내기가 label을 싣는 칸)', () {
      final c = SphereCycleRow.parse(cycleLine({'names': ['쥐', '소']}, name: '십이지'))!;
      expect(c.title, '십이지');
    });

    test('이름이 빈 목록이면 연호를 보고, 둘 다 없으면 없음', () {
      expect(SphereCycleRow.parse(cycleLine({'names': [], 'era': '연호'}))?.era, '연호');
      expect(SphereCycleRow.parse(cycleLine({'names': [], 'label': '빈 줄'})), isNull);
    });
  });

  group('깨진 data는 없음으로 친다', () {
    test('JSON이 깨졌거나 · 객체가 아니거나 · 비었으면 없음', () {
      for (final data in ['{"names":["쥐",', '[1,2]', '"글"', '', null]) {
        expect(SphereCycleRow.parse(cycleLine(data)), isNull, reason: 'data $data');
      }
    });

    test('kind 3이 아니면 풀지 않는다', () {
      expect(SphereCycleRow.parse(SphereLine.fromJson({'kind': 2, 'sphere': 'steppe', 'data': '{"era":"갑자"}'})), isNull);
    });

    test('깨진 kind 3은 없는 줄로 치고 다음 kind 3을 받는다 — 둘째 성한 줄은 버린다(첫 것만)', () {
      final rows = collectSphereRows([
        cycleLine('{"names":'),
        cycleLine({'era': '첫 연호', 'from': 1, 'step': 1}),
        cycleLine({'era': '둘째 연호', 'from': 1, 'step': 1}),
      ]);
      expect(rows['steppe']!.cycle?.era, '첫 연호');
      expect(rows['steppe']!.height, 15, reason: '주기 13 + 2 (시대 없음)');
      expect(rows['steppe']!.cycleTop, 0, reason: '시대 줄이 없으면 주기 줄이 맨 위');
    });

    test('깨진 kind 3뿐이면 그 문화권은 줄이 없다', () {
      expect(collectSphereRows([cycleLine('{')]), isEmpty);
    });
  });

  group('모으기', () {
    test('시대만 있으면 14 + 2 · 시작과 끝이 모두 없는(0) 시대는 뺀다 · 차례는 답의 차례', () {
      final rows = collectSphereRows([
        SphereLine(SphereLine.epoch, 'steppe', 200, 300, '둘째'),
        SphereLine(SphereLine.epoch, 'steppe', 0, 0, '때 없는 시대'),
        SphereLine(SphereLine.epoch, 'steppe', 100, 200, '첫째'),
        SphereLine(SphereLine.epoch, 'steppe', 0, 50, '끝만'),
      ]);
      expect(rows['steppe']!.epochs.map((e) => e.name), ['둘째', '첫째', '끝만']);
      expect(rows['steppe']!.height, 16);
      expect(rows['steppe']!.cycle, isNull);
    });

    test('모르는 갈래 · 문화권 id가 빈 줄(사람 띠도)은 담지 않는다 — 그런 줄뿐이면 빈 모음(높이 0)', () {
      final rows = collectSphereRows([
        SphereLine(SphereLine.person, '', 100, 200, '문화권 없는 임금', data: '[{"uid":"a","cell":0},{"uid":"b","cell":1}]'),
        SphereLine(9, 'steppe', 100, 200, '새 갈래'),
        SphereLine(SphereLine.epoch, '', 100, 200, '문화권 없는 시대'),
      ]);
      expect(rows, isEmpty);
      expect(SphereRows.none.height, 0);
      expect(SphereRows.none.isEmpty, isTrue);
      expect(SphereRows.none.lanes, 0);
    });

    test('문화권마다 따로 모은다', () {
      final rows = collectSphereRows([
        SphereLine(SphereLine.epoch, 'a', 1, 2, '가 시대'),
        cycleLine({'era': '나 연호'}, sphere: 'b'),
        SphereLine(SphereLine.epoch, 'b', 3, 4, '나 시대'),
      ]);
      expect((rows['a']!.height, rows['b']!.height), (16, 29));
      expect(rows['a']!.cycle, isNull);
      expect(rows['b']!.epochs.single.name, '나 시대');
    });
  });

  group('사람 띠(4단계 과제 4 걸음 1)', () {
    test('정답 자료 f4-crowns: 사람 하나(은 하림) · 왕관 여섯이 세 문화권의 띠에 — 머리 단 차례가 가장 앞선 설령 빙원권 밑 한 줄(16 + 2 = 18)', () {
      final json = jsonDecode(File('test/fixtures/f4-crowns-layout4.json').readAsStringSync()) as Map<String, dynamic>;
      final rows = collectSphereRows(fixtureLines('f4-crowns'), spheres: [for (final s in json['spheres'] as List) (s as Map)['id'] as String]);
      expect(rows.keys, ['frost-ridge']);
      final frost = rows['frost-ridge']!;
      expect(frost.persons, hasLength(1));
      final p = frost.persons.single;
      expect((p.name, p.uid, p.lane), ('은 하림', 'f4-crowns/ps-harim', 0));
      expect(p.crowns, hasLength(6));
      expect(p.crowns.first, (uid: 'f4-crowns/o-seol', cell: 1));
      // 왕관 여섯이 놓인 띠의 트랙 — 설령(frost-ridge) · 백사만(prism-strait) · 청림(jade-canopy) 세 문화권.
      final trackOf = {for (final b in json['periods'] as List) (b as Map)['uid']: b['track']};
      final sphereOf = [for (final t in json['tracks'] as List) (t as Map)['sphere']];
      expect({for (final c in p.crowns) sphereOf[trackOf[c.uid] as int]}, {'frost-ridge', 'prism-strait', 'jade-canopy'});
      expect((p.startYear, p.endYear), (1420, 1455));
      expect(p.when, '1420 ~ 1455 · 왕관 6');
      expect((frost.lanes, frost.height, frost.personTop), (1, 18, 0), reason: '시대 · 주기 줄이 없으면 사람 띠가 맨 위');
      expect(frost.epochs, isEmpty);
      expect(frost.cycle, isNull);
    });

    test('줄 나눔 — 겹치는 둘은 두 줄, 끝과 다음 시작 사이가 2해면 한 줄(미리보기 끝 + 2 ≤ 시작) · 1해면 두 줄', () {
      final rows = collectSphereRows([
        personLine('가', 1000, 1050),
        personLine('나', 1030, 1080), // 가와 겹침 → 둘째 줄
        personLine('다', 1052, 1090), // 가의 끝 1050 + 2 = 1052 → 첫 줄(끝 1090)
        personLine('라', 1082, 1100), // 첫 줄은 1090 + 2 > 1082라 못 들고, 나의 끝 1080 + 2 = 1082 → 둘째 줄
      ]);
      final r = rows['steppe']!;
      expect([for (final p in r.persons) (p.name, p.lane)], [('가', 0), ('나', 1), ('다', 0), ('라', 1)], reason: '답의 차례 그대로 · 줄 번호');
      expect(r.lanes, 2);
      expect(r.height, 2 * 16 + 2);
      final tight = collectSphereRows([personLine('가', 1000, 1050), personLine('나', 1051, 1060)])['steppe']!;
      expect([for (final p in tight.persons) p.lane], [0, 1], reason: '1해 틈은 두 줄');
      final edge = collectSphereRows([personLine('가', 1000, 1050), personLine('나', 1050, 1060)])['steppe']!;
      expect(edge.lanes, 2, reason: '맞닿기만 해도 두 줄(겹등왕 · 쌍등왕처럼)');
    });

    test('시작 차례로 나눈다(답의 차례가 아님) — 같은 시작이면 답의 차례 · 기원전을 건너는 사람도 해 좌표로(0년 빈 자리)', () {
      final rows = collectSphereRows([
        personLine('늦은', 1100, 1120),
        personLine('이른', 1000, 1098), // 먼저 첫 줄을 잡고 끝 1098 + 2 = 1100 ≤ 1100 → 늦은도 첫 줄
        personLine('같은 시작', 1000, 1010), // 이른과 같은 시작 — 답의 차례가 뒤라 둘째 줄
      ]);
      expect([for (final p in rows['steppe']!.persons) (p.name, p.lane)], [('늦은', 0), ('이른', 0), ('같은 시작', 1)]);
      final bc = collectSphereRows([personLine('기원전', -30, -1), personLine('기원후', 2, 20)])['steppe']!;
      expect([for (final p in bc.persons) p.lane], [0, 0], reason: '−1 + 2 = 1 ≤ 2(해 좌표의 수 셈 — 미리보기와 같음)');
      expect(bc.persons.first.when, '기원전 30 ~ 기원전 1 · 왕관 2');
    });

    test('머리 단 목록에 없는 문화권의 사람은 뺀다(목록이 주어지면) · 시대 · 주기 · 사람이 함께면 시대 → 주기 → 사람 차례로', () {
      final lines = [
        personLine('초원 임금', 1000, 1050),
        personLine('바다 임금', 1000, 1050, sphere: 'sea'),
        SphereLine(SphereLine.epoch, 'steppe', 100, 200, '초원 시대'),
        cycleLine({'era': '초원 연호', 'from': 1, 'step': 1}),
      ];
      final all = collectSphereRows(lines);
      expect(all.keys.toSet(), {'steppe', 'sea'});
      final known = collectSphereRows(lines, spheres: ['steppe']);
      expect(known.keys, ['steppe']);
      final r = known['steppe']!;
      expect(r.persons.single.name, '초원 임금');
      expect((r.epochTop, r.cycleTop, r.personTop), (0, 14, 27));
      expect(r.height, 14 + 13 + 16 + 2);
      expect(collectSphereRows(lines, spheres: const []), isEmpty);
    });

    test('왕관 data가 깨졌으면 왕관 0 — 띠는 그대로 둔다(내보내기가 고른 사람)', () {
      final rows = collectSphereRows([SphereLine(SphereLine.person, 'steppe', 100, 200, '깨진 왕관', data: '[{')]);
      final p = rows['steppe']!.persons.single;
      expect(p.crowns, isEmpty);
      expect(p.when, endsWith('· 왕관 0'));
      expect(rows['steppe']!.lanes, 1);
    });
  });

  // ── 같은 주기(감독 결정 2026-10-25 '육십갑자는 머리 단 주기 줄만') ──────────────────────────
  // 문화권 주기 줄이 날짜 칸 간지 줄(최상위 yearCycle — 없음 · off면 내장 육십갑자)과 해마다 같은 이름을 돌리는가.
  // 같으면 펼친 문화권 머리 단이 그리는 동안 날짜 칸이 간지 줄을 넣지 않는다(axis_model_test '같은 주기는 머리 단 주기 줄만').
  group('날짜 칸 간지 줄과 같은 주기(sameYearsAs)', () {
    /// 내장 육십갑자의 이름 예순 — 4년(갑자)부터 차례로(aux_calendar.dart `yearGanji`와 같은 글: 갑자 · 을축 · … · 계해).
    final sixty = List<String>.unmodifiable([for (int i = 0; i < 60; i++) yearGanji(4 + i)]);
    const fire = ['한낮', '별', '바람', '쇠', '새벽', '노을', '달', '물', '숲'];
    const fireAxis = YearCycle(names: fire, start: 1, label: '불씨해');

    test('내장 육십갑자와 문화권 육십갑자(이름 60 · 기준 해 4)는 같다 — remake-6의 동아시아 yearCycles 꼴(검토 지적 3)', () {
      expect((sixty.first, sixty[1], sixty.last), ('갑자', '을축', '계해'));
      final ganji = SphereCycleRow.names(sixty, 4, '육십갑자');
      expect(ganji.sameYearsAs(null), isTrue);
      // 사용자 순환이 아닌 날짜 칸 주기(이름 없음 · 이름 하나)도 내장 육십갑자다.
      expect(ganji.sameYearsAs(const YearCycle()), isTrue);
      expect(ganji.sameYearsAs(const YearCycle(names: ['외톨이'], start: 4)), isTrue);
      // 날짜 칸 주기를 사용자 순환으로 같은 육십갑자를 적어도 같다.
      expect(ganji.sameYearsAs(YearCycle(names: sixty, start: 4, label: '육십갑자')), isTrue);
    });

    test('기준 해가 길이만큼 어긋난 같은 돌림은 같다 — 천문 해로 센다(기원전으로 건너면 해 좌표로 한 해 더)', () {
      expect(SphereCycleRow.names(sixty, 64, '육십갑자').sameYearsAs(null), isTrue);
      // 천문 해 4 − 60 = −56 = 해 좌표 기원전 57년. 해 좌표로 60 뺀 −56(천문 해 −55)은 0년 빈 자리 때문에 한 해 어긋나 다르다.
      expect(SphereCycleRow.names(sixty, -57, '육십갑자').sameYearsAs(null), isTrue);
      expect(SphereCycleRow.names(sixty, -56, '육십갑자').sameYearsAs(null), isFalse);
      // 사용자 순환(불씨해 — 아홉 · 기준 1년): 10년 · 기원전 9년(천문 해 1 − 9 = −8)도 같다.
      expect(const SphereCycleRow.names(fire, 1, '불씨해').sameYearsAs(fireAxis), isTrue);
      expect(const SphereCycleRow.names(fire, 10, '불씨해').sameYearsAs(fireAxis), isTrue);
      expect(const SphereCycleRow.names(fire, -9, '불씨해').sameYearsAs(fireAxis), isTrue);
      // 이름을 k만큼 돌리고 기준 해도 k만큼 옮긴 것도 해마다 같은 이름이라 같다.
      expect(SphereCycleRow.names([...fire.skip(2), ...fire.take(2)], 3, '불씨해').sameYearsAs(fireAxis), isTrue);
    });

    test('이름 · 길이 · 기준 해가 다르면 다르다 · 연호 눈금은 늘 다르다 · 줄 이름표는 보지 않는다', () {
      expect(SphereCycleRow.names([...fire.take(8), '구름'], 1, '불씨해').sameYearsAs(fireAxis), isFalse, reason: '이름 하나 다름');
      expect(SphereCycleRow.names(fire.take(8).toList(), 1, '불씨해').sameYearsAs(fireAxis), isFalse, reason: '길이 다름');
      expect(const SphereCycleRow.names(fire, 2, '불씨해').sameYearsAs(fireAxis), isFalse, reason: '기준 해 다름');
      expect(const SphereCycleRow.names(fire, 1, '다른 이름표').sameYearsAs(fireAxis), isTrue, reason: '이름표는 견주지 않음');
      expect(SphereCycleRow.names(sixty, 5, '육십갑자').sameYearsAs(null), isFalse);
      for (final (name, axis) in [('없음', null), ('불씨해', fireAxis), ('끔', const YearCycle(off: true))]) {
        expect(const SphereCycleRow.era('빙원', 300, 10, '빙원력').sameYearsAs(axis), isFalse, reason: '연호 눈금 · 날짜 칸 $name');
        expect(const SphereCycleRow.era('갑자', 4, 1, '육십갑자').sameYearsAs(axis), isFalse, reason: '연호 눈금 · 날짜 칸 $name');
      }
    });

    test('날짜 칸 주기가 off · null이면 내장 육십갑자와 견준다', () {
      final ganji = SphereCycleRow.names(sixty, 4, '육십갑자');
      const fireRow = SphereCycleRow.names(fire, 1, '불씨해');
      const fireOff = YearCycle(names: fire, start: 1, label: '불씨해', off: true);
      expect(fireRow.sameYearsAs(fireAxis), isTrue);
      expect(fireRow.sameYearsAs(fireOff), isFalse, reason: '끈 사용자 순환 = 내장 육십갑자(길이 60)');
      expect(fireRow.sameYearsAs(null), isFalse);
      expect(ganji.sameYearsAs(fireOff), isTrue);
      expect(ganji.sameYearsAs(null), isTrue);
      expect(ganji.sameYearsAs(fireAxis), isFalse);
    });

    test('정답 자료 f4-sphere: 분지권 주기 줄(불씨해)은 맨 위 간지 설정(불씨해)과 같고 설령권(빙원력)은 다르다', () {
      final rows = collectSphereRows(fixtureLines());
      expect(rows['ember-basin']!.cycle!.sameYearsAs(fireAxis), isTrue);
      expect(rows['frost-ridge']!.cycle!.sameYearsAs(fireAxis), isFalse);
      expect(rows['ember-basin']!.cycle!.sameYearsAs(null), isFalse, reason: '내장 육십갑자와는 다름');
    });
  });
}
