// JS 이름(TAG · G · PEEK · KEYR · CH · HOLE · DIA · ORDER · O · V · S · L · M · C · Tr · X0 · X1 · H · Y …)을 그대로 둔다 — 목업을 줄 그대로 옮겨 견주기 쉽게.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import '../js.dart';
import '../kit.dart';
import '../render.dart';
import '../scene.dart';
import '../svg_lite.dart';

// 꼬리표 — 실제 띠에 입히기 · 공통 도움(JS window.TAG) — .claude/research/stage2/mock/themes/t-common.js(sha256 df82f95903ca)를 줄 그대로 옮김.
// 원본의 저장소 사본: test/mock/source/themes/t-common.js — 연구 폴더의 원본이 바뀌어도 옮긴 판의 기준은 이 사본이다.
// 새 앱의 띠 짜임(layout.dart _bandOf · bands.dart _paintBand/_paintTab/paintHostSheets · strips.dart · links.dart)을 흉내 내는
// 줄 쌓기 · 단 · 글줄 · 네모 · 승계선과, 서고의 꼬리표 · 구멍 · 꼬리 마름모(blend.js · h-c.js)를 갈래 파일이 함께 쓴다.
// JS는 갈래 파일이 그리는 때에만 window.TAG를 찾는다(이 파일이 이름 차례로 뒤에 읽혀서) — Dart는 이 파일을 가져와(import) [TAG]를 쓴다.
// 상태가 없다: 그린 자리는 넘겨받은 g(띠 자리 — bb · tie) · 장면에 적는다(같은 갈래로 여러 번 그리므로).

const _P = K.P;

/// 띠 높이 — 4 + 지도자 칸 25(있으면) + 글줄 21 × n + 4.
num _bandH(Map<String, dynamic> tr) => TAG.G['inset']! + (jsTruthy(tr['leaders']) ? TAG.G['leader']! + TAG.G['slot']! : 0) + jsOr<num>(tr['lines'], 1) * TAG.G['line']! + TAG.G['inset']!;

/// JS window.TAG — t-common.js가 내보내는 값 · 함수. 갈래는 `TAG.geom(…)`처럼 부른다.
const TAG = TagKit._();

class TagKit {
  const TagKit._();

  /// 새 앱의 G(layout.dart:19-31) — 탭 줄 18 · 줄 사이 8 · 트랙 아래 9 · 띠 안 위아래 4 · 지도자 칸 22 + 3 · 글줄 21 · 미정 꼬리 44
  Map<String, num> get G => const {'tab': 18, 'gap': 8, 'pad': 9, 'inset': 4, 'leader': 22, 'slot': 3, 'line': 21, 'fade': 44};
  num get PEEK => 6;
  num get KEYR => 12;
  num get CH => 5;
  num get HOLE => 6;
  num get DIA => 3;

  /* ══ 장면 — 1330 ~ 1520년 · 동아시아 한 문화권 · 트랙 넷(모두 지도자 칸 + 사건 글줄 둘 — 앱은 트랙의 줄이 여섯 이하면 글줄 둘) ══
     맵 · 목록은 <String, dynamic> · <dynamic>으로 — 그리는 쪽이 geo · lane · out 같은 값을 적어 넣는다. */
  Map<String, dynamic> scene(Map<String, dynamic> S) {
    const GR = SCENE_GROUP;
    Map<String, dynamic> O(String n, num a, num b, String c, String t, [Map<String, dynamic> more = const {}]) => <String, dynamic>{'n': n, 'a': a, 'b': b, 'c': c, 't': t, 'g': GR[t], ...more};
    Map<String, dynamic> V(String n, num y, [Object? imp]) => <String, dynamic>{'n': n, 'y': y, 'imp': jsTruthy(imp)};
    S['win'] = <String, dynamic>{'y0': 1330, 'y1': 1520};
    S['title'] = '1330 ~ 1520년';
    S['labels'] = <dynamic>[
      <String, dynamic>{'n': '남북조 시대', 'a': 1336, 'b': 1392},
      <String, dynamic>{'n': '전국 시대', 'a': 1467, 'b': 1590},
    ];
    S['cultures'] = <dynamic>[
      <String, dynamic>{
        'n': '동아시아',
        'tracks': <dynamic>[
          <String, dynamic>{
            'n': '한국', 'leaders': true, 'lines': 2, //
            'rows': <dynamic>[
              <String, dynamic>{
                'label': '고려 · 조선',
                'items': <dynamic>[
                  O('고려', 918, 1392, _P['rose']!, '국가', {
                    'cells': <dynamic>[<dynamic>['충숙왕', 1332, 1339], <dynamic>['충혜왕', 1339, 1344], <dynamic>['충목왕', 1344, 1348], <dynamic>['충정왕', 1348, 1351], <dynamic>['공민왕', 1351, 1374], <dynamic>['우왕', 1374, 1388], <dynamic>['창왕', 1388, 1389], <dynamic>['공양왕', 1389, 1392]],
                    'ev': <dynamic>[V('홍건적 침입', 1359), V('위화도 회군', 1388, 1)],
                  }),
                  O('조선', 1392, 1897, _P['sky']!, '국가', {
                    'from': 'direct', 'selected': true, //
                    'cells': <dynamic>[<dynamic>['태조', 1392, 1398], <dynamic>['정종', 1398, 1400], <dynamic>['태종', 1400, 1418], <dynamic>['세종', 1418, 1450], <dynamic>['문종', 1450, 1452], <dynamic>['단종', 1452, 1455], <dynamic>['세조', 1455, 1468], <dynamic>['예종', 1468, 1469], <dynamic>['성종', 1469, 1494], <dynamic>['연산군', 1494, 1506], <dynamic>['중종', 1506, 1544]],
                    'ev': <dynamic>[V('한양 천도', 1394), V('왕자의 난', 1398), V('대마도 정벌', 1419), V('훈민정음', 1446, 1), V('계유정난', 1453), V('경국대전', 1485), V('무오사화', 1498), V('중종반정', 1506)],
                  }),
                ],
              },
              <String, dynamic>{
                'label': '탐라 · 대금',
                'items': <dynamic>[O('탐라', 1105, 1404, _P['mint']!, '국가'), O('대금', 1453.6, 1454.1, _P['mocha']!, '국가')],
              },
            ],
          },
          <String, dynamic>{
            'n': '중국', 'leaders': true, 'lines': 2, //
            'rows': <dynamic>[
              <String, dynamic>{
                'label': '원 · 명',
                'items': <dynamic>[
                  O('원', 1271, 1368, _P['peri']!, '국가', {
                    'serve': <String, dynamic>{'to': '몽골 제국', 'c': _P['sand'], 'rel': '명목상', 'a': 1271},
                    'cells': <dynamic>[<dynamic>['문종', 1329, 1332], <dynamic>['혜종', 1333, 1368]],
                    'ev': <dynamic>[V('홍건적의 난', 1351)],
                  }),
                  O('명', 1368, 1644, _P['peach']!, '국가', {
                    'from': 'direct',
                    'cells': <dynamic>[<dynamic>['홍무제', 1368, 1398], <dynamic>['건문제', 1398, 1402], <dynamic>['영락제', 1402, 1424], <dynamic>['홍희제', 1424, 1425], <dynamic>['선덕제', 1425, 1435], <dynamic>['정통제', 1435, 1449], <dynamic>['경태제', 1449, 1457], <dynamic>['천순제', 1457, 1464], <dynamic>['성화제', 1464, 1487], <dynamic>['홍치제', 1487, 1505], <dynamic>['정덕제', 1505, 1521]],
                    'ev': <dynamic>[V('정난의 변', 1399), V('정화의 원정', 1405, 1), V('토목의 변', 1449)],
                  }),
                ],
              },
              <String, dynamic>{
                'label': '북원 · 건주 여진',
                'items': <dynamic>[
                  O('북원', 1368, 1388, _P['slate']!, '국가', {
                    'fuzzyE': true,
                    'cross': <String, dynamic>{'from': '원', 'how': 'direct'},
                    'cells': <dynamic>[<dynamic>['혜종', 1368, 1370], <dynamic>['소종', 1370, 1378], <dynamic>['천원제', 1378, 1388]],
                  }),
                  O('건주 여진', 1403, 1616, _P['sage']!, '집단'),
                ],
              },
            ],
          },
          <String, dynamic>{
            'n': '티베트', 'leaders': true, 'lines': 2, //
            'rows': <dynamic>[
              <String, dynamic>{
                'label': '겔룩파',
                'items': <dynamic>[
                  O('겔룩파', 1409, 9999, _P['butter']!, '교단', {
                    'cells': <dynamic>[<dynamic>['쫑카파', 1409, 1419], <dynamic>['걀찹 제', 1419, 1431], <dynamic>['케둡 제', 1431, 1438], <dynamic>['바소', 1438, 1450]],
                    'ev': <dynamic>[V('데풍 사원', 1416), V('세라 사원', 1419), V('타실훈포 사원', 1447)],
                  }),
                ],
              },
            ],
          },
          <String, dynamic>{
            'n': '일본', 'leaders': true, 'lines': 2, //
            'rows': <dynamic>[
              <String, dynamic>{
                'label': '조정',
                'items': <dynamic>[
                  O('조정', 538, 9999, _P['lav']!, '국가', {
                    'cells': <dynamic>[<dynamic>['고다이고', 1318, 1336], <dynamic>['고묘', 1336, 1348], <dynamic>['스코', 1348, 1351], <dynamic>['고코곤', 1352, 1371], <dynamic>['고엔유', 1371, 1382], <dynamic>['고코마쓰', 1382, 1412], <dynamic>['쇼코', 1412, 1428], <dynamic>['고하나조노', 1428, 1464], <dynamic>['고쓰치미카도', 1464, 1500], <dynamic>['고카시와바라', 1500, 1526]],
                    'ev': <dynamic>[V('남북조 합일', 1392, 1)],
                  }),
                ],
              },
              <String, dynamic>{
                'label': '남조',
                'items': <dynamic>[
                  O('남조', 1336, 1392, _P['pink']!, '정부', {
                    'rival': true,
                    'cells': <dynamic>[<dynamic>['고다이고', 1336, 1339], <dynamic>['고무라카미', 1339, 1368], <dynamic>['조케이', 1368, 1383], <dynamic>['고카메야마', 1383, 1392]],
                  }),
                ],
              },
              <String, dynamic>{
                'label': '막부',
                'items': <dynamic>[
                  O('무로마치 막부', 1336, 1573, _P['sand']!, '실권 정권', {
                    'serve': <String, dynamic>{'to': '조정', 'c': _P['lav'], 'rel': '명목상', 'a': 1336},
                    'cells': <dynamic>[<dynamic>['다카우지', 1338, 1358], <dynamic>['요시아키라', 1358, 1367], <dynamic>['요시미쓰', 1368, 1394], <dynamic>['요시모치', 1394, 1423], <dynamic>['요시카즈', 1423, 1425], <dynamic>['요시노리', 1429, 1441], <dynamic>['요시카쓰', 1442, 1443], <dynamic>['요시마사', 1449, 1473], <dynamic>['요시히사', 1473, 1489], <dynamic>['요시타네', 1490, 1493], <dynamic>['요시즈미', 1494, 1508], <dynamic>['요시타네', 1508, 1521]],
                    'ev': <dynamic>[V('오에이의 난', 1399), V('가키쓰의 난', 1441), V('오닌의 난', 1467, 1), V('메이오 정변', 1493)],
                  }),
                ],
              },
            ],
          },
        ],
      },
    ];
    S['detail'] = <String, dynamic>{
      'path': <dynamic>['동아시아', '한국'], 'title': '조선', 'when': '1392 ~ 1897년', 'kind': '국가', 'group': '다스리는 것', //
      'text': '이성계가 고려를 이어 세운 나라. 한양에 도읍하고 성리학을 나라의 틀로 삼았다.',
      'facts': <dynamic>[<dynamic>['도읍', '한양'], <dynamic>['왕실', '전주 이씨'], <dynamic>['트랙', '한국']],
      'offices': <dynamic>[
        <String, dynamic>{
          'n': '왕', 'count': 27, //
          'rows': <dynamic>[<dynamic>['태조 이성계', '1392 ~ 1398'], <dynamic>['정종', '1398 ~ 1400'], <dynamic>['태종', '1400 ~ 1418'], <dynamic>['세종', '1418 ~ 1450']],
        },
      ],
      'links': <dynamic>[<dynamic>['앞', '고려', '직접']],
    };
    // 뒤로 이어지는 객체(꼬리 마름모 자리) — 같은 줄의 다음 객체가 from을 가졌거나, 다른 줄 객체가 cross.from으로 가리킴
    final all = <dynamic>[];
    for (final C in S['cultures']) {
      for (final Tr in C['tracks']) {
        for (final r in Tr['rows']) {
          final items = r['items'] as List;
          for (final (i, o) in items.indexed) {
            all.add(o);
            if (jsTruthy(o['from']) && i != 0) items[i - 1]['out'] = true;
          }
        }
      }
    }
    for (final o in all) {
      if (jsTruthy(o['cross'])) {
        final a = all.where((q) => q['n'] == o['cross']['from']).firstOrNull;
        if (a != null) a['out'] = true;
      }
    }
    return S;
  }

  /* ══ 줄 쌓기 ══ */
  /// 지금 앱 그대로(layout.dart _stack · _bandOf): 줄 위 틈 = 탭 18(트랙 둘째 줄부터 + 8) · 띠 = 4 + 지도자 25 + 글줄 21 × n + 4 · 트랙 아래 9
  void layoutApp(Map<String, dynamic> S, Map<String, dynamic> L, Map<String, num> M) {
    num y = M['top']!;
    var ri = 0, ti = 0, ci = 0;
    for (final cu in S['cultures']) {
      final C = L['cultures'][ci++];
      C['y0'] = y;
      for (final tr in cu['tracks']) {
        final Tr = L['tracks'][ti++];
        Tr['y0'] = y;
        for (final (i, _) in (tr['rows'] as List).indexed) {
          final row = L['rows'][ri++], gap = (i != 0 ? G['gap']! : 0) + G['tab']!;
          row['y'] = y;
          row['yBand'] = y + gap;
          row['h'] = _bandH(tr);
          row['spec'] = <String, dynamic>{'leaders': jsTruthy(tr['leaders']), 'lines': jsOr<num>(tr['lines'], 1)};
          y += gap + row['h'];
        }
        Tr['y1'] = y + 2;
        y += G['pad']!;
      }
      C['y1'] = y - 4;
    }
    L['bottom'] = y;
  }

  /// 서고 그대로(blend.js relayout): 줄 위 틈 5(섬기는 객체가 있는 줄 20) · 꼬리표 머리 24(+ 글줄 21 × (n − 1)) · 칸이 있는 줄만 사슬 16 · 줄 사이 3 · 트랙 사이 4
  void layoutSeogo(Map<String, dynamic> S, Map<String, dynamic> L, Map<String, num> M) {
    num y = M['top']!;
    var ri = 0, ti = 0, ci = 0;
    for (final cu in S['cultures']) {
      final C = L['cultures'][ci++];
      C['y0'] = y;
      for (final tr in cu['tracks']) {
        final Tr = L['tracks'][ti++];
        Tr['y0'] = y;
        for (final r in tr['rows']) {
          final row = L['rows'][ri++];
          final items = r['items'] as List;
          final top = items.any((o) => jsTruthy(o['serve'])) ? M['tabHS']! : M['tabH0']!;
          final head = 24 + (jsOr<num>(tr['lines'], 1) - 1) * G['line']!, chain = jsTruthy(tr['leaders']) && items.any((o) => jsTruthy(o['cells'])) ? M['chainH']! : 0;
          row['y'] = y;
          row['yBand'] = y + top;
          row['h'] = head + chain;
          row['spec'] = <String, dynamic>{'seogo': true, 'lines': jsOr<num>(tr['lines'], 1), 'head': head, 'chain': chain};
          y += top + row['h'] + M['gap']!;
        }
        Tr['y1'] = y - M['gap']!;
        y += M['trackGap']!;
      }
      C['y1'] = y - M['trackGap']!;
    }
    L['bottom'] = y;
  }

  /* ══ 띠 자리 ══ b = 그릴 띠의 값(1px 선 맞춤 끝남) */
  Map<String, dynamic> geom(MockLayers p, Map<String, dynamic> o, Map<String, dynamic> g) {
    final row = g['row'];
    final Map<String, dynamic> sp = (row != null ? row['spec'] : null) ?? <String, dynamic>{'leaders': false, 'lines': 1, 'head': jsRound(g['h']), 'chain': 0, 'parts': true};
    num x0 = g['x0'], x1 = g['x1'];
    var short = false;
    // 6px 알약(bands.dart _minBandPx)
    if (!jsTruthy(g['cl']) && !jsTruthy(g['cr']) && x1 - x0 < 6) {
      final m = jsRound((x0 + x1) / 2);
      x0 = m - 3;
      x1 = m + 3;
      short = true;
    }
    final X0 = K.px(x0), X1 = jsRound(x1) - .5, y0 = jsRound(g['y']), H = jsRound(g['h']);
    final num lines = jsOr(sp['lines'], 1);
    final leaders = jsTruthy(sp['leaders']);
    final textTop = y0 + G['inset']! + (leaders ? G['leader']! + G['slot']! : 0);
    // JS의 it[k − 1] · it[k + 1] — 줄에 없으면(k = −1) 앞은 없고 뒤는 첫 객체.
    final List it = row != null ? row['items'] : const [];
    final k = it.indexOf(o);
    final prev = k - 1 >= 0 && k - 1 < it.length ? it[k - 1] : null, next = k + 1 >= 0 && k + 1 < it.length ? it[k + 1] : null;
    final b = <String, dynamic>{
      'X0': X0, 'X1': X1, 'y0': y0, 'Y': y0 + .5, 'H': H, 'B': y0 + H - .5, 'w': X1 - X0, 'short': short, 'cl': jsTruthy(g['cl']), 'cr': jsTruthy(g['cr']), //
      'fuzzy': jsTruthy(o['fuzzyE']) && !jsTruthy(g['cr']), 'sp': sp, 'lines': lines, 'leaders': leaders,
      'seamL': prev != null && prev['b'] == o['a'], 'seamR': next != null && next['a'] == o['b'], 'next': next,
      'leaderTop': y0 + G['inset']!, 'textTop': textTop, 'lineY': (num i) => textTop + G['line']! / 2 + i * G['line']!, //
      'anchor': lines > 1 ? textTop + G['line']! : textTop + G['line']! / 2,
    };
    b['XR'] = b['fuzzy'] ? b['X1'] + G['fade']! : b['X1']; // 미정 끝은 44px 꼬리
    g['bb'] = b;
    return b;
  }

  String kindOf(Map<String, dynamic> o) => o['g'] == '영토 밖' ? 'key' : (o['g'] == '무리' ? 'plain' : 'cham');

  /// 구멍의 가로 자리 — 왼쪽에서 7(확정). 영토 밖(둥근 끝 반지름 12)은 7이면 구멍 테가 둥근 끝에 닿아(0.7px) 9로 비킴
  num holeX(Map<String, dynamic> b, String kind) => b['X0'] + (kind == 'key' ? 9 : 7);

  /// 꼬리표 윤곽 — kind 'cham'(왼쪽 두 귀 모따기 5) · 'key'(왼쪽 둥근 끝 — 반지름 상한 12) · 'plain'(직각). 오른쪽은 늘 직각.
  /// cl = 왼쪽이 화면 밖 · open = 오른쪽 세로 테 없음(미정 꼬리)
  String outline(num x0, num y, num x1, num h, String kind, Object? cl, [Map<String, dynamic> o = const {}]) {
    const n = jsNum;
    final yb = y + h, w = x1 - x0;
    String d;
    if (jsTruthy(cl) || kind == 'plain') {
      d = 'M${n(x1)},${n(y)} H${n(x0)} V${n(yb)} H${n(x1)}';
    } else if (kind == 'key') {
      final r = jsMin(jsMin(o['r'] ?? KEYR, h / 2), w);
      d = 'M${n(x1)},${n(y)} H${n(x0 + r)} A${n(r)},${n(r)} 0 0 0 ${n(x0)},${n(y + r)} V${n(yb - r)} A${n(r)},${n(r)} 0 0 0 ${n(x0 + r)},${n(yb)} H${n(x1)}';
    } else {
      final c = jsMin(jsMin(o['c'] ?? CH, w / 2), h / 2);
      d = 'M${n(x1)},${n(y)} H${n(x0 + c)} L${n(x0)},${n(y + c)} V${n(yb - c)} L${n(x0 + c)},${n(yb)} H${n(x1)}';
    }
    return jsTruthy(o['open']) ? d : '$d Z';
  }

  /// 미정 끝의 옅어짐 — 진짜 끝(xa)에서 44px 뒤(xb)까지
  String fade(MockLayers p, num xa, num xb, String color) {
    final id = K.id('fade'), gr = E('linearGradient', {'id': id, 'gradientUnits': 'userSpaceOnUse', 'x1': xa, 'x2': xb, 'y1': 0, 'y2': 0}, p.defs);
    E('stop', {'offset': 0, 'stop-color': color, 'stop-opacity': 1}, gr);
    E('stop', {'offset': 1, 'stop-color': color, 'stop-opacity': 0}, gr);
    return 'url(#$id)';
  }

  /// 꼬리표 하나 칠하기 — 칠 · 테(무리는 테 없음 · 대립은 점선 테 · 미정은 오른쪽이 옅어지며 열림)
  ({String fill, String edge}) paintTag(BaseTheme th, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> b, num x0, num y, num h, String kind, MockEl layer, [Map<String, dynamic> extra = const {}]) {
    final fill = th.fillOf(o['c']), edge = th.edgeOf(o['c']);
    final f = b['fuzzy'] ? fade(p, b['X1'], b['XR'], fill) : fill, s = b['fuzzy'] ? fade(p, b['X1'], b['XR'], edge) : edge;
    E('path', {'d': jsOr(extra['d'], outline(x0, y, b['XR'], h, kind, b['cl'])), 'fill': f, 'stroke': 'none'}, layer);
    if (kind != 'plain') E('path', {'d': jsOr(extra['dOpen'], outline(x0, y, b['XR'], h, kind, b['cl'], {'open': b['fuzzy']})), 'fill': 'none', 'stroke': s, 'stroke-dasharray': jsTruthy(o['rival']) ? '3 2' : null}, layer);
    return (fill: fill, edge: edge);
  }

  /* ══ 띠 안의 단 — 지금 앱의 지도자 칸(strips.dart: 둥근 6 · 높이 22 · 종이 62% / 번갈아 제 색 12% · 테 = 제 색 92% + 먹 · 글 11.5 · 제 색 30% + 먹) ══ */
  void appCells(BaseTheme th, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> b, num lo, num hi, num top, String bandFill) {
    if (!jsTruthy(o['cells']) || !jsTruthy(b['leaders'])) return;
    final soft = K.mixOk(o['c'], .92, K.INK), ink = K.mix(o['c'], .30, K.INK), on = K.mix('#ffffff', .62, bandFill), alt = K.mix(o['c'], .12, '#ffffff');
    var i = 0;
    for (final [n, a, e, ...] in o['cells']) {
      final xa = jsMax(p.X(a), lo), xe = jsMin(p.X(e), hi);
      i++;
      if (xe - xa < 2) continue;
      final l = jsRound(xa) + .5, r = jsRound(xe) - .5, w = r - l;
      E('path', {'d': K.rr(l, top + .5, w, G['leader']! - 1, jsMin(6, w / 2)), 'fill': i % 2 != 0 ? on : alt, 'stroke': soft}, p.band);
      final full = th.tw(n, 11.5, 'body') + 12 <= w, head = !full && th.tw((n as String)[0], 11.5, 'body') + 8 <= w;
      if (full || head) th.t(p.band, (l + r) / 2, K.base(top + G['leader']! / 2, 11.5), full ? n : n[0], 'body', {'size': 11.5, 'fill': ink, 'anchor': 'middle'});
    }
  }

  /// 서고 사슬 — 꼬리표 아래 이어 붙인 흰 꼬리표(모따기 3 · 먹 25) · 칸 글 8.5는 다 들어갈 때만
  void chain(BaseTheme th, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> b, num y, num h, String kind) {
    if (!jsTruthy(o['cells'])) return;
    String k(num a) => th.k(a);
    final num x0 = b['X0'], x1 = b['X1'];
    final ck = kind == 'key' ? 'key' : 'cham';
    E('path', {
      'd': outline(x0, y, x1, h, ck, b['cl'], {'c': 3, 'r': jsMin(KEYR, h / 2)}),
      'fill': '#ffffff',
      'stroke': k(.25),
    }, p.band);
    num lastX = -1;
    for (final [n, a, e, ...] in o['cells']) {
      final xa = jsMax(jsMax(p.X(a), x0 + 2), p.CL - 1), xe = jsMin(p.X(e), x1 - 2);
      if (xe - xa < 1) continue;
      for (final xx in [xa, xe]) {
        final q = jsRound(xx) + .5;
        if ((q - lastX).abs() < 2.5 || q < x0 + 3 || q > x1 - 3) continue;
        E('line', {'x1': q, 'x2': q, 'y1': y + 1, 'y2': y + h - 1, 'stroke': k(.2)}, p.band);
        lastX = q;
      }
      if (th.tw(n, 8.5, 'body', 400) <= xe - xa - 6) th.t(p.band, xa + 3, K.base(y + h / 2, 8.5), n, 'body', {'size': 8.5, 'wt': 400, 'fill': K.nameInk(o['c'])});
    }
  }

  /* ══ 사건 글줄 — 점 + 이름(앱: 점 반지름 3.5 · 이름 11.5 · 띠 안쪽 9로 당김 · 글줄 둘에 번갈아 · 겹치면 뺌) ══
     opt: { lines[가운데 y] · lo · hi(점 자리) · rlim(이름 끝) · busy[글줄마다 막힌 구간] · size · dot · gap } */
  void events(BaseTheme th, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> b, Map<String, dynamic> opt) {
    if (!jsTruthy(o['ev'])) return;
    final num size = opt['size'] ?? 11.5, dot = opt['dot'] ?? 3.5, gap = opt['gap'] ?? 6;
    final List lines = opt['lines'];
    final List busy = opt['busy'] ?? [for (final _ in lines) <List<num>>[]];
    for (final e in jsSorted(List.of(o['ev'] as List), (u, v) => u['y'] - v['y'])) {
      final x = jsMin(jsMax(p.X(e['y']), opt['lo']), opt['hi']);
      if (p.X(e['y']) < opt['lo'] - 30) continue;
      final wt = jsTruthy(e['imp']) ? 700 : 400, w = th.tw(e['n'], size, 'body', wt), a = x - dot - 1, z = x + dot + gap + w + 2;
      // rlim이 없으면 막지 않는다(JS에서 z > undefined는 거짓).
      if (opt['rlim'] != null && z > opt['rlim']) continue;
      for (var li = 0; li < lines.length; li++) {
        if ((busy[li] as List).any((q) => a < q[1] + 4 && z > q[0] - 4)) continue;
        final num cy = lines[li];
        E('circle', {'cx': x, 'cy': cy, 'r': dot, 'fill': th.edgeOf(o['c'])}, p.band);
        th.t(p.band, x + dot + gap, K.base(cy, size), e['n'], 'body', {'size': size, 'wt': wt, 'fill': jsTruthy(e['imp']) ? th.k(1) : th.k(.72)});
        busy[li].add(<num>[a, z]);
        break;
      }
    }
  }

  /* ══ 구멍 · 꼬리 마름모 · 실(h-c.js 그대로) ══ */
  void hole(BaseTheme th, MockLayers p, num x, num y, bool sel) {
    E('circle', {'cx': x, 'cy': y, 'r': 2.5, 'fill': '#ffffff', 'stroke': sel ? K.INK : th.k(.45)}, p.band);
  }

  void diamond(MockLayers p, num cx, num cy, String c) {
    const n = jsNum;
    E('path', {'d': 'M${n(cx)},${n(cy - DIA)} L${n(cx + DIA)},${n(cy)} L${n(cx)},${n(cy + DIA)} L${n(cx - DIA)},${n(cy)} Z', 'fill': K.mixOk(c, .6, K.INK), 'stroke': 'none'}, p.over);
  }

  /// 마름모 가운데(dx, dy) → 뒤 꼬리표의 구멍(hx, hy). 줄을 건너면 세로 통로 xv에서 곧게 굽음
  void thread(BaseTheme th, MockLayers p, num dx, num dy, num hx, num hy, bool ind, num xv) {
    const n = jsNum;
    String d;
    if ((dy - hy).abs() < 1) {
      d = 'M${n(dx)},${n(dy)} H${n(hx - 2.5)}';
    } else {
      final r = jsMin(jsMin(6, (hy - dy).abs() / 2), jsMax(0, hx - 2.5 - xv)), up = hy < dy ? -1 : 1;
      d = 'M${n(dx)},${n(dy)} H${n(xv - r)} Q${n(xv)},${n(dy)} ${n(xv)},${n(dy + up * r)} V${n(hy - up * r)} Q${n(xv)},${n(hy)} ${n(xv + r)},${n(hy)} H${n(hx - 2.5)}';
    }
    E('path', {'d': d, 'stroke': th.k(.5), 'stroke-width': 1.5, 'stroke-dasharray': ind ? '3 2' : null, 'fill': 'none', 'stroke-linejoin': 'round'}, p.over);
  }

  /// 꼬리표 갈래의 승계 — 같은 줄(link) · 줄 건넘(extra) 모두 g.tie = { hx, hy(구멍) · dx, dy(마름모) · xe(오른쪽 끝) } 로
  void tieLink(BaseTheme th, MockLayers p, Map<String, dynamic> a, Map<String, dynamic> b, String how) {
    final at = a['tie'], bt = b['tie'];
    if (at == null || bt == null || at['dx'] == null || bt['hx'] == null) return;
    if (bt['hx'] - at['dx'] < 10) return;
    thread(th, p, at['dx'], at['dy'], bt['hx'], bt['hy'], how == 'indirect', at['xe']);
    diamond(p, at['dx'], at['dy'], a['o']['c']);
  }

  void tieCross(BaseTheme th, MockLayers p, Map<String, dynamic> L) {
    final all = [for (final r in L['rows']) ...r['items']];
    for (final o in all) {
      if (!jsTruthy(o['cross']) || o['geo'] == null || o['geo']['tie'] == null) continue;
      final a = all.where((q) => q['n'] == o['cross']['from'] && q['geo'] != null).firstOrNull;
      if (a == null || a['geo']['tie'] == null || a['geo']['tie']['dx'] == null) continue;
      // 세로 통로: 같은 줄의 다음 꼬리표와 맞닿으면 그 틈의 가운데, 아니면 끝 + 8
      final ab = a['geo']['bb'], nx = ab['next'] != null && ab['next']['geo'] != null ? ab['next']['geo']['bb'] : null;
      final xv = nx != null && nx['X0'] - ab['X1'] < 12 ? (ab['X1'] + nx['X0']) / 2 : ab['X1'] + 8;
      thread(th, p, a['geo']['tie']['dx'], a['geo']['tie']['dy'], o['geo']['tie']['hx'], o['geo']['tie']['hy'], o['cross']['how'] == 'indirect', xv);
      diamond(p, a['geo']['tie']['dx'], a['geo']['tie']['dy'], a['c']);
    }
  }

  /* ══ 섬김 — 서고의 받침 카드(상국 빛깔 24% · 꼬리표 뒤 · 위로 6 드러남 · 뒤가 떨어져 있으면 오른쪽으로도 6) ══ */
  Map<String, dynamic> card(BaseTheme th, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> g, Map<String, dynamic> b, num top, num h, String kind) {
    final s = o['serve'], later = p.X(s['a']) > g['x0'] + 1;
    final num xs = later ? K.px(p.X(s['a'])) : b['X0'];
    final num dx = b['next'] != null && p.X(b['next']['a']) - p.X(o['b']) < 16 ? 0 : PEEK;
    final fill = th.fillOf(s['c']), stroke = th.edgeOf(s['c']), cy = top - PEEK, xr = jsMin(b['X1'] + (b['cr'] ? 0 : dx), p.CR + 40);
    E('path', {'d': outline(xs + dx, cy, xr, h, kind, b['cl'] || later), 'fill': fill, 'stroke': stroke}, p.under);
    return <String, dynamic>{'xs': xs + dx, 'xr': xr, 'cy': cy, 'fill': fill, 'stroke': stroke, 's': s};
  }

  /// 상국 이름 탭(서고 — 왼쪽 위 모따기 4 · 높이 12) — 받침 카드 윗변(yb)에서 솟음 · 오른쪽 끝 tr
  num hostTab(BaseTheme th, MockLayers p, Map<String, dynamic> cd, num tr, num yb) {
    const n = jsNum, ht = 12, c = 4;
    final s = cd['s'], w = th.tw(s['to'], 8.5, 'name') + 14, tl = tr - w;
    E('path', {'d': 'M${n(tl)},${n(yb + 1)} V${n(yb - ht + c)} L${n(tl + c)},${n(yb - ht)} H${n(tr)} V${n(yb + 1)} Z', 'fill': cd['fill']}, p.under);
    E('path', {'d': 'M${n(tl)},${n(yb)} V${n(yb - ht + c)} L${n(tl + c)},${n(yb - ht)} H${n(tr)} V${n(yb)}', 'fill': 'none', 'stroke': cd['stroke']}, p.under);
    th.t(p.under, tl + 7, K.base(yb - ht / 2, 8.5), s['to'], 'name', {'size': 8.5, 'fill': K.tabInk(s['c'])});
    return tl;
  }

  double hostW(BaseTheme th, Map<String, dynamic> s) => th.tw(s['to'], 8.5, 'name') + 14;
}

/* ══ 판 차례 ══ JS는 이 파일이 마지막에 읽혀 window.THEMES를 갈래 차례로 맞춤 — Dart는 판 목록(boards.dart)에 이것을 건다 */
const ORDER = ['t-0', 't-a', 't-b', 't-c', 't-d'];

/// 판 목록을 갈래 차례(ORDER)로 — ORDER에 없는 갈래는 99번째로 모두 같고, 같은 것은 원래 차례 그대로(JS sort는 안정 정렬).
List<T> sortThemes<T extends BaseTheme>(List<T> themes) => jsSorted(themes, (a, b) => jsOr(ORDER.indexOf(a.id) + 1, 99) - jsOr(ORDER.indexOf(b.id) + 1, 99));
