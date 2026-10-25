// JS 이름(GORYEO · JOSEON · CHOE · MING · BOH1 · BOH2 · RULE · DETAIL · S4_REC · FLAG · O · V · S · L · M · TG · X0 · Y · H …)을 그대로 둔다 — 목업을 줄 그대로 옮겨 견주기 쉽게.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import '../js.dart';
import '../kit.dart';
import '../render.dart';
import '../scene.dart';
import '../svg_lite.dart';
import 't_common.dart';

// 조각 ④ 결정 판 — 공통 도움(s4-0-common) — .claude/research/stage2/mock/themes/s4-0-common.js(sha256 5fee7ea8ecd3)를 줄 그대로 옮김.
// 원본의 저장소 사본: test/mock/source/themes/s4-0-common.js — 연구 폴더의 원본이 바뀌어도 옮긴 판의 기준은 이 사본이다.
// 갈래 E(꼬리표 — 머리 24 · 흰 층 16 · 구멍 · 꼬리 마름모)를 바탕으로 집권 · 실권 · 지도자 흰 층을 여러 단 쌓고,
// 손잡이(머리 줄 단추 `▸ 단체 n` / 흰 꼬리표 `⌄ n` / 플래그) · 띠 밑 집권 사슬 · 펼친 단체 줄 · 옮겨 앉기 실 · 풀린 그릇 열쇠표를 그린다.
// JS의 window.S4.register({ id, code, name, idea, pro, con, rec, opt })는 [S4Theme](기준 방향을 물려받음 — render.js merge가 BASE에 덮는 것과 같음)이고,
// 갈래 파일 아홉의 등록은 boards.dart의 목록 항목이다. window.TAG는 t_common.dart의 [TAG].
// 장면(1180 ~ 1700년): 한국 — 고려(실권 층) · 최씨 정권(제 띠 + 받침 카드) · 조선(여섯 붕당) / 중국 — 명(집권 없는 단체 둘) / 라틴 유럽 — 보헤미아 왕국의 옮겨 앉기(1526).
// JS의 HEAD · LINE · FLOOR · M은 파일 안 이름이라 _를 붙였다(render.dart의 HEAD · 갈래의 M 고리와 겹치지 않게).

const _P = K.P;
const _HEAD = 24, _LINE = 21, _FLOOR = 16;
const _M = <String, num>{'top': 124, 'clipTop': 118, 'tabH': 15, 'tabH0': 5, 'tabHS': 20, 'bandH': 24, 'cellsH': 40, 'gap': 3, 'trackGap': 4, 'cultureGap': 9, 'laneH': 14, 'laneGap': 3};

/* ══ 자료 ══ 장면이 참조로 쓰고 고치지 않는다(그리는 쪽이 적는 값은 장면의 객체에) */
const GORYEO = [['의종', 1146, 1170], ['명종', 1170, 1197], ['신종', 1197, 1204], ['희종', 1204, 1211], ['강종', 1211, 1213], ['고종', 1213, 1259], ['원종', 1259, 1274], ['충렬왕', 1274, 1308], ['충선왕', 1308, 1313], ['충숙왕', 1313, 1339], ['충혜왕', 1339, 1344], ['충목왕', 1344, 1348], ['충정왕', 1348, 1351], ['공민왕', 1351, 1374], ['우왕', 1374, 1388], ['창왕', 1388, 1389], ['공양왕', 1389, 1392]];
const JOSEON = [['태조', 1392, 1398], ['정종', 1398, 1400], ['태종', 1400, 1418], ['세종', 1418, 1450], ['문종', 1450, 1452], ['단종', 1452, 1455], ['세조', 1455, 1468], ['예종', 1468, 1469], ['성종', 1469, 1494], ['연산군', 1494, 1506], ['중종', 1506, 1544], ['인종', 1544, 1545], ['명종', 1545, 1567], ['선조', 1567, 1608], ['광해군', 1608, 1623], ['인조', 1623, 1649], ['효종', 1649, 1659], ['현종', 1659, 1674], ['숙종', 1674, 1720]];
const CHOE = [['최충헌', 1196, 1219], ['최우', 1219, 1249], ['최항', 1249, 1257], ['최의', 1257, 1258]];
const MING = [['홍무제', 1368, 1398], ['건문제', 1398, 1402], ['영락제', 1402, 1424], ['홍희제', 1424, 1425], ['선덕제', 1425, 1435], ['정통제', 1435, 1449], ['경태제', 1449, 1457], ['천순제', 1457, 1464], ['성화제', 1464, 1487], ['홍치제', 1487, 1505], ['정덕제', 1505, 1521], ['가정제', 1521, 1567], ['융경제', 1567, 1572], ['만력제', 1572, 1620], ['천계제', 1620, 1627], ['숭정제', 1627, 1644]];
const BOH1 = [['오타카르 1세', 1198, 1230], ['바츨라프 1세', 1230, 1253], ['오타카르 2세', 1253, 1278], ['바츨라프 2세', 1278, 1305], ['얀', 1310, 1346], ['카렐 4세', 1346, 1378], ['바츨라프 4세', 1378, 1419], ['지기스문트', 1419, 1437], ['라디슬라우스', 1453, 1457], ['이르지', 1458, 1471], ['블라디슬라프', 1471, 1516], ['루드비크', 1516, 1526]];
const BOH2 = [['페르디난트 1세', 1526, 1564], ['막시밀리안', 1564, 1576], ['루돌프 2세', 1576, 1611], ['마티아스', 1611, 1619], ['페르디난트 2세', 1619, 1637], ['페르디난트 3세', 1637, 1657], ['레오폴트 1세', 1657, 1705]];

/// 조선의 집권 사슬 [이름, 시작, 끝, 색]
final RULE = List<List<Object>>.unmodifiable([
  ['훈구', 1455, 1567, _P['slate']!], ['사림', 1567, 1575, _P['sand']!], ['동인', 1575, 1591, _P['mint']!], //
  ['남인', 1591, 1599, _P['sage']!], ['북인', 1599, 1623, _P['lav']!], ['서인', 1623, 1674, _P['peach']!],
]);

const DETAIL = <String, Map<String, dynamic>>{
  'seoin': {
    'path': ['동아시아', '한국', '조선'], 'title': '서인', 'when': '1575 ~ 1683년', 'kind': '단체', 'group': '영토가 본업이 아닌 것', //
    'text': '사림이 동서로 갈릴 때 심의겸 쪽에 선 붕당. 1623년 인조반정으로 정권을 잡았고, 1683년 노론과 소론으로 갈라졌다.',
    'facts': [['그릇', '조선'], ['갈래', '붕당'], ['집권', '1623 ~ 1674']],
    'offices': [
      {
        'n': '영수', 'count': 3, //
        'rows': [['심의겸', '1575 ~'], ['정철', '1589 ~'], ['김류', '1623 ~']],
      },
    ],
    'links': [['앞', '사림', '갈라짐'], ['뒤', '노론 · 소론', '갈라짐']],
  },
  'choe': {
    'path': ['동아시아', '한국'], 'title': '최씨 정권', 'when': '1196 ~ 1258년', 'kind': '실권 정권', 'group': '다스리는 것', //
    'text': '최충헌이 이의민을 몰아내고 세운 무신 정권. 고려 왕을 받들되 나라의 실권을 쥐었고 4대 62년을 이었다.',
    'facts': [['명목 군주', '고려'], ['그릇', '고려'], ['도읍', '개경']],
    'offices': [
      {
        'n': '집정', 'count': 4, //
        'rows': [['최충헌', '1196 ~ 1219'], ['최우', '1219 ~ 1249'], ['최항', '1249 ~ 1257'], ['최의', '1257 ~ 1258']],
      },
    ],
    'links': [['앞', '이의민 정권', '직접'], ['뒤', '김준 정권', '직접']],
  },
  'boh': {
    'path': ['라틴 유럽', '합스부르크 군주국'], 'title': '보헤미아 왕국', 'when': '1198 ~ 1918년', 'kind': '제후국', 'group': '다스리는 것', //
    'text': '프라하를 도읍으로 한 체코 땅의 왕국. 1526년 합스부르크가의 페르디난트 1세가 왕위를 이어 합스부르크 군주국으로 옮겨 앉았다.',
    'facts': [['그릇', '합스부르크 군주국'], ['도읍', '프라하']],
    'offices': [
      {
        'n': '그릇', 'count': 2, //
        'rows': [['신성 로마', '1198 ~ 1526'], ['합스부르크 군주국', '1526 ~ 1918']],
      },
    ],
    'links': [['앞', '보헤미아 공국', '직접']],
  },
};

/// 갈래마다 마지막으로 쌓은 줄의 기록(JS window.S4_REC) — 원천이 상수라 그릴 때마다 같은 값이 덮인다.
final S4_REC = <String, Map<String, dynamic>>{};

/* ══ 장면 ══ opt: { chain: 'floor' | 'lane', handle: 'btn' | 'tag' | 'flag' | null, open, real, move: 'A' | 'B' | null, detail, flagOpen }
   맵 · 목록은 <String, dynamic> · <dynamic>으로 — 그리는 쪽이 geo · lane · floors · out 같은 값을 적어 넣는다. */
Map<String, dynamic> _scene(Map<String, dynamic> S, Map<String, dynamic> opt) {
  const GR = SCENE_GROUP;
  Map<String, dynamic> O(String n, num a, num b, String c, String t, [Map<String, dynamic> more = const {}]) => <String, dynamic>{'n': n, 'a': a, 'b': b, 'c': c, 't': t, 'g': GR[t], ...more};
  Map<String, dynamic> V(String n, num y, [Object? imp]) => <String, dynamic>{'n': n, 'y': y, 'imp': jsTruthy(imp)};
  S['win'] = <String, dynamic>{'y0': 1180, 'y1': 1700};
  S['title'] = '1180 ~ 1700년';
  S['labels'] = <dynamic>[
    <String, dynamic>{'n': '몽골 제국 시대', 'a': 1206, 'b': 1368},
    <String, dynamic>{'n': '르네상스', 'a': 1400, 'b': 1600},
    <String, dynamic>{'n': '대항해 시대', 'a': 1450, 'b': 1650},
  ];
  final goryeo = O('고려', 918, 1392, _P['rose']!, '국가', {
    'cells': GORYEO,
    'ev': <dynamic>[V('몽골 침입', 1231), V('위화도 회군', 1388, 1)],
  });
  if (jsTruthy(opt['real'])) {
    goryeo['real'] = <dynamic>[
      <String, dynamic>{'n': '최씨 정권', 'a': 1196, 'b': 1258, 'c': _P['butter']},
    ];
  }
  final joseon = O('조선', 1392, 1897, _P['sky']!, '국가', {
    'from': 'direct', 'cells': JOSEON, //
    'ev': <dynamic>[V('훈민정음', 1446, 1), V('임진왜란', 1592, 1), V('인조반정', 1623)],
    'groups': 6, 'open': jsTruthy(opt['open']),
  });
  final row1 = <String, dynamic>{'label': '고려 · 조선', 'items': <dynamic>[goryeo, joseon]};
  if (opt['chain'] == 'floor') {
    joseon['power'] = <dynamic>[
      for (final [n, a, b, c, ...] in RULE) <String, dynamic>{'n': n, 'a': a, 'b': b, 'c': c},
    ];
  } else {
    row1['lane'] = <String, dynamic>{
      'grp': true,
      'chains': <dynamic>[
        <String, dynamic>{'at': 1455, 'count': 6, 'items': RULE, 'open': jsTruthy(opt['open'])},
      ],
    };
  }
  final choe = O('최씨 정권', 1196, 1258, _P['butter']!, '실권 정권', {
    'serve': <String, dynamic>{'to': '고려', 'c': _P['rose'], 'rel': '명목상', 'a': 1196},
    'cells': CHOE,
  });
  final kr = <dynamic>[row1];
  if (jsTruthy(opt['open'])) {
    kr.addAll([
      <String, dynamic>{
        'grp': true,
        'items': <dynamic>[
          O('훈구', 1453, 1567, _P['slate']!, '단체'),
          O('동인', 1575, 1591, _P['mint']!, '단체', {
            'cross': <String, dynamic>{'from': '사림', 'how': 'direct'},
          }),
          O('북인', 1591, 1623, _P['lav']!, '단체', {'from': 'direct'}),
        ],
      },
      <String, dynamic>{
        'grp': true,
        'items': <dynamic>[O('사림', 1470, 1575, _P['sand']!, '단체'), O('서인', 1575, 1683, _P['peach']!, '단체', {'from': 'direct'})],
      },
      <String, dynamic>{
        'grp': true,
        'items': <dynamic>[
          O('남인', 1591, 1800, _P['sage']!, '단체', {
            'cross': <String, dynamic>{'from': '동인', 'how': 'direct'},
          }),
        ],
      },
    ]);
  }
  kr.add(<String, dynamic>{
    'label': '최씨 정권',
    'items': <dynamic>[choe],
  });
  final ming = O('명', 1368, 1644, _P['peach']!, '국가', {
    'cells': MING,
    'ev': <dynamic>[V('정화의 원정', 1405, 1), V('토목의 변', 1449)],
    'groups': 2,
    'groupNames': <dynamic>[
      <dynamic>['동림당', _P['mint']],
      <dynamic>['엄당', _P['lav']],
    ],
  });
  final cnRow = <String, dynamic>{
    'label': '명',
    'items': <dynamic>[ming],
  };
  if (opt['chain'] == 'lane') {
    cnRow['lane'] = <String, dynamic>{
      'grp': true,
      'chains': <dynamic>[
        <String, dynamic>{'at': 1604, 'count': 2, 'items': <dynamic>[]},
      ],
    };
  }
  S['cultures'] = <dynamic>[
    <String, dynamic>{
      'n': '동아시아',
      'tracks': <dynamic>[
        <String, dynamic>{'n': '한국', 'leaders': true, 'lines': 2, 'rows': kr},
        <String, dynamic>{
          'n': '중국', 'leaders': true, 'lines': 2, //
          'rows': <dynamic>[cnRow],
        },
      ],
    },
  ];
  if (jsTruthy(opt['move'])) {
    final b1 = O('보헤미아 왕국', 1198, 1526, _P['peri']!, '제후국', {
      'mv': 'boh',
      'keys': <dynamic>[
        <String, dynamic>{'n': '신성 로마', 'a': 1198},
      ],
      'cells': BOH1,
    });
    final b2 = O('보헤미아 왕국', 1526, 1918, _P['peri']!, '제후국', {
      'mv': 'boh',
      'keys': <dynamic>[
        <String, dynamic>{'n': '합스부르크 군주국', 'a': 1526},
      ],
      'cells': BOH2,
    });
    final aut = O('오스트리아', 1156, 1918, _P['sage']!, '제후국', {
      'keys': <dynamic>[
        <String, dynamic>{'n': '신성 로마', 'a': 1156},
      ],
    });
    final hun = O('헝가리 왕국', 1000, 1918, _P['butter']!, '국가', {
      'keys': <dynamic>[
        <String, dynamic>{'n': '합스부르크 군주국', 'a': 1526},
      ],
    });
    final rows = opt['move'] == 'A'
        ? [
            [b1],
            [b2],
            [aut],
            [hun],
          ]
        : [
            [b1, b2],
            [aut],
            [hun],
          ];
    (S['cultures'] as List).add(<String, dynamic>{
      'n': '라틴 유럽',
      'tracks': <dynamic>[
        <String, dynamic>{
          'n': '라틴 유럽', 'leaders': true, 'lines': 2, //
          'rows': <dynamic>[
            for (final items in rows) <String, dynamic>{'key': true, 'items': <dynamic>[...items]},
          ],
        },
      ],
    });
  }
  S['detail'] = DETAIL[jsOr(opt['detail'], 'seoin')];
  // 흰 층 차례(계약 3절: 집권 → 실권 → 지도자) · 꼬리 마름모 자리(뒤로 이어지는 객체)
  for (final C in S['cultures']) {
    for (final Tr in C['tracks']) {
      for (final r in Tr['rows']) {
        final items = r['items'] as List;
        for (final (i, o) in items.indexed) {
          final floors = o['floors'] = <dynamic>[];
          if (jsTruthy(o['power'])) floors.add(<String, dynamic>{'kind': 'power', 'cells': o['power']});
          if (jsTruthy(o['real'])) floors.add(<String, dynamic>{'kind': 'real', 'cells': o['real']});
          if (jsTruthy(o['cells'])) {
            floors.add(<String, dynamic>{
              'kind': 'leader',
              'cells': <dynamic>[
                for (final [n, a, b, ...] in o['cells']) <String, dynamic>{'n': n, 'a': a, 'b': b},
              ],
            });
          }
          if (jsTruthy(o['from']) && i != 0) items[i - 1]['out'] = true;
        }
      }
    }
  }
  final all = [
    for (final C in S['cultures'])
      for (final Tr in C['tracks'])
        for (final r in Tr['rows']) ...r['items'],
  ];
  for (final o in all) {
    if (jsTruthy(o['cross'])) {
      final a = all.where((q) => q['n'] == o['cross']['from']).firstOrNull;
      if (a != null) a['out'] = true;
    }
  }
  return S;
}

/* ══ 줄 쌓기 — 갈래 E(t-common layoutSeogo)와 같되 흰 층을 객체마다 세고(줄 = 가장 많은 것), 사슬 줄(lane)과 단체 줄(grp · 왼쪽 칸 한 칸 들임)을 더함 ══ */
Map<String, dynamic> _layout(Map<String, dynamic> S, Map<String, dynamic> L, Map<String, num> M) {
  num y = M['top']!;
  var ri = 0, ti = 0, ci = 0;
  final rec = <String, dynamic>{'rows': <dynamic>[], 'tracks': <dynamic>[]};
  for (final cu in S['cultures']) {
    final C = L['cultures'][ci++];
    C['y0'] = y;
    for (final tr in cu['tracks']) {
      final Tr = L['tracks'][ti++];
      Tr['y0'] = y;
      for (final r in tr['rows']) {
        final row = L['rows'][ri++];
        final items = r['items'] as List;
        final top = items.any((o) => jsTruthy(o['serve'])) ? M['tabHS']! : (jsTruthy(r['key']) ? M['tabH']! : M['tabH0']!);
        final num lines = jsOr(tr['lines'], 1), head = _HEAD + (lines - 1) * _LINE;
        final nf = items.fold<num>(0, (m, o) => jsMax(m, (o['floors'] as List? ?? const []).length));
        row['y'] = y;
        row['yBand'] = y + top;
        row['h'] = head + nf * _FLOOR;
        row['spec'] = <String, dynamic>{'seogo': true, 'lines': lines, 'head': head, 'floors': nf, 'chain': 0};
        if (jsTruthy(r['grp'])) row['depth'] = 1;
        y += top + row['h'];
        if (jsTruthy(row['lane'])) {
          row['laneY'] = y + M['laneGap']!;
          y += M['laneGap']! + M['laneH']!;
        }
        rec['rows'].add(<String, dynamic>{
          'label': jsOr(r['label'], items.map((o) => o['n']).join(' · ')), 'track': tr['n'], 'y': row['y'], 'yBand': row['yBand'], 'h': row['h'], //
          'bottom': y, 'grp': jsTruthy(r['grp']),
        });
        y += M['gap']!;
      }
      Tr['y1'] = y - M['gap']!;
      y += M['trackGap']!;
      rec['tracks'].add(<String, dynamic>{'n': tr['n'], 'y0': Tr['y0'], 'y1': Tr['y1']});
    }
    C['y1'] = y - M['trackGap']!;
    y += M['cultureGap']!;
  }
  L['bottom'] = y;
  return rec;
}

/* ══ 작은 재료 ══ */
/// 선 아이콘 꺾쇠(Lucide chevron 규격 — 24칸 · 굵기 1.5)를 up · down으로
void _chev(MockEl g, String dir, num x, num y, num size, String color) {
  final s = size / 24;
  final pts = dir == 'up'
      ? const [
          [6, 15],
          [12, 9],
          [18, 15],
        ]
      : const [
          [6, 9],
          [12, 15],
          [18, 9],
        ];
  E('path', {
    'd': [for (final (i, [a, b]) in pts.indexed) '${i != 0 ? 'L' : 'M'}${jsNum(x + a * s)},${jsNum(y + b * s)}'].join(' '),
    'fill': 'none', 'stroke': color, 'stroke-width': 1.5, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', //
  }, g);
}

/// (ㄱ) 머리 줄 단추 — 지금 앱 `▸ 속국 n`과 한 가족(scopes.dart ScopeMarks: 높이 16 · 좌우 6 · 모서리 5 · 글 10 · 종이색 칠 + 띠 테 빛깔 1px)
({num x0, num x1}) _button(BaseTheme th, MockLayers p, Map<String, dynamic> o, String text, num x, num cy) {
  final w = jsRound(th.tw(text, 10, 'ui', 400) + 14), X = K.px(x), Y = K.px(cy - 8);
  E('path', {'d': K.rr(X, Y, w, 16, 5), 'fill': th.tok['paper'], 'stroke': th.edgeOf(o['c'])}, p.band);
  th.t(p.band, X + 7, K.base(cy, 10), text, 'ui', {'size': 10, 'wt': 400, 'fill': K.mix(o['c'], .30, K.INK)});
  return (x0: X, x1: X + w);
}

/// (ㄴ) 흰 꼬리표 손잡이 — 목업 d7-c(모따기 3 · 선 아이콘 ⌄ 10 · 수 8.5 400 먹 60) · x0 = 왼쪽(.5 맞춤) · y = 윗변(.5 맞춤)
({num x0, num x1}) _whiteTag(BaseTheme th, MockLayers p, String cnt, num x0, num y, num h, Object? open) {
  String k(num a) => th.k(a);
  final w = jsRound(4 + 10 + 3 + K.TW(cnt, 8.5, 400) + 5);
  E('path', {'d': TAG.outline(x0, y, x0 + w, h, 'cham', false, {'c': 3}), 'fill': th.tok['paper'], 'stroke': k(.4)}, p.band);
  _chev(p.band, jsTruthy(open) ? 'up' : 'down', x0 + 4, y + (h - 10) / 2, 10, k(.6));
  th.t(p.band, x0 + 17, K.base(y + h / 2, 8.5), cnt, 'ui', {'size': 8.5, 'wt': 400, 'fill': k(.6)});
  return (x0: x0, x1: x0 + w);
}

/// (감독 2026-10-15 안) 포스트잇 플래그 — 꼬리표 윗변에 살짝 얹힌 빗금 꼬리(접은 기능이 있다는 표시 · 글 없음).
/// 누르면 같은 플래그가 위로 늘어나 창이 된다: 머리(이름 + 수 + 펼침 선 아이콘) 아래에 접힌 것의 목록(색 점 + 이름).
/// x = 플래그 왼쪽 · top = 꼬리표 윗변 · items = [[이름, 색]] · open = 창
const FLAG = (w: 14, h: 7, hatch: 3);

({num x0, num x1}) _flag(BaseTheme th, MockLayers p, Map<String, dynamic> o, num x, num top, List items, bool open, String title) {
  const n = jsNum;
  String k(num a) => th.k(a);
  final edge = th.edgeOf(o['c']), X = K.px(x), T = K.px(top);
  final fillC = K.mixOk(o['c'], .5, th.tok['paper']);
  final layer = open ? p.over : p.band;
  if (!open) {
    E('path', {'d': 'M${n(X)},${n(T)} V${n(T - FLAG.h)} H${n(X + FLAG.w)} V${n(T)}', 'fill': fillC, 'stroke': edge}, layer);
    for (var i = 1; i <= FLAG.hatch; i++) {
      final a = X + i * 4 - 2;
      E('line', {'x1': a, 'y1': T - .5, 'x2': a + 4, 'y2': T - FLAG.h + .5, 'stroke': edge, 'stroke-opacity': .55}, layer);
    }
    return (x0: X, x1: X + FLAG.w);
  }
  // 창: 폭은 머리 글에 맞춤 · 줄 16 · 아래는 꼬리표 윗변에 붙음(플래그가 늘어난 꼴 — 아랫단에 빗금 띠 7)
  const rowH = 16, pad = 7;
  final head = '$title ${items.length}';
  final w = jsRound(<num>[th.tw(head, 10, 'ui', 700) + 30, for (final [nm, ...] in items) th.tw(nm, 9.5, 'body', 400) + 26].reduce(jsMax) + pad);
  final h = 20 + items.length * rowH + 4 + FLAG.h;
  final Y0 = T - h;
  E('path', {'d': 'M${n(X)},${n(T)} V${n(Y0)} H${n(X + w)} V${n(T)}', 'fill': th.tok['paper'], 'stroke': edge}, layer);
  // 아랫단 = 닫힌 플래그의 빗금 꼬리 그대로(어디서 나온 창인지)
  E('rect', {'x': X + .5, 'y': T - FLAG.h, 'width': w - 1, 'height': FLAG.h - .5, 'fill': fillC}, layer);
  for (var a = X + 2; a < X + w - 4; a += 4) {
    E('line', {'x1': a, 'y1': T - .5, 'x2': a + 4, 'y2': T - FLAG.h + .5, 'stroke': edge, 'stroke-opacity': .55}, layer);
  }
  E('line', {'x1': X, 'x2': X + w, 'y1': T - FLAG.h + .5, 'y2': T - FLAG.h + .5, 'stroke': edge}, layer);
  // 머리: 이름 + 수 · 오른쪽 끝에 '제 줄로 펼침' 선 아이콘(테 안의 줄)
  th.t(layer, X + pad, K.base(Y0 + 10.5, 10), title, 'ui', {'size': 10, 'wt': 700, 'fill': k(.85)});
  th.t(layer, X + pad + th.tw(title, 10, 'ui', 700) + 4, K.base(Y0 + 10.5, 10), jsStr(items.length), 'ui', {'size': 10, 'wt': 400, 'fill': k(.5)});
  final ix = X + w - 16, iy = Y0 + 5;
  E('rect', {'x': ix + .5, 'y': iy + .5, 'width': 10, 'height': 10, 'rx': 1.5, 'fill': 'none', 'stroke': k(.6)}, layer);
  E('line', {'x1': ix + 3, 'x2': ix + 8, 'y1': iy + 4.5, 'y2': iy + 4.5, 'stroke': k(.6)}, layer);
  E('line', {'x1': ix + 3, 'x2': ix + 6, 'y1': iy + 7.5, 'y2': iy + 7.5, 'stroke': k(.6)}, layer);
  E('line', {'x1': X + 4, 'x2': X + w - 4, 'y1': Y0 + 20.5, 'y2': Y0 + 20.5, 'stroke': k(.12)}, layer);
  for (final (i, [nm, c, ...]) in items.indexed) {
    final cy = Y0 + 20 + 2 + i * rowH + rowH / 2;
    E('circle', {'cx': X + pad + 3, 'cy': cy, 'r': 3, 'fill': th.fillOf(c), 'stroke': th.edgeOf(c)}, layer);
    th.t(layer, X + pad + 11, K.base(cy, 9.5), nm, 'body', {'size': 9.5, 'wt': 400, 'fill': k(.8)});
  }
  return (x0: X, x1: X + w);
}

/// 풀린 그릇의 열쇠표(앱 FolderLook: 높이 12 · 띠 윗변 위 2 · 둥근 끝 6 · 구멍 6 · 글 8.5 먹 65 · 띠 시작 + 16에서 45° 실)
void _keys(BaseTheme th, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> b) {
  const n = jsNum, h = 12;
  String k(num a) => th.k(a);
  num last = -1e9;
  for (final t in o['keys']) {
    final xa = jsMax(K.px(p.X(t['a'])), (b['cl'] ? p.CL : b['X0']) + 16), w = jsRound(th.tw(t['n'], 8.5, 'name') + 17);
    final kx = jsMax(xa + 3, last + 4), ky = b['Y'] - h - 2;
    E('path', {'d': 'M${n(xa)},${n(b['Y'])} L${n(kx + 6)},${n(ky + 6)}', 'stroke': k(.45), 'fill': 'none'}, p.under);
    E('path', {'d': TAG.outline(kx, ky, kx + w, h, 'key', false, {'r': 6}), 'fill': th.tok['paper'], 'stroke': k(.4)}, p.under);
    E('circle', {'cx': kx + 6, 'cy': ky + 6, 'r': 1.5, 'fill': th.tok['paper'], 'stroke': k(.45)}, p.under);
    th.t(p.under, kx + 11, K.base(ky + 6, 8.5), t['n'], 'name', {'size': 8.5, 'fill': k(.65)});
    last = kx + w;
  }
}

/// 흰 층의 윤곽(t-e floor) — 왼쪽 아래 귀만 꼬리표 꼴을 따름
String _floorD(num x0, num ys, num x1, num yb, String kind, Object? cl, num tagH) {
  const n = jsNum;
  const TG = TAG;
  if (jsTruthy(cl) || kind == 'plain') return 'M${n(x1)},${n(ys)} H${n(x0)} V${n(yb)} H${n(x1)} Z';
  if (kind == 'key') {
    final r = jsMin(jsMin(TG.KEYR, tagH / 2), yb - ys);
    return 'M${n(x1)},${n(ys)} H${n(x0)} V${n(yb - r)} A${n(r)},${n(r)} 0 0 0 ${n(x0 + r)},${n(yb)} H${n(x1)} Z';
  }
  final c = jsMin(TG.CH, yb - ys);
  return 'M${n(x1)},${n(ys)} H${n(x0)} V${n(yb - c)} L${n(x0 + c)},${n(yb)} H${n(x1)} Z';
}

/// 명목 지도자 — 제 기간의 절반 이상이 실권 칸과 겹침(core.js groupStrip)
bool _nominal(Map<String, dynamic> o, Map<String, dynamic> c) {
  if (!jsTruthy(o['real'])) return false;
  final num len = c['b'] - c['a'];
  if (len <= 0) return false;
  num ov = 0;
  for (final r in o['real']) {
    ov += jsMax(0, jsMin(c['b'], r['b']) - jsMax(c['a'], r['a']));
  }
  return ov * 2 >= len;
}

/// 흰 층 한 단 — leader(t-e 그대로: 세로 금 먹 20 · 글 8.5 400) · power(단체 색 24% 칠 · 글 8.5 700) · real(단체 색 45% 칠 · 금 64% + 먹 · 글 먹빛)
void _paintFloor(BaseTheme th, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> b, Map<String, dynamic> f, num top, String kind) {
  String k(num a) => th.k(a);
  final yb = top + _FLOOR;
  final num lo = b['X0'] + (b['cl'] ? 2 : 6), hi = b['X1'] - 2;
  num lastX = -1;
  void divider(num xx, String col) {
    final q = jsRound(xx) + .5;
    if ((q - lastX).abs() < 2.5 || q < b['X0'] + 3 || q > b['X1'] - 3) return;
    E('line', {'x1': q, 'x2': q, 'y1': top + 1, 'y2': yb - 1, 'stroke': col}, p.band);
    lastX = q;
  }

  for (final c in f['cells']) {
    final xa = jsMax(jsMax(p.X(c['a']), lo), p.CL - 1), xe = jsMin(p.X(c['b']), hi);
    if (xe - xa < 1) continue;
    if (f['kind'] == 'leader') {
      for (final xx in [xa, xe]) {
        divider(xx, k(.2));
      }
      if (th.tw(c['n'], 8.5, 'body', 400) <= xe - xa - 6) th.t(p.band, xa + 3, K.base(top + _FLOOR / 2, 8.5), c['n'], 'body', {'size': 8.5, 'wt': 400, 'fill': K.nameInk(o['c']), 'op': _nominal(o, c) ? .5 : null});
      continue;
    }
    final real = f['kind'] == 'real', l = jsRound(xa), r = jsRound(xe);
    E('rect', {'x': l, 'y': top + .5, 'width': r - l, 'height': _FLOOR - 1, 'fill': real ? K.mix(c['c'], .45, th.tok['paper']) : th.fillOf(c['c'])}, p.band);
    for (final xx in [xa, xe]) {
      divider(xx, real ? K.mixOk(c['c'], .64, K.INK) : k(.2));
    }
    final s = K.fit(c['n'], xe - xa - 6, 8.5, 700);
    if (s.isNotEmpty) th.t(p.band, xa + 3, K.base(top + _FLOOR / 2, 8.5), s, 'name', {'size': 8.5, 'fill': real ? K.mix(c['c'], .10, K.INK) : K.tabInk(c['c'])});
  }
}

/* ══ 객체 = 갈래 E 꼬리표 + 흰 층 여러 단 + 손잡이 ══ */
void _object(BaseTheme th, Map<String, dynamic> S, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> g, Map<String, dynamic> opt) {
  const TG = TAG;
  final b = TG.geom(p, o, g), sel = jsTruthy(o['selected']), kind = TG.kindOf(o);
  String k(num a) => th.k(a);
  final num head = jsOr(b['sp']['head'], _HEAD);
  final List floors = o['floors'] ?? const [];
  final hh = head - 1, H = hh + floors.length * _FLOOR;
  g['tagBottom'] = b['Y'] + H;
  final cd = jsTruthy(o['serve']) ? TG.card(th, p, o, g, b, b['Y'], H, kind) : null;
  if (jsTruthy(o['keys'])) _keys(th, p, o, b);
  final edge = TG.paintTag(th, p, o, b, b['X0'], b['Y'], H, kind, p.band).edge;
  final tops = <num>[];
  if (floors.isNotEmpty) {
    final num ys = b['Y'] + hh, yb = b['Y'] + H, xr = b['XR'];
    E('path', {'d': _floorD(b['X0'], ys, xr, yb, kind, b['cl'], H), 'fill': b['fuzzy'] ? TG.fade(p, b['X1'], b['XR'], '#ffffff') : '#ffffff', 'stroke': 'none'}, p.band);
    final line = b['fuzzy'] ? TG.fade(p, b['X1'], b['XR'], edge) : edge;
    for (final (i, f) in floors.indexed) {
      final top = ys + i * _FLOOR;
      tops.add(top);
      E('path', {'d': 'M${jsNum(b['cl'] ? b['X0'] : b['X0'] + .5)},${jsNum(top)} H${jsNum(xr)}', 'stroke': line}, p.band);
      _paintFloor(th, p, o, b, f, top, kind);
    }
    if (kind != 'plain') {
      E('path', {
        'd': TG.outline(b['X0'], b['Y'], b['XR'], H, kind, b['cl'], {'open': b['fuzzy']}),
        'fill': 'none',
        'stroke': b['fuzzy'] ? TG.fade(p, b['X1'], b['XR'], edge) : edge,
        'stroke-dasharray': jsTruthy(o['rival']) ? '3 2' : null,
      }, p.band);
    }
  }
  final tie = g['tie'] = <String, dynamic>{'xe': b['X1']};
  num nx = p.CL + 6;
  if (!b['cl'] && !b['short']) {
    tie['hx'] = TG.holeX(b, kind);
    tie['hy'] = b['Y'] + TG.HOLE;
    nx = tie['hx'] + 7;
    TG.hole(th, p, tie['hx'], tie['hy'], sel);
  }
  if (jsTruthy(o['out']) && !b['cr'] && !b['short']) {
    tie['dx'] = b['X1'] - 7;
    tie['dy'] = b['Y'] + TG.HOLE;
  }
  final rlim = jsMin(tie['dx'] != null ? tie['dx'] - 8 : b['X1'] - 6, p.CR - 6);
  final num l1 = b['y0'] + 12;
  final lines = [for (var i = 0; i < b['lines']; i++) l1 + i * TG.G['line']!];
  final busy = [for (final _ in lines) <List<num>>[]];
  final String s = b['short'] ? '' : K.fit(o['n'], rlim - nx, 9, 700);
  num nameEnd = nx;
  if (s.isNotEmpty) {
    th.t(p.band, nx, K.base(l1, 9), s, 'name', {'size': 9, 'fill': sel ? K.INK : (jsTruthy(o['rival']) ? k(.6) : (o['g'] == '무리' ? K.nameInk(o['c']) : K.tabInk(o['c'])))});
    nameEnd = nx + th.tw(s, 9, 'name');
    busy[0].add([nx - 4, nameEnd + 4]);
  }
  if (tie['dx'] != null) busy[0].add([tie['dx'] - 6, tie['dx'] + 6]);
  // 손잡이 — 단체가 든 나라(o.groups = 접힌 단체 수)에만
  if (jsTruthy(o['groups']) && jsTruthy(opt['handle'])) {
    final cnt = jsStr(o['groups']);
    if (opt['handle'] == 'flag') {
      // 플래그 = 구멍(과 매다는 실) 오른쪽 6 · 윗변에 얹힘. 펼친 창은 그 자리에서 위로.
      final num fx = (tie['hx'] ?? b['X0'] + 7) + 6;
      final List list = o['groupNames'] ?? [for (final [n, _, _, c, ...] in RULE) <dynamic>[n, c]];
      _flag(th, p, o, fx, b['Y'], list, opt['flagOpen'] == o['n'], '단체');
    } else if (opt['handle'] == 'btn') {
      final hb = _button(th, p, o, '${jsTruthy(o['open']) ? '▾' : '▸'} 단체 $cnt', nameEnd + 4, l1);
      if (hb.x1 <= rlim) busy[0].add([hb.x0 - 3, hb.x1 + 3]);
    } else {
      final pi = floors.indexWhere((f) => f['kind'] == 'power');
      if (pi >= 0) {
        final first = floors[pi]['cells'][0], x1 = K.px(p.X(first['a'])) - 3, w = jsRound(4 + 10 + 3 + K.TW(cnt, 8.5, 400) + 5);
        _whiteTag(th, p, cnt, x1 - w, tops[pi] + 2, 12, o['open']); // 집권 층 첫 칸 왼쪽 · 위아래 2 띄움
      } else {
        final hb = _whiteTag(th, p, cnt, K.px(nameEnd + 4), K.px(l1 - 6), 12, o['open']); // 집권 층이 없으면 머리 줄
        busy[0].add([hb.x0 - 3, hb.x1 + 3]);
      }
    }
  }
  TG.events(th, p, o, b, {'lines': lines, 'busy': busy, 'size': 9.5, 'dot': 2.5, 'gap': 3.5, 'lo': (b['cl'] ? p.CL : b['X0']) + 14, 'hi': b['X1'] - 9, 'rlim': rlim});
  if (cd != null) {
    final tr = jsMin(cd['xr'], p.CR) - 8;
    if (tr - TG.hostW(th, o['serve']) > cd['xs'] + 30) TG.hostTab(th, p, cd, tr, cd['cy']);
  }
  if (sel) E('path', {'d': TG.outline(b['X0'] - 2, b['Y'] - 2, b['XR'] + 2, H + 4, kind, b['cl'], {'c': 6, 'r': 14}), 'fill': 'none', 'stroke': K.INK, 'stroke-width': 1.5}, p.over);
}

/* ══ 실 — 줄 건너는 승계(갈라짐 · 세로 통로는 띠 뒤 · 구멍으로 드는 토막만 띠 위) · ⑤ 옮겨 앉기 ══ */
void _cross(BaseTheme th, MockLayers p, Map<String, dynamic> L) {
  const n = jsNum;
  String k(num a) => th.k(a);
  final all = [for (final r in L['rows']) ...r['items']];
  for (final o in all) {
    if (!jsTruthy(o['cross']) || o['geo'] == null || o['geo']['tie'] == null || o['geo']['tie']['hx'] == null) continue;
    final a = all.where((q) => q['n'] == o['cross']['from'] && q['geo'] != null).firstOrNull;
    if (a == null || a['geo']['tie'] == null || a['geo']['tie']['dx'] == null) continue;
    final ab = a['geo']['bb'], nx = ab['next'] != null && ab['next']['geo'] != null ? ab['next']['geo']['bb'] : null;
    final num xv = nx != null && nx['X0'] - ab['X1'] < 12 ? (ab['X1'] + nx['X0']) / 2 : ab['X1'] + 8;
    final num dx = a['geo']['tie']['dx'], dy = a['geo']['tie']['dy'], hx = o['geo']['tie']['hx'], hy = o['geo']['tie']['hy'];
    final r = jsMin(jsMin(6, (hy - dy).abs() / 2), jsMax(0, hx - 2.5 - xv)), up = hy < dy ? -1 : 1;
    final st = <String, Object?>{'stroke': k(.5), 'stroke-width': 1.5, 'fill': 'none', 'stroke-linejoin': 'round', 'stroke-dasharray': o['cross']['how'] == 'indirect' ? '3 2' : null};
    // 마름모 → 통로로 굽는 토막과 구멍으로 드는 토막은 띠 위 · 세로 통로만 띠 뒤(다른 꼬리표 뒤로 지남)
    E('path', {'d': 'M${n(dx)},${n(dy)} H${n(xv - r)} Q${n(xv)},${n(dy)} ${n(xv)},${n(dy + up * r)}', ...st}, p.over);
    E('path', {'d': 'M${n(xv)},${n(dy + up * r)} V${n(hy - up * r)}', ...st}, p.links);
    E('path', {'d': 'M${n(xv)},${n(hy - up * r)} Q${n(xv)},${n(hy)} ${n(xv + r)},${n(hy)} H${n(hx - 2.5)}', ...st}, p.over);
    TAG.diamond(p, dx, dy, a['c']);
  }
}

/// ⑤ 옮겨 앉기 — 같은 mv의 토막 둘. 다른 줄(A): d3-a 규칙(앞 토막 아랫변의 매듭 → 옮긴 해 왼쪽 6으로 곧게 → 반지름 6 사분원 → 뒤 토막 구멍 · 점선은 띠 뒤 · 구멍 토막은 띠 위).
/// 같은 줄(B): 이음매 가운데 · 구멍 높이에 매듭 + 구멍으로 드는 짧은 실만
void _moves(BaseTheme th, MockLayers p, Map<String, dynamic> L) {
  const n = jsNum;
  String k(num a) => th.k(a);
  final m = <String, List<dynamic>>{};
  for (final r in L['rows']) {
    for (final o in r['items']) {
      if (jsTruthy(o['mv']) && o['geo'] != null && jsTruthy(o['geo']['tie'])) (m[o['mv']] ??= []).add(o);
    }
  }
  for (final id in m.keys) {
    final a = jsSorted(m[id]!, (x, y) => x['a'] - y['a']);
    for (var i = 1; i < a.length; i++) {
      final A = a[i - 1]['geo'], B = a[i]['geo'], ba = A['bb'], bb = B['bb'], hx = B['tie']['hx'], hy = B['tie']['hy'];
      if (hx == null) continue;
      if (identical(A['row'], B['row'])) {
        final cx = (ba['X1'] + bb['X0']) / 2;
        E('path', {'d': 'M${n(cx)},${n(hy)} H${n(hx - 3)}', 'stroke': k(.5), 'stroke-width': 1.5, 'fill': 'none'}, p.over);
        E('circle', {'cx': cx, 'cy': hy, 'r': 2, 'fill': k(.5)}, p.over);
        continue;
      }
      const R = 6;
      final down = hy > A['tie']['hy'], vx = jsRound(jsMin(ba['X1'], bb['X0']) - 6) + .5;
      final num y0 = down ? A['tagBottom'] : ba['Y'], y1 = hy, ex = hx - 3;
      final st = <String, Object?>{'fill': 'none', 'stroke': k(.5), 'stroke-width': 1.5, 'stroke-dasharray': '3 2'};
      E('path', {'d': 'M${n(vx)},${n(y0)} V${n(y1 + (down ? -R : R))} Q${n(vx)},${n(y1)} ${n(vx + R)},${n(y1)} H${n(bb['X0'])}', ...st}, p.links);
      E('path', {'d': 'M${n(bb['X0'])},${n(y1)} H${n(ex)}', ...st, 'stroke-dasharray': null}, p.over);
      E('circle', {'cx': vx, 'cy': y0, 'r': 2, 'fill': k(.5)}, p.over);
    }
  }
}

/* ══ 등록 ══ JS register(def)가 만드는 갈래 객체 — 기준 방향(BASE)에 고리를 덮는다. 그리기 상태는 두지 않는다(같은 갈래로 여러 번 그림). */
class S4Theme extends BaseTheme {
  /// [M]은 JS def.M — 갈래마다 더 바꿀 치수(s4 갈래 파일은 쓰지 않음).
  S4Theme({required this.id, required this.code, required this.name, this.idea = '', this.pro = '', this.con = '', this.rec = false, required this.opt, Map<String, num> M = const {}}) : _defM = M;

  @override
  final String id;
  @override
  final String code;
  @override
  final String name;
  @override
  final String idea;
  @override
  final String pro;
  @override
  final String con;
  @override
  final bool rec;
  @override
  final Map<String, dynamic> opt;
  final Map<String, num> _defM;

  @override
  String get by => 'Fable';
  /// 판 카드용 값(API.md의 방향 객체) — 지금 읽는 곳 없음(board-s4 · render.js 모두).
  bool get keepB => false;

  /// JS Object.assign({}, M, def.M || {}) — 그 위에 render.js merge가 BASE.M을 깐다(BaseTheme.M).
  @override
  Map<String, num> get mOverride => {..._M, ..._defM};

  @override
  Map<String, dynamic>? scene(Map<String, dynamic> S) => _scene(S, opt);

  @override
  void frame(Map<String, dynamic> S, MockLayers p, [Map<String, dynamic>? L]) {
    final rec = _layout(S, L!, M);
    S4_REC[id] = rec;
    super.frame(S, p, L);
  }

  @override
  void object(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> o, Map<String, dynamic> g) => _object(this, S, p, o, g, opt);

  @override
  void link(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> a, Map<String, dynamic> b, String how) => TAG.tieLink(this, p, a, b, how);

  /* ══ ②(나) 띠 밑 집권 사슬 + 손잡이 — 목업 d7-c 그대로(직위 줄 자리 · 띠 아래 틈 3 · 높이 14 · 첫 칸 둥근 끝 + 구멍 + 실) ══
     JS는 자유 함수 lanes(th, …)가 window.BASE.lanes.call(th, …)로 기준 고리를 부른다 — Dart는 그 본문을 이 고리로 옮겨 super.lanes로 부른다
     (자유 함수에서 th.lanes를 부르면 이 고리로 되돌아와 끝나지 않음). */
  @override
  void lanes(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> L) {
    const n = jsNum, TG = TAG;
    final tk = tok, Mm = M;
    final other = [
      for (final r in L['lanes'])
        if (!jsTruthy(r['lane']['grp'])) r,
    ];
    if (other.isNotEmpty) super.lanes(S, p, {...L, 'lanes': other});
    for (final r in L['lanes']) {
      final ln = r['lane'];
      if (!jsTruthy(ln['grp'])) continue;
      final y = K.px(r['laneY']), h = Mm['laneH']! - 1, top = y - Mm['laneGap']! - 1;
      for (final ch in ln['chains']) {
        final xs = K.px(p.X(ch['at']));
        num? prev;
        for (final (i, [nm, a, bb, c, ...]) in (ch['items'] as List).indexed) {
          final x0 = prev ?? K.px(p.X(a)), x1 = jsRound(jsMin(p.X(bb), p.CR + 30)) - .5, kind = i != 0 ? 'plain' : 'key';
          E('path', {'d': TG.outline(x0, y, x1, h, kind, false, {'r': h / 2}), 'fill': fillOf(c), 'stroke': edgeOf(c)}, p.band);
          var tx = x0 + 4;
          if (i == 0) {
            final hx = x0 + 5.5, hy = y + h / 2;
            E('path', {'d': 'M${n(hx)},${n(hy - 1.5)} V${n(top)}', 'stroke': k(.45), 'fill': 'none'}, p.band);
            E('circle', {'cx': hx, 'cy': hy, 'r': 1.5, 'fill': tk['paper'], 'stroke': k(.45)}, p.band);
            tx = x0 + 11;
          }
          final s = K.fit(nm, jsMin(x1, p.CR) - tx - 3, 8.5, 700);
          if (s.isNotEmpty) t(p.band, tx, K.base(y + h / 2, 8.5), s, 'name', {'size': 8.5, 'fill': tabInkOf(c)});
          prev = x1;
        }
        final cnt = jsStr(ch['count']), w = jsRound(4 + 10 + 3 + K.TW(cnt, 8.5, 400) + 5);
        final x1 = (ch['items'] as List).isNotEmpty ? xs - 3 : xs + w;
        _whiteTag(this, p, cnt, x1 - w, y, h, ch['open']);
      }
    }
  }

  @override
  void extra(Map<String, dynamic> S, MockLayers p, Map<String, dynamic> L) {
    _cross(this, p, L);
    _moves(this, p, L);
  }
}
