import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show mapEquals, setEquals;
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdfrx/pdfrx.dart';

import 'controller.dart';
import 'shell/phone_scale.dart';
import 'ui/dlc_add.dart';
import 'ui/seed_carry.dart';
import 'engine.dart';
import 'measure/runner.dart';
import 'measure/summary_view.dart';
import 'pack_panel.dart';
import 'scene/fonts.dart';
import 'scene/aux_calendar.dart';
import 'scene/cleartype.dart' show ClearTypeInfo;
import 'scene/cleartype_prefs.dart';
import 'scene/axis_model.dart';
import 'scene/emphasis.dart' as em show Emphasis, Look;
import 'scene/hit_test.dart';
import 'scene/lens_titles.dart';
import 'scene/marks.dart';
import 'scene/paint/axis.dart' show axisCellKey;
import 'scene/paint/gutter.dart';
import 'scene/paint/scopes.dart' show FlagEntry, FlagKind, FlagSpot, ScopeIn, ScopeLayer, ScopePress;
import 'scene/layout.dart';
import 'scene/scene.dart';
import 'scene/view_memory.dart';
import 'scene/viewport.dart' show SceneView;
import 'shell/app_shell.dart';
import 'shell/look.dart';
import 'shell/parts.dart';
import 'shell/sheet_parts.dart' show SheetPaperButton, SheetRun;
import 'timeline_view.dart';
import 'ui/filter_query.dart';
import 'ui/filter_state.dart';
import 'ui/group_tree.dart';
import 'ui/scene_bridge.dart';
import 'ui/app_bus.dart';
import 'ui/app_glue.dart';
import 'ui/app_memory.dart';
import 'ui/board_views.dart';
import 'ui/year_cycle.dart';
import 'ui/cards.dart';
import 'ui/context_menu.dart';
import 'ui/detail_scope.dart' show gatheredScopes, setScopeGathered;
import 'ui/detail_shell.dart';
import 'ui/doc_window.dart';
import 'ui/edge_hint.dart';
import 'ui/export_image.dart';
import 'ui/date_text.dart' show defaultAuxTables;
import 'ui/filter_sheet_body.dart';
import 'ui/legend.dart';
import 'ui/flag_window.dart';
import 'ui/metro_card.dart';
import 'ui/names_display.dart' show applySavedScreenFont, readSavedNamesUi;
import 'ui/motion_meter.dart';
import 'ui/search.dart';
import 'ui/settle_glue.dart';
import 'ui/shell_keys.dart';
import 'ui/theme_lens.dart';
import 'ui/tools_measure.dart';
import 'ui/tools_table.dart';
import 'ui/tools_year.dart';

String dateLabel(num minute) {
  final d = DateTime.fromMillisecondsSinceEpoch((minute * 60000).round(), isUtc: true);
  return '${d.year <= 0 ? '기원전 ${1 - d.year}' : d.year}년 ${d.month}월 ${d.day}일';
}

class ArchiveApp extends StatefulWidget {
  const ArchiveApp({super.key, required this.arguments});
  final List<String> arguments;
  @override
  State<ArchiveApp> createState() => ArchiveAppState();
}

class ArchiveAppState extends State<ArchiveApp> {
  final engine = ArchiveEngine();
  final controller = TimelineController();
  TimelineScene? scene;
  final query = TextEditingController();
  final captureKey = GlobalKey(), timelineKey = GlobalKey();
  final shellKey = GlobalKey<AppShellState>();
  Map<String, dynamic>? meta, source;
  bool ready = false;

  /// 부품들이 주고받는 길 · 장면에 닿는 다리 · 명령 나누기. 저장소를 연 뒤에 선다.
  AppBus? bus;
  SceneBridge? bridge;
  AppGlue? glue;
  SearchController? search;
  ClusterCardController? cards;
  SettleGlue? settle;

  /// 집합 보기(10건 6): 독의 `🗂` 단추 · 그 아래 목록 · 시대 구분 카드가 함께 쓰는 상태(`bus.slot(BoardViews.slotName)`).
  BoardViews? boardViews;
  YearCycleGlue? yearCycle;
  /// 렌즈(주제 보기 — 감독 선택 D5 결정 5 A · 6 B): 독의 `◎ 렌즈` · 차림표 · S · Shift+S · Esc · ⋯ 한 줄이 함께 쓰는 상태.
  ThemeLensGlue? lens;

  String status = '저장소를 준비하고 있습니다';
  String? failure, dbPath, notice;
  int total = 0, unknown = 0;
  final startup = Stopwatch()..start();
  double firstReadyMs = 0;
  double? launchToReadyMs;
  Timer? _blurTimer, _noticeTimer;
  Offset _tapAt = Offset.zero;
  Size _windowSize = Size.zero;

  late final FocusNode searchFocus = FocusNode(
    debugLabel: '검색',
    // ↑ ↓ Enter Esc는 검색 머리가 먼저 받는다(명세 5-2).
    onKeyEvent: (node, event) => search?.handleKey(event) == true ? KeyEventResult.handled : KeyEventResult.ignored,
  );

  String? option(String name) {
    for (final arg in widget.arguments) {
      if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
    }
    return null;
  }

  /// 재는 중인가(측정 스크립트가 켠 것 · 그림만 뜨는 것). **이때는 기억을 읽지도 쓰지도 않는다** — 장면이 달라지면 측정이 무효다.
  bool get measureMode => option('--measure') != null || option('--capture-only') == 'yes';

  /// 기억의 자리(판정 R50): `--memory-dir=<폴더>`면 기억 · 휴대폰 꼴 저장소를 그 폴더에 둔다(운영체제의 앱 자료 폴더를 묻지도 않음 — 앱을 띄우는
  /// 검사가 쓴다) · `--capture-memory`(그림만 뜰 때 — D4 다시 열기 검사)는 재는 동안에도 그 폴더에만 기억한다 · 평소 측정과 미리보기는 기억을 건드리지 않는다.
  late final memoryPlace = MemoryPlace.of(widget.arguments);
  Directory? get _memoryFolder => memoryPlace.folder;
  bool get _rememberView => memoryPlace.remember;

  /// 메이커 미리보기(2026-10-16 — 메이커의 '연표로 ↗'가 띄움): `--preview-dlc=<작업본 .htpack>`이면 서재(저장소 + DLC/ 폴더)를 임시 폴더에 복사해
  /// 열고, 뜬 뒤에 그 사본 위에 작업본을 얹는다(같은 id는 작업본이 이김 — 엔진 `add_pack`의 `prefer_given` · 판정 R39). 서재 · DLC 목록 · 보기 기억은 건드리지 않는다
  /// (기억을 읽지도 쓰지도 않음). `--preview-view=<시작 분>,<끝 분>`은 메이커가 보던 범위 — 그 자리에서 연다.
  String? get previewDlc {
    final v = option('--preview-dlc');
    return v == null || v.isEmpty ? null : v;
  }

  bool get previewMode => previewDlc != null;

  (double, double)? get _previewView {
    final v = (option('--preview-view') ?? '').split(',');
    if (v.length != 2) return null;
    final a = double.tryParse(v[0]), b = double.tryParse(v[1]);
    return a == null || b == null || b <= a ? null : (a, b);
  }

  /// 미리보기 동안 맨 위 줄 아래 알림 칸에 늘 남는 글(다른 알림이 사라지면 이것으로 돌아온다).
  /// 형식 4 작업본에 붙이던 "이 앱 판은 … 아직 그리지 않습니다" 한 줄(리메이크 5단계 과제 10)은 4단계에서 앱이 그 장치를 그리게 되어 걷었다(0.1.0).
  static const _previewNote = '메이커 미리보기 — 서재는 그대로입니다(이 창에서 바꾼 것은 남지 않음)';

  /// 메이커 미리보기의 저장소: 서재(저장소 + 옆의 DLC/ 폴더)를 임시 폴더에 복사한다 — 작업본은 뜬 뒤에 이 사본 위에 얹는다.
  /// 창마다 제 폴더(`ht-preview/<시각>`)를 쓰고, 지난 폴더는 지워 본다(아직 열린 창이 쥔 것은 남는다). 임시 폴더는 `--memory-dir`이면 그 아래(판정 R50).
  Future<String> _previewStore(String library) async {
    final sep = Platform.pathSeparator;
    final root = Directory('${memoryPlace.scratch.path}${sep}ht-preview');
    if (root.existsSync()) {
      for (final old in root.listSync().whereType<Directory>()) {
        try {
          await old.delete(recursive: true);
        } catch (_) {}
      }
    }
    // 저장소 · 일지(-wal · -journal — 판정 R60 M-10) · DLC 폴더를 그 폴더에.
    return copyLibraryForPreview(library, Directory('${root.path}$sep${DateTime.now().millisecondsSinceEpoch}'));
  }

  @override
  void initState() {
    super.initState();
    registerDetailKinds();
    // 검사 손잡이 `--phone=yes`(또는 `=<폭>`): 컴퓨터에서도 휴대폰의 좁힌 왼쪽 칸으로 배치한다(줄여 그리지는 않는다 — `--capture-size=1100x…`로 휴대폰의 배치 창을 뜬다).
    final phone = option('--phone');
    if (phone != null && phone != 'no') {
      SceneView.phone = true;
      SceneView.phoneGutter = double.tryParse(phone) ?? SceneView.phoneGutter;
    }
    searchFocus.addListener(_onSearchFocus);
    _open();
  }

  /// 휴대폰: 설치 파일에 든 저장소(`assets/seed/archive.db`)를 앱 전용 폴더에 놓는다 — 처음 실행이거나 든 저장소가 바뀌었을 때만
  /// (표식은 `seed.json`의 stamp). SQLite는 진짜 파일 경로가 있어야 열 수 있어 묶음 안의 것을 그대로는 못 연다.
  /// 든 저장소가 없는 빌드(Windows · 검사)는 그대로 지나간다 — 저장소가 없으면 뒤의 `engine.start`가 까닭을 말한다.
  /// 새 판이면 사용자가 넣은 DLC를 잇는다(계획 P4 정한 것 #14 · 판정 R34 D — [SeedCarry]): 새 시드를 옆 파일에 써 두고 자료 처리부로 옛 저장소의
  /// 사용자 DLC(꺼 둔 것 포함)를 그 새 시드에 넣은 뒤(`add_pack` `from_store` — 휴대폰 · 컴퓨터 같은 길) 바꿔 놓는다. 넣지 못하면 옛 저장소 그대로 · 알림.
  /// 원본이 저장소에도 DLC 폴더에도 없는 DLC가 있으면 지킨다(판정 R34 A). 휴대폰은 옛 저장소를 못 읽으면 놓되 옛 파일은 옆에 둔다.
  /// 엔진 도구(`도구/`의 archive-tool)가 있는 곳은 바탕이 다른 새 시드일 때 원본을 `DLC/다른-바탕/`에 꺼내 둔다.
  Future<void> _placeSeed(String path) async {
    final Map info;
    try {
      info = jsonDecode(await rootBundle.loadString('assets/seed/seed.json')) as Map;
    } catch (_) {
      return; // 시드가 든 빌드가 아니다(그대로 지나간다)
    }
    final waiting = status;
    try {
      final tool = DlcTools.find()?.archiveTool ?? '';
      final library = engineLibraryPath();
      final carry = tool.isNotEmpty && File(tool).existsSync() ? SeedCarry.withTool(tool, library: library) : SeedCarry.withEngine(library);
      final result = await carry.place(
        path: path,
        stamp: '${info['stamp']}',
        seed: () async {
          final bytes = await rootBundle.load('assets/seed/${info['database']}');
          return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
        },
        // 판 올림 뒤 첫 실행은 넣어 둔 DLC를 옮기느라 오래 걸릴 수 있다 — 첫 화면의 준비 말로 무엇을 하는지 보인다(판정 R60 M-12).
        progress: (line) {
          if (mounted) setState(() => status = line);
        },
      );
      _seedNotice = result.kept ?? result.note;
    } catch (e) {
      // 놓다가 던졌다(디스크 · 권한 …) — 옛 저장소는 그대로 두는 차례라(SeedCarry) 그대로 열고 한 줄 알린다(고침 1회차 Minor).
      _seedNotice = '앱의 새 판 자료를 놓다가 멈췄습니다 — 지금 저장소를 그대로 엽니다(다음에 켤 때 다시 해 봅니다): ${dlcErrorText(e)}';
    } finally {
      if (mounted && status != waiting) setState(() => status = waiting);
    }
  }

  /// 시드를 놓으며 남은 알림(옮긴 DLC · 지킨 까닭 — 앱이 뜨면 한 번 보인다).
  String? _seedNotice;

  /// 시드를 놓으며 남은 알림을 보인다(옮기기는 시드를 놓기 전에 끝났다 — 판정 R34 D).
  void _showSeedNotice() {
    final notice = _seedNotice;
    _seedNotice = null;
    if (notice != null) _showNotice(notice);
  }

  /// 저장소를 열 때 한 번(판정 R32 · R33): DLC 폴더에는 있는데 저장소에도 끈 목록에도 폴더 기억의 묘비에도 없는 사용자 DLC를 고쳐 쓰기로 들인다 —
  /// Windows 설치본 · 포터블은 판을 올리며 `자료/…/archive.db`를 새 판의 것으로 통째로 덮어, 사용자 DLC가 폴더에만 남는다(고쳐 쓰기 길은 저장소가
  /// 하나뿐인 진실이라 스스로는 폴더를 읽지 않는다). 같은 id는 가장 높은 판 · 기본팩은 빼고 · 엔진 `add_pack` 길(원본은 그 폴더 파일) ·
  /// 쓰기 일꾼(화면을 막지 않음). 살피는 동안부터 다른 DLC 일이 끼지 못하게 잡아 두고([DlcJob.hold]), DLC를 **하나씩** 넣어 하나가 실패해도 나머지를
  /// 넣는다. 넣지 못한 파일 · 읽지 못한 파일은 지문으로 기억해(`DLC/sync.json`) 그 파일이 바뀌기 전에는 다시 해 보거나 알리지 않는다. 뺀 DLC의
  /// 남은 파일(지우기 실패)은 여기서 마저 지운다. 끈 목록(`hidden.json`)이나 폴더 기억이 있는데 읽지 못하면 들이지 않고 알린다(꺼 둔 · 뺀 DLC가
  /// 되살아나지 않게). 들일 것이 없으면 아무것도 하지 않는다(두 번째 열기부터).
  /// 엔진 도구(`도구/`의 archive-tool — 폴더 파일 읽기)가 없는 곳 · DLC가 없는 저장소 · 메이커 미리보기 · 재기 · 그림만(저장소를 주었어도 — 저장소 옆
  /// `DLC/`를 쓰지 않는다: [MemoryPlace.leaveDlcFolder] · 판정 R63-4)에서는 하지 않는다.
  /// 그 앞에(도구가 없는 휴대폰도) 낡은 끄기 묘비를 치우고(판정 R63-5) DLC 폴더의 오래된 임시 파일을 지운다(① m-5).
  Future<void> _syncDlcFolder() async {
    final db = dbPath, s = scene;
    if (db == null || s == null || !dlcFolderSyncAllowed(preview: previewMode, leaveStore: memoryPlace.leaveStore, leaveDlcFolder: memoryPlace.leaveDlcFolder)) return;
    final keys = [for (final p in s.layout.packs) p.key];
    dlcOpenTidy(db, stored: keys, hidden: dlcJob.hidden);
    final tool = DlcTools.find()?.archiveTool ?? '';
    if (tool.isEmpty) return;
    if (keys.isEmpty) return;
    final blocked = DlcFolderSync.blocked(db);
    if (blocked != null) {
      _showNotice(blocked);
      return;
    }
    // 이미 다른 DLC 일이 돌면 이번에는 넘긴다(다음 열기에서 다시 살핀다) · 잡기 · 하나씩 넣기 · 실패 기억 · 어느 길로 끝나든 풀기는 [DlcFolderImport](8 검토).
    _dlcNeedsRestart = false;
    final initial = DlcFolderState.read(db) ?? DlcFolderState.empty;
    final versions = {for (final e in dlcJob.packFacts.entries) if (e.value.version.isNotEmpty) e.key: e.value.version};
    final notice = await DlcFolderImport.run(
      job: dlcJob,
      state: initial,
      pending: (state) => DlcFolderSync.withTool(tool, scratch: memoryPlace.scratch)
          .pending(db: db, storeKeys: keys, storeVersions: versions, hidden: dlcJob.hidden, baseKey: dlcBaseKey, state: state),
      // 들이기의 기억은 지금 파일에 합친다(판정 R60 M-7 — 들이는 동안 DLC 일이 적은 묘비를 옛 값으로 덮지 않게).
      keep: (state) {
        try {
          DlcFolderState.update(db, (now) => DlcFolderState.mergeImport(now, initial: initial, imported: state));
        } catch (_) {}
      },
      canPut: (p) => scene?.layout.packs.isNotEmpty ?? false,
      put: (p, i, count) => _runDlcJob(
        files: [p.path],
        label: p.name,
        held: true,
        startNotice: 'DLC 폴더에만 남은 DLC를 저장소에 다시 넣는 중(${i + 1}/$count — «${p.name}»)…',
        doneNotice: 'DLC «${p.name}»을(를) 다시 넣었습니다(${i + 1}/$count).',
      ),
      stopped: () => !mounted || scene == null || _dlcNeedsRestart,
      restarted: () => _dlcNeedsRestart,
    );
    if (mounted && notice != null) _showNotice(notice);
    // 저장소에 든 DLC 가운데 DLC 폴더 사본이 없는 것을 꺼내 채운다(판정 R60 I-2 — 다음 판 올림 뒤 다시 들이기가 믿는 사본 · 잡아 두고: 다른 DLC 일과 겹치지 않게).
    final now = scene;
    if (!mounted || now == null || _dlcNeedsRestart || !dlcJob.hold('DLC 폴더를 맞추는 중…')) return;
    try {
      final packs = [
        for (final p in now.layout.packs)
          if (p.key.isNotEmpty) SeedPack(p.key, dlcJob.packFacts[p.key]?.version ?? '', original: dlcJob.packFacts[p.key]?.original ?? true),
      ];
      await fillDlcFolderCopies(db: db, packs: packs, packOut: (store, id, file) => archiveToolPackOut(tool, store, id, file));
    } finally {
      dlcJob.release();
    }
  }

  /// 저장소의 보관함(꺼 둔 DLC의 원본 — `{"op":"kept_packs"}`)을 읽어 둔다 — 끈 목록에 카드가 없는 꺼 둔 DLC도 DLC 관리 창이 그린다(판정 R60 I-3 덤).
  /// 옛 자료 처리부 · 실패면 비운다. 지운 DLC의 묘비(`DLC/sync.json`의 removed)에 든 id는 카드로 세우지 않는다(예전 판 앱이 꺼 둔 채 지워 보관함에
  /// 원본만 남은 것 — ① m-4).
  Future<void> _loadKept() async {
    final gone = dlcKeptGone(dbPath);
    try {
      dlcJob.keptFrom(await engine.call({'op': 'kept_packs'}), gone: gone);
    } catch (_) {
      dlcJob.keptFrom(null);
    }
  }

  /// 고쳐 쓰기가 저장소를 고쳐 쓴 뒤 다시 열거나 새 뼈대를 읽지 못했다([DlcApplied.restart]) — 이어지는 DLC 일을 멈춘다(앱을 다시 켜야 한다).
  bool _dlcNeedsRestart = false;

  Future<void> _open() async {
    try {
      var path = option('--db');
      if (path == null && Platform.isWindows) {
        final config = File('${File(Platform.resolvedExecutable).parent.path}/prototype.json');
        final data = jsonDecode(await config.readAsString()) as Map;
        path = File('${config.parent.path}/${data['database']}').absolute.path;
      }
      if (path == null) {
        // 휴대폰: 앱 자료 폴더(`archive-prototype-v2/archive.db` — `--memory-dir`면 그 폴더)에 시드를 놓는다.
        path = await memoryPlace.storePath();
        await _placeSeed(path);
      }
      if (previewMode) path = await _previewStore(path);
      dbPath = path;
      // 보던 기간은 **자료보다 먼저** 읽는다(명세 9 ㈐-23) — 첫 화면이 처음부터 그 범위의 줄 높이로 지어지게.
      final savedView = _rememberView ? await AppMemory.readView(folder: _memoryFolder) : null;
      // 끈 ClearType(기억 parts['text'])도 화면이 서기 전에 읽는다 — 기억을 연 뒤(첫 장면 뒤)에 읽으면 그 사이 멈춘 장면 하나가 ClearType일 수 있다.
      if (_rememberView) ClearTypePrefs.loadPart(await AppMemory.readPart('text', folder: _memoryFolder));
      final info = await engine.start(path);
      // Windows의 ClearType 설정(켬 여부 · 칸 차례)을 앱을 켤 때 한 번 읽는다. 옛 자료 처리부는 이 조회에 실패하므로 그때는 꺼짐 — 앱은 회색 그대로다.
      try {
        ClearTypePrefs.system = ClearTypeInfo.read(await engine.call({'op': 'cleartype'}));
      } catch (_) {
        ClearTypePrefs.system = const ClearTypeInfo(false, false);
      }
      // 검증 대본의 `--cleartype=off`는 첫 장면부터 회색이어야 하므로 화면이 서기 전에 적용한다(먼저 읽은 기억보다 뒤에 — 명령줄이 이긴다).
      ClearTypePrefs.applyOption(option('--cleartype'));
      // 문서 그림(형식 3 images — 10건 D3 결정 9 B)의 바이트는 자료 처리부의 `archive_blob`으로 바이트 그대로 받는다
      // (이을 것이 없으면 문서 창이 `{"op":"blob"}`의 base64 답으로 대신한다 — ui/doc_window.dart의 docBlob).
      docBlob = engine.blob;
      meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
      total = int.parse(meta!['count']);
      unknown = int.parse(meta!['unknown']);
      final shape = await engine.call({'op': 'layout'});
      final shapeJson = Map<String, dynamic>.from(shape['data'] as Map);
      // 화면 글꼴(10건 9 — 감독 결정 D2-5 A · 갈래 D2): 필터 '표기'의 [글꼴 ▾]로 고른 글꼴이 있으면 장면을 만들기 전에 실어 맨 앞에 둔다
      // (글 폭 · 그림판을 처음부터 그 글꼴로 — 고르지 않았으면 아무것도 하지 않는다). 측정 모드는 늘 기본 글꼴.
      // 기억은 [memoryPlace]의 폴더에서 읽는다(`--memory-dir`이면 운영체제의 앱 자료 폴더를 읽지 않음 — 판정 R50).
      if (!measureMode) {
        await applySavedScreenFont((q) async => Map<String, dynamic>.from((await engine.call(q))['data'] as Map), saved: await readSavedNamesUi(folder: _memoryFolder));
      }
      final layout = SceneLayout.fromJson(shapeJson);
      // 카드의 판 · 원본(layout 답의 packs[] — 원본 없이 든 DLC의 끄기는 화면에서만 · 그 .htpack을 알아보기 — 고침 1회차 I-1 · 과제 11c).
      dlcJob.factsFrom(shapeJson);
      await _loadKept();
      // 옛 판에서 기본팩을 뺀 기억(baseRemoved)은 그 기본팩이 다시 든 저장소를 처음 열 때 화면에서 끈 목록으로 옮긴다(판정 R60 M-3 — 측정 · 미리보기는 그대로).
      if (!measureMode && !previewMode) {
        try {
          migrateBaseRemoved(path, layout, baseKey: dlcBaseKey);
        } catch (_) {}
      }
      // 끈 DLC(저장소 옆 DLC/hidden.json — 2026-10-16 감독 건의): 보통은 저장소에서 빠져 있고, 다 꺼서 짓지 않았을 때만 남아 있다 — 그것은 끈 채로 연다.
      dlcJob.loadHidden(path);
      final away = dlcOffAtOpen(layout, dlcJob.hidden);
      if (away.isNotEmpty) {
        layout
          ..reduceMotion = true
          ..enable({for (final p in layout.packs) if (!away.contains(p.id)) p.id})
          ..reduceMotion = false;
      }
      controller
        ..setExtent(double.parse(meta!['min']), double.parse(meta!['max']))
        ..setContentHeight(layout.totalHeight);
      scene = TimelineScene(
        controller: controller, layout: layout,
        // 필터의 거르개를 타일 조회에 싣는다(거르개가 바뀌면 배치의 판 번호가 바뀌어 타일을 다시 받는다 — _applyFilter).
        fetchTile: (level, x, chunk, packs) => engine.tile(level, x, chunk, packs, filter: _filter, variants: scene?.layout.variantKeys),
        // 타일 말고 곁들이는 자료(줄 이름 · 빈 줄 접기 · 사람 띠 왕관의 칸 …)를 층과 장면이 받아 오는 길.
        // 배열로 오는 답(cells_of — 왕관 표 sphere_crowns.dart)은 부품의 길(wrapAnswer)처럼 {items: […]}로 감싼다. 객체 답은 예전 그대로.
        ask: (query) async {
          final data = await _call(query);
          return data is List ? <String, dynamic>{'items': data} : Map<String, dynamic>.from(data as Map);
        },
      )..applyLayoutToView();
      scene!.addListener(_onViewState);
      final originalCount = info['data']['originals'];
      if (!mounted) return;
      _buildBus(shapeJson);
      firstReadyMs = startup.elapsedMicroseconds / 1000;
      // 측정 스크립트가 실행 시각(--launched=<epoch ms>)을 넘기면 '실행부터 첫 조작이 가능해질 때까지'를 적는다(다시 열기 합격선 2초).
      final launched = int.tryParse(option('--launched') ?? '');
      if (launched != null) launchToReadyMs = (DateTime.now().millisecondsSinceEpoch - launched).toDouble();
      setState(() {
        ready = true;
        status = '원문 ${formatCount(originalCount)}';
      });
      if (_rememberView) {
        final remembered = await AppMemory.open(folder: _memoryFolder);
        if (!mounted) return;
        // 필터 기억의 그릇 켬이 여기서 보기 상태를 바꿔 장면 듣개(_onViewState — 위에서 먼저 붙음)가 불리지만, 아래 되살리기가 끝나기 전에는
        // 기억의 보기 상태를 덮어쓰지 않는다(결함 ㉡ — [ViewMemory.restored]).
        glue!.attachMemory(remembered);
        // ClearType 설정(parts['text'])을 연 기억으로 한 번 더 맞춘다(위에서 먼저 읽었으니 보통 그대로) · 바뀐 때만 다시 그린다. 명령줄 끄기가 기억보다 이긴다.
        final clearTypeBefore = ClearTypePrefs.on;
        ClearTypePrefs.load(remembered);
        ClearTypePrefs.applyOption(option('--cleartype'));
        if (ClearTypePrefs.on != clearTypeBefore) scene?.requestFrame();
        yearCycle?.attachMemory(remembered);
        _restoreViewState(remembered);
        // 켠 DLC 판을 되살린다(보던 범위 그대로 — 임시 판은 기억하지 않는다).
        boardViews?.restore();
        lens?.attachMemory(remembered);
        _attachDocSide(remembered);
      }
      // 처음 켤 그릇(자료의 default — 리메이크 2부: 내보내기의 기본 배치는 모든 그릇을 풀어 둔다). 기억에 적힌 그릇은 그 값 그대로.
      await _openDefaultScopes();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final previewView = _previewView;
        if (savedView != null) {
          controller.showRange(savedView.start, savedView.end);
        } else if (previewView != null) {
          controller.showRange(previewView.$1, previewView.$2);
        } else {
          controller.showAll();
        }
        // 메이커 미리보기: 서재의 임시 사본 위에 작업본을 얹는다(뒤에서 — 끝나면 그 트랙이 제자리에서 자라남).
        final preview = previewDlc;
        if (preview != null) {
          setState(() => notice = _previewNote);
          unawaited(_runDlcJob(files: [preview], preview: true));
        }
        // 앱의 새 판(시드)을 놓았으면 넣어 두었던 사용자 DLC를 다시 넣고(계획 P4 정한 것 #14), DLC 폴더에만 남은 사용자 DLC를 들인다(판정 R32 —
        // Windows 설치본 · 포터블은 판을 올리며 저장소 파일을 덮는다). 뒤에서 돌고, 아래의 DLC 손잡이는 이것이 끝난 뒤에 건다(일은 한 번에 하나).
        final startup = () async {
          _showSeedNotice();
          await _syncDlcFolder();
        }();
        unawaited(startup);
        final target = option('--measure');
        if (target != null) runMeasure(this, target);
        // 연결 프로그램으로 .htpack을 열었을 때(`--add-dlc=<파일;파일>`): 뜬 뒤에 뒤에서 더한다(4단계 1걸음 · 검증의 손잡이이기도 하다).
        // `--dlc-delay=<ms>`: 검증 대본이 그 전의 장면을 찍을 수 있게 더하기 · 빼기를 그만큼 늦춘다(보통은 0).
        final delay = Duration(milliseconds: int.tryParse(option('--dlc-delay') ?? '') ?? 0);
        Future<void> later(FutureOr<void> Function() act) async {
          await startup;
          await Future<void>.delayed(delay);
          if (mounted) await act();
        }

        // 저장소를 주지 않은 재기 · 그림만은 저장소를 고쳐 쓰는 손잡이를 하지 않는다(판정 R50 넘김 — 검사가 기본 저장소 `prototype.json`에 닿지 않게).
        const storeHandles = ['--add-dlc', '--off-dlc', '--on-dlc', '--remove-dlc'];
        if (memoryPlace.leaveStore) {
          if (storeHandles.any((name) => (option(name) ?? '').isNotEmpty)) _showNotice('검사 실행은 저장소(--db)를 주지 않으면 DLC를 넣거나 빼지 않습니다.');
          return;
        }
        final add = option('--add-dlc');
        if (add != null && add.isNotEmpty) {
          unawaited(later(() => addDlcFiles(add.split(';').map((f) => f.trim()).where((f) => f.isNotEmpty).toList())));
        }
        // 검증의 손잡이: `--off-dlc=<글자 id,…>` · `--on-dlc=<글자 id,…>`면 뜬 뒤에 그 DLC를 끄고 켠다(창의 스위치와 같은 길 — 엔진이 저장소에서 빼고 넣음).
        for (final (name, on) in const [('--off-dlc', false), ('--on-dlc', true)]) {
          final keys = (option(name) ?? '').split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).toSet();
          if (keys.isEmpty) continue;
          unawaited(later(() {
            final cards = DlcCardInfo.of(scene!.layout, facts: dlcJob.packFacts, hidden: dlcJob.hidden, kept: dlcJob.kept).where((c) => keys.contains(c.key)).toList();
            if (cards.isNotEmpty) return toggleDlcs(cards, on);
          }));
        }
        // 검증의 손잡이: `--remove-dlc=<DLC 글자 id>`면 뜬 뒤에 그 DLC를 뺀다(창의 삭제 단추와 같은 길 — 끄는 흐름 → 뒤에서 엔진이 고쳐 씀).
        final drop = option('--remove-dlc');
        if (drop != null && drop.isNotEmpty) {
          unawaited(later(() {
            final card = DlcCardInfo.of(scene!.layout, hidden: dlcJob.hidden, kept: dlcJob.kept).where((c) => c.key == drop).firstOrNull;
            if (card != null) return removeDlc(card);
          }));
        }
      });
    } catch (e) {
      if (mounted) setState(() => failure = e.toString());
    }
  }

  /// 부품이 쓰는 길을 짓고 이어 붙인다.
  void _buildBus(Map<String, dynamic> layoutJson) {
    final made = AppBus(
      // 배열로 오는 답(entities · cells_of)은 부품이 기다리는 `{items: […]}`로 감싼다.
      ask: (query) async => wrapAnswer(await _call(query)),
      controller: controller,
      scene: scene!,
    );
    final made2 = LiveSceneBridge(made)..onSelfScroll = () => cards?.markSelfScroll();
    final made3 = AppGlue(
      bus: made,
      bridge: made2,
      onFilter: () => shellKey.currentState?.toggleFilterSheet(),
      onTable: () => _dialog(showTableDialog),
      onImage: () => _dialog(showExportDialog),
      onPacks: openPacks,
      onSearchFocus: searchFocus.requestFocus,
      onSearchClose: () => search?.clear(),
      onClose: _closeTopMost,
      onNotice: _showNotice,
      onChanged: _redraw,
    )..start();
    made3.fillTrackSlots(layoutJson);
    // 문서 창은 처음에 나란히(연표 옆 칸) — 기억이 있으면 [_attachDocSide]가 그 값으로 바꾼다.
    made.slot(docSideSlot).value = true;
    bus = made;
    bridge = made2;
    glue = made3;
    yearCycle?.dispose();
    yearCycle = YearCycleGlue(made, meta ?? {})..start(ready: !_rememberView);
    // 집합 보기: 판 기록(entity `board:<열쇠>`)은 뒤에서 읽는다 — 다 읽기 전에도 단추 · 목록은 변형의 이름으로 선다.
    final views = BoardViews(bus: made, apply: _applyBoard, memory: () => glue?.memory);
    boardViews?.dispose();
    boardViews = views;
    made.slot(BoardViews.slotName).value = views;
    unawaited(views.load());
    // 정착 때 화면 밖으로 밀려난 것을 가장자리 안내에 싣는다(명세 7-20).
    settle = SettleGlue(bus: made)..start();
    // 렌즈: 주제 사전(항목 기록 themes)을 읽고 slot 'themeLens'를 들어 장면(줄 배치 · 켠 변형 · 사건 옅게)에 잇는다.
    lens?.dispose();
    lens = ThemeLensGlue(bus: made)..start();
    // 보조 달력의 '달의 시작 표'는 앱에 하나 — 날짜 칸과 상세 창의 음력 곁들임이 함께 쓴다(저장소마다 새로).
    // 다섯 달력을 모두 미리 받는다(합쳐 0.47MB) — 음력뿐 아니라 이슬람력 · 페르시아력으로 **적은** 날짜 글도 되짚어 읽는다(11물결 dates ⑶).
    final cals = AuxCalendarStore(made.ask);
    AuxCalendarStore.shared = cals;
    for (final cal in AuxCalendar.list) {
      cals.ensure(cal.id, onReady: (_, _) => scene?.requestFrame());
    }
    // 날짜 글을 읽는 자리(상세 창 · 도구 · 검색)가 저마다 표를 넘기지 않아도 되게 기본 표를 한 자리에서 잇는다(11물결 dates ⑵).
    defaultAuxTables = cals.table;
    search = SearchController(bus: made, text: query)..addListener(_redraw);
    cards = ClusterCardController(bus: made);
    made.selection.addListener(_onPicked);
    made.slot(slotFilters).addListener(_redraw);
    made.slot(slotFilters).addListener(_applyFilter);
    made.slot(slotZen).addListener(_redraw);
    // 단체 계보 창이 열리고 닫히면 확대 단추 · 상세 칸이 창 위로 비키고 돌아온다(shell의 stageBottomInset).
    made.slot(groupTreeSlot).addListener(_redraw);
    // 표시 상태: 기준선 · 기간 재기 · 고른 인물 · 승계선 보기를 장면에 옮긴다.
    for (final name in const ['marker', 'measure', 'measure_on']) {
      made.slot(name).addListener(_syncMarks);
    }
    made.slot(slotFilters).addListener(_syncMarks);
    made.selection.addListener(_syncMarks);
    // 대범위 모아 보기: 시트의 칩(FilterState.scopes) · 상세 창의 스위치와 메뉴(slot 'scopes') · 연표 안 단추가 모두 같은 보기 상태를 켜고 끈다.
    made.slot(slotScopes).addListener(_scopesFromSlot);
    made.slot(slotFilters).addListener(_scopesFromFilters);
    // 이어 붙이기(AppGlue)가 받지 않는 명령 — 대범위 · 승계선 세 값 · 트랙 접기(문서 · 트랙 문서는 문서 창이 스스로 받는다).
    made.slot(slotCommand).addListener(_onCommand);
    _loadShownHistoricity();
  }

  void _syncMarks() {
    final b = bus, s = scene;
    if (b == null || s == null) return;
    final marks = SceneMarks.of(s), span = controller.view.span;
    final marker = b.slot('marker').value;
    marks.marker = marker is num ? marker.toDouble() : null;
    marks.markerText = marks.marker == null ? '' : pointText(marks.marker!, measurePrec(span, span));
    final range = b.slot('measure').value, on = b.slot('measure_on').value == true;
    if (on && range is List && range.length == 2 && range[0] is num && range[1] is num) {
      final lo = (range[0] as num).toDouble(), hi = (range[1] as num).toDouble();
      marks.measure = lo <= hi ? (lo, hi) : (hi, lo);
      marks.measureText = measureLengthText(marks.measure!.$1, marks.measure!.$2, measurePrec(span, (hi - lo).abs()));
    } else {
      marks.measure = null;
      marks.measureText = '';
    }
    final picked = b.selection.value;
    marks.pickedFigure = picked != null && picked.kind == 'figure' ? picked.uid : null;
    // 날짜 칸에서 고른 칸은 그 고르기가 살아 있는 동안만 진하다.
    if (_axisPick != null && (picked == null || picked.uid != _axisPick!.$1 || picked.cell != _axisPick!.$2)) _axisPick = null;
    marks.pickedAxisCell = _axisPick?.$3;
    final filters = b.slot(slotFilters).value;
    if (filters is FilterState) {
      final succession = filters.show['succession'];
      marks.successionMode = succession == false ? 2 : succession == 'direct' ? 1 : 0;
      marks.showPartOf = filters.show['partOf'] != false;
      marks
        ..showAlt = filters.showAlt
        ..showHouses = filters.showing('houses')
        ..leaderLabel = filters.leaderLabel
        ..leaderOrdinal = filters.leaderOrdinal
        ..lens = filters.lens
        // 날짜 칸의 표시 체크 넷 — 끄면 그 줄이 날짜 칸에서 빠지고 높이가 360ms로 줄어든다(그리개가 `axis.setShown`으로 옮긴다).
        ..showGanji = filters.showing('ganji')
        ..showEras = filters.showing('eras')
        ..showCapitals = filters.showing('capitals')
        ..showEpochs = filters.showing('epochs');
      _askLens(s, filters.lens);
    }
    marks.version++;
    s.requestFrame();
  }

  /// 지금 물어 둔 관점(같은 것을 두 번 묻지 않게). 실패하면 되돌려 다음에 다시 묻는다.
  String? _lensAsked;

  /// 관점(lens)이 바뀌면 바꿔 끼울 이름을 다시 묻는다(계약 2-6절의 `lens_names`). 기본('')이면 묻지 않고 자료의 이름으로 되돌린다.
  /// 답은 `LensTitles`에 담기고, 그 판 번호가 장면의 이름 자리 지문에 들어 있어 이름 자리가 다시 돈다.
  void _askLens(TimelineScene s, String? lens) {
    final key = lens == null || lens.isEmpty ? '' : lens;
    if (_lensAsked == key) return;
    _lensAsked = key;
    if (key.isEmpty) {
      LensTitles.of(s).clear();
      s.requestFrame();
      return;
    }
    Map<int, String> pick(Object? v) => v is! Map
        ? const {}
        : {for (final e in v.entries) if (int.tryParse('${e.key}') != null) int.parse('${e.key}'): '${e.value}'};
    unawaited(
      _call({'op': 'lens_names', 'lens': key}).then(
        (r) {
          if (_lensAsked != key) return; // 그 사이에 관점이 바뀌었다
          if (r is! Map) {
            // 답 꼴이 다르면 조용히 비우지 않는다 — 남겨서 '그림만 뜨는 실행'의 시작-장면.json이 잡게 한다.
            if (askFailures.length < 200) askFailures.add('lens_names: 답이 Map이 아님(${r.runtimeType}) ← {"op":"lens_names","lens":"$key"}');
            _lensAsked = null; // 다음에 다시 묻는다
            return;
          }
          LensTitles.of(s).put(events: pick(r['events']), bands: pick(r['bands']));
          s.requestFrame();
        },
        // `_call`은 askFailures에 적고 rethrow 한다 — 받지 않으면 처리되지 않은 비동기 예외가 되고,
        // `_lensAsked`가 그대로라 그 관점의 이름이 영영 빈다(지시서 '어제의 교훈'의 조용히 비는 길).
        onError: (Object _) {
          if (_lensAsked == key) _lensAsked = null;
        },
      ),
    );
  }

  // ---- 필터를 자료에 잇기: 시트의 값 → 거르개(계약 2-2) → 타일과 조회 명령, 끈 트랙은 줄 쌓기에도 ----
  Map<String, dynamic>? _filter;
  Set<String>? _shownHistoricity;

  /// 실패한 조회의 기록. 부품은 조회가 실패하면 그 묶음만 조용히 비우므로(창은 그대로 선다) 눈에 띄지 않는다 —
  /// 여기에 남겨 검증(그림만 뜨는 실행의 시작-장면.json)이 읽는다. 2026-09-22: 분을 소수 꼴로 보내 엔진이 거절하던 것을 이것으로 찾았다.
  final askFailures = <String>[];

  /// [whileWriting]: 저장소를 고쳐 쓰는 동안에도 곧바로 묻는다(뼈대를 바꾸는 쪽 — [_carryOver] · [_reloadStore]만). 그 밖의 조회는 고쳐 쓰는 동안
  /// (쓰기 직전부터 새 뼈대로 바꿀 때까지) 미룬다 — 엔진은 COMMIT 순간만 잠그므로 COMMIT 뒤 새 뼈대를 받기 전의 답은 새 줄 번호라, 줄 번호로 답하는
  /// 조회(사건 목록 · 같은 시기 · 검색 결과의 줄 · 줄 이름 …)가 옛 뼈대에 엉뚱하게 비친다(과제 8 고침 1회차 걱정 2). 미룬 조회는 새 저장소에 묻는다.
  Future<Object?> _call(Map<String, dynamic> query, {bool whileWriting = false}) async {
    final s = scene;
    if (!whileWriting && s != null && s.storeWriting) await s.storeSettled;
    final asked = _filtered(query);
    try {
      return (await engine.call(asked))['data'];
    } catch (e) {
      if (askFailures.length < 200) {
        final text = '${asked['op']}: $e ← ${jsonEncode(asked)}';
        askFailures.add(text.length > 600 ? text.substring(0, 600) : text);
      }
      rethrow;
    }
  }

  /// 거르개를 받는 조회 명령이면 지금의 거르개를 실어 보낸다(부품이 제 것을 실었으면 그대로 둔다).
  /// 저장소의 DLC 가운데 끈 것이 있으면 켠 DLC 목록(`packs`)도 싣는다 — 끈 DLC가 검색 · 같은 해 · 표 …에 나오지 않게([packOps]).
  Map<String, dynamic> _filtered(Map<String, dynamic> query) {
    final f = _filter, op = query['op'], layout = scene?.layout;
    final keys = layout?.variantKeys ?? const <String>[];
    final withFilter = f != null && filteredOps.contains(op) && query['filter'] is! Map;
    final withVariants = keys.isNotEmpty && variantOps.contains(op) && query['variants'] == null;
    final withPacks = layout != null && layout.enabledPacks.length < layout.packs.length && packOps.contains(op) && query['packs'] == null;
    if (!withFilter && !withVariants && !withPacks) return query;
    return {...query, if (withFilter) 'filter': f, if (withVariants) 'variants': keys, if (withPacks) 'packs': layout.enabledPacks};
  }

  /// 실재성 칩 줄에 지금 보이는 것 — 저장된 '끔'은 보이는 것만 센다(명세 06 6-4).
  Future<void> _loadShownHistoricity() async {
    try {
      final answer = (await engine.call({'op': 'legend_kinds'}))['data'];
      final raw = answer is Map ? answer['historicity'] : null;
      _shownHistoricity = {
        if (raw is List)
          for (final h in raw) '${h is Map ? h['id'] : h}',
      };
    } catch (_) {
      _shownHistoricity = null;
    }
    // 검색도 같은 목록으로 제 거르개를 짓는다(실재성 칩을 끈 나라가 검색에서만 계속 나오지 않게).
    bus?.slot('shownHistoricity').value = _shownHistoricity;
    _applyFilter();
  }

  void _applyFilter() {
    final state = bus?.slot(slotFilters).value, s = scene;
    if (state is! FilterState || s == null) return;
    final next = filterQueryOf(state, shownHistoricity: _shownHistoricity);
    final key = next == null ? '' : jsonEncode(next);
    final off = {for (final id in state.tracksOff) if (int.tryParse(id) != null) int.parse(id)};
    final stacked = s.applyViewState(s.layout.viewState.copyWith(offTracks: off));
    if (!s.layout.setFilterKey(key) && !stacked) return;
    _filter = next;
    // 관점의 이름도 거르개를 타는 조회다(`filteredOps`) — 거르개가 바뀌면 다시 묻는다.
    final lens = _lensAsked;
    if (lens != null && lens.isNotEmpty) {
      _lensAsked = null;
      _askLens(s, lens);
    }
    // 거른 뒤의 빈 줄을 다시 묻고, 새 판의 타일을 받게 한 장면을 청한다.
    s.folder.forget();
    controller.setContentHeight(s.layout.totalHeight);
    s.requestFrame();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  /// 표 · 이미지의 대화 상자(자리는 앱이 잡는다).
  void _dialog(Future<void> Function(BuildContext context, AppBus bus) open) {
    final context = navigatorKey.currentContext, b = bus;
    if (context == null || !context.mounted || b == null) return;
    unawaited(open(context, b));
  }

  void _closeTopMost() {
    if (shellKey.currentState?.closeTopMost() ?? false) return;
    bus?.clearSelection();
  }

  void _showNotice(String text) {
    _noticeTimer?.cancel();
    setState(() => notice = text);
    _noticeTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => notice = previewMode ? _previewNote : null); // 미리보기 동안은 그 표시로 돌아옴
    });
  }

  /// 검색 칸이 초점을 잃으면 150ms 뒤에 목록을 접는다(명세 5-2).
  void _onSearchFocus() {
    _blurTimer?.cancel();
    if (searchFocus.hasFocus) return;
    _blurTimer = Timer(const Duration(milliseconds: 150), () {
      search?.close();
      _redraw();
    });
  }

  // ---- 원문(PDF · 삽화 · 본문) ----

  /// 고른 것이 연표의 사건이면 그 원문을 받아 둔다 — 상세 창 맨 아래의 `원문` 단추가 이것을 쓴다.
  Future<void> _onPicked() async {
    final picked = bus?.selection.value;
    unawaited(_loadDocKeys(picked?.uid));
    final id = picked?.eventId;
    if (id == null) {
      if (source != null && mounted) setState(() => source = null);
      return;
    }
    try {
      final event = await engine.call({'op': 'event', 'id': id});
      final sourceId = (event['data'] as Map)['source'];
      if (sourceId == null) {
        if (mounted) setState(() => source = null);
        return;
      }
      final answer = await engine.call({'op': 'source', 'id': sourceId});
      if (mounted && bus?.selection.value?.eventId == id) setState(() => source = Map<String, dynamic>.from(answer['data']));
    } catch (_) {
      if (mounted) setState(() => source = null);
    }
  }

  /// 칸 목록의 📄 단추가 보일지 가리는 표(slot 'docKeys') — 고른 항목의 기록에 내보내기가 얹어 둔 x_cellDocs.
  Future<void> _loadDocKeys(String? uid) async {
    final b = bus;
    if (b == null) return;
    if (uid == null || uid.isEmpty) {
      b.slot('docKeys').value = null;
      return;
    }
    try {
      final record = await b.ask({'op': 'entity', 'uid': uid});
      if (b.selection.value?.uid != uid) return;
      // 항목 기록의 json은 글로 온다.
      final raw = record['json'];
      final json = raw is String ? jsonDecode(raw) : raw;
      final keys = json is Map ? json['x_cellDocs'] : null;
      b.slot('docKeys').value = keys;
    } catch (_) {
      b.slot('docKeys').value = null;
    }
  }

  /// 상세 창 맨 아래 줄: 원문 단추(없으면 그 칸이 없다).
  Widget? sourceFoot() {
    final files = source?['files'];
    if (files is! List || files.isEmpty) return null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${source!['title']}', style: const TextStyle(fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w600, color: Ui.text2)),
        ),
        for (final raw in files)
          ShellButton(
            onPressed: () => openFile(Map<String, dynamic>.from(raw as Map)),
            child: Text(
              raw['kind'] == 'pdf'
                  ? 'PDF 원문'
                  : raw['kind'] == 'image'
                  ? '삽화 열기'
                  : '본문 열기',
            ),
          ),
      ],
    );
  }

  Future<void> openFile(Map<String, dynamic> file) async {
    if (!mounted) return;
    await showDialog<void>(
      context: captureKey.currentContext!,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 1380,
          height: 900,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(child: Text(source?['title'] ?? '원문', style: const TextStyle(fontFamily: Ui.title, fontFamilyFallback: Ui.titleFallback, fontSize: 18, fontWeight: FontWeight.w700))),
                    IconButton(tooltip: '닫기', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Expanded(
                child: file['kind'] == 'pdf'
                    ? PdfViewer.file(file['path'], params: const PdfViewerParams(maxImageBytesCachedOnMemory: 32 * 1024 * 1024))
                    : file['kind'] == 'image'
                    ? InteractiveViewer(minScale: .5, maxScale: 6, child: Center(child: Image.file(File(file['path']), cacheWidth: 1600)))
                    : FutureBuilder<String>(
                        future: File(file['path']).readAsString(),
                        builder: (context, snapshot) => SingleChildScrollView(
                          padding: const EdgeInsets.all(28),
                          child: SelectableText(snapshot.data ?? '본문을 읽고 있습니다', style: const TextStyle(fontSize: 19, height: 1.8)),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> screenshot(String path) async {
    await WidgetsBinding.instance.endOfFrame;
    // 오른쪽 클릭 메뉴 · 대화 상자처럼 길잡이 위에 따로 서는 것은 `captureKey`의 경계 밖이라 경계만 찍으면 그림에 없다
    // (2026-09-22의 점검에서 메뉴가 안 찍힘) — 그런 것이 떠 있을 때만 창 전체(뿌리 층)를 찍는다. 그 밖에는 늘 경계를 찍는다:
    // `--capture-size`의 그림은 창의 크기와 무관하게 정확히 그 크기여야 1배 나란히 비교가 성립한다(뿌리 층은 창의 크기다).
    // 떠 있는 창(세계표 — OverlayPortal로 길잡이의 층에 선다)도 경계 밖이다.
    final b = bus;
    final floating = (navigatorKey.currentState?.canPop() ?? false) || (b != null && DetailHost.windowOpen(b));
    final image = (floating ? await _rootImage() : null) ?? await (captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  }

  /// 뿌리 층의 그림(논리 크기 · 1배). 뿌리 층은 기기 배율만큼 키운 변환 층이라 실제 픽셀로 자르고 배율의 역수로 줄인다.
  Future<ui.Image?> _rootImage() async {
    try {
      final view = RendererBinding.instance.renderViews.first;
      final ratio = view.flutterView.devicePixelRatio;
      // ignore: invalid_use_of_protected_member
      final layer = view.layer;
      if (layer is! OffsetLayer) return null;
      return await layer.toImage(Offset.zero & (view.size * ratio), pixelRatio: 1 / ratio);
    } catch (_) {
      return null;
    }
  }

  // ---- 메뉴 ----

  /// 독의 `⋯`: 명세 8-2의 줄 + 맨 위 안내 두 줄 + 맨 아래 `측정`. `자료집`은 메뉴의 `🧩 자료집 관리`가 맡는다(`Cmd.dlc`).
  Future<void> openDockMenu(BuildContext buttonContext) {
    final b = bus, g = glue;
    if (b == null || g == null) return Future<void>.value();
    return showShellMenu(
      buttonContext,
      bus: b,
      flags: _menuFlags(),
      head: [
        MenuRow.note('사건 ${formatCount(total)} · 날짜 미정 ${formatCount(unknown)}'),
        MenuRow.note(status),
        const MenuRow.sep(),
      ],
      tail: [
        const MenuRow.sep(),
        MenuRow('측정', onSelected: ready && !measuring ? quickMeasure : null),
      ],
    );
  }

  /// DLC 관리 창(`ui/dlc_manager.dart`). 켜고 끄기는 자유다 — 다 끄면 연표 자리에 안내가 선다(`dlcTimelineEmpty`).
  /// 배포 폴더의 도구(`도구/`)가 있으면 `📂 파일에서 더하기…`와 카드의 `DLC 삭제`도 선다(`ui/dlc_add.dart` — 앱이 켜진 채로 뒤에서 다시 짓고 바꿔 넣는다 · 4단계 1걸음).
  Future<void> openPacks() async {
    final host = navigatorKey.currentContext;
    if (host == null || !host.mounted || scene == null) return;
    final tools = measureMode ? null : DlcTools.find();
    await showDlcManager(
      host, scene!,
      onChanged: (_) {
        setState(() {});
        // 화면에서만 켜고 끈 것(바탕 · 원본 없이 든 DLC — 판정 R43 · 고침 1회차)은 끈 목록에 기억해 다음 실행에도 끈 채로 연다(휴대폰 · 컴퓨터 —
        // 8 검토 2회차 Minor 1). 측정 · 검사(도구 없음)는 적지 않는다.
        final db = dbPath, s = scene;
        if (tools != null && db != null && s != null) {
          try {
            // 엔진이 켜고 끄거나 빼는 중인 DLC(화면에서 먼저 접힘)는 그 일이 끝나며 적는다 — 여기서 화면에서만 끈 것으로 적지 않는다(② Minor 3).
            rememberScreenOff(db, s.layout, cards: _screenOffCards(s.layout), busy: {...dlcJob.toggling.keys, if (dlcJob.removingKey.isNotEmpty) dlcJob.removingKey});
            dlcJob.loadHidden(db);
          } catch (e) {
            dlcJob.notice('끈 DLC를 기억하지 못했습니다 — 앱을 다시 켜면 다시 켜집니다(${dlcErrorText(e)}).');
          }
        }
      },
      job: dlcJob,
      // 휴대폰은 시스템 고르기 창(MainActivity.kt — 과제 10a) — 고르고 앱 안으로 옮기는 동안 일을 잡아 두고(두 번째 고르기가 앞 결과를 지우지 않게),
      // 창을 못 열거나 거른 파일이 있으면 그 까닭을 창의 위 칸에.
      onAddFiles: tools == null ? null : () => pickAndAddDlc(addDlcFiles, job: dlcJob),
      // 지우기 · 끄기 · 켜기는 휴대폰도 엔진 하나로(계획 P4 과제 10b) — 창이 카드마다 길을 가른다(dlcCardRoute).
      onRemove: tools == null ? null : removeDlc,
      onToggle: tools == null ? null : toggleDlcs,
    );
  }

  // ---- DLC 더하기 · 빼기 · 끄기 · 켜기(4단계 1걸음 — `docs/설계-아카이브-4단계-1걸음-DLC-앱-안에서.md` · 계획 한 벌 P4 과제 8 · 10b — 계약 2-7 · 2-7-1):
  //      엔진의 쓰기 일꾼이 제자리에서 고쳐 쓰고(`add_pack` · `remove_pack` — 배치도 엔진이 · 휴대폰과 컴퓨터가 같다 · 닫았다 열지 않음 · 그동안에도
  //      연표가 끌림) → 뼈대를 다시 읽어 줄이 흐른다(`first_pos`부터만 타일을 버림). 엔진이 빼지 못하는 바탕 · 원본 없이 든 DLC의 끄기는 화면에서만
  //      (판정 R43). 예전 Node 다시 짓기 길과 .htlayout 받기는 걷었다(계획 P4 과제 11c) ----
  final dlcJob = DlcJob();

  /// DLC 파일(.htpack)들을 더한다(같은 id면 판이 높은 것으로 바뀐다). 끝나면 새 DLC는 켜진 채 그 트랙이 제자리에서 0에서 자라난다.
  Future<void> addDlcFiles(List<String> files) => _runDlcJob(files: files);

  /// DLC 하나를 뺀다 — 먼저 끄는 흐름으로 접히고(360ms), 그 뒤에 뒤에서 저장소를 고쳐 쓴다(그때는 이미 빠진 뒤라 화면이 움직이지 않는다).
  /// 실패하면 화면을 되돌린다(저장소 그대로).
  Future<void> removeDlc(DlcCardInfo card) async {
    final s = scene;
    if (s == null) return;
    if (card.key.isEmpty) {
      _showNotice('이 DLC는 아주 예전 판의 저장소에 든 것이라 앱에서 뺄 수 없습니다 — 끄면 화면에서 가려집니다.');
      return;
    }
    final before = s.layout.enabledPacks.toSet();
    if (card.stored && s.layout.isPackEnabled(card.id)) {
      s.setPacks({...s.layout.enabledPacks}..remove(card.id));
      setState(() {});
    }
    final ok = await _runDlcJob(removeKey: card.key, label: card.name);
    if (!ok && mounted && scene == s && !setEquals(s.layout.enabledPacks.toSet(), before)) s.setPacks(before);
  }

  /// DLC를 켜고 끈다(2026-10-16 감독 건의 "숨기면 연표 자체에서 등장하지 않게"): 끈 DLC를 **저장소에서 뺀다** — 화면에서만 가리면 날짜 칸의 시대 · 검색 ·
  /// 필터 · 판 …에 남았다. 끌 때는 먼저 화면에서 접히고(끄는 흐름) 엔진이 그 DLC를 빼고(`remove_pack delete:false` — 원본은 저장소의 보관함 · 파일은 DLC
  /// 폴더에도 남는다), 켤 때는 보관함(없으면 DLC 폴더의 파일)에서 다시 넣은 저장소에서 그 트랙이 0에서 자라난다(계획 P4 과제 10b — 휴대폰도).
  /// 엔진이 빼지 못하는 바탕(저장소의 첫 DLC)과 원본 없이 든 DLC의 끄기는 화면에서만 켜고 끈다(끈 목록에 기억 — 판정 R43: 도구가 있어도 다시 짓지
  /// 않는다 · 고침 1회차 I-1). 실패하면 저장소에서 빼던 몫의 화면만 되돌린다 — 그사이 뼈대를 다시 읽었으면(앞의 걸음은 고쳐 썼다) 옛 번호를 씌우지 않는다.
  Future<void> toggleDlcs(List<DlcCardInfo> cards, bool on) async {
    final s = scene;
    if (s == null) return;
    if (dlcJob.running) {
      _showNotice('DLC 작업이 아직 도는 중입니다 — 끝난 뒤에 다시 해 주세요.');
      return;
    }
    DlcRoute route(DlcCardInfo c) => dlcCardRoute(c, s.layout, hidden: dlcJob.hidden, on: on);
    final stores = [for (final c in cards) if (route(c) == DlcRoute.engine) c];
    final keys = [for (final c in stores) c.key];
    Set<int> turned(Set<int> from, Set<int> ids) => on ? {...from, ...ids} : from.difference(ids);
    // 화면에서만 켜고 끄는 것(바탕 · 원본 없이 든 DLC의 끄기) 먼저 — 끈 목록에 기억해 다음 실행에도 끈 채로 연다(10a와 같은 길). 저장소에서 빼는 것은 그 뒤.
    final screenCards = [for (final c in cards) if (c.stored && route(c) == DlcRoute.screen) c];
    final screen = {for (final c in screenCards) c.id};
    final db = dbPath;
    if (screen.isNotEmpty) {
      s.setPacks(turned(s.layout.enabledPacks.toSet(), screen));
      if (db != null && !measureMode) {
        try {
          rememberScreenOff(db, s.layout, cards: _screenOffCards(s.layout), busy: {for (final c in stores) c.key});
          dlcJob.loadHidden(db);
        } catch (e) {
          // 깨진 끈 목록은 덮지 않는다(판정 R60 I-3) — 그 까닭을 알린다(화면에서만 끈 것은 다음 실행에 다시 켜진다).
          _showNotice('끈 DLC를 기억하지 못했습니다 — 앱을 다시 켜면 다시 켜집니다(${dlcErrorText(e)}).');
        }
      }
      // 원본 없이 든 DLC를 끈 까닭 — 어느 DLC인지 함께(바탕이면 바탕의 사정이 먼저라 알리지 않는다 — 10b 고침 재검토 · ② Minor 7).
      final why = [for (final c in screenCards) dlcScreenNote(c, s.layout, hidden: dlcJob.hidden, on: on)].where((w) => w != dlcScreenOnlyNote).toSet();
      if (why.isNotEmpty) _showNotice(why.join(' '));
    }
    final before = s.layout.enabledPacks.toSet();
    final reloads = _reloads;
    s.setPacks(turned(before, {for (final c in stores) if (c.stored) c.id}));
    setState(() {});
    if (keys.isEmpty) return;
    final ok = await _runDlcJob(offKeys: on ? const [] : keys, onKeys: on ? keys : const [], label: stores.map((c) => c.name).join(' · '), turnOn: on);
    // 모두 끄기가 도중에 멈추면 앞의 걸음은 저장소를 고쳐 써 뼈대를 다시 읽었다 — 그때는 옛 뼈대의 자료집 번호를 새 뼈대에 씌우지 않는다(고침 1회차 Minor ·
    // 아직 저장소에 남은 DLC는 다시 읽을 때 켰다 — dlcTurnOnAfterReload).
    if (mounted && scene == s && dlcToggleShouldRestore(ok: ok, reloaded: _reloads != reloads)) s.setPacks(before);
  }

  /// 화면에서만 끌 때 끈 목록에 함께 적을 카드(저장소에 든 DLC마다 — 판정 R60 M-6: 판 올림으로 저장소에서 빠져도 창에 남게).
  Map<String, Map<String, dynamic>> _screenOffCards(SceneLayout layout) => {
    for (final c in DlcCardInfo.of(layout, facts: dlcJob.packFacts)) if (c.stored && c.key.isNotEmpty) c.key: c.hiddenCard,
  };

  /// 뼈대를 다시 읽은 수([_reloadStore]) — 실패한 일이 화면을 되돌릴 때 그사이 뼈대가 바뀌었는지 본다.
  int _reloads = 0;

  /// [preview]: 메이커 미리보기의 작업본 얹기 — 같은 id는 작업본이 이기고(`--prefer-given`) 알림 글이 미리보기의 말.
  /// [offKeys] · [onKeys]: 끄고 켤 DLC([toggleDlcs] — [turnOn]이면 켜는 쪽). 참이면 해냈다.
  /// [startNotice] · [doneNotice]: 고쳐 쓰기 길의 시작 · 성공 알림을 바꿔 적는다(DLC 폴더에서 다시 들이기 — [_syncDlcFolder]).
  /// [held]: 부른 쪽이 [DlcJob.hold]로 잡아 둔 일을 이어서 한다(도는 중이어도 거절하지 않음 · 일찍 끝나면 잡음을 푼다).
  Future<bool> _runDlcJob({
    List<String> files = const [],
    String? removeKey,
    String label = '',
    bool preview = false,
    List<String> offKeys = const [],
    List<String> onKeys = const [],
    bool turnOn = false,
    String? startNotice,
    String? doneNotice,
    bool held = false,
  }) async {
    final db = dbPath, s = scene;
    if (db == null || s == null) {
      if (held) dlcJob.release();
      return false;
    }
    if (dlcJob.running && !held) {
      _showNotice('DLC 작업이 아직 도는 중입니다 — 끝난 뒤에 다시 해 주세요.');
      return false;
    }
    // 길(계획 P4 과제 10b · 11c — [dlcRoute]): 엔진 하나(휴대폰 · 컴퓨터 · 메이커 미리보기 — 판정 R39) · 화면에서만 · 할 수 없음 — 엔진에 가지 않는 것은
    // 길을 고르기 전에 거절한다(저장소 · 화면 그대로 · 화면에서만 켜고 끄는 것은 [toggleDlcs] · DLC 관리 창이 먼저 가른다).
    final route = dlcRoute(packKeys: [for (final p in s.layout.packs) p.key], hidden: dlcJob.hidden, baseKey: dlcBaseKey,
        removeKey: removeKey, offKeys: offKeys, onKeys: onKeys, preview: preview);
    if (route != DlcRoute.engine) {
      final cannot = dlcRouteRefusal(removeKey: removeKey);
      if (held) dlcJob.release();
      dlcJob.refuse(cannot);
      _showNotice(cannot);
      return false;
    }
    final known = {for (final p in s.layout.packs) _packKey(p)};
    _dlcClock = Stopwatch()..start();
    _dlcFlowMs = _dlcEngineMs = null;
    _dlcFirstPos = null;
    final ok = await _applyDlcJob(
      db: db, files: files, removeKey: removeKey, label: label, offKeys: offKeys, onKeys: onKeys, turnOn: turnOn, known: known,
      startNotice: startNotice, doneNotice: doneNotice, preview: preview,
    );
    _writeDlcTiming('apply', ok);
    return ok;
  }

  /// 고쳐 쓰기 길(계획 P4 과제 8 · 10b · 계약 2-7-1 — 바꿔 넣기 · 다시 열기 없음): 엔진의 쓰기 일꾼에 맡기는 동안([DlcJob.apply]) 연표는 옛 저장소로
  /// 그대로 끌리고, 끝나면 뼈대를 다시 읽어 엔진의 `first_pos`부터만 타일을 버린다([DlcApplyFlow] · [_reloadStore]). 실패하면 저장소 · 화면 그대로.
  Future<bool> _applyDlcJob({
    required String db,
    required List<String> files,
    String? removeKey,
    required String label,
    required List<String> offKeys,
    required List<String> onKeys,
    required bool turnOn,
    required Set<String> known,
    String? startNotice,
    String? doneNotice,
    bool preview = false,
  }) async {
    final s = scene!;
    final toggle = offKeys.isNotEmpty || onKeys.isNotEmpty;
    _showNotice(startNotice ?? (preview ? '메이커 미리보기 — 작업본을 얹는 중(서재는 그대로)…' : toggle
        ? 'DLC «$label»을(를) ${turnOn ? '켜는' : '끄는'} 중 — 저장소를 고쳐 씁니다…'
        : removeKey != null ? 'DLC «$label»을(를) 빼는 중…' : 'DLC를 더하는 중 — 뒤에서 저장소를 고쳐 씁니다(그동안에도 연표를 볼 수 있습니다).'));
    _DlcCarry? carry;
    final flow = DlcApplyFlow(
      job: dlcJob,
      scene: s,
      engineCall: engine.call,
      engineApply: _writeStore,
      // 옮겨 적을 것(옛 띠 번호 → uid · 옛 번호 → 이름 · 열쇠)은 엔진이 쓰기 **전에** 옛 저장소에서 셈한다(고침 2회차 Minor 2 — COMMIT 뒤 새 저장소에
      // 옛 띠 번호를 물으면 엔진이 번호를 다시 쓸 때 다른 띠를 가리킨다).
      beforeWrite: () async => carry = await _carryOver(),
      reload: (keepBefore) async {
        // 켤 DLC: 켜기 부탁 + 더하기로 끈 목록에서 뺀 DLC(덧붙임 N2: 끈 채 더해도 화면에서 켜진 채로) + 끄기 부탁 가운데 아직 저장소에 남은 것(모두 끄기가
        // 도중에 멈춤 — 끈 목록에 없어 다음 실행에 켜지므로 화면도 켠다 · 11c 검토).
        await _reloadStore(carry ?? await _carryOver(), turnOn: dlcTurnOnAfterReload(onKeys: onKeys, offKeys: offKeys, turnedOn: dlcJob.turnedOn), keepBefore: keepBefore);
      },
    );
    // 지금 저장소에 든 DLC(빼기 · 끄기 · 켜기가 엔진에 갈 것인지) · 끄는 DLC의 카드(끈 목록에 적어 저장소에서 빠진 뒤에도 창이 그린다).
    final stored = {for (final p in s.layout.packs) if (p.key.isNotEmpty) p.key};
    final offCards = {
      for (final c in DlcCardInfo.of(s.layout, facts: dlcJob.packFacts, hidden: dlcJob.hidden))
        if (c.stored && offKeys.contains(c.key)) c.key: c.hiddenCard,
    };
    // 메이커 미리보기(판정 R39): 서재의 임시 사본(`_previewStore`) 위에 작업본을 `prefer_given`으로 — 같은 id면 판과 상관없이 작업본이 이긴다.
    final done = await flow.run(db: db, files: files, removeKey: removeKey, offKeys: offKeys, onKeys: onKeys, stored: stored, offCards: offCards, preferGiven: preview);
    _dlcEngineMs = (done.data['ms'] as num?)?.toDouble();
    _dlcFirstPos = done.firstPos;
    if (!mounted) return false;
    dlcJob.loadHidden(db);
    if (done.restart) {
      _dlcNeedsRestart = true;
      _showNotice('저장소는 고쳐 썼지만 다시 열거나 새로 읽지 못했습니다 — 앱을 다시 켜 주세요.');
      return false;
    }
    if (!done.ok) {
      // 원본 없는 DLC의 .htpack을 DLC 폴더에 두고 끝났으면 그 알림만('더하기에 실패했습니다 — …두었습니다'는 모순처럼 읽힌다 — 11c 검토).
      _showNotice(dlcJob.stashedNote ??
          (preview
              ? '메이커 미리보기 — 작업본을 얹지 못했습니다: ${dlcJob.lastLine}'
              : 'DLC ${toggle ? (turnOn ? '켜기' : '끄기') : removeKey != null ? '빼기' : '더하기'}에 실패했습니다 — ${dlcJob.lastLine}'));
      return false;
    }
    final added = [for (final p in scene!.layout.packs) if (!known.contains(_packKey(p))) p.name];
    if (preview) {
      _showNotice('메이커 미리보기 — 작업본을 얹었습니다${added.isEmpty ? '' : '(«${added.join(' · ')}»)'}.');
      dlcJob.reset();
      return true;
    }
    _showNotice(doneNotice ?? (toggle
        ? 'DLC «$label»을(를) ${turnOn ? '켰' : '껐'}습니다.'
        : removeKey != null
        ? 'DLC «$label»을(를) 뺐습니다.'
        : (added.isEmpty ? 'DLC를 고쳐 썼습니다(새 DLC 없음 — 같은 id면 판만 바뀝니다).' : 'DLC «${added.join(' · ')}»을(를) 더했습니다.')));
    _forgetStoredDlc(db);
    dlcJob.reset();
    return true;
  }

  /// 저장소에 켜진 채 든 DLC(사용자가 다시 넣음 · 켬)는 폴더 기억의 묘비에서 뺀다(판정 R33 — 다음 판 올림 뒤에는 다시 들이게).
  void _forgetStoredDlc(String db) {
    final s = scene;
    if (s == null) return;
    DlcFolderState.forgetStored(db, [for (final p in s.layout.packs) if (p.key.isNotEmpty && !dlcJob.hidden.off.contains(p.key)) p.key]);
  }

  /// 엔진의 쓰기 일꾼에 맡긴다(`add_pack` · `remove_pack` — 계약 2-7-1 · [ArchiveEngine.write]: 따로 된 isolate가 같은 자료 처리부를 열어 부르므로
  /// 타일 · 조회 일꾼의 줄을 막지 않는다). 답은 `archive_call`의 겉 그대로(`ok` · `data` · `error` · `code` · `committed`).
  Future<Map<String, dynamic>> _writeStore(Map<String, dynamic> request) => engine.write(request);

  /// 검증의 손잡이(`--dlc-timing=<파일>`): DLC 일 하나마다 고른 뒤 흐름이 시작될 때까지(뼈대를 바꾼 때)의 시간 · 길 · 엔진 시간을 JSON 한 줄씩 덧붙인다.
  Stopwatch? _dlcClock;
  double? _dlcFlowMs, _dlcEngineMs;
  int? _dlcFirstPos;

  void _writeDlcTiming(String route, bool ok) {
    final path = option('--dlc-timing');
    final clock = _dlcClock;
    if (path == null || path.isEmpty || clock == null) return;
    try {
      File(path).writeAsStringSync(
        '${jsonEncode({'route': route, 'ok': ok, 'flow_ms': _dlcFlowMs, 'total_ms': clock.elapsedMicroseconds / 1000, 'engine_ms': _dlcEngineMs, 'first_pos': _dlcFirstPos})}\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  /// DLC를 알아보는 열쇠 — 글자 id, 없으면(옛 저장소) 이름.
  static String _packKey(PackInfo p) => p.key.isNotEmpty ? p.key : '#${p.name}';

  /// 저장소가 바뀌기 **전에**(옛 저장소 · 옛 뼈대) 옛 번호를 이름 · 열쇠로 적어 둔다(새 번호는 다시 읽은 뒤 이름으로 찾는다). 펼친 상국의 띠 번호는
  /// 엔진에 물어 uid로 바꾸므로 반드시 옛 저장소에 묻는다 — [DlcApplyFlow.beforeWrite](엔진이 쓰기 직전).
  /// COMMIT 뒤의 새 저장소에 옛 띠 번호를 물으면, 엔진이 띠 번호를 다시 매길 때 다른 띠를 가리킬 수 있다(번호를 그대로 쓴다는 약속은 없다).
  Future<_DlcCarry> _carryOver() async {
    final s = scene!, b = bus!;
    final l = s.layout;
    final packKey = {for (final p in l.packs) p.id: _packKey(p)};
    final trackKey = {for (int i = 0; i < l.tracks.length; i++) l.tracks[i].id: l.trackIdentity(i)};
    final view = l.viewState;
    // 펼친 상국은 띠 번호라 이름(uid)으로 적어 둔다.
    final hosts = <String>[], groupHosts = <String>[];
    for (final (ids, out) in [(view.expandedHosts, hosts), (view.expandedGroups, groupHosts)]) {
      for (final id in ids) {
        try {
          final a = await _call({'op': 'uid_of', 'kind': 'band', 'id': id}, whileWriting: true);
          if (a is Map && a['uid'] is String) out.add(a['uid'] as String);
        } catch (_) {}
      }
    }
    // 접은 민족 묶음의 열쇠는 (트랙 번호 · 첫 줄 · 깊이 · 종류)라 번호에 매여 있다 — (트랙 열쇠 · 이름 · 깊이 · 종류)로 적는다.
    final groups = <String>{};
    for (int i = 0; i < l.tracks.length; i++) {
      final t = l.tracks[i];
      for (final g in t.groups) {
        if (view.isGroupFolded(l.groupKeyOf(t, g))) groups.add('${l.trackIdentity(i)}|${g.name}:${g.depth}:${g.kind}');
      }
    }
    final filters = b.slot(slotFilters).value;
    return _DlcCarry(
      known: packKey.values.toSet(),
      wasOn: {for (final id in l.enabledPacks) packKey[id]!},
      foldedTracks: {for (final id in view.foldedTracks) if (trackKey[id] != null) trackKey[id]!},
      offTracks: {for (final id in view.offTracks) if (trackKey[id] != null) trackKey[id]!},
      foldedGroups: groups,
      hostUids: hosts,
      groupHostUids: groupHosts,
      openScopes: {...view.openScopes},
      foldedSpheres: {...view.foldedSpheres},
      knownSpheres: {for (final x in l.spheres) x.id},
      shelvedScopes: {...view.shelvedScopes},
      selection: b.selection.value,
      // 필터 시트의 끈 트랙은 번호 글이다 — 열쇠로 바꿔 두었다가 새 번호로 되돌린다(번호가 아닌 글은 그대로).
      tracksOffFilter: filters is FilterState ? {for (final t in filters.tracksOff) trackKey[int.tryParse(t) ?? -1] ?? t} : const <String>{},
    );
  }

  /// 바꿔 넣거나 고쳐 쓴 저장소의 뼈대를 다시 읽어 장면에 잇는다 — 줄은 옛 자리에서 새 자리로 흐르고([TimelineScene.replaceLayout]),
  /// 켠 DLC · 접은 트랙 · 끈 트랙 · 접은 민족 · 펼친 상국 · 켠 대범위 · 고른 것 · 필터의 끈 트랙은 새 번호로 옮겨 적는다. 새로 온 DLC는 켠다.
  /// 고쳐 쓰기 뒤에도 늘 `{"op":"layout"}`을 다시 받는다(자료집 · 트랙 번호는 빼고 다시 넣으면 다시 쓰인다 — 얹힌 몫 5). [keepBefore]는 엔진의
  /// `first_pos`(그 자리 앞의 줄 묶음 타일은 남긴다 — −1이면 모두 · 바꿔 넣은 저장소는 0).
  Future<void> _reloadStore(_DlcCarry carry, {Set<String> turnOn = const {}, int keepBefore = 0}) async {
    final s = scene, b = bus, g = glue;
    if (s == null || b == null || g == null) return;
    final info = await engine.call({'op': 'info'});
    meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
    total = int.parse(meta!['count']);
    unknown = int.parse(meta!['unknown']);
    final shape = await engine.call({'op': 'layout'});
    final shapeJson = Map<String, dynamic>.from(shape['data'] as Map);
    dlcJob.factsFrom(shapeJson);
    await _loadKept();
    _reloads++;
    final fresh = SceneLayout.fromJson(shapeJson);
    final packOf = {for (final p in fresh.packs) _packKey(p): p.id};
    final off = dlcJob.hidden.off;
    final enabled = dlcEnabledAfterReload(packOf: packOf, off: off, wasOn: carry.wasOn, known: carry.known, turnOn: turnOn);
    final trackAt = {for (int i = 0; i < fresh.tracks.length; i++) fresh.trackIdentity(i): i};
    Set<int> trackIds(Set<String> keys) => {for (final k in keys) if (trackAt[k] != null) fresh.tracks[trackAt[k]!].id};
    final hosts = <int>{}, groupHosts = <int>{};
    for (final (uids, out) in [(carry.hostUids, hosts), (carry.groupHostUids, groupHosts)]) {
      for (final uid in uids) {
        try {
          final a = await _call({'op': 'id_of', 'uid': uid}, whileWriting: true);
          if (a is Map && a['band'] is num) out.add((a['band'] as num).toInt());
        } catch (_) {}
      }
    }
    final groups = <String>{};
    for (int i = 0; i < fresh.tracks.length; i++) {
      final t = fresh.tracks[i];
      for (final gr in t.groups) {
        if (carry.foldedGroups.contains('${fresh.trackIdentity(i)}|${gr.name}:${gr.depth}:${gr.kind}')) groups.add(fresh.groupKeyOf(t, gr));
      }
    }
    // 문화권(리메이크 조각 ②): 접어 둔 것은 그대로, 이번에 새로 생긴 문화권은 접힌 채로 들어온다(처음 접힘 — 하나만 편 모습을 지킴).
    final foldedSpheres = {
      for (final x in fresh.spheres)
        if (carry.foldedSpheres.contains(x.id) || (carry.knownSpheres.isNotEmpty && !carry.knownSpheres.contains(x.id))) x.id,
    };
    // 선반에 둔 그릇(과제 7 걸음 5)도 켠 대범위처럼 uid 그대로 — 뼈대를 갈아 끼운 뒤 아래 `_onViewState()`가 이 보기 상태째 기억에 적는다.
    final view = ViewState(foldedTracks: trackIds(carry.foldedTracks), foldedGroups: groups, offTracks: trackIds(carry.offTracks), expandedHosts: hosts, expandedGroups: groupHosts, openScopes: carry.openScopes, foldedSpheres: foldedSpheres, shelvedScopes: carry.shelvedScopes);
    controller.setExtent(double.parse(meta!['min']), double.parse(meta!['max']));
    final cycleGlue = yearCycle;
    if (cycleGlue == null) {
      s.replaceLayout(fresh, enabled: enabled, view: view, keepBefore: keepBefore);
    } else {
      cycleGlue.replaceMeta(meta ?? {}, applyLayout: () => s.replaceLayout(fresh, enabled: enabled, view: view, keepBefore: keepBefore));
    }
    _dlcFlowMs = _dlcClock == null ? null : _dlcClock!.elapsedMicroseconds / 1000;
    s.applyLayoutToView();
    g.fillTrackSlots(shapeJson);
    // 렌즈: 새 저장소의 주제 사전으로 차림표를 다시 읽고 켠 렌즈를 새 배치에 다시 잇는다(사라졌거나 숨은 주제면 끈다).
    final lensGlue = lens;
    if (lensGlue != null) unawaited(lensGlue.load());
    final filters = b.slot(slotFilters).value;
    if (filters is FilterState) {
      final off = {for (final k in carry.tracksOffFilter) trackAt[k] != null ? '${fresh.tracks[trackAt[k]!].id}' : k};
      if (!setEquals(off, filters.tracksOff)) b.slot(slotFilters).value = filters.copyWith(tracksOff: off);
    }
    // 보조 달력의 표 · 실재성 칩 · 거르개는 저장소마다 새로(`_buildBus`와 같은 길).
    final cals = AuxCalendarStore(b.ask);
    AuxCalendarStore.shared = cals;
    for (final cal in AuxCalendar.list) {
      cals.ensure(cal.id, onReady: (_, _) => scene?.requestFrame());
    }
    defaultAuxTables = cals.table;
    search?.clear();
    cards?.close();
    final marks = SceneMarks.of(s)
      ..expanded = s.layout.expandedHostsShown
      ..scopesOn = {...view.openScopes};
    marks.version++;
    em.Emphasis.of(s).clear();
    // 같은 사람의 칸 표는 띠 번호로 적어 두었으므로 새 저장소에서는 다시 찾는다.
    _twinKeys.clear();
    _twinTables.clear();
    marks.hotTwins = null;
    _rememberedState = null;
    _onViewState();
    // 집합 보기: 새 뼈대는 판을 끈 채 온다 — 판 목록을 다시 읽고 기억한 DLC 판이 아직 있으면 다시 켠다.
    boardViews
      ?..layoutChanged()
      ..restore();
    // 고른 것: 기록이 아직 있으면 같은 것을 다시 골라(새 번호로 창이 다시 선다) 없으면 닫는다.
    final picked = carry.selection;
    if (picked != null) {
      b.clearSelection();
      try {
        await _call({'op': 'entity', 'uid': picked.uid});
        b.select(picked.uid, kind: picked.kind, cell: picked.cell);
      } catch (_) {}
    }
    await _loadShownHistoricity();
    if (mounted) setState(() => status = '원문 ${formatCount((info['data']['originals'] as num?)?.toInt() ?? 0)}');
  }

  // ---- 앱 안의 빠른 측정: 지금 보는 장면에서 여섯 구간을 10초씩 재고 결과를 요약해 보여 준다 ----
  final navigatorKey = GlobalKey<NavigatorState>();
  bool measuring = false;
  String measureProgress = '';

  Future<void> quickMeasure() async {
    // 재는 동안 계측 창이 열려 있으면 0.15초마다의 되그리기가 가짜 장면을 섞는다 — 먼저 닫는다(배율도 1배로 돌아온다).
    // 배율 자체는 `runMeasure` 들머리가 한 번 더 못 박는다.
    final b = bus;
    if (b != null) MotionMeter.toggle(b, false);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final folder = '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}측정-결과${Platform.pathSeparator}$stamp';
    setState(() {
      measuring = true;
      measureProgress = '준비';
    });
    final report = await runMeasure(
      this,
      folder,
      options: MeasureOptions(seconds: 10, repeats: 1, cold: false, from: controller.view.lo, to: controller.view.hi),
      onProgress: (progress) => mounted ? setState(() => measureProgress = progress) : null,
    );
    if (!mounted) return;
    setState(() => measuring = false);
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 640),
          child: report == null
              ? Padding(padding: const EdgeInsets.all(24), child: SelectableText('측정을 끝내지 못했습니다. 까닭은 $folder 의 측정-실패.txt에 적었습니다.'))
              : MeasureSummaryView(report: report, folder: folder),
        ),
      ),
    );
  }

  // ---- 연표에서 누른 것 ----

  /// 사건이면 그 항목의 창을 열고, 개수 알약이면 그 통의 사건 목록을 카드로 띄운다.
  Future<void> hit(Hit h) async {
    final g = glue, card = cards;
    if (g == null || card == null) return;
    if (h.kind == HitKind.none) {
      // 빈 곳: 같은 해 보기가 열려 있으면 기준선을 그 자리로(반올림하지 않은 그 자리 그대로), 아니면 고르기를 풀어 상세 창을 닫는다(명세 7-02).
      card.close();
      if (g.yearOpen) {
        bus!.slot(yearSlot).value = YearRequest(h.lo);
      } else {
        bus!.clearSelection();
      }
      return;
    }
    // 누른 자리의 띠 · 사건 번호는 이미 안다 — 이름을 엔진에 묻고(uid_of) 그 이름의 자리를 다시 묻는(ids_of) 두 번의 왕복을 기다리는 동안
    // 앞서 고른 것의 강조가 그대로 남아 보였다(감독 검토 2026-09-22 "전 조직의 강조가 잠깐 유지"). 곧바로 밝기를 바꾸고, 답이 오면 같은 값으로 굳는다.
    _emphasizeNow(h);
    if (h.kind == HitKind.event) {
      await g.pickEvent(h.eventId, row: h.row);
    } else if (h.kind != HitKind.pill) {
      await _hitMore(h);
    } else if (h.kind == HitKind.pill) {
      final span = clusterOf(h);
      card.press(
        // 알약에 적힌 수(`Hit.count`)를 그대로 싣는다 — 카드의 머리글이 목록이 오기 전에도 건수를 적는다.
        ClusterSpan(key: span.key, row: h.row, lo: h.lo, hi: h.hi, count: h.count),
        // 알약의 자리는 맞히기가 돌려주지 않는다 — 손이 닿은 자리를 닻으로 삼는다.
        anchor: Rect.fromCenter(center: _tapAt, width: 28, height: 18),
      );
    }
  }

  void _emphasizeNow(Hit h) {
    final live = bridge;
    if (live == null) return;
    switch (h.kind) {
      case HitKind.event:
        live.emphasize(em.Look(event: h.eventId, row: h.row >= 0 ? h.row : null));
      case HitKind.band || HitKind.square || HitKind.figure || HitKind.hang:
        if (h.bandId > 0) live.emphasize(em.Look(band: h.bandId));
      case HitKind.cell:
        if (h.bandId > 0) live.emphasize(em.Look(band: h.bandId, cell: h.ref.isEmpty || h.ref.startsWith('@') ? null : h.ref));
      case HitKind.memberButton || HitKind.scopeButton || HitKind.hangButton || HitKind.flag || HitKind.link || HitKind.pill || HitKind.none:
        break;
    }
  }

  // ── 같은 사람의 칸(건의 8의 6-나 — 커서가 올라간 지도자 칸의 짝) ──

  /// 칸 열쇠(`'띠|칸 참조'`) → 같은 사람의 모든 칸 열쇠(올린 칸 포함 · 짝이 없으면 빈 묶음). 저장소가 바뀌면 비운다.
  final _twinKeys = <String, Set<String>>{};

  /// 나라 uid → 그 기록의 짝 표([twinTableOf]) — 같은 띠의 칸마다 기록을 다시 풀지 않게.
  final _twinTables = <String, Map<String, List<(String, String)>>>{};
  int _twinTurn = 0;

  /// 커서가 칸에 올라가면 그 사람의 다른 칸을 찾아 [SceneMarks.hotTwins]에 싣는다(늦게 온 답은 버린다).
  Future<void> _hoverTwins(String? key) async {
    final turn = ++_twinTurn;
    Set<String>? next;
    if (key != null) {
      next = _twinKeys[key] ?? await _twinsOf(key);
      if (turn != _twinTurn) return;
    }
    final s = scene;
    if (s == null) return;
    final marks = SceneMarks.of(s);
    final value = next == null || next.isEmpty ? null : next;
    if (value == null && marks.hotTwins == null) return;
    marks
      ..hotTwins = value
      ..version += 1;
    s.requestFrame();
  }

  Future<Set<String>> _twinsOf(String key) async {
    final bar = key.indexOf('|');
    final band = bar < 0 ? null : int.tryParse(key.substring(0, bar));
    final ref = bar < 0 ? '' : key.substring(bar + 1);
    final b = bus, g = glue;
    if (band == null || b == null || g == null || !(ref.startsWith('leader:') || ref.startsWith('cabinet:'))) return const {};
    final found = await _uidOfBand(band);
    if (found == null) return const {};
    var table = _twinTables[found.$1];
    if (table == null) {
      table = twinTableOf(await detailEntity(b, found.$1));
      if (_twinTables.length >= 64) _twinTables.clear();
      _twinTables[found.$1] = table;
    }
    final pairs = table[ref] ?? const [];
    var out = const <String>{};
    if (pairs.isNotEmpty) {
      final places = await g.placesOf([for (final p in pairs) p.$1]);
      final keys = {
        key,
        for (final p in pairs)
          if (places[p.$1]?.band != null) '${places[p.$1]!.band}|${p.$2}',
      };
      if (keys.length > 1) out = keys;
    }
    if (_twinKeys.length >= 512) _twinKeys.clear();
    return _twinKeys[key] = out;
  }

  /// 띠 번호 → 항목 기록의 열쇠(계약 2-1의 uid_of).
  Future<(String, String)?> _uidOfBand(int band) async {
    if (band <= 0) return null;
    try {
      final answer = await bus!.ask({'op': 'uid_of', 'kind': 'band', 'id': band});
      final uid = answer['uid'];
      return uid is String && uid.isNotEmpty ? (uid, '${answer['kind'] ?? 'period'}') : null;
    } catch (_) {
      return null;
    }
  }

  /// 짝 꼬리표(트랙을 건너는 승계 — 구역 60 · 이어 주는 선 걸음 4)를 눌렀다: 상대 띠로 날아간다 — 앞 끝의 꼬리표면 상대(뒤 나라)의 시작,
  /// 뒤 끝이면 상대(앞 나라)의 끝을 지금 배율 그대로 화면 가운데에. 가는 길은 검색 결과와 같다(LiveSceneBridge.go — 상대 줄이 접힌 트랙 ·
  /// 민족 안이면 먼저 펴고, 닿으면 그 띠에 고리). [key]는 '<0 앞 끝 · 1 뒤 끝>:<상대 uid>'.
  Future<void> _flyToCross(String key) async {
    final g = glue, b = bus, cut = key.indexOf(':');
    if (g == null || b == null || cut < 0) return;
    final uid = key.substring(cut + 1);
    final place = (await g.placesOf([uid]))[uid];
    final start = place?.start;
    if (place == null || start == null) return;
    final at = key.startsWith('1') ? (place.end ?? start) : start;
    final span = b.controller.view.span;
    b.goTo(at - span / 2, at + span / 2, row: place.row, ring: uid);
  }

  /// 연표의 몸통에서 누른 것(사건 · 알약 말고): 띠 · 칸 · 인물 · 이름표 · 네모 → 그 항목의 상세, 단추 → 펼치기/모아 보기.
  Future<void> _hitMore(Hit h) async {
    final b = bus;
    if (b == null) return;
    switch (h.kind) {
      case HitKind.link when h.ref.startsWith(crossTagHitRef):
        await _flyToCross(h.ref.substring(crossTagHitRef.length));
      case HitKind.band || HitKind.square:
        final found = await _uidOfBand(h.bandId);
        if (found != null) b.select(found.$1, kind: found.$2);
      case HitKind.cell:
        if (h.ref.startsWith('@')) {
          b.select(h.ref.substring(1));
        } else {
          final found = await _uidOfBand(h.bandId);
          if (found != null) b.select(found.$1, kind: found.$2, cell: h.ref.isEmpty ? null : h.ref);
        }
      case HitKind.figure:
        if (h.ref.isNotEmpty) {
          b.select(h.ref, kind: 'figure');
        } else {
          // '인물 n명' 한 칸 → 그 정권 상세의 인물 묶음으로.
          final found = await _uidOfBand(h.bandId);
          if (found != null) b.select(found.$1, kind: found.$2, cell: 'figures');
        }
      case HitKind.hang:
        if (h.ref.startsWith('@')) {
          b.select(h.ref.substring(1));
        } else {
          final found = await _uidOfBand(h.bandId);
          if (found != null) b.select(found.$1, kind: found.$2);
        }
      case HitKind.memberButton:
        _toggleVariant(host: h.bandId);
      case HitKind.flag:
        _toggleFlag(h.bandId);
      case HitKind.hangButton:
        _toggleHangs(h.row);
      case HitKind.scopeButton:
        // 집합 보기 판 이름표 → 집합 보기 목록(지금 연표의 onBoardName). 그 밖에는 대범위 모아 보기 단추.
        // 폴더 탭 · 열쇠표는 바꿀 상태를 줄 칸에 싣는다(1 펼침 · 2 접힘 · 3 풀림 · 4 선반 — 리메이크 조각 ③), 본국 띠의 단추는 0(켜고 끄기).
        // 선반 기억에 든 그릇의 라벨 · ▸ · 열쇠표는 5(가지 접기 뒤집기 — 선반 기억을 남김 · 과제 7 걸음 5 · 감독 확인거리).
        if (h.ref == ScopeIn.boardRef) {
          boardViews?.openList();
        } else {
          _pressScope(h.ref, h.row);
        }
      case HitKind.link || HitKind.event || HitKind.pill || HitKind.none:
        break;
    }
  }

  /// 소속 펼치기 · 대범위 모아 보기: 보기 상태(ViewState)의 변형을 켜고 끈다 — 배치가 그 변형의 줄을 끼워 다시 쌓고(360ms),
  /// 판 번호가 갈려 타일 · 빈 줄 접기 · 줄 이름을 켠 변형과 함께 다시 받는다. 저장소에 그 변형이 없으면(옛 저장소) 아무 일도 없다.
  // ── 플래그 창(리메이크 2부 — 꼬리표마다 접고 펴는 것을 모은 창) ──

  /// 열린 플래그 창(없으면 null) — 그 띠의 플래그 자리와 칸(연 때의 것).
  FlagSpot? _flag;

  /// 열린 플래그 창의 띠 번호(검증 대본의 기록 — 없으면 null).
  int? get openFlagBand => _flag?.band;

  /// 플래그를 눌렀다: 그 띠의 창을 열거나(다른 띠의 창이 열려 있으면 갈아 끼움) 같은 플래그면 닫는다.
  void _toggleFlag(int band) {
    final view = timelineKey.currentState;
    final spot = view is TimelineViewState ? view.flagOf(band) : null;
    setState(() => _flag = spot == null || _flag?.band == band ? null : spot);
  }

  void _closeFlag() {
    if (_flag != null) setState(() => _flag = null);
  }

  /// 창의 칸을 눌렀다 — 그 갈래의 접기 · 펴기(옛 머리 줄 단추와 같은 일)를 하고 창을 닫는다.
  void _pickFlag(FlagSpot spot, FlagEntry e) {
    _closeFlag();
    switch (e.kind) {
      case FlagKind.members:
        _toggleVariant(host: spot.band);
      case FlagKind.hangs:
        _toggleHangs(e.row);
      case FlagKind.groups:
        _toggleVariant(groups: spot.band);
      case FlagKind.scope:
        _toggleVariant(scope: e.scope);
    }
  }

  /// 플래그 창 — 아랫단(플래그 칠)이 꼬리표 윗변에 닿게 플래그 왼쪽에서 위로 선다(배치 px × 돋보기 배율).
  Widget _flagWindow() {
    final spot = _flag;
    if (spot == null) return const SizedBox.shrink();
    final mag = controller.view.mag;
    return Positioned(
      left: spot.rect.left * mag,
      top: spot.rect.bottom * mag,
      child: FractionalTranslation(
        translation: const Offset(0, -1),
        child: FlagWindow(spot: spot, onPick: (e) => _pickFlag(spot, e)),
      ),
    );
  }

  void _toggleVariant({int? host, String? scope, int? groups}) {
    final s = scene;
    if (s == null) return;
    final layout = s.layout;
    var next = layout.viewState;
    // 펼칠 때 켠 선반이 그 상국 줄을 빼 두었으면 그 선반도 뺀다(선반 → 펼침 — `viewForHostExpanded` · 선반 그릇 안 상국 띠의 소속 단추).
    if (host != null && host > 0) next = layout.viewForHostExpanded(host, !layout.isHostExpanded(host), next);
    // 단체 펼치기(리메이크 조각 ④ — 나라 띠의 플래그 창 '단체 n'): 소속 펼치기와 같은 길.
    if (groups != null && groups > 0) next = layout.viewForGroupsExpanded(groups, !layout.isGroupsExpanded(groups), next);
    if (scope != null && scope.isNotEmpty) {
      // 켤 때는 그 가지의 접힘 기억을 지운다 — 늘 펼친 채로 모인다(지금 연표의 `toggleScope` · js/timeline.js 7786).
      // `revealForScope`에 `next`를 넘겨야 바로 위의 소속 펼치기(`viewForHostExpanded`)가 조용히 사라지지 않는다.
      next = layout.isScopeOpen(scope) ? next.withScopeOpen(scope, false) : layout.revealForScope(scope, next);
    }
    _applyVariantView(next, scope: scope);
  }

  /// 그릇의 세 상태(리메이크 조각 ③ · 설계 4-6 #2 B): 폴더 탭의 라벨 · 세 칸 손잡이와 풀린 그릇의 열쇠표가 부른다 —
  /// 켜기 · 끄기 · 가지 접기를 한 보기 상태로 묶어 다시 쌓기가 한 번이다.
  void _setScopeState(String uid, ScopeState state) {
    final s = scene;
    if (s == null || uid.isEmpty) return;
    _applyVariantView(s.layout.viewForScopeState(uid, state), scope: uid);
  }

  /// 그릇 누름(그림판의 폴더 탭 · 상자 라벨 · 열쇠표 · 본국 띠 단추와 왼쪽 칸 폴더가 싣는 번호 [press]): 할 일은 [ScopeLayer.actionOf]가 가른다
  /// (5 가지 접기 뒤집기 · 1 ~ 4 상태 · 그 밖 켜고 끄기 — 왼쪽 칸 폴더는 [toggle] 거짓이라 켜고 끄기 없음 · 과제 7 검토 고침).
  void _pressScope(String uid, int press, {bool toggle = true}) {
    switch (ScopeLayer.actionOf(press)) {
      case (ScopePress.fold, _):
        _toggleScopeFold(uid);
      case (ScopePress.state, final ScopeState state):
        _setScopeState(uid, state);
      case _:
        if (toggle) _toggleVariant(scope: uid);
    }
  }

  /// 선반 기억에 든 그릇의 라벨 · ▸ · 열쇠표 · 왼쪽 칸 폴더 누름(누름 5 — 과제 7 걸음 5): 가지만 접고 펴며 선반 기억은 남긴다
  /// (메이커 서고 미리보기의 라벨 누름과 같음 — 선반 → 접힘 → 다시 누르면 선반). 차림표의 네 줄은 [_setScopeState](선반 기억을 뺌). 감독 확인거리.
  void _toggleScopeFold(String uid) {
    final s = scene;
    if (s == null || uid.isEmpty) return;
    _applyVariantView(s.layout.viewForScopeFold(uid), scope: uid);
  }

  /// 변형(소속 펼치기 · 대범위)이 바뀐 보기 상태를 넣고, 단추 · 이름표의 밭과 시트 · 상세 창의 스위치를 맞춘다.
  void _applyVariantView(ViewState next, {String? scope}) {
    final s = scene;
    if (s == null) return;
    final layout = s.layout;
    if (!s.applyViewState(next)) return;
    controller.setContentHeight(layout.totalHeight);
    s.folder.forget();
    // 단추의 ▸/▾와 이름표를 그리는 층의 밭(펼친 상위 정권 · 켠 대범위)도 함께.
    final marks = SceneMarks.of(s)
      ..expanded = layout.expandedHostsShown
      ..scopesOn = {...layout.viewState.openScopes};
    marks.version++;
    cards?.markSelfScroll();
    s.requestFrame();
    // 연표 안 단추로 켠 것이 시트의 칩 · 상세 창의 스위치 · 메뉴의 ✓에도 비치게 되적는다(듣는 쪽은 달라진 것이 없으면 아무것도 하지 않는다).
    final b = bus;
    if (scope != null && scope.isNotEmpty && b != null) setScopeGathered(b, scope, layout.isScopeOpen(scope));
  }

  /// 매달린 속국 이름표 접기(상국 띠의 `▾ 속국 n` 단추 · 건의 8 · 2026-10-14): 그 줄의 띠 아래 덧단에서 매달린 줄들의 몫을 빼거나 되돌린다.
  /// 누른 줄은 화면에서 제자리이고(세로 닻) 아래 줄이 360ms 동안 따라 올라오거나 내려간다.
  void _toggleHangs(int row) {
    final s = scene;
    if (s == null || row < 0 || row >= s.layout.rowCount) return;
    final layout = s.layout;
    final next = layout.viewState.withHangsOpen(row, layout.isHangFolded(row));
    if (!s.applyViewState(next, hold: (row, layout.rowTop(row) - controller.view.top))) return;
    controller.setContentHeight(layout.totalHeight);
    cards?.markSelfScroll();
    s.requestFrame();
  }

  /// 집합 보기(10건 6 · 결정 1 A): 판 하나를 켜고(열쇠) 끈다(빈 글). 판 트랙이 맨 위에 쌓이고 나머지 트랙은 판의 접힘으로
  /// 접힌다(접힘 기억은 그대로). 판 번호가 갈려 타일 · 빈 줄 접기 · 줄 이름을 켠 판과 함께 다시 받는다. [hold]는 붙잡을 줄.
  bool _applyBoard(String key, (int, double) hold) {
    final s = scene;
    if (s == null) return false;
    final layout = s.layout;
    if (!s.applyViewState(layout.withBoardState(key), hold: hold)) return false;
    controller.setContentHeight(layout.totalHeight);
    s.folder.forget();
    cards?.markSelfScroll();
    s.requestFrame();
    return true;
  }

  // ---- 접은 트랙 · 접은 민족 · 펼친 상국을 기억한다(명세 8-28). 켠 대범위는 필터의 값과 함께, 끈 트랙은 칩과 함께 이미 기억된다 ----
  ViewState? _rememberedState;

  /// 문서 창의 나란히 ↔ 넓게를 기억한다(`parts['doc'] = {'side': 참/거짓}` — 고를 때만 적힌다).
  void _attachDocSide(AppMemory memory) {
    final b = bus;
    if (b == null) return;
    final saved = memory.parts['doc']?['side'];
    if (saved is bool) b.slot(docSideSlot).value = saved;
    b.slot(docSideSlot).addListener(() {
      final side = b.slot(docSideSlot).value == true;
      if (memory.parts['doc']?['side'] == side) return;
      memory.parts['doc'] = {'side': side};
      memory.save();
    });
  }

  /// 보기 기억(parts['viewState'] — 읽기 · 쓰기는 scene/view_memory.dart). 되살리기가 끝나기 전에는 쓰지 않는다(결함 ㉡ — 과제 7 걸음 5).
  final _viewMemory = ViewMemory();

  /// 기억의 보기 상태를 되살린다(기억을 이은 뒤 한 번 — 필터 기억이 켠 그릇 위에 접힘 · 펼침 · 문화권 · 선반을 얹는다). 되살릴 것이 없어도 끝나면
  /// 그때부터 보기 상태를 기억에 적는다([ViewMemory.restored]).
  void _restoreViewState(AppMemory memory) {
    try {
      final s = scene;
      if (s == null) return;
      // 문화권(리메이크 조각 ②): 기억이 있으면 마지막으로 본 모습 그대로(지금 자료에 없는 문화권은 버림) — 없으면 처음 접힘(자료의 default 하나만 폄)을 둔다.
      // 선반(과제 7 걸음 5): 지금 저장소에 그 그릇이 없는 uid는 버린다 · 켠 그릇이 선반 기억에 있으면 엔진의 선반 변형을 켠다.
      final next = ViewMemory.read(memory.parts[ViewMemory.part], s.layout.viewState, spheres: ViewMemory.spheresOf(s.layout), scopes: ViewMemory.scopesOf(s.layout));
      if (next == null) return;
      // 여는 참이라 흐름 없이 바로 그 모습으로.
      final was = s.layout.reduceMotion;
      s.layout.reduceMotion = true;
      final changed = s.layout.setViewState(next);
      s.layout.reduceMotion = was;
      _rememberedState = s.layout.viewState;
      if (!changed) return;
      controller.setContentHeight(s.layout.totalHeight);
      s.folder.forget();
      final marks = SceneMarks.of(s)..expanded = s.layout.expandedHostsShown;
      marks.version++;
      bus?.slot(slotFoldAll).value = s.layout.allFolded;
      s.requestFrame();
    } finally {
      _viewMemory.restored = true;
    }
  }

  /// 보기 상태가 갈렸다(어느 길로든 — 왼쪽 칸 · 메뉴 · 가려는 곳 펴기 · 연표 안 단추): 층의 밭과 슬롯을 맞추고 기억한다.
  void _onViewState() {
    final s = scene, b = bus;
    if (s == null || b == null) return;
    final now = s.layout.viewState;
    if (identical(now, _rememberedState)) return;
    _rememberedState = now;
    final marks = SceneMarks.of(s);
    final shown = s.layout.expandedHostsShown;
    if (!setEquals(marks.expanded, shown) || !setEquals(marks.scopesOn, now.openScopes)) {
      marks
        ..expanded = shown
        ..scopesOn = {...now.openScopes};
      marks.version++;
    }
    if (b.slot(slotFoldAll).value != s.layout.allFolded) b.slot(slotFoldAll).value = s.layout.allFolded;
    // 가려는 곳 펴기가 켠 대범위도 시트의 칩 · 상세 창의 스위치에 비친다.
    final slot = gatheredScopes(b);
    final wanted = {for (final uid in now.openScopes) uid: true, for (final uid in slot.keys) if (!now.openScopes.contains(uid)) uid: false};
    if (!mapEquals(slot, wanted)) b.slot(slotScopes).value = wanted;
    // 기억에 적기 — 기억을 잇는 동안(필터 기억의 그릇 켬이 보기 상태를 바꿔 이 듣개가 불림)은 되살리기 전이라 적지 않는다(결함 ㉡ · [ViewMemory.write]).
    final memory = glue?.memory;
    if (memory != null && _viewMemory.write(memory.parts, now)) memory.save();
  }

  /// 대범위를 켜고 끈 값(uid → 켬)을 보기 상태에 맞춘다 — 다른 것만 바꾼다.
  /// 자료의 default 그릇 가운데 켠 그릇 슬롯(기억 · 필터)에 값이 없는 것을 켠다 — 여는 참이라 흐름 없이 바로.
  /// 내보내기의 기본 배치가 모든 그릇을 풀어 두므로(export/base.mjs) 처음 모습은 여기서 정해진다(웹의 scopeOn — 기록 없으면 default와 같은 뜻).
  Future<void> _openDefaultScopes() async {
    final b = bus, s = scene;
    if (b == null || s == null) return;
    Map<String, dynamic> answer;
    try {
      answer = await b.ask({'op': 'scopes'});
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final gathered = gatheredScopes(b);
    final was = s.layout.reduceMotion;
    s.layout.reduceMotion = true;
    for (final x in (answer['scopes'] as List? ?? const [])) {
      if (x is! Map || x['default'] != true) continue;
      final uid = '${x['uid'] ?? ''}';
      if (uid.isEmpty || gathered.containsKey(uid) || s.layout.isScopeOpen(uid)) continue;
      _toggleVariant(scope: uid);
    }
    s.layout.reduceMotion = was;
  }

  void _applyScopes(Map<String, bool> wanted) {
    final s = scene;
    if (s == null) return;
    for (final one in wanted.entries) {
      if (s.layout.isScopeOpen(one.key) != one.value) _toggleVariant(scope: one.key);
    }
  }

  void _scopesFromSlot() {
    final b = bus;
    if (b == null) return;
    final wanted = gatheredScopes(b);
    _applyScopes(wanted);
    // 켠 그릇은 필터의 값으로 기억한다(parts['filters'].scopes) — 필터 시트의 대범위 칩(`_tapScope`)과 같은 길. 결함 ㉢(과제 7 걸음 5에서 고침):
    // 예전에는 이때 라벨 · 차림표로 켠 그릇이 기억되지 않아, 다시 켜면 그 그릇이 (자료의 default가 아니면) 풀려 있었다 — 선반 기억
    // (viewState.shelvedScopes)도 켠 그릇에만 걸리므로 함께 사라졌다. 필터 시트를 연 적이 없어 값이 아직 없으면 **지금 보기 조건**(켠 단 · 밀도 ·
    // 조감 모양 · 조감 전 밀도)에서 시작한다(검토 고침 — 기본값에서 시작하면 다음 실행에 그 밀도 0이 기억의 조감을 덮었다 · [FilterState.fromConditions]).
    // 조건과 같은 값이고 나머지 표시 · 거르기는 기본값(그림의 기본 — SceneMarks · 거르개 없음)이라 그림은 그대로다.
    final value = b.slot(slotFilters).value;
    final state = value is FilterState ? value : FilterState.fromConditions(b.conditions.value, birdFrom: glue?.memory?.ui.birdFrom ?? 0);
    if (wanted.entries.any((e) => state.scopes[e.key] != e.value)) {
      b.slot(slotFilters).value = state.copyWith(scopes: {...state.scopes, ...wanted});
    }
  }

  void _scopesFromFilters() {
    final b = bus, state = bus?.slot(slotFilters).value;
    if (b == null || state is! FilterState || state.scopes.isEmpty) return;
    _applyScopes(state.scopes);
    final slot = gatheredScopes(b);
    if (state.scopes.entries.any((e) => slot[e.key] != e.value)) b.slot(slotScopes).value = {...slot, ...state.scopes};
  }

  /// 이어 붙이기가 받지 않는 명령들(메뉴 · 단축키가 낸다).
  void _onCommand() {
    final b = bus, s = scene, command = bus?.slot(slotCommand).value;
    if (b == null || s == null || command is! AppCommand) return;
    switch (command.name) {
      case Cmd.scope:
        final uid = command.uid;
        if (uid != null && uid.isNotEmpty) setScopeGathered(b, uid, !s.layout.isScopeOpen(uid));
      case Cmd.scopeState:
        // 그릇 안 오른쪽 클릭 메뉴의 펼침 · 선반 · 접음 · 풂(리메이크 2부 · 감독 "그릇 옆 버튼 3개 … 그냥 우클릭으로" · 선반은 과제 7 걸음 5) —
        // 넷 모두 선반 기억을 맞춘다(선반만 넣고 나머지 셋은 뺀다 — 메이커 서고 미리보기 setScopeState와 같음).
        final uid = command.uid, state = ScopeState.values.where((x) => x.name == command.arg).firstOrNull;
        if (uid != null && uid.isNotEmpty && state != null) _setScopeState(uid, state);
      case Cmd.fold:
        final live = bridge;
        if (command.trackId != null && live is LiveSceneBridge) live.toggleTrack(command.trackId!);
      case Cmd.succession:
        final state = b.slot(slotFilters).value;
        if (state is FilterState) {
          b.slot(slotFilters).value = state.withShowValue('succession', command.arg == 'off' ? false : (command.arg == 'direct' ? 'direct' : true));
        }
    }
  }

  /// 메뉴의 ✓ — 승계선과 대범위는 기억이 아니라 지금 상태에서 읽는다(기억의 그 열쇠는 아무도 채우지 않는다).
  MenuFlags _menuFlags() {
    final base = glue!.menuFlags(measuring: measuring);
    final state = bus?.slot(slotFilters).value, s = scene, b = bus;
    final succession = state is FilterState ? state.showValue('succession') : true;
    return MenuFlags(
      measuring: base.measuring,
      bird: base.bird,
      filterOpen: base.filterOpen,
      legend: base.legend,
      allFolded: base.allFolded,
      zen: base.zen,
      // 움직임 계측 창은 제 슬롯이 켬/끔의 임자다(기억이 아니다 — `ui/motion_meter.dart`).
      motion: b != null && MotionMeter.isOpen(b),
      hasMap: base.hasMap,
      clearType: base.clearType,
      clearTypeShown: base.clearTypeShown,
      succession: succession == false ? Succession.off : (succession == 'direct' ? Succession.direct : Succession.all),
      scopesOn: {
        ...base.scopesOn,
        if (s != null)
          for (final uid in s.layout.viewState.openScopes) uid: true,
      },
      lensName: lens == null ? null : (lens!.current?.name ?? ''),
    );
  }

  /// 오른쪽 클릭한 자리에 있는 것: 누름과 같은 맞히기로 항목(띠 · 칸 · 인물 · 이름표 · 사건)의 열쇠를, 왼쪽 칸이면 그 트랙을 찾는다.
  Future<MenuSpot> _probe(Offset local) async {
    final v = controller.view, s = scene, b = bus;
    final minute = v.minuteAt(v.layoutOf((local.dx, local.dy)).$1);
    final view = timelineKey.currentState;
    if (view is! TimelineViewState || s == null || b == null) return MenuSpot(at: minute);
    final g = view.gutterAt(local);
    if (g != null) {
      final track = g.track >= 0 && g.track < s.layout.tracks.length ? s.layout.tracks[g.track] : null;
      return MenuSpot(
        uid: g.kind == GutterHitKind.row && g.uid.isNotEmpty ? g.uid : null,
        trackId: track?.id,
        trackName: track?.name ?? '',
        folded: track != null && s.layout.isTrackFolded(track.id),
      );
    }
    final h = view.hitAt(local);
    // 그 자리를 품은 가장 안쪽 그릇(폴더 · 상자) — 메뉴에 그 그릇의 네 상태(감독 "우클릭한 위치가 그 그릇의 안이면" · ✓는 상태 이름으로 맞춘다).
    final box = view.scopeAt(local);
    String? uid;
    switch (h.kind) {
      case HitKind.event:
        uid = await uidOfEvent(b, h.eventId);
      case HitKind.figure:
        uid = h.ref.isNotEmpty ? h.ref : (await _uidOfBand(h.bandId))?.$1;
      case HitKind.cell || HitKind.hang:
        uid = h.ref.startsWith('@') ? h.ref.substring(1) : (await _uidOfBand(h.bandId))?.$1;
      case HitKind.band || HitKind.square:
        uid = (await _uidOfBand(h.bandId))?.$1;
      case HitKind.scopeButton:
        // 집합 보기 판 이름표는 항목이 아니다(대범위 uid가 아님).
        uid = h.ref.isEmpty || h.ref == ScopeIn.boardRef ? null : h.ref;
      case HitKind.memberButton || HitKind.hangButton || HitKind.flag || HitKind.link || HitKind.pill || HitKind.none:
        break;
    }
    return MenuSpot(uid: uid, at: minute, scope: box?.$1, scopeName: box?.$2 ?? '', scopeState: box?.$3.name ?? '');
  }

  /// 왼쪽 칸에서 누른 것: 트랙 이름 → 트랙 접기, 민족 칸 → 민족 접기, 줄 이름 → 그 띠의 상세, 사람 띠 → 그 인물의 창.
  void gutterHit(GutterHit h) {
    final live = bridge, s = scene, b = bus;
    if (live is! LiveSceneBridge || s == null || b == null) return;
    switch (h.kind) {
      case GutterHitKind.trackName:
        if (h.track >= 0 && h.track < s.layout.tracks.length) live.toggleTrack(s.layout.tracks[h.track].id);
      case GutterHitKind.people:
        // 집합 보기의 칩(원래 트랙 `__from:` · 제 민족 `__bp:`)은 접기 단추가 아니다(지금 연표의 data-board-chip).
        if (isBoardChipKey(h.uid)) return;
        // 대범위 가지의 점선 칸은 `track.groups`에 번호가 없다(group < 0) — 가지의 열쇠(`__scope:<uid>`)로 접고 편다.
        if (h.group < 0) {
          live.toggleScopeGroup(h.track, h.uid);
        } else {
          live.toggleGroup(h.track, h.group);
        }
      case GutterHitKind.row:
        if (h.uid.isNotEmpty) b.select(h.uid);
      case GutterHitKind.chip:
        // 민족 딱지 → 그 민족의 문서(열쇠 `people:<id>`를 딱지가 실어 보낸다).
        if (h.uid.isNotEmpty) b.slot(slotDoc).value = h.uid;
      case GutterHitKind.cap:
        // 줄 이름의 노선 표시 → 도읍 노선도 카드. 누르면 **고정**으로 연다(지금 연표의 `js/viewer.js` 2298과 같다).
        if (h.uid.isNotEmpty) b.slot(metroSlot).value = MetroRequest(h.uid, pinned: true);
      case GutterHitKind.lane:
        // 분류 색 점(열어 줄 창이 없다)
        break;
      case GutterHitKind.sphere:
        // 문화권 머리 단 → 그 문화권 접기 · 펴기(리메이크 조각 ②).
        if (h.uid.isNotEmpty) live.toggleSphere(h.uid);
      case GutterHitKind.folder:
        // 왼쪽 칸의 폴더 그림 · 이름(리메이크 2부) → 폴더 탭의 라벨과 같이 펼침 ↔ 접힘(row = 바꿀 상태 1 펼침 · 2 접힘 · 선반 기억이면 5 가지 접기 뒤집기).
        if (h.uid.isEmpty) return;
        _pressScope(h.uid, h.row, toggle: false);
      case GutterHitKind.person:
        // 문화권 머리 단 밑 사람 띠(리메이크 4단계 과제 4 걸음 3) → 그 인물의 창(칭호 묶음 · 혈연).
        // 인물 기록이 없는 사람은 첫 왕관의 띠 칸 창(uid = 띠 uid · cell = `leader:i` — SpherePersonBand.opens).
        if (h.uid.isEmpty) return;
        if (h.cell.isNotEmpty) {
          b.select(h.uid, cell: h.cell);
        } else {
          b.select(h.uid, kind: 'figure');
        }
    }
  }

  /// 날짜 칸에서 고른 칸: (고른 항목 · 그 칸 참조 · 날짜 칸의 칸 열쇠). 고르기가 달라지면 풀린다(_syncMarks).
  (String, String?, String)? _axisPick;

  /// 날짜 칸에서 누른 칸: 시대 구분은 제 항목을, 연호 · 도읍은 그 정권의 칸 창을 연다(칸의 임자는 검색 색인 search_year가 안다 — 아직은 시대 구분만).
  void axisCell(AxisHit h) {
    // 시대 구분 · 연호 · 도읍 칸의 임자(uid)는 날짜 칸 자료에 실려 있지 않다 — 이름과 때로 찾는다.
    final cell = h.cell, b = bus;
    if (cell == null || b == null) return;
    // 문화권 시대(리메이크 4단계 과제 3 걸음 3)는 날짜 칸 공통 줄에서 빠지고 문화권 머리 단 밑에만 있다 — 날짜 칸과 같은 목록으로
    // 그 uid는 이름 찾기에서 건너뛴다(같은 이름의 문화권 시대가 공통 줄 칸의 임자로 잡히지 않게). 문화권 시대가 없는 저장소는 빈 목록.
    final sphereEpochs = h.kind == AxisHitKind.epochCell ? (scene?.layout.sphereEpochUids ?? const <String>{}) : const <String>{};
    () async {
      try {
        final answer = await b.ask({'op': 'search', 'text': cell.name, 'kinds': h.kind == AxisHitKind.epochCell ? ['epoch'] : ['cell'], 'limit': 20});
        final items = answer['items'];
        if (items is! List) return;
        for (final raw in items) {
          if (raw is! Map || raw['name'] != cell.name) continue;
          final uid = raw['uid'];
          if (uid is! String || uid.isEmpty || sphereEpochs.contains(uid)) continue;
          final ref = raw['cell'];
          final cellRef = ref is String && ref.isNotEmpty ? ref : null;
          _axisPick = (uid, cellRef, axisCellKey(cell));
          b.select(uid, kind: '${raw['kind'] ?? ''}', cell: cellRef);
          _syncMarks();
          return;
        }
      } catch (_) {}
    }();
  }

  /// 오른쪽 클릭 메뉴를 열지 않을 자리(위에 뜬 창) — Flutter에서는 색만 칠한 부품이 누름을 막지 않는다.
  bool menuBlocked(Offset global) {
    final g = glue;
    if (g == null || _windowSize.isEmpty) return false;
    if ((g.detail.open || g.yearOpen) && global.dx >= _windowSize.width - Ui.detailWidth - 2 * Ui.detailInset && global.dy >= Ui.top) return true;
    // 범례 폴더 위(흰 둘레 6까지) — 폴더가 자리를 적기 전(나타나는 움직임 동안)은 옛 왼쪽 아래 460 × 560.
    if (bus?.slot(legendSlot).value == true) {
      final spot = bus?.slot(legendSpotSlot).value;
      if (spot is LegendSpot ? spot.global.inflate(6).contains(global) : global.dx <= 460 && global.dy >= _windowSize.height - 560) return true;
    }
    return false;
  }

  /// 연표 몸통. 아직 못 열었으면 그 자리에 까닭을 적는다(틀은 그대로 둔다).
  Widget timeline() {
    if (failure != null) return Center(child: SelectableText('열람 준비 중 문제가 생겼습니다.\n$failure'));
    if (!ready) return Center(child: Text(status, style: const TextStyle(color: Ui.text2)));
    final b = bus!;
    final view = TimelineView(
      key: timelineKey,
      scene: scene!,
      // 재는 동안에는 측정기의 합성 입력만 받는다. 글자 방식은 (나) 그림판이 기본('라' 관문의 결정).
      onlyDevice: option('--measure') != null || measuring ? measureDevice : null,
      onHit: hit,
      // 개수 알약에 손을 올리면 묶음 카드(명세 7-18) — 건수는 맞히기가 모르므로 카드가 받아 온 목록의 길이로 센다.
      onPill: (pill, at) => cards?.hover(
        pill == null ? null : ClusterSpan(key: clusterOf(pill).key, row: pill.row, lo: pill.lo, hi: pill.hi, count: pill.count),
        anchor: pill == null ? null : Rect.fromCenter(center: at, width: 28, height: 18),
      ),
      onGutterHit: gutterHit,
      onAxisCell: axisCell,
      onAxisTip: _onAxisTip,
      onHotCell: (key) => unawaited(_hoverTwins(key)),
      // 날짜 칸의 여닫음 · 연호 접기 · 배도 갈래 · 보조 달력 · 표시 넷을 기억한다(명세 8-4 · 측정 모드에서는 읽지도 쓰지도 않는다).
      axisState: _rememberView ? glue?.memory?.parts['axis'] : null,
      onAxisState: !_rememberView
          ? null
          : (state) {
              final m = glue?.memory;
              if (m == null) return;
              if (jsonEncode(state) == jsonEncode(m.parts['axis'])) return;
              m.parts['axis'] = state;
              m.save();
            },
      atlasText: option('--text') != 'paragraph',
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            // 묶음 카드의 닻으로 쓸 자리(맞히기는 통의 범위만 알려 준다).
            onPointerDown: (e) {
              _tapAt = e.localPosition;
              // 플래그 창은 다른 곳을 누르면 닫힌다(그 플래그를 다시 누르는 것은 누름이 닫는다 — _toggleFlag).
              final f = _flag, mag = controller.view.mag;
              if (f != null && !f.rect.inflate(4).contains(e.localPosition / mag)) _closeFlag();
            },
            onPointerSignal: (_) => _closeFlag(),
            onPointerUp: (e) {
              _tapAt = e.localPosition;
              // 끌기가 멎었다 — 그때까지 미뤄 둔 손 밑의 알약을 이제 연다(관성이 없으면 active가 바뀌지 않는다).
              cards?.motionEnded();
            },
            child: ContextMenuArea(
              bus: b,
              probe: _probe,
              flagsOf: _menuFlags,
              blocked: menuBlocked,
              child: view,
            ),
          ),
        ),
        // 기간 재기의 끌기 판(꺼져 있으면 자리를 차지하지 않는다) · 묶음 카드 · 가장자리 안내 · 범례.
        Positioned.fill(child: MeasureLayer(bus: b)),
        Positioned.fill(child: ClusterCardLayer(bus: b, cards: cards!, precision: viewPrecision(controller.view.span), gutter: controller.view.left)),
        Positioned.fill(child: EdgeHint(bus: b, gutter: controller.view.left, axisHeight: controller.view.head)),
        Positioned.fill(child: LegendCard(bus: b)),
        // 도읍 노선도 카드(명세 06의 4-2 · slot 'metro'를 듣는다 · 닫혀 있으면 자리를 차지하지 않는다).
        // 카드가 받는 값은 **화면 px**이라 배치 값에 배율을 곱해 넘긴다(돋보기에서 왼쪽 칸 위에 겹치지 않게).
        Positioned.fill(child: MetroCard(bus: b, gutter: controller.view.left * controller.view.mag, head: controller.view.head * controller.view.mag)),
        // 플래그 창(리메이크 2부 — 꼬리표마다 접고 펴는 것을 모은 창 · 닫혀 있으면 자리를 차지하지 않는다).
        _flagWindow(),
        // 단체 계보 창(감독 선택 D5 결정 4 A · slot 'groupTree'를 듣는다 · 닫혀 있으면 자리를 차지하지 않는다 — 이 층이 붙어야 '단체 계보' 단추가 선다).
        Positioned.fill(child: GroupTreeLayer(bus: b)),
        // 승계표 넓은 창(화면 아래 서랍 · slot 'succWide' · 단체 계보 창과 한 자리 · 닫혀 있으면 자리를 차지하지 않는다 — 이 층이 붙어야 좁은 창의 '넓게'가 선다).
        // 서랍의 키가 바뀌면 앱 틀을 다시 그려 배율 알약 · 상세 칸을 서랍 위로 비킨다(아래 stageBottomInset).
        Positioned.fill(child: SuccessionDrawer(bus: b, onInset: _redraw)),
        // 움직임 계측 · 느리게 보기(메뉴 `◔` · 감독용). 범례보다 위에 서고 자리는 스스로 잡는다.
        Positioned.fill(child: MotionMeter(bus: b)),
        // 날짜 칸의 칸 도움말(css의 `title` — 커서를 올리면 120ms에 뜨는 작은 상자).
        _axisTipBubble(),
        // DLC를 다 껐을 때의 안내(지금 연표의 `.tl-empty` — 색은 css `--paper-muted`).
        if (dlcTimelineEmpty(scene!.layout))
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Text(dlcEmptyText,
                    style: TextStyle(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback, fontSize: 14, color: Color(0xff666666))),
              ),
            ),
          ),
      ],
    );
  }

  /// 날짜 칸에서 커서가 올라간 칸의 도움말: (글, 그 칸의 왼쪽 끝, 커서의 y) — 모두 배치 px.
  (String, double, double)? _axisTip;

  void _onAxisTip(String tip, double x, double y) {
    final now = tip.isEmpty ? null : (tip, x, y);
    if (now?.$1 == _axisTip?.$1 && now?.$2 == _axisTip?.$2) return;
    setState(() => _axisTip = now);
  }

  /// 도움말 상자 — `Tooltip` 위젯이 아니라 연표 위에 직접 올린 작은 상자다(날짜 칸은 위젯이 아니라 그림이라 붙일 곳이 없다).
  Widget _axisTipBubble() {
    final tip = _axisTip;
    if (tip == null) return const SizedBox.shrink();
    final mag = controller.view.mag;
    return Positioned(
      left: (tip.$2 * mag).clamp(0.0, _windowSize.width <= 0 ? 0.0 : _windowSize.width - 8),
      top: (tip.$3 + 18) * mag,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: 1,
          duration: const Duration(milliseconds: 120),
          curve: Ui.ease,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
            decoration: BoxDecoration(
              color: Ui.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Ui.line),
            ),
            child: Text(tip.$1, style: const TextStyle(fontSize: 11.5, height: 1.35, color: Ui.text2)),
          ),
        ),
      ),
    );
  }

  /// 필터 시트 발 오른쪽 끝의 도구 단추 줄(명세 7절 머리).
  /// 리메이크 4단계 서고 시트(감독 고름 G5 #9 다듬기 판): 흰 이름 종이 단추(모따기 3 · 테 먹 45 · 글 12 굵게) — 그림 없이 이름만.
  Widget toolsRow(AppBus bus) => SheetRun(
    children: [
      for (final (label, command) in const [
        ('같은 해', Cmd.year),
        ('기간 재기', Cmd.measure),
        ('표', Cmd.table),
        ('이미지 · 인쇄', Cmd.image),
        ('범례', Cmd.legend),
      ])
        SheetPaperButton(label: label, onTap: () => runCommand(bus, command)),
    ],
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    debugShowCheckedModeBanner: false,
    title: '별여울 아카이브 · 3단계 시제품',
    // 휴대폰에서는 화면을 가로 1100px짜리 창으로 배치해 통째로 줄여 그린다(`shell/phone_scale.dart`) — 길잡이 위에 서는 메뉴 · 대화 상자까지 함께.
    builder: (context, child) => PhoneScale(child: child!),
    theme: ThemeData(
      useMaterial3: true,
      // 일반 글과 공용 제목은 프리텐다드. 고른 화면 글꼴과 팩 대체 목록도 여기서 잇는다.
      fontFamily: sceneFamilyNow,
      fontFamilyFallback: sceneFallbackNow,
      scaffoldBackgroundColor: Ui.bg,
      colorScheme: ColorScheme.fromSeed(seedColor: Ui.accent, surface: Ui.surface),
    ),
    home: Scaffold(
      // --capture-size=1920x1080: 창의 크기와 무관하게 그 크기로 배치해 그림을 뜬다(지금 연표의 기준 그림과 같은 크기로 나란히 놓으려고).
      body: _captureFrame(
        RepaintBoundary(
          key: captureKey,
          child: SafeArea(child: _shell()),
        ),
      ),
    ),
  );

  Widget _shell() {
    final b = bus, g = glue, s = search;
    _windowSize = MediaQuery.sizeOf(context);
    final zen = b != null && zenOf(b);
    final shell = AppShell(
      key: shellKey,
      controller: controller,
      timeline: timeline(),
      searchController: query,
      searchFocus: searchFocus,
      onSearchChanged: s == null ? null : (text) => s.setQuery(text),
      onSearchSubmitted: s == null ? null : (_) => s.activate(),
      searchResults: b != null && s != null && s.showResults ? SearchPanel(bus: b, controller: s) : null,
      onCloseResults: () {
        s?.close();
        _redraw();
      },
      detail: b == null ? null : DetailHost(bus: b, framed: false),
      detailOpen: g?.detail.open ?? false,
      detailBare: true,
      detailFoot: (g?.detail.open ?? false) ? sourceFoot() : null,
      onCloseDetail: () => b?.clearSelection(),
      stageOverlay: b == null ? null : YearPanel(bus: b),
      filterSheet: b == null ? null : FilterSheetBody(bus: b, tools: toolsRow(b)),
      filterOpen: g?.filters.filterOpen ?? false,
      onFilterOpen: (open) => g?.setFilterOpen(open),
      dockButtons: [if (boardViews != null) BoardDockButton(views: boardViews!)],
      layers: [if (boardViews != null) BoardListLayer(views: boardViews!)],
      onMenu: openDockMenu,
      onBird: b == null ? null : () => runCommand(b, Cmd.bird),
      dockAfterFilter: [if (lens != null) LensDockButton(glue: lens!), if (b != null) DocDockButton(bus: b)],
      // 계보 창(연표 아래쪽 · 연표 높이의 56%, 525까지)이 떠 있는 동안: 확대 단추 · 상세 칸이 그 위로.
      // 승계표 넓은 창(화면 아래 서랍)이 떠 있으면 그 키만큼 — 둘은 한 자리라 함께 열리지 않는다.
      stageBottomInset: b == null ? null : (h) => b.slot(groupTreeSlot).value != null ? GroupTreeLayerState.sheetHeight(h) : SuccessionDrawer.insetOn(b),
      notice: measuring ? '측정 중 · $measureProgress — 끝날 때까지 이 창을 가리거나 줄이지 말고 기다려 주세요' : notice,
      pills: b == null ? const [] : [MeasurePill(bus: b)],
      float: b == null ? null : (child) => ZenHide(bus: b, child: child),
      topLeft: b == null ? null : ZenExitButton(bus: b),
      top: zen ? 0 : Ui.top,
      // Esc · `/`는 단축키 부품이 맡는다(명세 8-1의 차례가 그쪽에 있다).
      ownKeys: b == null,
      frozen: measuring,
    );
    if (b == null) return shell;
    // 단축키는 연표보다 **바깥**에 둔다 — 연표가 이미 처리한 키가 여기까지 올라오지 않게.
    // 문서(위키) 창은 앱 틀 위를 덮는다(닫혀 있으면 자리를 차지하지 않는다 · slot 'doc'을 듣는다).
    return ShellKeys(
      bus: b,
      windowOpen: () => (g?.windowOpen ?? false) || b.slot(slotDoc).value != null,
      child: Stack(
        children: [
          shell,
          DocWindow(
            bus: b,
            padding: EdgeInsets.fromLTRB(12, (zen ? 0 : Ui.top) + 12, 12, 16),
            top: zen ? 0 : Ui.top,
          ),
        ],
      ),
    );
  }

  Widget _captureFrame(Widget child) {
    final size = (option('--capture-size') ?? '').split('x').map(double.tryParse).toList();
    if (size.length != 2 || size[0] == null || size[1] == null) return child;
    return OverflowBox(
      alignment: Alignment.topLeft, minWidth: size[0], maxWidth: size[0], minHeight: size[1], maxHeight: size[1],
      child: SizedBox(width: size[0], height: size[1], child: child),
    );
  }

  @override
  void dispose() {
    yearCycle?.dispose();
    _blurTimer?.cancel();
    _noticeTimer?.cancel();
    scene?.removeListener(_onViewState);
    settle?.dispose();
    lens?.dispose();
    glue?.memory?.dispose();
    glue?.dispose();
    search?.removeListener(_redraw);
    search?.dispose();
    cards?.dispose();
    boardViews?.dispose();
    bus?.selection.removeListener(_onPicked);
    bus?.dispose();
    query.dispose();
    searchFocus.dispose();
    scene?.dispose();
    controller.dispose();
    engine.close();
    super.dispose();
  }
}

/// 저장소를 바꿔 넣는 사이에 들고 있는 것 — 옛 번호를 이름 · 열쇠로 적은 것(`_carryOver` → `_reloadStore`).
class _DlcCarry {
  const _DlcCarry({
    required this.known,
    required this.wasOn,
    required this.foldedTracks,
    required this.offTracks,
    required this.foldedGroups,
    required this.hostUids,
    this.groupHostUids = const <String>[],
    required this.openScopes,
    required this.selection,
    required this.tracksOffFilter,
    this.foldedSpheres = const <String>{},
    this.knownSpheres = const <String>{},
    this.shelvedScopes = const <String>{},
  });

  /// 접어 둔 문화권 · 바꾸기 전에 있던 문화권(id — 리메이크 조각 ②).
  final Set<String> foldedSpheres, knownSpheres;

  /// 선반에 둔 그릇(uid — 과제 7 걸음 5). 켠 대범위처럼 글자 uid라 그대로 옮긴다(새 저장소에 없는 그릇도 남긴다 — 다시 들면 선반으로 · 기억에서는 읽을 때 버린다).
  final Set<String> shelvedScopes;

  /// 바꾸기 전에 있던 DLC의 열쇠 · 그 가운데 켜 둔 것.
  final Set<String> known, wasOn;

  /// 접은 트랙 · 끈 트랙(트랙 열쇠) · 접은 민족(트랙 열쇠|이름:깊이:종류) · 켠 대범위(uid) · 필터 시트의 끈 트랙(열쇠 또는 글).
  final Set<String> foldedTracks, offTracks, foldedGroups, openScopes, tracksOffFilter;

  /// 펼친 상국 · 단체를 펼친 나라(띠의 uid).
  final List<String> hostUids, groupHostUids;
  final Selection? selection;
}
