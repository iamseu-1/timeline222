import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;

import '../scene/fonts.dart';
import '../scene/glyph_ranges.dart';
import '../shell/look.dart';
import 'app_bus.dart';
import 'app_memory.dart';
import 'detail_format3.dart';
import 'detail_shell.dart';
import 'shell_keys.dart' show slotNotice;

// ════════════════════════════════════════════════════════════════════════════════════════════
//  원어 병기 · 글꼴 — 새 앱(아카이브) 몫 (10건 3 · 9 — 감독 선택 docs/설계-10건/감독-선택.md D2 · 갈래 D2)
//  설계 docs/설계-10건/3-9-원어와-글꼴.md 7절(구현 기록 — 웹)을 새 앱에 같은 글 · 같은 차례 · 같은 값으로.
//
//  1. 보는 사람 설정 [NamesUi] — 웹 ht.ui.names = {orig, kinds} · ht.ui.fonts = {screen}. 앱은 AppMemory.parts['names']에
//     {orig, kinds, screen?}으로, 고를 때만 적는다(고르기 전에는 열쇠가 없다 — 지금 사용자 그대로). 값은 bus.slot('names').
//  2. 이름 정보 [NamesInfo] — 엔진 {"op":"names_info"}: 이름 목록이 있는 자료집 · 글꼴 목록. 필터 '표기' 무리는 켜진 자료집에
//     이름 목록이나 글꼴이 있을 때만 보인다(웹 syncNamesUi). bus.slot('namesInfo').
//  3. 글꼴 팩 [ScriptFonts] — 켜진 DLC의 글꼴 파일을 엔진 {"op":"font_data"}(저장소가 품은 원본에서 꺼낸 것)로 받아 FontLoader로 싣고,
//     대체 글꼴 목록(scene/fonts.dart의 sceneFallbackNow) 끝에 더한다 → 화면 글꼴에 없는 글자를 채움. 실린 글꼴의 덮는 범위를
//     판정 표(scene/glyph_ranges.dart)에 더한다. 화면 글꼴([글꼴 ▾])은 앱을 켤 때 장면을 만들기 전에 한 번 맨 앞에([applySavedScreenFont]).
//  4. 상세 창 — [NamesHead](제목 바로 아래 두 줄: 첫 원어 19px · 첫 로마자 13px · 언어 · 종류 딱지 없음, 풍선에만) ·
//     [NamesRest](설명 바로 위 '다른 이름 n개' 칸) · [NamesLine](지명 · 성씨처럼 딸린 한 줄) · [NamesPlace](사건 장소 · 도읍 지명 줄).
//     그릴 수 없는 이름(창 표 + 켜진 팩에 없는 글자)은 글 대신 '원어 — ○○ · 글꼴 없음' 딱지. 이름 글은 U+2068 … U+2069로 방향을 가둔다.
//     자료는 내보내기가 미리 푼 x_nameHead · x_cellNameHead · 지명 줄의 head · x_surnameHead — 없는 옛 저장소는 x_names(F1 꼴)로 예전처럼.
//  5. [NamesGlue] — 앱 틀(app_glue.dart)이 세운다: 이름 정보 묻기 · 글꼴 싣기 · 장면의 왼쪽 칸 값(SceneNames) · 기억.
// ════════════════════════════════════════════════════════════════════════════════════════════

/// AppBus 슬롯 이름: 보는 사람 설정(NamesUi) · 이름 정보(NamesInfo).
const slotNames = 'names', slotNamesInfo = 'namesInfo';

/// 적용 체크의 종류(웹 kinds): 나라(시대 · 왕조 · 가문 · 성씨 · 연호 · 내각 · 단체 · 제도) · 인물(지도자 · 인물) · 지명(도읍 · 지명).
enum NameKind { polity, person, place }

// ────────────────────────────────────────────────────────────────────────────────────────────
//  1. 보는 사람 설정
// ────────────────────────────────────────────────────────────────────────────────────────────

@immutable
class NamesUi {
  const NamesUi({this.orig = 'detail', this.polity = true, this.person = true, this.place = true, this.screen});

  /// 원어 고르기의 값과 이름 — 웹 HT.NAMES_ORIG 차례 그대로(목록 차례 = 상세 창만 · 없음 · 왼쪽 칸에도).
  static const origOptions = <(String, String)>[('detail', '상세 창만'), ('none', '없음'), ('band', '왼쪽 칸에도')];

  /// `detail` 상세 창만(기본) · `none` 없음 · `band` 왼쪽 칸에도.
  final String orig;

  /// 적용 체크(나라 · 인물 · 지명). 끈 종류는 '없음'과 같다.
  final bool polity, person, place;

  /// 화면 글꼴로 쓸 글꼴 기록의 uid(`font:<id>` — 한글을 덮는 글꼴만). null = 기본.
  final String? screen;

  bool on(NameKind kind) => switch (kind) {
    NameKind.polity => polity,
    NameKind.person => person,
    NameKind.place => place,
  };

  /// 이 종류의 이름 목록을 상세 창에 보이나 — [kind]가 null이면 적용 체크 밖(사건 제목의 다른 이름 — 원어 고르기만 따른다).
  bool shown(NameKind? kind) => orig != 'none' && (kind == null || on(kind));

  /// 왼쪽 줄 이름 칸에 원어를 함께 적나 — 웹 viewer.js `origFn`이 함수를 넘기는 때.
  bool get band => orig == 'band' && polity;

  NamesUi copyWith({String? orig, bool? polity, bool? person, bool? place, String? screen, bool noScreen = false}) => NamesUi(
    orig: orig ?? this.orig,
    polity: polity ?? this.polity,
    person: person ?? this.person,
    place: place ?? this.place,
    screen: noScreen ? null : (screen ?? this.screen),
  );

  /// 모르는 값 · 없는 값은 기본(웹 HT.namesUi).
  factory NamesUi.fromJson(Object? v) {
    final o = v is Map ? v : const {};
    final k = o['kinds'] is Map ? o['kinds'] as Map : const {};
    final orig = origOptions.any((x) => x.$1 == o['orig']) ? o['orig'] as String : 'detail';
    final screen = o['screen'] is String && (o['screen'] as String).isNotEmpty ? o['screen'] as String : null;
    return NamesUi(orig: orig, polity: k['polity'] != false, person: k['person'] != false, place: k['place'] != false, screen: screen);
  }

  Map<String, dynamic> toJson() => {
    'orig': orig,
    'kinds': {'polity': polity, 'person': person, 'place': place},
    if (screen != null) 'screen': screen,
  };

  /// 지금 값(슬롯이 비면 기본).
  static NamesUi of(AppBus bus) {
    final v = bus.slot(slotNames).value;
    return v is NamesUi ? v : const NamesUi();
  }

  @override
  bool operator ==(Object other) =>
      other is NamesUi && other.orig == orig && other.polity == polity && other.person == person && other.place == place && other.screen == screen;
  @override
  int get hashCode => Object.hash(orig, polity, person, place, screen);
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  2. 이름 정보 · 글꼴 목록
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 글꼴 기록 하나(엔진 names_info의 fonts[] — 파일은 없고 이름 · 라이선스 · 덮는 범위만).
@immutable
class FontEntry {
  FontEntry({required this.uid, required this.pack, this.id = '', this.family = '', this.license = '', this.scripts = const [], this.ranges = const [], this.note = ''})
    : covers = fontRanges(ranges: ranges, scripts: scripts);

  factory FontEntry.fromJson(Map<String, dynamic> m) {
    List<String> texts(Object? v) => [if (v is List) for (final x in v) if (x is String) x];
    return FontEntry(
      uid: '${m['uid'] ?? ''}',
      pack: (m['pack'] as num?)?.toInt() ?? 0,
      id: '${m['id'] ?? ''}',
      family: '${m['family'] ?? ''}',
      license: '${m['license'] ?? ''}',
      scripts: texts(m['scripts']),
      ranges: texts(m['ranges']),
      note: '${m['note'] ?? ''}',
    );
  }

  final String uid, id, family, license, note;

  /// 자료집 번호(저장소의 packs.id — layout.packs[].id와 같다).
  final int pack;
  final List<String> scripts, ranges;

  /// 덮는 범위(적은 ranges, 없으면 scripts마다의 기본 범위 — 웹 HT.fontRanges).
  final List<GlyphRange> covers;

  /// 화면 글꼴로 고를 수 있나 — 한글 음절 전부를 덮어야(웹 HT.fontHasHangul).
  bool get hangul => coversHangul(covers);
}

@immutable
class NamesInfo {
  const NamesInfo({this.packs = const {}, this.fonts = const []});

  factory NamesInfo.fromJson(Map<String, dynamic> m) => NamesInfo(
    packs: {if (m['packs'] is List) for (final p in m['packs'] as List) if (p is num) p.toInt()},
    fonts: [if (m['fonts'] is List) for (final f in m['fonts'] as List) if (f is Map) FontEntry.fromJson(f.cast<String, dynamic>())],
  );

  /// 이름 목록이 있는 자료집 번호.
  final Set<int> packs;
  final List<FontEntry> fonts;

  /// 필터 '표기' 무리를 보이나 — 켜진 자료집에 이름 목록이나 글꼴이 하나라도 있을 때(웹 `fonts.length || modelHasNames(m)`).
  bool visible(Iterable<int> enabled) {
    final on = enabled.toSet();
    return packs.any(on.contains) || fonts.any((f) => on.contains(f.pack));
  }

  /// 켜진 자료집의 글꼴(목록 차례).
  List<FontEntry> fontsOn(Iterable<int> enabled) {
    final on = enabled.toSet();
    return [for (final f in fonts) if (on.contains(f.pack)) f];
  }

  static NamesInfo of(AppBus bus) {
    final v = bus.slot(slotNamesInfo).value;
    return v is NamesInfo ? v : const NamesInfo();
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  3. 글꼴 팩 싣기
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 자료 처리부에 묻는 길(답의 data).
typedef NamesAsk = Future<Map<String, dynamic>> Function(Map<String, dynamic> query);

/// 앱이 실은 DLC 글꼴. 글꼴은 엔진(Flutter)에 한 번 실으면 내릴 수 없어 앱에 하나다.
class ScriptFonts {
  ScriptFonts._();
  static final instance = ScriptFonts._();

  /// 실은 글꼴(uid) · 싣지 못한 글꼴(uid → 까닭 — 원본 없음 · 파일 꼴 틀림 …).
  final _loaded = <String>{};
  final failed = <String, String>{};

  /// 켜진(실린) 글꼴이 덮는 범위 — 창 표에 더할 것 · 띠 표에 더할 것(그림판이 그릴 수 없는 범위를 뺀 것).
  List<GlyphRange> windowExtra = const [], bandExtra = const [];

  /// 앱을 켤 때 화면 글꼴로 실은 글꼴(uid). 화면 글꼴은 다시 켤 때까지 바뀌지 않는다.
  String? screenUid;

  /// 켜진 글꼴이나 덮는 범위가 바뀔 때마다 오른다 — 상세 창의 이름 · 장면의 왼쪽 칸이 듣는다.
  final revision = ValueNotifier<int>(0);

  /// 브라우저 안 이름과 같은 꼴 — 이름이 같은 글꼴이 여러 DLC에 있어도 섞이지 않게(웹 'HT 글꼴 <팩> <글꼴>').
  static String familyOf(String uid) => 'HT 글꼴 $uid';

  bool isLoaded(String uid) => _loaded.contains(uid);

  /// 글꼴 파일 하나를 싣는다.
  Future<void> load(String uid, Uint8List bytes) async {
    final loader = FontLoader(familyOf(uid))..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loaded.add(uid);
  }

  /// 켜진 글꼴([fonts] — 켜진 자료집의 것)을 싣고(처음 보는 것만 묻는다) 대체 글꼴 목록 · 덮는 범위를 맞춘다. 바뀌었으면 참.
  /// 켜고 끄기가 잇달아도 차례대로 한다(앞의 싣기가 끝난 뒤 — 뒤의 부탁이 이긴다).
  Future<bool> use(List<FontEntry> fonts, NamesAsk ask) {
    final next = _queue.then((_) => _use(fonts, ask), onError: (Object _) => _use(fonts, ask));
    _queue = next;
    return next;
  }

  Future<bool> _queue = Future<bool>.value(false);

  Future<bool> _use(List<FontEntry> fonts, NamesAsk ask) async {
    final need = [for (final f in fonts) if (!_loaded.contains(f.uid) && !failed.containsKey(f.uid)) f.uid];
    for (var i = 0; i < need.length; i += 32) {
      final part = need.sublist(i, i + 32 > need.length ? need.length : i + 32);
      Map<String, dynamic>? answer;
      try {
        answer = await ask({'op': 'font_data', 'uids': part});
      } catch (_) {
        for (final uid in part) {
          failed[uid] = '자료 처리부가 글꼴 파일을 주지 않았습니다';
        }
      }
      if (answer == null) continue;
      for (final one in answer['fonts'] as List? ?? const []) {
        if (one is! Map) continue;
        final uid = '${one['uid'] ?? ''}';
        try {
          await load(uid, base64Decode('${one['data']}'));
        } catch (_) {
          failed[uid] = '글꼴 파일을 읽지 못했습니다';
        }
      }
      for (final one in answer['missing'] as List? ?? const []) {
        if (one is Map) failed['${one['uid']}'] = '${one['why'] ?? '글꼴 파일이 없습니다'}';
      }
      for (final uid in part) {
        if (!_loaded.contains(uid)) failed.putIfAbsent(uid, () => '글꼴 파일이 없습니다');
      }
    }
    return refresh([for (final f in fonts) if (_loaded.contains(f.uid)) f]);
  }

  /// 실린 글꼴 [on]으로 대체 글꼴 목록과 덮는 범위를 맞춘다(실린 글꼴만 — 파일이 없는 글꼴의 범위는 더하지 않는다). 바뀌었으면 참.
  bool refresh(List<FontEntry> on) {
    final extras = packExtras([for (final f in on) f.covers]);
    final families = [for (final f in on) if (f.uid != screenUid) familyOf(f.uid)];
    final fallback = screenUid == null && families.isEmpty ? sceneFontFallback : [if (screenUid != null) sceneFontFamily, ...sceneFontFallback, ...families];
    final same = listEquals(fallback, sceneFallbackNow) && listEquals(extras.window, windowExtra) && listEquals(extras.band, bandExtra);
    if (same) return false;
    sceneFallbackNow = fallback;
    windowExtra = extras.window.isEmpty ? const [] : extras.window;
    bandExtra = extras.band.isEmpty ? const [] : extras.band;
    revision.value++;
    return true;
  }

  /// 검사용: 처음 상태로(실은 글꼴은 Flutter에 남지만 쓰지 않는다).
  @visibleForTesting
  void resetForTest() {
    _loaded.clear();
    failed.clear();
    screenUid = null;
    _queue = Future<bool>.value(false);
    windowExtra = const [];
    bandExtra = const [];
    sceneFamilyNow = sceneFontFamily;
    sceneFallbackNow = sceneFontFallback;
  }
}

/// 기억 파일에서 보는 사람 설정만 먼저 읽는다(자료를 열기 전 — 화면 글꼴을 장면보다 먼저 실으려고). 없으면 기본.
Future<NamesUi> readSavedNamesUi({Directory? folder}) async {
  try {
    final file = File('${(folder ?? await AppMemory.defaultFolder()).path}/${AppMemory.fileName}');
    if (!await file.exists()) return const NamesUi();
    final data = jsonDecode(await file.readAsString());
    final parts = data is Map ? data['parts'] : null;
    return NamesUi.fromJson(parts is Map ? parts[slotNames] : null);
  } catch (_) {
    return const NamesUi();
  }
}

/// 화면 글꼴(결정 5 A의 [글꼴 ▾] — 한글을 덮는 글꼴만): 앱을 켤 때 **장면을 만들기 전에** 한 번 싣고 글꼴 목록 맨 앞에 둔다.
/// 장면의 글 폭 · 그림판 · 이름 자리를 처음부터 그 글꼴로 재게 하려는 것이다(웹은 바로 바꾸고 다시 잰다 — 앱은 다시 켤 때 바뀐다).
/// 고른 글꼴이 없거나 · 찾지 못하거나 · 한글을 덮지 않거나 · 파일을 꺼내지 못하면 아무것도 바꾸지 않는다(지금 화면 그대로). 실었으면 참.
Future<bool> applySavedScreenFont(NamesAsk ask, {NamesUi? saved, Duration limit = const Duration(seconds: 3)}) async {
  final ui = saved ?? await readSavedNamesUi();
  final uid = ui.screen;
  if (uid == null) return false;
  try {
    return await () async {
      final info = NamesInfo.fromJson(await ask({'op': 'names_info'}));
      final font = info.fonts.where((f) => f.uid == uid).firstOrNull;
      if (font == null || !font.hangul) return false;
      final answer = await ask({'op': 'font_data', 'uids': [uid]});
      final one = (answer['fonts'] as List? ?? const []).whereType<Map>().where((f) => f['uid'] == uid).firstOrNull;
      if (one == null) return false;
      final fonts = ScriptFonts.instance;
      await fonts.load(uid, base64Decode('${one['data']}'));
      fonts.screenUid = uid;
      sceneFamilyNow = ScriptFonts.familyOf(uid);
      fonts.refresh([font]);
      return true;
    }().timeout(limit);
  } catch (_) {
    return false;
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  4. 이어 붙이기 — 이름 정보 · 글꼴 · 왼쪽 칸 · 기억
// ────────────────────────────────────────────────────────────────────────────────────────────

class NamesGlue {
  NamesGlue(this.bus);
  final AppBus bus;

  String _packsKey = '';
  int _version = -1, _turn = 0;
  bool _started = false, _disposed = false;
  AppMemory? _memory;

  void start() {
    if (_started) return;
    _started = true;
    bus.scene.addListener(_onScene);
    bus.slot(slotNames).addListener(_apply);
    bus.slot(slotNamesInfo).addListener(_useFonts);
    ScriptFonts.instance.revision.addListener(_apply);
    _onScene();
    _apply();
  }

  void dispose() {
    _disposed = true;
    if (!_started) return;
    _started = false;
    bus.scene.removeListener(_onScene);
    bus.slot(slotNames).removeListener(_apply);
    bus.slot(slotNamesInfo).removeListener(_useFonts);
    bus.slot(slotNames).removeListener(_save);
    ScriptFonts.instance.revision.removeListener(_apply);
  }

  /// 자료집 구성이 바뀌면(DLC 더하기 · 빼기 — 저장소가 바뀜) 이름 정보를 다시 묻고, 켜고 끄기만 바뀌면 켜진 글꼴만 다시 맞춘다.
  void _onScene() {
    final layout = bus.scene.layout;
    if (layout.version == _version) return;
    _version = layout.version;
    final key = [for (final p in layout.packs) '${p.id}:${p.key}'].join(',');
    if (key != _packsKey) {
      _packsKey = key;
      unawaited(_ask());
    } else {
      _useFonts();
    }
  }

  Future<void> _ask() async {
    final turn = ++_turn;
    var info = const NamesInfo();
    try {
      info = NamesInfo.fromJson(await bus.ask({'op': 'names_info'}));
    } catch (_) {
      // 이 조회를 모르는 옛 자료 처리부 — 이름 목록 · 글꼴이 없는 것과 같다(무리가 숨고 화면은 그대로).
    }
    if (_disposed || turn != _turn) return;
    bus.slot(slotNamesInfo).value = info;
  }

  void _useFonts() {
    if (_disposed) return;
    final info = NamesInfo.of(bus);
    unawaited(ScriptFonts.instance.use(info.fontsOn(bus.scene.layout.enabledPacks), bus.ask));
  }

  /// 표기 설정 · 켜진 글꼴이 바뀌면 장면의 왼쪽 칸 값을 맞추고 다시 그리게 한다.
  void _apply() {
    if (_disposed) return;
    final ui = NamesUi.of(bus);
    final names = SceneNames.of(bus.scene);
    final extra = ScriptFonts.instance.bandExtra;
    if (names.origBand == ui.band && identical(names.bandExtra, extra)) return;
    names
      ..origBand = ui.band
      ..bandExtra = extra
      ..version += 1;
    bus.scene.requestFrame();
  }

  /// 기억을 붙인다: 적어 둔 설정이 있으면 싣고, 그다음부터 바뀔 때만 적는다(고르기 전에는 열쇠가 없다).
  void attachMemory(AppMemory memory) {
    _memory = memory;
    final saved = memory.parts[slotNames];
    if (saved != null) bus.slot(slotNames).value = NamesUi.fromJson(saved);
    bus.slot(slotNames).addListener(_save);
  }

  void _save() {
    final memory = _memory, ui = bus.slot(slotNames).value;
    if (memory == null || ui is! NamesUi) return;
    memory.parts[slotNames] = ui.toJson();
    memory.save();
  }

  /// 필터 시트가 설정을 바꿀 때. 화면 글꼴이 바뀌면 다시 켤 때 바뀐다고 알린다.
  static void set(AppBus bus, NamesUi next) {
    final before = NamesUi.of(bus);
    if (before == next) return;
    bus.slot(slotNames).value = next;
    if (before.screen != next.screen) {
      bus.slot(slotNotice).value = next.screen == null ? '화면 글꼴을 기본으로 — 앱을 다시 켜면 바뀝니다' : '화면 글꼴을 골랐습니다 — 앱을 다시 켜면 바뀝니다';
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  5. 상세 창의 이름
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 미리 푼 이름 하나(`{text, lang?, langName?, kind?, when?, note?, mw?}`).
@immutable
class NameItem {
  const NameItem(this.text, {this.lang = '', this.langName = '', this.kind = '', this.when = '', this.note = '', this.mw = const []});

  static NameItem? of(Object? v) {
    if (v is! Map) return null;
    String s(String k) => v[k] is String ? v[k] as String : '';
    final text = s('text');
    if (text.isEmpty) return null;
    return NameItem(text, lang: s('lang'), langName: s('langName'), kind: s('kind'), when: s('when'), note: s('note'), mw: codePoints(v['mw']));
  }

  final String text, lang, langName, kind, when, note;

  /// 내장 창 표에 없는 글자(내보내기가 실은 것).
  final List<int> mw;

  /// 올렸을 때의 풍선 — 종류 · 언어 이름 · 쓴 기간 · 메모(웹 nameTip).
  String get tip => [kind, langName, when, note].where((x) => x.isNotEmpty).join(' · ');

  /// 켜진 글꼴로도 그릴 수 없는 글자(비면 그린다).
  List<int> missing(List<GlyphRange> windowExtra) => stillMissing(mw, windowExtra);
}

/// 머리의 셋(내보내기 x_nameHead · x_cellNameHead · 지명 줄 head · x_surnameHead).
@immutable
class NameHead {
  const NameHead({this.first, this.second, this.rest = const []});

  static NameHead? of(Object? v) {
    if (v is! Map) return null;
    return NameHead(
      first: NameItem.of(v['first']),
      second: NameItem.of(v['second']),
      rest: [if (v['rest'] is List) for (final x in v['rest'] as List) ?NameItem.of(x)],
    );
  }

  final NameItem? first, second;
  final List<NameItem> rest;
}

/// 상세 창 이름의 공용 모양.
abstract final class NamesLook {
  /// 머리 첫 줄(원어): 19px · 400 · 줄높이 1.35 · 글자 사이 .01em · `--text-2` (css `.detail .names-orig`).
  static TextStyle get orig =>
      TextStyle(fontFamily: sceneFamilyNow, fontSize: 19, fontWeight: FontWeight.w400, height: 1.35, letterSpacing: .19, color: Ui.text2, fontFamilyFallback: sceneFallbackNow);

  /// 머리 둘째 줄(로마자): 13px · 줄높이 1.4 · `--text-2` (글자 사이는 몸통의 −.01em).
  static TextStyle get roman => TextStyle(fontSize: 13, height: 1.4, letterSpacing: -.13, color: Ui.text2, fontFamilyFallback: sceneFallbackNow);

  /// '다른 이름' 칸: 종류 11.5 옅은 글 · 이름 14.5/600 · 쓴 기간 11.5 옅은 글.
  static const restKind = TextStyle(fontSize: 11.5, height: 1.5, color: Ui.text3);
  static TextStyle get restName => TextStyle(fontSize: 14.5, height: 1.5, fontWeight: FontWeight.w600, color: Ui.text, fontFamilyFallback: sceneFallbackNow);
  static const restWhen = TextStyle(fontSize: 11.5, height: 1.5, color: Ui.text3);

  /// 딸린 한 줄(`.aka`): 12px · `--text-3` · 안의 `<small>`은 10px.
  static TextStyle get line => TextStyle(fontSize: 12, height: 1.5, color: Ui.text3, fontFamilyFallback: sceneFallbackNow);
  static const lineSmall = 10.0;

  /// '글꼴 없음' 딱지: 12px · 400 · 둥근 4 · 채움 없이 ink20의 1px 선 · `--text-3`.
  static const chip = TextStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w400, letterSpacing: 0, color: Ui.text3);
}

/// 이름 글(방향을 가둔 글 — 표준 꼬리표면 그 언어로).
Widget _nameText(NameItem n, TextStyle style) {
  final body = Text(detailIsolate(n.text), style: style, locale: detailLocaleOf(n.lang));
  return n.tip.isEmpty ? body : Tooltip(message: n.tip, child: body);
}

/// 그릴 수 없는 이름의 딱지: "원어 — 가상 문자 · 글꼴 없음"(올리면 까닭).
class NamesNoFontChip extends StatelessWidget {
  const NamesNoFontChip({super.key, required this.what, required this.missing});
  final String what;
  final List<int> missing;

  String get label => '$what — ${missingScriptName(missing)} · 글꼴 없음';

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '이 $what의 문자가 화면 글꼴에 없습니다 — 글꼴 팩을 넣으면 보입니다',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(Ui.innerRadius), border: Border.all(color: Ui.line)),
      child: Text(label, style: NamesLook.chip, maxLines: 1, softWrap: false),
    ),
  );
}

/// 이름 하나 — 그릴 수 있으면 글, 없으면 딱지.
Widget _nameOrChip(NameItem n, TextStyle style, String what) {
  final missing = n.missing(ScriptFonts.instance.windowExtra);
  return missing.isEmpty ? _nameText(n, style) : NamesNoFontChip(what: what, missing: missing);
}

/// 설정 · 켜진 글꼴이 바뀌면 다시 그린다.
class _NamesListen extends StatelessWidget {
  const _NamesListen({required this.bus, required this.builder});
  final AppBus bus;
  final Widget Function(NamesUi ui) builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([bus.slot(slotNames), ScriptFonts.instance.revision]),
    builder: (context, _) => builder(NamesUi.of(bus)),
  );
}

/// 상세 창 머리 — 제목 바로 아래 두 줄(감독 결정 D2-1 A · 언어 · 종류 딱지 없음).
/// [head]는 미리 푼 머리(x_nameHead 꼴), [old]는 그 열쇠가 없는 옛 저장소의 x_names(F1 꼴 — 예전 줄로 그린다).
/// 이름이 없거나 표기 설정으로 숨기면 아무것도 그리지 않는다(자리도 없음 — 지금 모습 그대로).
class NamesHead extends StatelessWidget {
  const NamesHead({super.key, required this.bus, this.head, this.old, this.kind});
  final AppBus bus;
  final Object? head, old;
  final NameKind? kind;

  @override
  Widget build(BuildContext context) => _NamesListen(bus: bus, builder: _build);

  Widget _build(NamesUi ui) {
    if (!ui.shown(kind)) return const SizedBox.shrink();
    final h = NameHead.of(head);
    if (h == null) {
      final lines = DetailNamesLine(old);
      return lines.isEmpty ? const SizedBox.shrink() : lines;
    }
    final extra = ScriptFonts.instance.windowExtra;
    final first = h.first, second = h.second;
    final firstOk = first != null && first.missing(extra).isEmpty;
    final showSecond = second != null && second.missing(extra).isEmpty; // 둘째 줄 글을 그릴 수 없으면 그 줄을 뺀다
    if (first == null && !showSecond) return const SizedBox.shrink();
    // 첫 줄이 그려진 원어면 css의 위 −1px(제목 아래 4px와 겹쳐 3px)을 그림만 1px 올리고 아래 여백을 1px 줄여 맞춘다.
    final lift = firstOk;
    final lines = <Widget>[
      if (first != null)
        Padding(
          padding: EdgeInsets.only(bottom: (showSecond ? 3 : 9) - (lift && !showSecond ? 1 : 0)),
          child: Align(
            alignment: Alignment.centerLeft,
            child: firstOk ? _nameText(first, NamesLook.orig) : NamesNoFontChip(what: '원어', missing: first.missing(extra)),
          ),
        ),
      if (showSecond)
        Padding(
          padding: EdgeInsets.only(bottom: lift ? 8 : 9),
          child: Align(alignment: Alignment.centerLeft, child: _nameText(second, NamesLook.roman)),
        ),
    ];
    final column = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: lines);
    return lift ? Transform.translate(offset: const Offset(0, -1), child: column) : column;
  }
}

/// '다른 이름 n개' 칸 — 설명 바로 위(머리 두 줄에 오르지 않은 이름만 · 종류 · 글 · 쓴 기간 · 메모).
class NamesRest extends StatelessWidget {
  const NamesRest({super.key, required this.bus, this.head, this.kind});
  final AppBus bus;
  final Object? head;
  final NameKind? kind;

  @override
  Widget build(BuildContext context) => _NamesListen(bus: bus, builder: _build);

  Widget _build(NamesUi ui) {
    final h = NameHead.of(head);
    if (!ui.shown(kind) || h == null || h.rest.isEmpty) return const SizedBox.shrink();
    final rows = h.rest;
    // [종류][이름 — 그 아래 메모][쓴 기간]. 예전에는 '기간 · 메모'를 한 글로 셋째 칸(제 폭 그대로)에 두어, 메모가 길면 그 칸이
    // 창 폭을 다 가져가고 이름 칸(나머지 폭)이 0이 되어 이름이 한 글자씩 세로로 섰다(감독 건의 2026-10-14 4번 — 高/麗 · 고/려).
    // 이제 메모는 이름 아래 작은 글로 흐르고, 기간 칸은 제 폭이되 창의 40%를 넘지 않는다(넘으면 그 안에서 줄을 바꾼다).
    TableRow rowOf(int i, NameItem n) {
      final gap = EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : 6);
      return TableRow(
        children: [
          Padding(padding: gap.copyWith(right: 12), child: Text(n.kind, style: NamesLook.restKind, softWrap: false)),
          Padding(
            padding: gap.copyWith(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _nameOrChip(n, NamesLook.restName, '이름'),
                if (n.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(n.note, style: NamesLook.restWhen)),
              ],
            ),
          ),
          Padding(padding: gap, child: Text(n.when, style: NamesLook.restWhen, textAlign: TextAlign.right)),
        ],
      );
    }

    // 바로 아래 설명(명조 15px)과 붙지 않게 칸 아래 14px(웹 `.names-rest`의 margin-bottom — 접혀도 같다).
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DetailBox(
        title: '다른 이름',
        small: '${rows.length}',
        children: [
          Table(
            columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth(), 2: MinColumnWidth(IntrinsicColumnWidth(), FractionColumnWidth(.4))},
            defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [for (final (i, n) in rows.indexed) rowOf(i, n)],
          ),
        ],
      ),
    );
  }
}

/// 딸린 한 줄(지명 · 성씨 — 웹 namesLineHTML): "[lead] 원어 · 로마자 · 다른 이름 글 (종류 · 기간 · 메모) · …"(다른 이름은 작은 글).
/// 머리의 두 이름도 그릴 수 없으면 '이름 — ○○ · 글꼴 없음' 딱지. 이 줄에도 언어 · 종류 딱지는 없다(풍선에만).
class NamesLine extends StatelessWidget {
  const NamesLine({super.key, required this.bus, required this.lead, this.head, this.old, this.kind, this.oldLead});
  final AppBus bus;

  /// 줄 앞의 말(`성 바다 — ` · `지명 바닷골 <small>(위 구역)에 속함</small> — `).
  final List<DetailBit> lead;
  final Object? head;

  /// 미리 푼 머리가 없는 옛 저장소의 이름 줄(x_names 꼴)과 그때의 앞말 — [DetailNamesLine]으로 예전처럼.
  final Object? old;
  final List<DetailBit>? oldLead;
  final NameKind? kind;

  /// 그 줄이 서는가(설정 · 자료) — 지명 줄이 '이름 없는 지명'과 같게 물러날지 정할 때.
  static bool stands(NamesUi ui, NameKind? kind, Object? head, Object? old) {
    if (!ui.shown(kind)) return false;
    final h = NameHead.of(head);
    if (h != null) return h.first != null || h.second != null || h.rest.isNotEmpty;
    return !DetailNamesLine(old).isEmpty;
  }

  @override
  Widget build(BuildContext context) => _NamesListen(bus: bus, builder: _build);

  Widget _build(NamesUi ui) {
    if (!stands(ui, kind, head, old)) return const SizedBox.shrink();
    final h = NameHead.of(head);
    if (h == null) return DetailNamesLine(old, lead: oldLead ?? lead);
    final base = NamesLook.line;
    final small = base.copyWith(fontSize: NamesLook.lineSmall);
    InlineSpan bit(DetailBit b) => TextSpan(text: b.text, style: b.kind == DetailBitKind.small ? small : null);
    InlineSpan name(NameItem n, TextStyle style) =>
        WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: _nameOrChip(n, style, '이름'));
    final heads = [?h.first, ?h.second];
    final spans = <InlineSpan>[
      for (final b in lead) bit(b),
      for (final (i, n) in heads.indexed) ...[if (i > 0) const TextSpan(text: ' · '), name(n, base)],
      if (h.rest.isNotEmpty) ...[
        TextSpan(text: '${heads.isNotEmpty ? ' · ' : ''}다른 이름 ', style: small),
        for (final (i, n) in h.rest.indexed) ...[
          if (i > 0) TextSpan(text: ' · ', style: small),
          name(n, small),
          if ([n.kind, n.when, n.note].any((x) => x.isNotEmpty)) TextSpan(text: ' (${[n.kind, n.when, n.note].where((x) => x.isNotEmpty).join(' · ')})', style: small),
        ],
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(TextSpan(children: spans), style: base),
    );
  }
}

/// 지명 줄(사건 '장소' · 도읍 칸 '지명' — 웹 placeHTML(ref, lead)): 이름 · 바로 위 구역 · 원어.
/// 표기 설정으로 숨긴 지명(또는 이름 목록이 없는 지명)은 위 구역이 있거나 앞말이 '지명'이 아닐 때만 이름 줄 하나로 선다.
class NamesPlace extends StatelessWidget {
  const NamesPlace({super.key, required this.bus, required this.place, required this.lead});
  final AppBus bus;

  /// 지명 줄(`{name, uid?, up?, names?, head?}` — x_place · x_cellPlaces의 값).
  final Object? place;
  final String lead;

  @override
  Widget build(BuildContext context) => _NamesListen(bus: bus, builder: _build);

  Widget _build(NamesUi ui) {
    final p = place is Map ? (place as Map).cast<String, dynamic>() : null;
    final name = p == null ? '' : '${p['name'] ?? ''}';
    if (p == null || name.isEmpty) return const SizedBox.shrink();
    final up = DetailPlaceLine.upOf(p);
    final head = [
      DetailBit('$lead $name'),
      if (up.isNotEmpty) ...[const DetailBit(' '), DetailBit.small('$up에 속함')],
    ];
    if (NamesLine.stands(ui, NameKind.place, p['head'], p['names'])) {
      return NamesLine(bus: bus, lead: [...head, const DetailBit(' — ')], head: p['head'], old: p['names'], kind: NameKind.place);
    }
    return up.isNotEmpty || lead != '지명' ? DetailLine(head) : const SizedBox.shrink();
  }
}
