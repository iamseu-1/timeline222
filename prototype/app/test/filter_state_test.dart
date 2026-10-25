import 'package:archive_prototype/ui/filter_state.dart';
import 'package:flutter_test/flutter_test.dart';

// 필터 상태의 규칙 — 명세 docs/명세-3단계/06-상세-검색-필터-도구.md 6-3 · 6-4 · 9절 ㈐-16 · 18.

void main() {
  test('적히지 않은 칩은 켜진 것이고, 누르면 끈 것만 쌓인다', () {
    const state = FilterState();
    expect(state.chipOn(ChipGroup.tracks, '1'), isTrue, reason: '기억된 것이 없으면 모두 켜짐');
    final off = state.toggleChip(ChipGroup.tracks, '1');
    expect(off.chipOn(ChipGroup.tracks, '1'), isFalse);
    expect(off.tracksOff, {'1'});
    expect(off.toggleChip(ChipGroup.tracks, '1').tracksOff, isEmpty, reason: '다시 누르면 켜진다');
  });

  test('Alt+클릭은 보이는 칩 가운데 누른 것만 켜고, 보이지 않는 칩의 기억은 그대로 둔다', () {
    const state = FilterState(kindsOff: {'culture'});
    final only = state.onlyChip(ChipGroup.kinds, 'state', ['state', 'federation', 'org']);
    expect(only.chipOn(ChipGroup.kinds, 'state'), isTrue);
    expect(only.chipOn(ChipGroup.kinds, 'federation'), isFalse);
    expect(only.chipOn(ChipGroup.kinds, 'org'), isFalse);
    expect(only.kindsOff.contains('culture'), isTrue, reason: '칩 줄에 없던 종류의 끔은 남는다');
  });

  test('실재성의 끔은 지금 칩 줄에 보이는 것만 센다', () {
    const state = FilterState(historicityOff: {'legendary', 'refuted'});
    expect(state.historicityOffAmong(['attested', 'semi']), isEmpty, reason: '칩 줄이 사라지면 나라가 모두 숨지 않는다');
    expect(state.historicityOffAmong(['attested', 'legendary']), {'legendary'});
    expect(state.historicityOff, {'legendary', 'refuted'}, reason: '저장값은 지우지 않는다 — 자료집을 다시 켜면 꺼 둔 대로');
  });

  test('대범위 모아 보기는 사람이 정한 적이 없으면 그 대범위의 기본값을 따른다', () {
    const state = FilterState();
    expect(state.scopeOn('s-1'), isFalse);
    expect(state.scopeOn('s-1', fallback: true), isTrue);
    final on = state.toggleScope('s-1');
    expect(on.scopeOn('s-1'), isTrue);
    expect(on.toggleScope('s-1', fallback: true).scopeOn('s-1', fallback: true), isFalse, reason: '적힌 값이 기본값을 이긴다');
  });

  test('표시 체크: 없는 열쇠는 기본값을 따르고, 승계선의 "직접 승계만"도 켜진 것으로 센다', () {
    const state = FilterState();
    expect(state.showing('dynasties'), isTrue);
    expect(state.showing('houses'), isFalse, reason: '가문 줄은 기본 끔');
    expect(state.showing('spotEcho'), isFalse, reason: '메아리는 기본 끔');
    final direct = state.withShowValue('succession', 'direct');
    expect(direct.showing('succession'), isTrue);
    expect(direct.withShowing('succession', false).showValue('succession'), isFalse, reason: '끄면 false가 된다');
  });

  test('이설은 show가 아니라 showAlt에 든다', () {
    const state = FilterState();
    expect(state.showing('showAlt'), isTrue);
    final off = state.withShowing('showAlt', false);
    expect(off.showAlt, isFalse);
    expect(off.show.containsKey('showAlt'), isFalse);
  });

  test('띠 안의 단 켬/끔과 밀도만 보기 조건으로 넘어간다', () {
    const state = FilterState();
    expect(state.toConditions().dynasties, isTrue);
    final next = state.withShowing('phases', false).withShowing('houses', true).withDensity(1);
    final c = next.toConditions();
    expect(c.phases, isFalse);
    expect(c.density, 1);
    expect(c.leaders, isTrue);
    expect(c, state.toConditions().copyWith(phases: false, density: 1), reason: '가문은 칠만 바꾸므로 보기 조건에 없다');
  });

  test("표시 체크 '단체'(감독 선택 D5) — 기본 켬 · 끄면 보기 조건의 단체가 꺼져 집권 단 · 실권 단 · 겹 탭이 숨는다", () {
    const state = FilterState();
    expect(bandToggles.map((t) => t.key), contains('groups'));
    expect(bandToggles.firstWhere((t) => t.key == 'groups').label, '단체');
    expect(state.showing('groups'), isTrue, reason: '옛 설정에 없는 열쇠는 켠 채(HT.SHOW_DEFAULTS.groups)');
    expect(state.toConditions().groups, isTrue);
    final off = state.withShowing('groups', false);
    expect(off.toConditions().groups, isFalse);
    expect(off.toConditions(), state.toConditions().copyWith(groups: false));
    expect(FilterState.fromJson(off.toJson()).showing('groups'), isFalse, reason: '기억에 적고 다시 읽는다');
  });

  test('조감으로 바꿀 때 직전 밀도를 기억한다', () {
    const state = FilterState();
    final wide = state.withDensity(-1);
    final bird = wide.withDensity(2);
    expect(bird.birdFrom, -1);
    expect(bird.withDensity(2).birdFrom, -1, reason: '조감에서 조감으로는 기억을 덮어쓰지 않는다');
    expect(bird.withDensity(bird.birdFrom).density, -1);
    expect(state.withDensity(7).density, 0, reason: '모르는 값은 자동으로');
  });

  test('기억한 것을 그대로 되읽는다', () {
    final state = const FilterState()
        .toggleChip(ChipGroup.tracks, '3')
        .toggleChip(ChipGroup.categories, '2')
        .toggleChip(ChipGroup.historicity, 'legendary')
        .toggleScope('scope-1')
        .withShowing('ganji', false)
        .withShowValue('succession', 'direct')
        .withShowing('showAlt', false)
        .withDensity(2)
        .copyWith(minImportance: 3, lens: 'local', birdShape: 'c', birdAuto: true, leaderLabel: 'temple', leaderOrdinal: true, filterOpen: true);
    expect(FilterState.fromJson(state.toJson()), state);
    expect(state.toJson()['tracks'], {'3': false}, reason: '끈 것만 적는다');
  });

  test('저장된 값이 없거나 어긋나면 기본값으로 읽고, 모르는 열쇠는 무시한다', () {
    expect(FilterState.fromJson(const {}), const FilterState());
    final odd = FilterState.fromJson(const {
      'density': 9,
      'minImportance': 0,
      'birdShape': 'z',
      'leaderLabel': '없는 표기',
      'birdFrom': 2,
      'show': {'dynasties': false, '없는열쇠': true, 'succession': '이상한값'},
      'lens': 'local',
    });
    expect(odd.density, 0);
    expect(odd.minImportance, 1);
    expect(odd.birdShape, 'a');
    expect(odd.leaderLabel, 'auto');
    expect(odd.birdFrom, 0);
    expect(odd.lens, 'local');
    expect(odd.showing('dynasties'), isFalse);
    expect(odd.show.containsKey('없는열쇠'), isFalse);
    expect(odd.showValue('succession'), isTrue, reason: '읽을 수 없는 값은 기본값(true)');
  });

  test('뒤에 생긴 표시 체크는 기본값으로 채워 읽는다', () {
    final old = FilterState.fromJson(const {
      'show': {'dynasties': true, 'leaders': true},
    });
    expect(old.showing('figures'), isTrue, reason: '옛 설정에 없던 인물 단이 꺼진 채로 나오지 않게');
    expect(old.showing('houses'), isFalse);
    expect(old.show.length, FilterState.showDefaults.length);
  });

  test('끈 것만 적은 목록으로도 읽는다', () {
    final state = FilterState.fromJson(const {
      'tracks': ['2', '5'],
    });
    expect(state.tracksOff, {'2', '5'});
    expect(state.chipOn(ChipGroup.tracks, '1'), isTrue);
  });
}
