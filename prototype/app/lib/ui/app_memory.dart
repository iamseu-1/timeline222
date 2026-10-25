import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../scene/layout.dart';

// 상태 기억 — 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md`의 8-4.
// 지금 연표는 브라우저 저장소에 열쇠마다 따로 담지만(ht.view · ht.ui …), 새 앱은 앱 자료 폴더의 JSON 파일 하나에 담는다.
// 규칙 셋: 쓰기는 400ms 모아서 한 번 · 깨진 파일은 버리고 기본값 · **보던 기간은 자료보다 먼저 읽는다**(명세 9 ㈐-23).

/// 보던 기간(분 — 1970-01-01 UTC 기준 정수 분).
@immutable
class ViewSpan {
  const ViewSpan(this.start, this.end);
  final double start, end;

  static ViewSpan? read(Object? value) {
    if (value is! Map) return null;
    final start = value['start'], end = value['end'];
    if (start is! num || end is! num || !(end > start)) return null;
    return ViewSpan(start.toDouble(), end.toDouble());
  }

  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  @override
  bool operator ==(Object other) => other is ViewSpan && other.start == start && other.end == end;
  @override
  int get hashCode => Object.hash(start, end);
  @override
  String toString() => 'ViewSpan($start, $end)';
}

/// 승계선의 세 값(명세 8-4: `true` · `'direct'` · `false`).
enum Succession { all, direct, off }

/// 표시 체크(`ht.ui.show`). **저장된 파일에 없는 열쇠는 기본값으로 채운다** —
/// 뒤에 생긴 표시가 옛 사용자에게 꺼진 채 나오지 않게(명세 8-4의 규칙).
class ShowMemory {
  ShowMemory();

  /// 지금 연표의 `HT.SHOW_DEFAULTS` — 날짜 칸의 간지 · 연호 · 도읍만 끔(리메이크 2부 · [FilterState.showDefaults]와 같은 값).
  static const defaults = <String, bool>{
    'dynasties': true, 'leaders': true, 'cabinets': true, 'eras': false, 'capitals': false, 'ganji': false,
    'epochs': true, 'partOf': true, 'spotEcho': false, 'figures': true, 'phases': true, 'ranks': true, 'houses': false,
    'groups': true,
  };

  final Map<String, bool> _on = Map.of(defaults);

  /// 승계선만 세 값이다 — 나머지는 켬/끔.
  Succession succession = Succession.all;

  bool operator [](String key) => _on[key] ?? defaults[key] ?? false;
  void operator []=(String key, bool on) {
    if (defaults.containsKey(key)) _on[key] = on;
  }

  bool get dynasties => this['dynasties'];
  bool get leaders => this['leaders'];
  bool get cabinets => this['cabinets'];
  bool get phases => this['phases'];
  bool get ranks => this['ranks'];
  bool get figures => this['figures'];
  bool get groups => this['groups'];

  void readJson(Object? value) {
    if (value is! Map) return;
    for (final key in defaults.keys) {
      final one = value[key];
      if (one is bool) _on[key] = one;
    }
    final succ = value['succession'];
    succession = succ == false ? Succession.off : (succ == 'direct' ? Succession.direct : Succession.all);
  }

  Map<String, dynamic> toJson() => {
    for (final key in defaults.keys) key: this[key],
    'succession': switch (succession) { Succession.all => true, Succession.direct => 'direct', Succession.off => false },
  };
}

/// 승계표 · 세계표의 접힘 기억(`ht.ui.kinFold` — D1 확정 설계 3-4 · 4-5).
///
/// 보기 설정이지 파일이 아니다. 창마다(승계표는 정권 uid, 세계표는 뼈대 열쇠 `kin:<뿌리 가문 id>`) **기본값과 다르게 둔
/// 마디의 안정 열쇠**만 남긴다 — 앞 차례 번호는 자료가 바뀌면 밀리므로 쓰지 않는다. 모두 합쳐 [limit]개를 넘으면
/// 가장 오래 손대지 않은 창의 것부터 버린다(지금 연표와 같은 2,000).
class KinFoldMemory {
  KinFoldMemory();

  /// 남기는 열쇠 수의 한도.
  static const limit = 2000;

  /// 창 열쇠 → 기본과 다르게 둔 마디의 안정 열쇠. 차례가 곧 최근에 손댄 차례다(뒤가 새것).
  final _views = <String, List<String>>{};

  /// 바뀌면 부른다(기억 파일을 400ms 모아 쓰게 — [AppMemory]가 잇는다).
  VoidCallback? onChanged;

  /// 그 창에서 기본과 다르게 둔 마디들(없으면 빈 집합).
  Set<String> read(String view) => {...?_views[view]};

  /// 그 창의 다르게 둔 마디를 통째로 적는다. 비우면 그 창을 잊는다. 한도를 넘으면 오래된 창부터 버린다.
  void write(String view, Iterable<String> flipped) {
    final keys = flipped.toList();
    _views.remove(view);
    if (keys.isNotEmpty) _views[view] = keys;
    var total = 0;
    for (final one in _views.values) {
      total += one.length;
    }
    while (total > limit && _views.isNotEmpty) {
      final oldest = _views.keys.first;
      if (oldest == view && _views.length == 1) {
        // 창 하나가 한도를 넘으면 그 창의 앞(오래된) 것부터 버린다.
        final list = _views[view]!;
        final drop = total - limit;
        list.removeRange(0, drop);
        total -= drop;
        break;
      }
      total -= _views.remove(oldest)!.length;
    }
    onChanged?.call();
  }

  /// 기억한 창의 수.
  int get length => _views.length;

  void readJson(Object? value) {
    _views.clear();
    if (value is! Map) return;
    for (final entry in value.entries) {
      final list = entry.value;
      if (entry.key is! String || list is! List) continue;
      final keys = [for (final k in list) if (k is String && k.isNotEmpty) k];
      if (keys.isNotEmpty) _views[entry.key as String] = keys;
    }
  }

  Map<String, dynamic> toJson() => {for (final entry in _views.entries) entry.key: entry.value};
}

/// `ht.ui` — 필터 · 표시 · 접힘(명세 8-4의 열쇠와 초깃값).
class UiMemory {
  UiMemory();

  /// 칩 켬/끔. 기록이 없는 것은 켜진 것으로 본다(지금 연표와 같다).
  Map<String, bool> tracks = {}, categories = {}, kinds = {}, historicity = {};

  /// 대범위 모아 보기: 기록이 없으면 그 대범위의 기본값을 따른다.
  Map<String, bool> scopes = {};

  int minImportance = 1;

  /// −1 넉넉하게 · 0 자동 · 1 빽빽하게 · 2 조감.
  int density = 0;

  /// 조감 모양(a 이름+점 · b 이름만 · c 띠·선만) · 축소하면 조감 · 조감에 들기 직전의 밀도.
  String birdShape = 'a';
  bool birdAuto = false;
  int birdFrom = 0;

  bool showAlt = true;

  /// 관점(나라마다 제 이름) · 보조 달력 · 지도자 표기.
  String lens = '', altCal = '', leaderLabel = 'auto';
  bool leaderOrdinal = false;

  /// 범례가 열려 있는가 · 필터 시트가 열려 있는가.
  bool legend = false, filterOpen = false;

  /// 접힌 트랙(트랙 번호).
  List<int> folded = [];

  /// 접힌 민족 · 접힌 시대 · 열어 둔 날짜 칸 줄 · 펼친 도읍 구역 · 펼친 상국(모두 열쇠 글).
  List<String> foldedPeoples = [], foldedEras = [], axisOpen = [], openCapSec = [], expandedHosts = [];

  final show = ShowMemory();

  /// 승계표 · 세계표의 접힘(D1).
  final kinFold = KinFoldMemory();

  static UiMemory read(Object? value) {
    final ui = UiMemory();
    if (value is! Map) return ui;
    Map<String, bool> flags(Object? one) => one is Map
        ? {
            for (final entry in one.entries)
              if (entry.key is String && entry.value is bool) entry.key as String: entry.value as bool,
          }
        : {};
    List<String> texts(Object? one) => one is List ? [for (final x in one) if (x != null) '$x'] : [];
    List<int> numbers(Object? one) => one is List ? [for (final x in one) if (x is num) x.toInt() else if (int.tryParse('$x') != null) int.parse('$x')] : [];
    bool yes(Object? one, bool fallback) => one is bool ? one : fallback;
    int count(Object? one, int fallback) => one is num ? one.toInt() : fallback;
    String text(Object? one, String fallback) => one is String ? one : fallback;

    ui
      ..tracks = flags(value['tracks'])
      ..categories = flags(value['categories'])
      ..kinds = flags(value['kinds'])
      ..historicity = flags(value['historicity'])
      ..scopes = flags(value['scopes'])
      ..minImportance = count(value['minImportance'], 1)
      ..density = [-1, 0, 1, 2].contains(count(value['density'], 0)) ? count(value['density'], 0) : 0
      ..birdShape = ['a', 'b', 'c'].contains(text(value['birdShape'], 'a')) ? text(value['birdShape'], 'a') : 'a'
      ..birdAuto = yes(value['birdAuto'], false)
      ..birdFrom = count(value['birdFrom'], 0)
      ..showAlt = yes(value['showAlt'], true)
      ..lens = text(value['lens'], '')
      ..altCal = text(value['altCal'], '')
      ..leaderLabel = text(value['leaderLabel'], 'auto')
      ..leaderOrdinal = yes(value['leaderOrdinal'], false)
      ..legend = yes(value['legend'], false)
      ..filterOpen = yes(value['filterOpen'], false)
      ..folded = numbers(value['folded'])
      ..foldedPeoples = texts(value['foldedPeoples'])
      ..foldedEras = texts(value['foldedEras'])
      ..axisOpen = texts(value['axisOpen'])
      ..openCapSec = texts(value['openCapSec'])
      ..expandedHosts = texts(value['expandedHosts']);
    ui.show.readJson(value['show']);
    ui.kinFold.readJson(value['kinFold']);
    return ui;
  }

  Map<String, dynamic> toJson() => {
    'tracks': tracks, 'categories': categories, 'kinds': kinds, 'historicity': historicity, 'scopes': scopes,
    'minImportance': minImportance, 'density': density, 'birdShape': birdShape, 'birdAuto': birdAuto, 'birdFrom': birdFrom,
    'showAlt': showAlt, 'lens': lens, 'altCal': altCal, 'leaderLabel': leaderLabel, 'leaderOrdinal': leaderOrdinal,
    'legend': legend, 'filterOpen': filterOpen,
    'folded': folded, 'foldedPeoples': foldedPeoples, 'foldedEras': foldedEras, 'axisOpen': axisOpen,
    'openCapSec': openCapSec, 'expandedHosts': expandedHosts,
    'show': show.toJson(),
    if (kinFold.length > 0) 'kinFold': kinFold.toJson(),
  };
}

/// 기억이 놓이는 자리 — 명령줄에서 정한다(판정 R50: 앱을 띄우는 검사가 감독의 `%APPDATA%` 아래 기억 파일을 덮은 일 뒤).
///   · `--memory-dir=<폴더>`: 기억 파일(`ui-state.json`)과, 저장소를 주지 않은 휴대폰 꼴의 저장소(`archive.db` · 옆 `DLC/`)를 이 폴더에 둔다 —
///     운영체제의 앱 자료 폴더(Windows `%APPDATA%\local.archive\archive_prototype\archive-prototype-v2`)는 묻지도 않는다(path_provider는 물을 때
///     그 폴더를 만든다). 앱을 띄우는 검사(`smoke-windows.ps1` · `measure.mjs` · `d4-app-capture.mjs`)는 늘 이것으로 띄운다.
///   · `--capture-memory=<폴더>`(그림만 뜰 때 — D4 다시 열기 검사): 재는 동안에도 기억을 이 폴더에서만 읽고 쓴다(`--memory-dir`보다 앞선다).
///   · 재는 중(`--measure` · `--capture-only=yes`)과 메이커 미리보기(`--preview-dlc`)는 기억을 읽지도 쓰지도 않는다(`--capture-memory`만 예외 —
///     장면이 기억에 따라 달라지면 측정이 무효다).
///   · `--memory-dir`이면 앱이 만드는 임시 파일(메이커 미리보기의 서재 사본 · check-pack 결과)도 그 아래 `tmp/`에([scratch]) · 저장소를 주지 않은
///     재기 · 그림만은 저장소를 고쳐 쓰지 않는다([leaveStore] — 판정 R50 넘김: 기본 저장소에 R32 다시 들이기 · `--add-dlc` · `--off-dlc`가 닿지 않게).
class MemoryPlace {
  const MemoryPlace({this.folder, this.remember = true, this.scratchFolder, this.leaveStore = false, this.leaveDlcFolder = false});

  factory MemoryPlace.of(List<String> arguments) {
    String? option(String name) {
      for (final arg in arguments) {
        if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
      }
      return null;
    }

    Directory? folderOf(String? path) => path == null || path.isEmpty ? null : Directory(path);
    final capturing = option('--capture-only') == 'yes';
    final measuring = option('--measure') != null || capturing;
    final previewing = (option('--preview-dlc') ?? '').isNotEmpty;
    final capture = capturing ? folderOf(option('--capture-memory')) : null;
    final dir = folderOf(option('--memory-dir'));
    return MemoryPlace(
      folder: capture ?? dir,
      remember: (!measuring && !previewing) || capture != null,
      scratchFolder: dir == null ? null : Directory('${dir.path}${Platform.pathSeparator}tmp'),
      leaveStore: measuring && (option('--db') ?? '').isEmpty,
      leaveDlcFolder: measuring,
    );
  }

  /// 저장소 옆 `DLC/`를 쓰지 않는가 — 재는 중 · 그림만(`--measure` · `--capture-only=yes`)이면 저장소를 주었어도(판정 R63-4): 판 올림 뒤 다시 들이기(R32) ·
  /// 폴더 사본 채우기 · 묘비 정리 · 낡은 끄기 묘비 · 임시 파일 치우기를 하지 않는다(`measure.mjs --capture-only --db <실자료>`가 그 저장소의 DLC 폴더를
  /// 고쳐 쓰지 않게). 검증 손잡이(`--add-dlc` …)는 [leaveStore]가 가른다.
  final bool leaveDlcFolder;

  /// `--memory-dir`일 때 임시 파일의 자리(그 아래 `tmp/`). null이면 운영체제의 임시 폴더.
  final Directory? scratchFolder;

  /// 앱이 만드는 임시 파일(메이커 미리보기의 서재 사본 · check-pack 결과)의 자리 — 만들지는 않는다(쓰는 쪽이 만든다).
  Directory get scratch => scratchFolder ?? Directory.systemTemp;

  /// 저장소를 고쳐 쓰지 않는가 — 재는 중 · 그림만이면서 저장소(`--db`)를 주지 않았을 때(창의 기본 저장소 `prototype.json`): 판 올림 뒤 DLC 폴더
  /// 다시 들이기(R32) · 검증 손잡이(`--add-dlc` · `--off-dlc` · `--on-dlc` · `--remove-dlc`)를 하지 않는다. 보통 모드(연결 프로그램으로 연 .htpack)는 그대로.
  final bool leaveStore;

  /// 기억의 폴더(그 안에 `ui-state.json`). null이면 운영체제의 앱 자료 폴더([AppMemory.defaultFolder]).
  final Directory? folder;

  /// 기억을 읽고 쓰는가.
  final bool remember;

  /// 기억의 폴더 — 손잡이가 있으면 그것(운영체제에 묻지 않는다), 없으면 [platform](기본은 운영체제의 앱 자료 폴더).
  Future<Directory> resolve({Future<Directory> Function() platform = AppMemory.defaultFolder}) async => folder ?? await platform();

  /// 저장소를 주지 않았을 때(휴대폰 — 시드를 놓는 자리)의 저장소 경로 — 기억과 같은 폴더의 `archive.db`.
  Future<String> storePath({Future<Directory> Function() platform = AppMemory.defaultFolder}) async => '${(await resolve(platform: platform)).path}/archive.db';
}

/// 앱 자료 폴더의 JSON 파일 하나에 담는 기억.
///
/// 쓰는 길: 값을 바꾸고 [save]를 부르면 400ms 모아서 한 번 쓴다. [dispose]는 미뤄 둔 것을 마저 쓰기 **시작한다**.
///
/// **창을 닫을 때는 그 길이 돌지 않는다**(2026-10-13 이 PC의 Windows에서 확인): 창을 닫으면 위젯의 `dispose` 없이
/// 종료 물음(`didRequestAppExit`)만 오고 프로세스가 끝나며, 그때 시작만 한 쓰기는 파일에 놓이기 전에 끊긴다.
/// 그래서 지금은 닫기 직전 400ms 안에 바꾼 것이 적히지 않는다(파일은 직전에 쓴 값 그대로 온전하다 — 옆 파일에 쓰고 갈아 끼우므로).
/// 그것까지 남기려면 종료 물음에서 [flush]를 **기다린 뒤** 답해야 한다.
class AppMemory {
  AppMemory._(this.file, this.view, this.ui, this.delay, Map<String, Map<String, dynamic>> parts) {
    this.parts.addAll(parts);
    ui.kinFold.onChanged = save;
  }

  /// 기억 파일 — 앱 자료 폴더(`getApplicationSupportDirectory`) 아래 저장소와 같은 폴더에 둔다.
  static const fileName = 'ui-state.json', folderName = 'archive-prototype-v2';

  /// 파일에 적는 판. 모르는 판이어도 읽을 수 있는 열쇠는 읽는다.
  static const version = 1;

  final File file;

  /// 모아서 쓰는 시간(명세 8-4의 400ms).
  final Duration delay;

  /// 보던 기간. 아직 한 번도 담지 않았으면 null.
  ViewSpan? view;

  /// 필터 · 표시 · 접힘.
  UiMemory ui;

  /// 다른 부품이 **제 꼴 그대로** 담아 두는 자리(이름 → JSON). 이 파일은 뜻을 모르고 싣고 내린다 —
  /// 필터 시트의 `FilterState.toJson()`처럼 같은 값을 두 벌로 두지 않으려는 곳에 쓴다. 바꾼 뒤에는 [save]를 부른다.
  final parts = <String, Map<String, dynamic>>{};

  Timer? _timer;
  Future<void> _writing = Future<void>.value();
  bool _closed = false;

  /// 기억이 사는 폴더(주지 않았을 때의 기본).
  static Future<Directory> defaultFolder() async => Directory('${(await getApplicationSupportDirectory()).path}/$folderName');

  /// 기억을 읽어 연다. 파일이 없거나 깨졌으면 기본값이다(깨진 파일은 다음 쓰기에 덮어 쓴다).
  static Future<AppMemory> open({Directory? folder, Duration delay = const Duration(milliseconds: 400)}) async {
    final file = File('${(folder ?? await defaultFolder()).path}/$fileName');
    final saved = await _read(file);
    final parts = <String, Map<String, dynamic>>{};
    if (saved['parts'] is Map) {
      for (final one in (saved['parts'] as Map).entries) {
        if (one.key is String && one.value is Map) parts[one.key as String] = Map<String, dynamic>.from(one.value as Map);
      }
    }
    return AppMemory._(file, ViewSpan.read(saved['view']), UiMemory.read(saved['ui']), delay, parts);
  }

  /// **자료를 열기 전에** 보던 기간만 먼저 읽는다 — 첫 화면이 처음부터 그 범위의 줄 높이로 지어지게(명세 9 ㈐-23).
  /// 작은 파일 하나만 읽으므로 저장소를 여는 일과 나란히 할 수 있다.
  static Future<ViewSpan?> readView({Directory? folder}) async {
    final file = File('${(folder ?? await defaultFolder()).path}/$fileName');
    return ViewSpan.read((await _read(file))['view']);
  }

  /// **화면이 서기 전에** 부품의 기억 한 칸(`parts[name]`)만 먼저 읽는다 — 첫 장면부터 그 설정으로 그리게(ClearType 끔 등). 없으면 null.
  static Future<Map<String, dynamic>?> readPart(String name, {Directory? folder}) async {
    final file = File('${(folder ?? await defaultFolder()).path}/$fileName');
    final part = (await _read(file))['parts'];
    final one = part is Map ? part[name] : null;
    return one is Map ? Map<String, dynamic>.from(one) : null;
  }

  static Future<Map<String, dynamic>> _read(File file) async {
    try {
      if (!await file.exists()) return const {};
      final data = jsonDecode(await file.readAsString());
      return data is Map ? Map<String, dynamic>.from(data) : const {};
    } catch (_) {
      return const {}; // 깨진 파일은 버리고 기본값으로 연다
    }
  }

  /// 보던 기간을 적는다(400ms 모아서).
  void setView(double start, double end) {
    view = ViewSpan(start, end);
    save();
  }

  /// 바꾼 것을 400ms 모아서 한 번 쓴다.
  void save() {
    if (_closed) return;
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      _write();
    });
  }

  /// 미뤄 둔 쓰기를 지금 끝낸다(검사 · 앱을 닫을 때).
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    _write();
    await _writing;
  }

  /// 미뤄 둔 쓰기가 있으면 마저 쓰고 더 받지 않는다. 쓰기는 **시작만** 한다 — 파일에 놓인 것까지 보아야 하면 [written]을 기다린다.
  void dispose() {
    final pending = _timer != null;
    _timer?.cancel();
    _timer = null;
    if (pending) _write();
    _closed = true;
  }

  /// 지금까지 시작해 둔 쓰기가 모두 끝났을 때 끝난다 — 파일에 놓였을 때다(쓰지 못한 쓰기도 끝난 것으로 친다 · 시작한 것이 없으면 곧바로).
  /// 미뤄 둔 쓰기를 앞당기지는 않는다 — 그것은 [flush] · [dispose]가 한다.
  /// 쓰기는 옆 파일에 다 쓴 뒤 갈아 끼우는 일이라 끝나는 때가 기기의 형편에 달렸다(바쁜 Windows에서 0.3초를 넘긴 것을 쟀다) —
  /// 닫은 뒤 곧 프로세스가 끝나거나 그 폴더를 치우는 쪽은 시간을 어림해 기다리지 말고 이것을 기다린다.
  Future<void> get written => _writing;

  Map<String, dynamic> toJson() => {
    'version': version,
    if (view != null) 'view': view!.toJson(),
    'ui': ui.toJson(),
    if (parts.isNotEmpty) 'parts': parts,
  };

  void _write() {
    final text = jsonEncode(toJson());
    // 쓰다 만 파일이 남지 않게 옆에 다 쓴 뒤 갈아 끼운다(다음에 열 때 깨진 파일을 만나지 않게).
    _writing = _writing.then((_) async {
      final temp = File('${file.path}.tmp');
      await temp.parent.create(recursive: true);
      await temp.writeAsString(text, flush: true);
      await temp.rename(file.path);
    }).catchError((Object _) {});
  }

  /// 보기 조건(켠 단 · 밀도)을 기억과 잇는다: 먼저 기억한 값을 [conditions]에 넣고, 그다음부터 바뀔 때마다 적는다.
  /// 돌려주는 것을 부르면 듣기를 그만둔다.
  VoidCallback bindConditions(ValueNotifier<ViewConditions> conditions) {
    conditions.value = conditions.value.copyWith(
      dynasties: ui.show.dynasties,
      leaders: ui.show.leaders,
      cabinets: ui.show.cabinets,
      phases: ui.show.phases,
      ranks: ui.show.ranks,
      figures: ui.show.figures,
      groups: ui.show.groups,
      density: ui.density,
    );
    void listen() {
      final now = conditions.value;
      ui.show['dynasties'] = now.dynasties;
      ui.show['leaders'] = now.leaders;
      ui.show['cabinets'] = now.cabinets;
      ui.show['phases'] = now.phases;
      ui.show['ranks'] = now.ranks;
      ui.show['figures'] = now.figures;
      ui.show['groups'] = now.groups;
      if (now.density == 2 && ui.density != 2) ui.birdFrom = ui.density;
      ui.density = now.density;
      save();
    }

    conditions.addListener(listen);
    return () => conditions.removeListener(listen);
  }

  /// `↕` · `V`가 바꿀 밀도(명세 9 ㈐-18). 조감이 아니면 조감(2)으로 들어가며 직전 밀도를 [UiMemory.birdFrom]에 적고,
  /// 밀도가 조감이면 그 직전 밀도로 돌아간다. 자동 조감으로 들어가 있으면(밀도는 조감이 아닌데 화면이 조감) null —
  /// 그때는 밀도를 바꾸는 것이 아니라 '자동 조감 풀기'다.
  int? birdTarget({required bool inBird}) {
    if (!inBird) {
      ui.birdFrom = ui.density == 2 ? 0 : ui.density;
      ui.density = 2;
      save();
      return 2;
    }
    if (ui.density == 2) {
      ui.density = ui.birdFrom;
      save();
      return ui.density;
    }
    return null;
  }
}
