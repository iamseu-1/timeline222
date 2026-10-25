// JS 이름(SCENE · SCENE_GROUP · O · P · M · L)을 그대로 둔다 — 목업을 줄 그대로 옮겨 견주기 쉽게.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:convert';

import 'js.dart';
import 'kit.dart';

// 모든 방향이 그리는 같은 장면(1150 ~ 1650년)과 줄 쌓기 — .claude/research/stage2/mock/scene.js(sha256 f34dbd14695b)를 줄 그대로 옮김.
// 원본의 저장소 사본: test/mock/source/scene.js — 연구 폴더의 원본이 바뀌어도 옮긴 판의 기준은 이 사본이다.
// 대조(test/mock/layout_test.dart)는 같은 지문의 사본에서 노드로 뽑은 정답지(test/mock/fixtures/layout.json)와 한다.
// 장면은 JS 객체처럼 Map<String, dynamic>이고 열쇠 이름은 JS 그대로다(방향이 장면을 고쳐 끼우고 그리는 고리가 읽는다).

const _P = K.P;

/// 객체 — 종류는 구상 5-4 · 7절(열여덟: 직위 포함).
const _GROUP = {
  '시대': '그릇', '나라': '그릇', '동군연합': '그릇', '동맹': '그릇', '국가': '다스림', '연방': '다스림', '제후국': '다스림', '도시': '다스림', '정부': '다스림', //
  '실권 정권': '다스림', '속령': '다스림', '군벌': '다스림', '단체': '영토 밖', '교단': '영토 밖', '기사단': '영토 밖', '회사': '영토 밖', '직위': '영토 밖', '집단': '무리',
};

/// 종류 → 갈래(JS window.SCENE_GROUP). 방향이 제 장면의 객체를 만들 때 쓴다.
const SCENE_GROUP = _GROUP;

Map<String, dynamic> _O(String n, num a, num b, String? c, String t, [Map<String, dynamic> more = const {}]) => {'n': n, 'a': a, 'b': b, 'c': c, 't': t, 'g': _GROUP[t], ...more};

/// 장면 원본(JS window.SCENE). 그리는 쪽은 이것을 고치지 말고 [mockScene]으로 새로 베낀 것을 쓴다.
final Map<String, dynamic> SCENE = {
  'win': {'y0': 1150, 'y1': 1650},
  'title': '1150 ~ 1650년',
  // 맨 위 날짜 칸의 이름표 시대(아무도 품지 않는 시대 · 트랙을 넘음)
  'labels': [{'n': '몽골 제국 시대', 'a': 1206, 'b': 1368}, {'n': '르네상스', 'a': 1400, 'b': 1600}, {'n': '대항해 시대', 'a': 1450, 'b': 1650}],
  'cultures': [
    {'n': '동아시아', 'tracks': [
      {'n': '한국', 'rows': [
        {'items': [_O('고려', 918, 1392, _P['rose'], '국가', {'power': [{'n': '무신 정권', 'a': 1170, 'b': 1270}], 'ev': [{'n': '몽골 침입', 'y': 1231}]}), _O('조선', 1392, 1897, _P['sky'], '국가', {'from': 'direct', 'ev': [{'n': '임진왜란', 'y': 1592}]})]},
      ]},
      {'n': '중국', 'rows': [
        {'items': [_O('금', 1115, 1234, _P['butter'], '국가'), _O('원', 1271, 1368, _P['peri'], '국가', {'serve': {'to': '몽골 제국', 'c': _P['sand'], 'rel': '명목상', 'a': 1271}}), _O('명', 1368, 1644, _P['peach'], '국가', {'from': 'direct'})]},
        {'items': [_O('남송', 1127, 1279, _P['mint'], '국가'), _O('청', 1636, 1912, _P['slate'], '국가')]},
      ]},
      {'n': '일본', 'rows': [
        {'container': {'n': '일본', 't': '나라', 'pull': true, 'open': true, 'a': 538, 'b': 9999, 'c': _P['lav']}, 'rows': [
          {'items': [_O('조정', 538, 9999, _P['lav'], '국가', {'ev': [{'n': '겐무 신정', 'y': 1333}]})]},
          {'items': [_O('남조', 1336, 1392, _P['pink'], '정부', {'rival': true})]},
          {'cells': true, 'label': '막부', 'items': [
            _O('가마쿠라 막부', 1185, 1333, _P['sage'], '실권 정권', {'selected': true, 'serve': {'to': '조정', 'c': _P['lav'], 'rel': '명목상', 'a': 1185}, 'power': [{'n': '싯켄', 'a': 1203, 'b': 1333}],
              'cells': [['요리토모', 1192, 1199], ['요리이에', 1202, 1203], ['사네토모', 1203, 1219], ['요리쓰네', 1226, 1244], ['요리쓰구', 1244, 1252], ['무네타카', 1252, 1266], ['고레야스', 1266, 1289], ['히사아키', 1289, 1308], ['모리쿠니', 1308, 1333]], 'ev': [{'n': '원의 원정', 'y': 1274}]}),
            _O('무로마치 막부', 1336, 1573, _P['sand'], '실권 정권', {'from': 'indirect', 'serve': {'to': '조정', 'c': _P['lav'], 'rel': '명목상', 'a': 1336}, 'ev': [{'n': '오닌의 난', 'y': 1467}]}),
            _O('에도 막부', 1603, 1868, _P['mocha'], '실권 정권', {'from': 'indirect', 'serve': {'to': '조정', 'c': _P['lav'], 'rel': '명목상', 'a': 1603}})]},
          {'container': {'n': '전국 시대', 't': '시대', 'pull': true, 'open': true, 'a': 1467, 'b': 1590}, 'rows': [
            {'items': [_O('다케다', 1467, 1582, _P['rose'], '군벌')]},
            {'items': [_O('고호조', 1495, 1590, _P['slate'], '군벌')]},
            {'items': [_O('오다', 1551, 1582, _P['butter'], '군벌'), _O('도요토미 정권', 1582, 1598, _P['peach'], '실권 정권', {'from': 'direct', 'outR': true})]},
          ]},
        ]},
      ]},
    ]},
    {'n': '초원', 'closed': true, 'tabs': [{'n': '몽골 제국', 'y': 1206, 'c': _P['sand']}, {'n': '차가타이', 'y': 1225, 'c': _P['butter']}, {'n': '금장 칸국', 'y': 1242, 'c': _P['peach']}, {'n': '티무르', 'y': 1370, 'c': _P['mint']}, {'n': '카자흐', 'y': 1465, 'c': _P['sky']}], 'count': 9},
    {'n': '이슬람', 'tracks': [
      {'n': '이슬람', 'rows': [
        {'items': [_O('아바스 칼리파국', 750, 1258, _P['mint'], '국가', {'ev': [{'n': '바그다드 함락', 'y': 1258}]})], 'lane': {'n': '칼리파위', 'a': 1150, 'b': 1258}},
        {'items': [_O('맘루크 술탄국', 1250, 1517, _P['butter'], '국가')], 'lane': {'n': '칼리파위', 'a': 1261, 'b': 1517, 'status': '명목'}},
        {'items': [_O('오스만', 1299, 1922, _P['rose'], '국가', {'ev': [{'n': '콘스탄티노폴리스 함락', 'y': 1453}]})], 'lane': {'n': '칼리파위', 'a': 1517, 'b': 1924, 'status': '주장'}},
      ], 'office': {'n': '칼리파위', 't': '직위'}},
    ]},
    {'n': '라틴 유럽', 'tracks': [
      {'n': '라틴 유럽', 'rows': [
        {'container': {'n': '신성 로마', 't': '연방', 'pull': true, 'open': true, 'a': 962, 'b': 1806, 'c': _P['sky'], 'labels': [{'n': '대공위 시대', 'a': 1250, 'b': 1273}]}, 'rows': [
          {'items': [_O('보헤미아 왕국', 1198, 1918, _P['peri'], '제후국', {'outR': true, 'tags': [{'n': '합스부르크', 'a': 1526, 'kind': '가문'}]})]},
          {'items': [_O('오스트리아', 1156, 1804, _P['sage'], '제후국', {'tags': [{'n': '합스부르크', 'a': 1278, 'kind': '가문'}]})]},
          {'items': [_O('뤼베크', 1226, 1806, _P['sand'], '도시', {'tags': [{'n': '한자 동맹', 'a': 1356, 'kind': '동맹'}]})]},
        ]},
        {'items': [_O('프랑스 왕국', 987, 1792, _P['lav'], '국가', {'ev': [{'n': '백년 전쟁', 'y': 1337}]})]},
        {'cells': true, 'items': [_O('로마 교단', 33, 9999, _P['mocha'], '교단', {'offices': [{'n': '교황', 'a': 1150, 'b': 9999}, {'n': '대립 교황', 'a': 1378, 'b': 1417, 'status': '대립'}], 'ev': [{'n': '종교 개혁', 'y': 1517}]})]},
      ]},
    ]},
  ],
  'detail': {
    'path': ['동아시아', '일본', '막부'],
    'title': '가마쿠라 막부', 'when': '1185 ~ 1333년', 'kind': '실권 정권', 'group': '다스리는 것',
    'text': '미나모토노 요리토모가 가마쿠라에 세운 첫 무사 정권. 천황의 조정을 받들되 나라의 실권을 쥐었다.',
    'facts': [['명목 군주', '조정'], ['그릇', '일본'], ['도읍', '가마쿠라']],
    'offices': [{'n': '쇼군', 'count': 9, 'rows': [['미나모토노 요리토모', '1192 ~ 1199'], ['미나모토노 요리이에', '1202 ~ 1203'], ['미나모토노 사네토모', '1203 ~ 1219']]}, {'n': '싯켄', 'count': 16, 'note': '실권', 'rows': [['호조 도키마사', '1203 ~ 1205'], ['호조 요시토키', '1205 ~ 1224']]}],
    'links': [['뒤', '무로마치 막부', '간접']],
  },
};

/// [SCENE]을 깊이 베낀 새 장면 — JS의 `JSON.parse(JSON.stringify(SCENE))`와 같은 뜻.
/// 그리기가 장면을 고치므로(객체에 geo · 이름표 시대에 lane을 적음) 장면마다 새것을 써야 두 번 그려도 서로 물들지 않는다.
/// JSON을 한 번 지나므로 안의 맵 · 목록이 모두 `Map<String, dynamic>` · `List<dynamic>` — 방향이 어떤 값이든 고쳐 넣을 수 있다.
Map<String, dynamic> mockScene() => jsonDecode(jsonEncode(SCENE)) as Map<String, dynamic>;

/// 줄 배치 — 방향마다 다른 치수(M)로 같은 장면을 놓음.
/// M: { top, tabH, bandH, cellsH, gap, headH, padB, laneH, closedRoom, closedH, trackGap, cultureGap }
Map<String, dynamic> layoutScene(Map<String, dynamic> S, Map<String, num> M) {
  final L = <String, dynamic>{'rows': <Map<String, dynamic>>[], 'containers': <Map<String, dynamic>>[], 'cultures': <Map<String, dynamic>>[], 'tracks': <Map<String, dynamic>>[], 'closed': <Map<String, dynamic>>[], 'lanes': <Map<String, dynamic>>[]};
  num y = M['top']!;
  void walk(List rows, int depth, List<Map<String, dynamic>> stack, Map<String, dynamic> track, Map<String, dynamic> culture) {
    for (final r in rows.cast<Map<String, dynamic>>()) {
      if (jsTruthy(r['container'])) {
        final c = <String, dynamic>{...r['container'] as Map<String, dynamic>, 'depth': depth, 'stack': [...stack], 'yTop': y, 'track': track, 'culture': culture, 'rows': <Map<String, dynamic>>[]};
        y += c['depth'] == 0 ? M['headH']! : (M['headH2'] ?? M['headH']!);
        final before = (L['rows'] as List).length;
        walk(r['rows'] as List, depth + 1, [...stack, c], track, culture);
        c['rows'] = (L['rows'] as List<Map<String, dynamic>>).sublist(before);
        y += M['padB']!;
        c['yBottom'] = y;
        (L['containers'] as List<Map<String, dynamic>>).add(c);
        y += M['afterC'] ?? 0;
      } else {
        final h = jsTruthy(r['cells']) ? M['cellsH']! : M['bandH']!;
        final row = <String, dynamic>{'y': y, 'yBand': y + M['tabH']!, 'h': h, 'items': r['items'], 'depth': depth, 'stack': [...stack], 'track': track, 'culture': culture, 'lane': r['lane'], 'label': r['label']};
        y += M['tabH']! + h;
        if (jsTruthy(r['lane'])) {
          row['laneY'] = y + (M['laneGap'] ?? 1);
          y += (M['laneGap'] ?? 1) + M['laneH']!;
          (L['lanes'] as List<Map<String, dynamic>>).add(row);
        }
        y += M['gap']!;
        (L['rows'] as List<Map<String, dynamic>>).add(row);
      }
    }
  }

  for (final cu in (S['cultures'] as List).cast<Map<String, dynamic>>()) {
    final C = <String, dynamic>{...cu, 'y0': y};
    if (jsTruthy(cu['closed'])) {
      C['rowY'] = y + M['closedRoom']!;
      C['rowH'] = M['closedH'];
      y += M['closedRoom']! + M['closedH']! + M['gap']!;
      C['y1'] = y;
      (L['closed'] as List<Map<String, dynamic>>).add(C);
      (L['cultures'] as List<Map<String, dynamic>>).add(C);
      y += M['cultureGap']!;
      continue;
    }
    C['tracks'] = <Map<String, dynamic>>[];
    for (final tr in (cu['tracks'] as List).cast<Map<String, dynamic>>()) {
      final T = <String, dynamic>{...tr, 'y0': y, 'culture': C};
      walk(tr['rows'] as List, 0, [], T, C);
      T['y1'] = y - M['gap']!;
      (C['tracks'] as List<Map<String, dynamic>>).add(T);
      (L['tracks'] as List<Map<String, dynamic>>).add(T);
      y += M['trackGap']!;
    }
    C['y1'] = y - M['trackGap']!;
    (L['cultures'] as List<Map<String, dynamic>>).add(C);
    y += M['cultureGap']!;
  }
  L['bottom'] = y;
  return L;
}
