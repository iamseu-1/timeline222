// 빈 줄 접기 · 줄 흐름 검사가 함께 쓰는 작은 뼈대(3판의 줄 값을 가진 트랙 둘).
// 칸 층이 없어 띠 안이 '이름 색줄 + 사건 칸(+ 넉넉하게의 기간 막대)'뿐이다 — 줄의 몫이 손으로 셀 수 있는 값이 된다(두 장 꼬리표 · 리메이크 2부).
//   자동 · 빽빽하게: 글줄 1 · 막대 없음 → 띠 = 색줄 14 + 사건 칸 18 = 32,  줄의 몫 = 틈 + 띠
//   넉넉하게: 글줄 2 + 막대 2단 → 띠 = 14 + 사건 칸 18 × 2 + 막대 14 + 3(인물 없음) = 67
//   틈 = 첫 보이는 줄 0 + 줄 위 틈 5, 그다음 줄 3 + 5 = 8
//   트랙 = 위 여백 4 + 줄의 몫들 + 아래 여백 4,  트랙끼리는 틈 없이 이어 쌓인다

/// 3판의 줄 하나. 굳은 2판 값은 쓰지 않으므로(다시 쌓는다) 0으로 둔다.
Map<String, dynamic> foldRow(int id, {int kind = 0, int groupStart = 0, int zones = 0, int hem = 0}) => {
  'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
  'text_top': 0, 'text_lines': 1, 'rail_top': 0, 'organ_top': -1,
  'kind': kind, 'group_start': groupStart, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[],
  'fig': 0, 'fig_wide': 0, 'dep': 0, 'zones': zones, 'hem': hem,
};

/// 자료집 1(줄 0 · 1 · 2)과 자료집 2(줄 3 · 4). 자동 밀도의 줄 자리는 [4, 41, 81] · [129, 166], 전체 높이 125 + 85 = 210.
Map<String, dynamic> twoTrackLayout() => {
  'packs': [
    {'id': 1, 'name': '별여울 기록집', 'events': 12},
    {'id': 2, 'name': '해솔 기록집', 'events': 8},
  ],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울 갈래', 'color': 0xc27a45, 'rail_levels': 2,
      'rows': [foldRow(0, groupStart: 1), foldRow(1), foldRow(2)],
      'groups': [
        {'depth': 0, 'first': 0, 'count': 3, 'name': '별여울 사람', 'color': 0xc27a45, 'kind': 0},
      ],
    },
    {
      'id': 2, 'pack': 2, 'ord': 1, 'name': '해솔 갈래', 'color': 0x7a95c2, 'rail_levels': 2,
      'rows': [foldRow(3, groupStart: 1), foldRow(4)],
      'groups': [
        {'depth': 0, 'first': 3, 'count': 2, 'name': '해솔 사람', 'color': 0x7a95c2, 'kind': 0},
      ],
    },
  ],
  'epochs': <Map<String, dynamic>>[],
};

/// 트랙 하나에 줄 일곱과 겹친 민족 묶음 둘:
/// 바깥 묶음 A는 줄 1~3, 그 안의 묶음 B는 줄 3 하나. A를 접으면 줄이 다섯이 된다(리메이크 2부부터 자동 밀도의 글줄은 그래도 하나),
/// A 안에 숨은 B의 민족 경계는 틈을 벌리지 않는다.
Map<String, dynamic> sevenRowLayout() => {
  'packs': [
    {'id': 1, 'name': '별여울 기록집', 'events': 12},
  ],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울 갈래', 'color': 0xc27a45, 'rail_levels': 2,
      'rows': [
        foldRow(0),
        foldRow(1, groupStart: 1),
        foldRow(2),
        foldRow(3, groupStart: 1),
        foldRow(4),
        foldRow(5),
        foldRow(6),
      ],
      'groups': [
        {'depth': 0, 'first': 1, 'count': 3, 'name': '별여울 사람', 'color': 0xc27a45, 'kind': 0},
        {'depth': 1, 'first': 3, 'count': 1, 'name': '여울 갈래', 'color': 0xc27a45, 'kind': 0},
      ],
    },
  ],
  'epochs': <Map<String, dynamic>>[],
};
