// 문화권 머리 단 밑 줄(리메이크 4단계 과제 3 · 4 · 계획 정한 것 #3): 문화권 단위 줄(layout 답의 `sphereLines`)을 문화권 id마다 모은 순수 모델.
// 메이커 서고 미리보기의 같은 셈이 원본이다 — js/timeline.js `_sphereF4`(2124 ~ 2149줄)와 js/core.js `HT.f4Preview`의 `sphereRows`(7372 ~ 7385줄).
//   시대 = kind 2(문화권 시대 구분) 가운데 시작이나 끝이 있는 것 — 답의 차례 그대로.
//   주기 = kind 3(문화권 주기 줄)의 첫 것 — data JSON의 두 꼴 {names, start, label}(이름 돌림) · {era, from, step, label}(연호 눈금)을 푼다.
//          data가 깨졌거나 두 꼴 어디에도 맞지 않으면 그 줄은 없는 줄로 치고 다음 kind 3을 본다(미리보기도 그런 줄은 건너뛰고 다음 것을 받는다).
//   사람 띠 = kind 1(과제 4 걸음 1) — 왕관이 둘 이상인 사람(내보내기 export/persons.mjs · 미리보기 HT.personBands가 고른 것)을 그 줄의 문화권
//          (SphereLine.sphere — 내보내기가 왕관 트랙들의 문화권 가운데 머리 단 차례가 가장 앞선 것을 실음) 밑에. 시작 차례로 줄 나눔:
//          앞 사람의 끝 + 2해 ≤ 시작이면 같은 줄(미리보기 `_sphereF4` 2134 ~ 2148줄 — 분을 해 좌표로 바꿔 같은 셈).
//   높이 = (시대가 있으면 [G.sphereEpoch] 14) + (주기가 있으면 [G.sphereCycle] 13) + 사람 띠 줄 수 × [G.spherePerson] 16 + [G.sphereRowsPad] 2 —
//          줄이 하나도 없으면 0이고 덧 2도 없다(옛 저장소 · 문화권 줄이 없는 저장소의 쌓기가 4단계 전과 1배 같은 열쇠).
// 줄은 보는 범위와 상관없이 그 문화권에 있으면 둔다(설계 4-6 #1 조각 ② 규칙 — 보는 범위로 쌓기가 바뀌면 줄이 뛴다).
// 같은 주기(감독 결정 2026-10-25 '육십갑자는 머리 단 주기 줄만'): 주기 줄이 날짜 칸 간지 줄과 같은 해 이름을 돌리는가([SphereCycleRow.sameYearsAs]) —
//          펼친 문화권 머리 단이 같은 주기를 그리면 날짜 칸이 간지 줄을 넣지 않는다(axis_model.dart '3) 간지' · layout.dart `sphereCyclesShown`).
import 'aux_calendar.dart' show YearCycle, fromAstro, toAstro, yearGanji;
import 'layout.dart' show G, SphereLine;
import 'ruler.dart' show yearAt, yearLabel;

/// 문화권 시대 구분 한 칸(kind 2) — 시작 · 끝은 분(엔진 답 그대로).
class SphereEpochRow {
  const SphereEpochRow(this.name, this.start, this.end, {this.uid = '', this.color = 0});
  final String name;
  final int start, end;

  /// 시대 구분의 uid(공통 줄의 같은 시대를 가릴 때 — 과제 3 걸음 3) · 색.
  final String uid;
  final int color;

  @override
  bool operator ==(Object other) => other is SphereEpochRow && other.name == name && other.start == start && other.end == end && other.uid == uid && other.color == color;

  @override
  int get hashCode => Object.hash(name, start, end, uid, color);

  @override
  String toString() => 'SphereEpochRow($name · $start ~ $end)';
}

/// 문화권 주기 줄(kind 3) 하나 — 이름 돌림([names]가 있음) 또는 연호 눈금([era]가 있음) 가운데 하나.
class SphereCycleRow {
  const SphereCycleRow.names(this.names, this.start, this.label) : era = '', from = 0, step = 1;
  const SphereCycleRow.era(this.era, this.from, this.step, this.label) : names = const [], start = 0;

  /// 이름 돌림: 해마다 돌아가는 이름들과 첫 이름의 해(해 좌표).
  final List<String> names;
  final int start;

  /// 연호 눈금: 연호 이름 · 원년(해 좌표) · 눈금 간격(해 — 1 이상).
  final String era;
  final int from, step;

  /// 줄 이름표(왼쪽 칸) — 비면 연호 이름.
  final String label;

  /// 이름 돌림인가(아니면 연호 눈금).
  bool get isNames => names.isNotEmpty;

  /// 왼쪽 칸에 쓰는 줄 이름(미리보기 `cyc.label || cyc.era || ''`).
  String get title => label.isNotEmpty ? label : era;

  /// kind 3 줄 하나를 푼다 — data가 비었거나 깨졌거나 두 꼴 어디에도 맞지 않으면 null.
  /// 너그럽게: 수는 글로 와도 읽고(미리보기의 `Number(…) || 0`), 이름은 글로 바꾸고, step은 1 아래면 1. label이 비면 줄의 name(내보내기가 label을 싣는 칸).
  static SphereCycleRow? parse(SphereLine line) {
    final data = line.decoded;
    if (line.kind != SphereLine.cycle || data is! Map) return null;
    String text(Object? v) => switch (v) { null => '', final String s => s, final v => '$v' };
    int number(Object? v) => switch (v) {
      final num n when n.isFinite => n.toInt(),
      final String s => (num.tryParse(s.trim()) ?? 0).toInt(),
      _ => 0,
    };
    final label = text(data['label']).isNotEmpty ? text(data['label']) : line.name;
    final names = data['names'];
    if (names is List && names.isNotEmpty) {
      return SphereCycleRow.names(List.unmodifiable([for (final n in names) text(n)]), number(data['start']), label);
    }
    final era = text(data['era']);
    if (era.isEmpty) return null;
    final step = number(data['step']);
    return SphereCycleRow.era(era, number(data['from']), step < 1 ? 1 : step, label);
  }

  /// 날짜 칸 간지 줄의 주기([axis] — 최상위 yearCycle)와 해마다 같은 이름을 돌리는가(감독 결정 2026-10-25 '육십갑자는 머리 단 주기 줄만').
  ///  · 날짜 칸 쪽: [axis]가 사용자 순환(`custom` — 끄지 않았고 이름 2개 이상)이면 그 이름 돌림, 아니면(없음 · off · 이름 1개 이하) 내장 육십갑자
  ///    (길이 60 · 기준 해 4 · 이름 [yearGanji]) — 날짜 칸이 그리는 것(ruler.dart `_ganji`)과 같은 가름.
  ///  · 같음 = 이 줄이 이름 돌림([isNames])이고 길이가 같으며, 한 바퀴(길이만큼의 해) 동안 해마다 이름이 같은 것. 해는 천문 해([toAstro])로 센다 —
  ///    그리기(paint/sphere_lines.dart · aux_calendar.dart `YearCycle.index`)와 같은 셈이라 기준 해가 길이의 배수만큼 어긋난 같은 돌림도 저절로 같다.
  ///  · 연호 눈금(era · step)은 해 이름을 돌리지 않으므로 늘 다르다.
  bool sameYearsAs(YearCycle? axis) {
    if (!isNames) return false;
    final custom = axis != null && axis.custom ? axis : null; // 없으면 내장 육십갑자
    final length = custom?.names.length ?? 60;
    if (names.length != length) return false;
    final base = toAstro(start);
    for (int i = 0; i < length; i++) {
      // 이 줄의 i번 이름이 서는 해(천문 해 base + i — 그 해의 순번이 i)에 날짜 칸이 쓰는 이름.
      final year = fromAstro(base + i);
      if (names[i] != (custom?.name(year) ?? yearGanji(year))) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is SphereCycleRow && _sameNames(other.names, names) && other.start == start && other.era == era && other.from == from && other.step == step && other.label == label;

  static bool _sameNames(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(names), start, era, from, step, label);

  @override
  String toString() => isNames ? 'SphereCycleRow(이름 ${names.length} · 첫 해 $start · $label)' : 'SphereCycleRow($era · $from부터 $step해마다 · $label)';
}

/// 사람 띠 하나(kind 1) — 왕관이 둘 이상인 사람. 시작 · 끝은 분(엔진 답 그대로), [lane]은 그 문화권 사람 띠 영역 안의 줄 번호(0부터).
class SpherePersonRow {
  const SpherePersonRow(this.name, this.start, this.end, {this.uid = '', this.crowns = const [], this.lane = 0});
  final String name;
  final int start, end;

  /// 인물 uid(SphereLine.uid — 인물 기록이 없는 사람이면 빈 글).
  final String uid;

  /// 왕관(data의 `[{uid: 띠 uid, cell: 지도자 칸 순번}]`) — 과제 4 걸음 2의 실이 닿는 칸 · 띠 안 '왕관 n'의 수.
  final List<({String uid, int cell})> crowns;

  /// 줄 번호(미리보기 `ps._lane`).
  final int lane;

  /// 시작 · 끝의 해 좌표(0년 빈 자리 — ruler.dart의 [yearAt]).
  double get startYear => yearAt(start.toDouble());
  double get endYear => yearAt(end.toDouble());

  /// 띠 안 때 글: '시작해 ~ 끝해 · 왕관 n'. 미리보기의 글은 `${ps.start} ~ ${ps.end}  ·  왕관 n`이지만 css `white-space: nowrap`이 빈칸 둘을 하나로 접어
  /// 그려진 글은 빈칸 하나다. 해는 앱의 눈금 해 표기([yearLabel] — 기원전은 '기원전 n', '년'을 붙이지 않음 · 기원후는 미리보기의 맨 수와 같은 글).
  String get when => '${yearLabel(_whole(startYear))} ~ ${yearLabel(_whole(endYear))} · 왕관 ${crowns.length}';

  /// 해 좌표의 정수 해 — 분을 정수로 담아 해 경계 바로 앞으로 떨어진 값은 그 해로.
  static int _whole(double year) => (year + 1e-6).floor();

  SpherePersonRow _withLane(int lane) => SpherePersonRow(name, start, end, uid: uid, crowns: crowns, lane: lane);

  @override
  bool operator ==(Object other) =>
      other is SpherePersonRow &&
      other.name == name &&
      other.start == start &&
      other.end == end &&
      other.uid == uid &&
      other.lane == lane &&
      _sameCrowns(other.crowns, crowns);

  static bool _sameCrowns(List<({String uid, int cell})> a, List<({String uid, int cell})> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(name, start, end, uid, lane, Object.hashAll(crowns));

  @override
  String toString() => 'SpherePersonRow($name · $start ~ $end · 왕관 ${crowns.length} · 줄 $lane)';
}

/// 문화권 하나의 머리 단 밑 줄 — 시대 줄(있으면 맨 위) · 주기 줄(그 밑) · 사람 띠 [lanes]줄(그 밑).
class SphereRows {
  const SphereRows(this.epochs, this.cycle, [this.persons = const [], this.lanes = 0]);

  /// 줄이 하나도 없는 문화권.
  static const none = SphereRows([], null);

  final List<SphereEpochRow> epochs;
  final SphereCycleRow? cycle;

  /// 사람 띠(답의 차례 그대로 — 그리는 차례 · 저마다 줄 번호를 닮) · 사람 띠 줄 수.
  final List<SpherePersonRow> persons;
  final int lanes;

  bool get isEmpty => epochs.isEmpty && cycle == null && persons.isEmpty;

  /// 머리 단 밑에 더하는 높이(배치 px — 펼친 문화권만 쓴다). 줄이 없으면 0.
  double get height =>
      isEmpty ? 0 : (epochs.isEmpty ? 0 : G.sphereEpoch) + (cycle == null ? 0 : G.sphereCycle) + lanes * G.spherePerson + G.sphereRowsPad;

  /// 줄 자리(머리 단 밑 줄 영역의 위에서) — 시대 줄은 0, 주기 줄은 시대 줄이 있으면 14 아래, 사람 띠 첫 줄은 그 밑(줄마다 16 — 미리보기의 y 차례).
  double get epochTop => 0;
  double get cycleTop => epochs.isEmpty ? 0 : G.sphereEpoch;
  double get personTop => cycleTop + (cycle == null ? 0 : G.sphereCycle);

  @override
  String toString() => 'SphereRows(시대 ${epochs.length} · 주기 ${cycle ?? '없음'} · 사람 ${persons.length}($lanes줄) · 높이 $height)';
}

/// 문화권 id → 그 문화권의 머리 단 밑 줄. 줄이 하나도 없는 문화권은 담지 않는다(찾으면 [SphereRows.none]으로 친다).
/// [spheres](머리 단 목록의 문화권 id)를 주면 그 밖 문화권의 줄은 모두 뺀다 — 머리 단이 없는 문화권의 사람 띠는 그릴 자리가 없다.
Map<String, SphereRows> collectSphereRows(Iterable<SphereLine> lines, {Iterable<String>? spheres}) {
  final known = spheres?.toSet();
  final epochs = <String, List<SphereEpochRow>>{};
  final cycles = <String, SphereCycleRow>{};
  final persons = <String, List<SpherePersonRow>>{};
  for (final line in lines) {
    if (line.sphere.isEmpty || (known != null && !known.contains(line.sphere))) continue;
    if (line.kind == SphereLine.person) {
      (persons[line.sphere] ??= []).add(SpherePersonRow(line.name, line.start, line.end, uid: line.uid, crowns: line.crowns));
    } else if (line.kind == SphereLine.epoch) {
      // 시작이나 끝이 있는 것(미리보기 `e.start != null || e.end != null`) — 답을 읽을 때 빠진 시작 · 끝은 0이 되므로 둘 다 0이면 없는 것으로 친다.
      if (line.start == 0 && line.end == 0) continue;
      (epochs[line.sphere] ??= []).add(SphereEpochRow(line.name, line.start, line.end, uid: line.uid, color: line.color));
    } else if (line.kind == SphereLine.cycle && !cycles.containsKey(line.sphere)) {
      final cycle = SphereCycleRow.parse(line);
      if (cycle != null) cycles[line.sphere] = cycle;
    }
  }
  final out = <String, SphereRows>{};
  for (final id in {...epochs.keys, ...cycles.keys, ...persons.keys}) {
    final (people, lanes) = _laneSplit(persons[id] ?? const []);
    out[id] = SphereRows(List.unmodifiable(epochs[id] ?? const <SphereEpochRow>[]), cycles[id], people, lanes);
  }
  return out;
}

/// 사람 띠의 줄 나눔(미리보기 `_sphereF4`): 시작 차례로(같은 시작이면 답의 차례 — js의 안정 정렬) 앞 줄들 가운데 끝 + 2해 ≤ 시작인 첫 줄에, 없으면 새 줄.
/// 해는 해 좌표로 센다(0년 빈 자리 — 미리보기의 해 수와 같은 셈). 분을 정수로 담아 생긴 몇 분 안의 어긋남은 같은 때로 친다.
/// 답의 차례를 지킨 목록(줄 번호를 단 것)과 줄 수를 돌려준다.
(List<SpherePersonRow>, int) _laneSplit(List<SpherePersonRow> persons) {
  if (persons.isEmpty) return (const <SpherePersonRow>[], 0);
  final starts = [for (final p in persons) p.startYear];
  final order = List<int>.generate(persons.length, (i) => i)
    ..sort((a, b) {
      final d = starts[a].compareTo(starts[b]);
      return d != 0 ? d : a - b;
    });
  final ends = <double>[];
  final lanes = List<int>.filled(persons.length, 0);
  for (final i in order) {
    var k = ends.indexWhere((end) => end + 2 <= starts[i] + 1e-5);
    if (k < 0) {
      ends.add(double.negativeInfinity);
      k = ends.length - 1;
    }
    ends[k] = persons[i].endYear;
    lanes[i] = k;
  }
  return (List<SpherePersonRow>.unmodifiable([for (int i = 0; i < persons.length; i++) persons[i]._withLane(lanes[i])]), ends.length);
}
