import 'load_app_fonts.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/glyph_atlas.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/lens_titles.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/aux_calendar.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/ui/theme_lens.dart' show LensBook;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 장면을 화면 없이 그림으로 뜬다 — 앱을 빌드하지 않고도 그리기를 눈으로 확인하고 지금 연표의 기준 그림(results/dom/<장면>.png)과 나란히 놓는 길.
// 진짜 자료 처리부(DLL)와 진짜 저장소를 거친다. 결과는 1920×1080(맨 위 60px은 앱 틀의 자리 — 기준 그림과 같은 좌표).
// 사용(app 폴더에서):
//   flutter test --no-pub test/render_scene_test.dart --dart-define=SCENE=밀집-세부
//     [--dart-define=DB=../data/moonwake3/archive.db] [--dart-define=START=775 --dart-define=END=940] [--dart-define=SCROLL=0]
//     [--dart-define=MAG=1] [--dart-define=OUT=../results/render] [--dart-define=NAME=이름] [--dart-define=DUMP=yes]
//   SCENE은 전체 · 밀집-세부 · 한-나라의-100년 가운데 하나이거나, START · END(지금 연표의 해 좌표)를 직접 준다.
//   DUMP=yes면 그린 띠 · 이름 · 점 · 막대의 자리를 <이름>.json으로도 적는다(기준 덤프와 숫자로 대조할 때).
//   THEME=<주제 id>면 그 렌즈를 켠 장면(아래 _theme — 저장소에 렌즈 변형이 실려 있어야 한다: 내보내기 export/lens.mjs).

const _scene = String.fromEnvironment('SCENE', defaultValue: '밀집-세부');
const _db = String.fromEnvironment('DB');
const _start = String.fromEnvironment('START'), _end = String.fromEnvironment('END');
const _scroll = String.fromEnvironment('SCROLL', defaultValue: '0');
/// SCROLL_ROW = 이 줄(전체 줄 번호)의 윗변이 몸통 맨 위에서 30px 아래에 오게 굴린다(SCROLL 대신 — 아래쪽 트랙을 볼 때).
const _scrollRow = String.fromEnvironment('SCROLL_ROW');
const _mag = String.fromEnvironment('MAG', defaultValue: '1');
const _out = String.fromEnvironment('OUT', defaultValue: '../results/render');
const _name = String.fromEnvironment('NAME');
const _dump = String.fromEnvironment('DUMP');

/// 보기 조건: DENSITY = -1 넉넉하게 · 0 자동 · 1 빽빽하게 · 2 조감, HIDE = 끌 단을 쉼표로(dynasties,leaders,cabinets,phases,ranks,figures).
const _density = String.fromEnvironment('DENSITY'), _hide = String.fromEnvironment('HIDE');

/// 보기 상태: FOLD_TRACKS = all 또는 트랙 id를 쉼표로, FOLD_PEOPLE = all 또는 묶음 열쇠(layout.groupKeyOf)를 세미콜론으로, BIRD = a|b|c(조감의 모양).
/// 밝기 상태: PICK_BAND = 고른 띠의 번호, PICK_EVENT = 고른 사건의 번호(PICK_ROW = 그 줄), HOT_BAND = 손을 올린 띠.
const _pickBand = String.fromEnvironment('PICK_BAND'), _pickEvent = String.fromEnvironment('PICK_EVENT'), _pickRow = String.fromEnvironment('PICK_ROW'), _hotBand = String.fromEnvironment('HOT_BAND');
/// 변형: EXPAND = 펼칠 상위 정권의 띠 번호를 쉼표로, SCOPES = 모아 볼 대범위의 uid를 쉼표로(저장소에 그 변형이 있어야 한다 — moonwake3g부터).
const _expand = String.fromEnvironment('EXPAND'), _scopes = String.fromEnvironment('SCOPES');
/// 단체 펼치기(리메이크 조각 ④): GROUPS = 단체를 펼칠 나라 띠의 uid를 쉼표로(저장소에 변형 kind 5 `groups:…`가 있어야 한다 — 엔진의 id_of로 번호를 찾는다).
const _groups = String.fromEnvironment('GROUPS');
/// 문화권(리메이크 조각 ②): SPHERES = 펼칠 문화권 id를 쉼표로(나머지는 접음 · 비우면 자료의 처음 접힘 그대로).
const _spheres = String.fromEnvironment('SPHERES');
const _foldTracks = String.fromEnvironment('FOLD_TRACKS'), _foldPeople = String.fromEnvironment('FOLD_PEOPLE'), _bird = String.fromEnvironment('BIRD');
/// 집합 보기: BOARD = 켤 판의 열쇠(`view:<id>` · 시대 구분의 임시 판은 `view:epoch:<시대 구분 uid>` — 저장소에 그 변형 kind 3이 있어야 한다).
/// 켜면 판 트랙이 맨 위 · 나머지 트랙은 판의 접힘으로 접힌다(앱의 독 목록 스위치와 같은 상태 — 날아가기 · 맨 위로 올리기는 START · END · SCROLL로).
const _board = String.fromEnvironment('BOARD');
/// D4: EPOCH_FOLD=yes면 시대를 접는다. CYCLE_ON=yes는 간지(해 이름) 줄을 켠 장면이다(리메이크 2부부터 처음에는 끔).
const _epochFold = String.fromEnvironment('EPOCH_FOLD'), _cycleOn = String.fromEnvironment('CYCLE_ON');

/// 렌즈(주제 보기 — 감독 선택 D5 결정 5 A): THEME = 켤 주제 id(system · faction · law …). 앱의 렌즈 부품(lib/ui/theme_lens.dart)이 하는 일과 같게
/// 항목 기록 themes의 x_lens로 줄 배치(자리 트랙) · 변형 `theme:<id>` · 사건 고리 색 · 그 주제의 사건 번호를 맞춘다(웹 lens-check의 그림과 견줄 때).
const _theme = String.fromEnvironment('THEME');

/// 연합의 겹 탭(감독 선택 D5 결정 3 C + 덧판 x2 A): HOT_COAL = 커서를 올린 연합 단체의 uid — 구성 나라 띠만 또렷 · 가담 기간 조명 · 나머지 줄 옅게
/// (앱에서는 탭에 올리면 `timeline_view.dart`가 `SceneMarks.hotCoal`에 적는다). 표시 체크 '단체'를 끈 장면은 HIDE=groups.
const _hotCoal = String.fromEnvironment('HOT_COAL');

/// 필터 시트의 표시 값(그리기만 바꾸는 것 — `SceneMarks`):
///   HOUSES = yes(가문 줄) · ALT = no(이설 끄기) · LEADER_LABEL = auto|temple|posthumous|given|… · LEADER_ORDINAL = yes(대수) ·
///   LENS = ''|local|<트랙 번호 글>(관점 — 이름은 LENS_NAMES로 따로 넣는다) · AXIS_OFF = ganji,eras,capitals,epochs 가운데 끌 것을 쉼표로.
/// LENS_NAMES = `사건번호:이름;…` 또는 `b<띠번호>:이름;…`(엔진의 `lens_names` 답을 손으로 넣는 길 — 저장소에 관점이 없어도 그림을 뜰 수 있다).
const _houses = String.fromEnvironment('HOUSES'), _alt = String.fromEnvironment('ALT');
const _leaderLabel = String.fromEnvironment('LEADER_LABEL'), _leaderOrdinal = String.fromEnvironment('LEADER_ORDINAL');
const _lens = String.fromEnvironment('LENS'), _lensNames = String.fromEnvironment('LENS_NAMES'), _axisOff = String.fromEnvironment('AXIS_OFF');

const _scenes = {
  '전체': (-1500.0, 1500.0),
  '밀집-세부': (775.0, 940.0),
  '한-나라의-100년': (240.0, 340.0),
};

/// 지금 연표의 해 좌표(정수 N = N년 1월 1일 · 기원전 1년 = −1 · 0은 빈 자리) → 1970년 기준 분. 내보내기(scripts/export/base.mjs의 minute)와 같은 투영.
double minuteOfYear(double y) {
  final year = y.floor();
  final a = DateTime.utc(year < 0 ? year + 1 : year), b = DateTime.utc(year == -1 ? 1 : (year < 0 ? year + 2 : year + 1));
  return (a.millisecondsSinceEpoch + (b.millisecondsSinceEpoch - a.millisecondsSinceEpoch) * (y - year)) / 60000;
}

Future<void> _loadFonts() async {
  await loadAppFonts();
  // 검사 환경에는 시스템 글꼴이 없다 — 지금 연표가 이 PC에서 쓰는 글꼴을 파일에서 읽어 같은 이름으로 올린다.
  for (final (family, files) in [
    ('Noto Sans KR', ['C:/Windows/Fonts/NotoSansKR-VF.ttf']),
    ('Malgun Gothic', ['C:/Windows/Fonts/malgun.ttf', 'C:/Windows/Fonts/malgunbd.ttf']),
  ]) {
    final loader = FontLoader(family);
    var any = false;
    for (final path in files) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length)));
      any = true;
    }
    if (any) await loader.load();
  }
}

void main() {
  final dll = File('../engine/target/release/archive_engine.dll');
  final db = File(_db.isNotEmpty ? _db : (File('../data/moonwake3/archive.db').existsSync() ? '../data/moonwake3/archive.db' : '../data/moonwake2/archive.db'));
  final ready = dll.existsSync() && db.existsSync();

  test('장면을 그림으로 뜬다', () async {
    await _loadFonts();
    final (startYear, endYear) = _start.isNotEmpty && _end.isNotEmpty ? (double.parse(_start), double.parse(_end)) : _scenes[_scene]!;
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    final info = await engine.start(db.absolute.path);
    final meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
    final shape = await engine.call({'op': 'layout'});
    final layout = SceneLayout.fromJson(Map<String, dynamic>.from(shape['data'] as Map));
    const width = 1920.0, height = 1080.0, top = 60.0;
    final mag = double.parse(_mag);
    final controller = TimelineController()
      ..reduceMotion = true
      ..resize(width, height - top)
      ..setExtent(double.parse(meta['min'] as String), double.parse(meta['max'] as String))
      ..setContentHeight(layout.totalHeight);
    // 켠 변형은 타일과 줄을 아는 조회 명령에 함께 실어야 엔진이 줄 번호를 바꿔 싣는다(앱 틀의 _filtered와 같은 일).
    const variantOps = {'rows_near', 'row_labels', 'list', 'events_in', 'echo'};
    final scene = TimelineScene(
      controller: controller, layout: layout,
      fetchTile: (level, x, chunk, packs) => engine.tile(level, x, chunk, packs, variants: layout.variantKeys),
      ask: (query) async {
        final keys = layout.variantKeys;
        final asked = keys.isNotEmpty && variantOps.contains(query['op']) && query['variants'] == null ? {...query, 'variants': keys} : query;
        return Map<String, dynamic>.from((await engine.call(asked))['data'] as Map);
      },
    );
    addTearDown(scene.dispose);
    if (_density.isNotEmpty || _hide.isNotEmpty) {
      final off = _hide.split(',').toSet();
      layout.setConditions(layout.conditions.copyWith(
        density: _density.isEmpty ? null : int.parse(_density),
        dynasties: !off.contains('dynasties'), leaders: !off.contains('leaders'), cabinets: !off.contains('cabinets'),
        phases: !off.contains('phases'), ranks: !off.contains('ranks'), figures: !off.contains('figures'),
        groups: !off.contains('groups'),
      ));
      controller.setContentHeight(layout.totalHeight);
    }
    if (_bird.isNotEmpty) {
      layout.setConditions(layout.conditions.copyWith(birdShape: BirdShape.values.byName(_bird)));
      controller.setContentHeight(layout.totalHeight);
    }
    if (_expand.isNotEmpty || _scopes.isNotEmpty || _groups.isNotEmpty) {
      var state = layout.viewState;
      for (final id in _expand.split(',')) {
        if (id.isNotEmpty) state = state.withHostExpanded(int.parse(id), true);
      }
      for (final uid in _groups.split(',')) {
        if (uid.isEmpty) continue;
        final band = (Map<String, dynamic>.from((await engine.call({'op': 'id_of', 'uid': uid}))['data'] as Map))['band'];
        expect(band, isA<num>(), reason: '단체를 펼칠 나라 $uid의 띠가 저장소에 없다');
        state = state.withGroupsExpanded((band as num).toInt(), true);
      }
      for (final uid in _scopes.split(',')) {
        if (uid.isNotEmpty) state = state.withScopeOpen(uid, true);
      }
      layout
        ..setViewState(state)
        ..finishFlow();
      controller.setContentHeight(layout.totalHeight);
      // 단추의 ▸/▾ · 이름표를 그리는 층의 밭도 앱 틀처럼 함께.
      final marks = SceneMarks.of(scene)
        ..expanded = layout.expandedHostsShown
        ..scopesOn = {...layout.viewState.openScopes};
      marks.version++;
    }
    if (_board.isNotEmpty) {
      if (!layout.setBoard(_board)) throw StateError('저장소에 집합 보기 «$_board»가 없습니다(내보내기 export/boards.mjs가 실은 변형 kind 3의 열쇠)');
      layout.finishFlow();
      controller.setContentHeight(layout.totalHeight);
    }
    // HANGS=all: 매단 속국 꼬리표를 모든 줄에서 편다(처음에는 접힘 — 플래그 창의 '속국'과 같은 상태 · 리메이크 2부 두 장 ㄴ을 볼 때).
    if (const String.fromEnvironment('HANGS') == 'all') {
      var state = layout.viewState;
      for (int r = 0; r < layout.rowCount; r++) {
        if ((layout.spec(r)?.hang ?? 0) > 0) state = state.withHangsOpen(r, true);
      }
      layout
        ..setViewState(state)
        ..finishFlow();
      controller.setContentHeight(layout.totalHeight);
    }
    if (_spheres.isNotEmpty) {
      final open = _spheres.split(',').toSet();
      layout
        ..setViewState(layout.viewState.copyWith(foldedSpheres: {for (final x in layout.spheres) if (!open.contains(x.id)) x.id}))
        ..finishFlow();
      controller.setContentHeight(layout.totalHeight);
    }
    // GEO=yes: 켠 그릇마다 줄 · 깊이 · 자리, 보이는 줄마다 위 · 줄 몫의 내역(띠 높이 · 글줄 · 막대 자리 · 흰 층 · 예속 · 탭 줄)을 찍는다
    // (리메이크 2부 — 꼬리표가 왜 높은지 · 포개진 그릇이 어디에 앉는지 볼 때).
    if (const String.fromEnvironment('GEO') == 'yes') {
      for (final s in layout.scopesOn) {
        // ignore: avoid_print
        print('그릇 ${s.uid} 트랙 ${s.track} 줄 ${s.rows} 깊이 ${s.depth} 자리 ${layout.scopeSpanOf(s.uid)}');
      }
      for (int r = 0; r < layout.rowCount; r++) {
        if (!layout.isVisible(r)) continue;
        final g = layout.geo(r);
        // ignore: avoid_print
        print('줄 $r 위 ${layout.rowTop(r)} 높이 ${g.height} 띠위 ${g.bandTop} 띠 ${g.bandHeight} 글줄 ${g.textLines} 막대 ${g.railLevels}@${g.railTop} 층 ${g.floorTops}(왕조 ${g.dynastyTop} 시기 ${g.phaseTop} 지위 ${g.rankTop} 집권 ${g.powerTop} 실권 ${g.realTop} 지도자 ${g.leaderTop} 내각 ${g.cabinetTop} 기관 ${g.organTop}) 예속 ${g.depTop}/${g.depHeight} 탭줄 ${g.zoneTop}/${g.zoneLanes} 단 ${g.hemTop} 인물 ${g.figTop}/${g.figLevels}');
      }
    }
    if (_foldTracks.isNotEmpty || _foldPeople.isNotEmpty) {
      var state = layout.viewState;
      if (_foldTracks.isNotEmpty) {
        state = state.copyWith(foldedTracks: _foldTracks == 'all' ? {for (final t in layout.tracks) t.id} : {for (final id in _foldTracks.split(',')) int.parse(id)});
      }
      if (_foldPeople.isNotEmpty) {
        // 열쇠 글을 그대로 받으므로 대범위 가지의 열쇠(`<트랙 id>|__scope:<uid>` — `layout.variantGroupKeyOf`)도 넣을 수 있다.
        // flutter.bat(cmd)은 `|`를 넘기지 못하므로 `~`로 적어도 된다(`1~__scope:<uid>`).
        state = state.copyWith(
          foldedGroups: _foldPeople == 'all'
              ? {for (final t in layout.tracks) for (final g in t.groups) layout.groupKeyOf(t, g)}
              : _foldPeople.replaceAll('~', '|').split(';').toSet(),
        );
      }
      layout
        ..setViewState(state)
        ..finishFlow();
      controller.setContentHeight(layout.totalHeight);
    }
    if (_theme.isNotEmpty) {
      final book = LensBook.read(Map<String, dynamic>.from((await engine.call({'op': 'entity', 'uid': 'themes'}))['data'] as Map));
      final theme = book.byId(_theme);
      expect(theme, isNotNull, reason: '저장소의 주제 사전에 켤 수 있는 주제 $_theme이 없다');
      layout
        ..setThemeLens(theme!.id, slots: book.slot)
        ..finishFlow();
      controller.setContentHeight(layout.totalHeight);
      final ids = <int>{};
      if (theme.events.isNotEmpty) {
        final answer = Map<String, dynamic>.from((await engine.call({'op': 'ids_of', 'uids': theme.events}))['data'] as Map);
        for (final e in (answer['events'] as List? ?? const [])) {
          if (e is Map && e['id'] is num) ids.add((e['id'] as num).toInt());
        }
      }
      final marks = SceneMarks.of(scene)
        ..lensColor = theme.color & 0xffffff
        ..lensEvents = ids;
      marks.version++;
    }
    final cycles = YearCycle.fromMeta(meta);
    final cycle = cycles.isEmpty ? null : cycles.first;
    final cycleMarks = SceneMarks.of(scene)
      ..yearCycle = cycle
      ..showGanji = _cycleOn == 'yes'; // 리메이크 2부: 간지 줄은 처음에 끔(목업 날짜 칸) — CYCLE_ON=yes면 켠 장면
    cycleMarks.version++;
    // 필터 시트의 표시 값(그리기만 바꾸는 것) — 앱 틀의 `_syncMarks`가 하는 일과 같다.
    if (_houses.isNotEmpty || _alt.isNotEmpty || _leaderLabel.isNotEmpty || _leaderOrdinal.isNotEmpty || _lens.isNotEmpty || _axisOff.isNotEmpty) {
      final off = _axisOff.split(',').toSet();
      final marks = SceneMarks.of(scene)
        ..showHouses = _houses == 'yes'
        ..showAlt = _alt != 'no'
        ..leaderLabel = _leaderLabel.isEmpty ? 'auto' : _leaderLabel
        ..leaderOrdinal = _leaderOrdinal == 'yes'
        ..lens = _lens
        ..showGanji = !off.contains('ganji')
        ..showEras = !off.contains('eras')
        ..showCapitals = !off.contains('capitals')
        ..showEpochs = !off.contains('epochs');
      marks.version++;
    }
    // 관점의 이름: 저장소의 `lens_names`를 묻거나(LENS가 있고 LENS_NAMES가 없을 때) 손으로 넣은 것을 쓴다.
    if (_lensNames.isNotEmpty || _lens.isNotEmpty) {
      final events = <int, String>{}, bands = <int, String>{};
      if (_lensNames.isNotEmpty) {
        for (final one in _lensNames.split(';')) {
          final at = one.indexOf(':');
          if (at <= 0) continue;
          final key = one.substring(0, at), name = one.substring(at + 1);
          final band = key.startsWith('b');
          final id = int.tryParse(band ? key.substring(1) : key);
          if (id == null || name.isEmpty) continue;
          (band ? bands : events)[id] = name;
        }
      } else {
        final answer = Map<String, dynamic>.from((await engine.call({'op': 'lens_names', 'lens': _lens}))['data'] as Map);
        for (final (key, into) in [('events', events), ('bands', bands)]) {
          final raw = answer[key];
          if (raw is! Map) continue;
          for (final e in raw.entries) {
            final id = int.tryParse('${e.key}');
            if (id != null) into[id] = '${e.value}';
          }
        }
      }
      LensTitles.of(scene).put(events: events, bands: bands);
    }
    scene.applyLayoutToView();
    controller.resize(width, height - top);
    if (mag != 1) controller.magnifyTo(mag, const ui.Offset(width / 2, (height - top) / 2));
    controller.showRange(minuteOfYear(startYear), minuteOfYear(endYear));
    final rowTop = _scrollRow.isEmpty ? -1.0 : layout.rowTop(int.parse(_scrollRow));
    controller.scrollTo(rowTop >= 0 ? (rowTop - 30 < 0 ? 0.0 : rowTop - 30) : double.parse(_scroll));
    final text = AtlasText()
      ..maxNewPerFrame = 4000
      ..budgetMicros = 2000000;
    final painter = TimelinePainter(scene, text: text)..debug = true;
    if (_epochFold == 'yes') painter.axis.restoreState({'axisOpen': ['epochFold']});
    if (_pickBand.isNotEmpty || _pickEvent.isNotEmpty) {
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(em.Look(band: int.tryParse(_pickBand), event: int.tryParse(_pickEvent), row: int.tryParse(_pickRow)));
    }
    if (_hotBand.isNotEmpty) scene.hover(int.parse(_hotBand));
    if (_hotCoal.isNotEmpty) {
      final marks = SceneMarks.of(scene)..hotCoal = _hotCoal;
      marks.version++;
    }
    addTearDown(text.dispose);

    // 타일 · 이름 자리 · 글자가 모두 준비될 때까지 그려 본다(자료 조회와 이름 계산은 다른 작업자에서 돈다).
    int calm = 0;
    for (int i = 0; i < 400 && calm < 4; i++) {
      final recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), const ui.Size(width, height - top));
      recorder.endRecording().dispose();
      await Future<void>.delayed(const Duration(milliseconds: 25));
      scene.tick(25);
      final s = scene.stats, labels = scene.labelOutput;
      final settled = s.blanks == 0 && s.covers == 0 && !scene.fading && ((labels != null && labels.deferred == 0) || layout.allFolded) && !text.starved && !scene.labelWorker.busy && scene.settled;
      calm = settled ? calm + 1 : 0;
    }
    expect(calm, greaterThanOrEqualTo(4), reason: '장면이 가라앉지 않았습니다(타일 · 이름 자리 · 글자 준비)');

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, width, height), ui.Paint()..color = const ui.Color(0xfff4eee4));
    canvas.drawRect(const ui.Rect.fromLTWH(0, top, width, 1), ui.Paint()..color = const ui.Color(0x1a5a3c14));
    canvas.save();
    canvas.translate(0, top);
    canvas.clipRect(const ui.Rect.fromLTWH(0, 0, width, height - top));
    painter.paint(canvas, const ui.Size(width, height - top));
    canvas.restore();
    // PROBE=x,y(그림의 px — 맨 위 60 포함): 그 자리의 관계선 층 맞히기와 플래그를 찍는다(리메이크 2부 — 실제 앱의 누름을 좁힐 때).
    const probe = String.fromEnvironment('PROBE');
    if (probe.isNotEmpty) {
      final xy = probe.split(',').map(double.parse).toList();
      final h = painter.links.hitLinks(xy[0], xy[1] - top);
      // ignore: avoid_print
      print('탐침 ${xy[0]},${xy[1]} → ${h?.kind} 띠 ${h?.band} · 플래그 ${h == null ? null : painter.links.flagOf(h.band)?.rect}');
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    final name = _name.isNotEmpty ? _name : (_start.isNotEmpty ? '$_start-$_end' : _scene);
    final folder = Directory(_out)..createSync(recursive: true);
    File('${folder.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    if (_dump == 'yes') {
      final sink = painter.debugSink;
      File('${folder.path}/$name.json').writeAsStringSync(
        jsonEncode({
          'scene': {'name': name, 'start': startYear, 'end': endYear, 'left': controller.view.left, 'head': controller.view.head, 'top': top, 'scroll': controller.view.top},
          'bands': [for (final b in sink.bands) {'id': b.id, 'r': [b.rect.left, b.rect.top + top, b.rect.width, b.rect.height]}],
          'labels': [for (final l in sink.labels) {'kind': l.kind, 't': l.text, 'at': [l.at.dx, l.at.dy + top], 'alpha': l.alpha}],
          'dots': [for (final d in sink.dots) {'id': d.eventId, 'at': [d.at.dx, d.at.dy + top], 'extra': d.extra}],
          'bars': [for (final b in sink.bars) {'id': b.eventId, 'r': [b.rect.left, b.rect.top + top, b.rect.width, b.rect.height]}],
          'notes': {for (final e in sink.notes.entries) e.key: [for (final v in e.value) '$v']},
          'stats': {'shapes': scene.stats.shapes, 'labels': scene.stats.labels, 'tiles': scene.stats.tiles},
        }),
      );
    }
    // ignore: avoid_print
    print('저장: ${folder.absolute.path}${Platform.pathSeparator}$name.png (도형 ${scene.stats.shapes} · 글줄 ${scene.stats.labels} · 타일 ${scene.stats.tiles})');
  }, skip: ready ? false : '자료 처리부 DLL 또는 저장소가 없습니다', timeout: const Timeout(Duration(minutes: 3)));
}
