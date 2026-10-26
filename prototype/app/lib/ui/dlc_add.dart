import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../scene/layout.dart' show SceneLayout;
import '../scene/scene.dart';
import 'dlc_layout_import.dart';

// DLC 더하기 · 빼기 · 끄기 · 켜기의 뒷일(4단계 1걸음 — `docs/설계-아카이브-4단계-1걸음-DLC-앱-안에서.md` 3-3절 · A2 — `docs/설계-10건/A-아카이브-이음.md` 5절 ·
// 계획 한 벌 P4 과제 8 — 계약 2-7 `apply`).
//
// 길은 하나다 — **엔진이 제자리에서 고쳐 쓴다**([DlcJob.apply] · 휴대폰과 컴퓨터가 같다 · 계획 P4 과제 10b · 11c · 계약 2-7-1): 저장소를 바꿔 넣지 않고
// 엔진이 바뀐 트랙만 한 거래로 고쳐 쓴다(실패하면 저장소 그대로 · 쓰는 동안에도 화면은 옛 답으로 끌린다 · 앱은 엔진을 닫았다 다시 열지 않는다).
// 엔진은 앱 틀이 따로 된 일꾼(isolate)에서 부른다([DlcJob.applier] — `ArchiveEngine.write`). 넣기 = `{"op":"add_pack","files"}`(DLC 파일 .htpack
// 형식 1 ~ 4 · .json — 경로 여럿이면 한 번) · 지우기 = `{"op":"remove_pack","delete":true}` · 끄기 = `{"op":"remove_pack","delete":false}`(원본은 저장소의
// 보관함) · 켜기 = `{"op":"add_pack","ids"}`(보관함에서 — 없으면 DLC 폴더의 그 파일). 배치는 엔진이 셈한다(Rust — Node 없음). 고쳐 쓰기가 **끝난 뒤에만**
// DLC/ 폴더(새 파일 · 같은 id 다른 파일 · 지운 DLC)와 끈 목록(`DLC/hidden.json` — [DlcHidden])을 맞춘다(실패면 둘 다 그대로). 엔진 거절은 `code`로 갈라
// 쉬운 말로 알린다([dlcRefusalText]). 메이커 미리보기는 `add_pack`의 `prefer_given`(서재의 임시 사본 위에 · 같은 id면 판과 상관없이 작업본이 이김 — 판정 R39).
// 엔진이 빼지 못하는 바탕(저장소의 첫 DLC)과 원본 없이 든 DLC의 끄기는 화면에서만([DlcRoute.screen] — 판정 R43).
// 예전의 Node 길(`add-dlc.mjs`로 다시 짓기 · 배치만 셈하기)과 아카이브 배치 파일(.htlayout) 받기는 걷었다(계획 P4 과제 11c) — .htlayout을 고르면 쉬운 알림
// ([dlcOldLayoutText])만. 예전 배치로만 든 DLC(원본 없음)는 그 DLC의 .htpack을 더하면 엔진이 원본을 채우고, 표 없는 옛 저장소라 받지 못하면 그 파일을
// DLC 폴더에 두어 시드 잇기(`ui/seed_carry.dart` — 판정 R34 D)가 새 판 자료로 함께 옮기게 한다([DlcJob._stashOriginals]).
// 휴대폰(계획 한 벌 P4 과제 10a · 10b): 고르기 창은 `MainActivity.kt`의 `MethodChannel('ht/files')`([pickDlcFilesAndroid] — 돌아오지 않으면 제한 시간
// [dlcPickTimeout]) · 그 밖은 컴퓨터와 같은 엔진 길.

/// 이 자리의 DLC 길 — 넣기 · 빼기 · 끄기 · 켜기는 어디서나 엔진 하나로 된다(Node 없음 — 계획 P4 과제 11c). 휴대폰인지([phone] — 알림 글)와
/// 배포 폴더의 엔진 도구(`<실행 파일 폴더>/../도구/prototype/archive-tool(.exe)` — Rust · 시드 잇기의 원본 꺼내기 · 판 올림 뒤 DLC 폴더 다시 들이기(판정 R32)가
/// 쓴다)만 가린다.
class DlcTools {
  const DlcTools({this.archiveTool = '', this.phone = false});

  /// 엔진 도구(`archive-tool` — 저장소의 DLC 목록 · 원본 꺼내기 · DLC 폴더 파일 읽기). 없으면 빈 글.
  final String archiveTool;

  /// 휴대폰(안드로이드 · iOS)의 길인가 — 할 수 없는 일의 알림을 휴대폰의 말로 적는다.
  final bool phone;

  /// 도구가 없는 컴퓨터(개발 빌드 · 검사)의 길 — 넣기 · 빼기 · 끄기 · 켜기는 그대로 되고, 엔진 도구가 쓰는 일(판 올림 뒤 다시 들이기)만 하지 않는다.
  static const engineOnly = DlcTools();

  /// 휴대폰의 길 — 엔진 도구 없이 자료 처리부(FFI)로만.
  static const phoneOnly = DlcTools(phone: true);

  /// 늘 무엇인가를 돌려준다(도구가 없으면 [engineOnly]) — 앱 틀은 null이면 단추를 세우지 않는다(측정 모드만 null을 쓴다).
  static DlcTools? find() => _found ??= _look();
  static DlcTools? _found;

  static DlcTools _look() {
    if (Platform.isAndroid || Platform.isIOS) return phoneOnly;
    try {
      final sep = Platform.pathSeparator;
      final prototype = '${File(Platform.resolvedExecutable).parent.parent.path}$sep도구${sep}prototype';
      final name = 'archive-tool${Platform.isWindows ? '.exe' : ''}';
      // 배포 폴더(`도구/prototype/` — collect-app.mjs가 꾸린다), 없으면 그 아래 빌드 폴더(개발 자리를 이어 둔 때).
      for (final dir in [prototype, '$prototype${sep}engine${sep}target${sep}release']) {
        final file = '$dir$sep$name';
        if (File(file).existsSync()) return DlcTools(archiveTool: file);
      }
      return engineOnly;
    } catch (_) {
      return engineOnly;
    }
  }
}

/// 파일 고르기 창의 거르개 — DLC 파일(.htpack · 여러 개). Windows는 PowerShell의 창, Linux는 zenity · kdialog(있으면),
/// Android는 시스템 고르기 창([pickDlcFilesAndroid]). 다른 부품을 더하지 않으려고 운영체제의 창을 쓴다. 취소하거나 창이 없으면 빈 목록 —
/// 창을 열지 못했거나 고른 파일을 옮기지 못했으면 [onError]로 까닭을 말한다(Android).
Future<List<String>> pickDlcFiles({void Function(String why)? onError}) async {
  if (Platform.isAndroid) return pickDlcFilesAndroid(onError: onError);
  if (Platform.isWindows) return _pickWindows();
  if (Platform.isLinux) return _pickLinux();
  return const [];
}

/// 휴대폰의 고르기 창 채널(`android/…/MainActivity.kt` — 계획 P4 정한 것 #10: 새 플러그인 없이).
const dlcFilesChannel = MethodChannel('ht/files');

/// 안드로이드의 고르기 창 — `pick`이 시스템 창(ACTION_OPEN_DOCUMENT · 여러 개)을 띄우고, 고른 파일을 앱 캐시 폴더 `dlc-in/`에 복사해 그 경로를 준다
/// (엔진은 진짜 파일 경로로 읽는다 — content:// 주소는 못 연다 · 캐시 폴더는 다음 고르기에서 비운다 · 넣은 뒤 원본은 저장소와 DLC 폴더에 있다).
/// 취소하면 빈 목록. 창을 못 열거나 복사하지 못하면 [onError]로 까닭을 말하고 빈 목록 · 채널이 없으면(옛 실행본 · 검사) 빈 목록.
/// 답은 `{"paths":[…],"skipped":[파일 이름…]}`(복사하기 전에 거른 파일 — 팩 한도 64MB를 넘거나 DLC 이름이 아닌 큰 파일 · 예전 배치 파일 .htlayout) — 거른
/// 것이 있으면 [onError]로 그 까닭을 말한다(.htlayout은 [dlcOldLayoutText] — 계획 P4 과제 11c). 경로 목록만 오는 꼴도 받는다.
/// 창이 [timeout] 안에 돌아오지 않으면(안드로이드가 앱 화면을 다시 만들어 답이 사라짐 · 클라우드 파일 옮기기가 멈춤 — 10a 검토 N3) 기다리기를 멈추고
/// 까닭을 말한다(빈 목록 — 고르는 동안 잡아 둔 DLC 일이 풀린다 · 늦게 온 답은 버린다). `MainActivity.kt`도 그보다 오래된 고르기는 다음 `pick`에서 버린다.
Future<List<String>> pickDlcFilesAndroid({void Function(String why)? onError, Duration timeout = dlcPickTimeout}) async {
  try {
    final answer = await dlcFilesChannel.invokeMethod<Object?>('pick').timeout(timeout);
    final paths = answer is Map ? answer['paths'] : answer;
    final skipped = answer is Map && answer['skipped'] is List ? [for (final n in answer['skipped'] as List) '$n'] : const <String>[];
    final layouts = [for (final n in skipped) if (n.toLowerCase().endsWith('.htlayout')) n];
    final others = [for (final n in skipped) if (!layouts.contains(n)) n];
    for (final name in layouts) {
      onError?.call(dlcOldLayoutText(name));
    }
    if (others.isNotEmpty) {
      onError?.call('${others.join(' · ')}은(는) DLC 파일이 아니거나 너무 커서(팩은 64MB까지) 옮기지 않았습니다.');
    }
    return [for (final path in paths is List ? paths : const []) if ('$path'.isNotEmpty) '$path'];
  } on TimeoutException {
    onError?.call(dlcPickTimeoutText);
    return const [];
  } on PlatformException catch (e) {
    onError?.call(e.message ?? e.code);
    return const [];
  } on MissingPluginException {
    return const [];
  }
}

/// 고르기 창을 기다리는 한도(10a 검토 N3) — 고르고 앱 안으로 옮기기(클라우드 파일)까지. `MainActivity.kt`의 `STALE_MS`(9분)보다 길다: 이 한도로
/// 멈춘 뒤 다시 고르면 안드로이드 쪽은 남은 옛 고르기를 버리고 새 창을 연다.
const dlcPickTimeout = Duration(minutes: 10);

/// 고르기 창이 한도 안에 돌아오지 않았을 때의 알림.
const dlcPickTimeoutText = '파일 고르기 창이 돌아오지 않아 기다리기를 멈췄습니다 — 다시 골라 주세요.';

/// 고르는 동안 창 위 칸의 말 — 휴대폰은 창이 닫힌 뒤 고른 파일을 앱 안으로 복사한다(클라우드 파일이면 몇 초).
String get dlcPickingLine => Platform.isAndroid ? '고른 파일을 앱 안으로 옮기는 중…' : '파일을 고르는 중…';

/// DLC 관리 창의 '파일에서 더하기'(앱 틀이 단다): 고르기 창([pick] — 없으면 [pickDlcFiles]) → 고른 것이 있으면 [add](앱 틀의 더하기 — 한 번).
/// 취소(빈 목록)면 아무것도 하지 않는다. [job]이 있으면 고르고 옮기는 동안 잡아 두고([holding]의 말 — 도는 중이면 아무것도 하지 않음) 끝나면 풀어
/// 두 번째 고르기가 앞의 결과를 지우지 못하게 한다(8 검토 2회차 — 휴대폰은 고를 때마다 캐시 폴더를 비운다). 고르기의 까닭(못 엶 · 거른 파일)은 푼 뒤에
/// [job]의 알림으로 남긴다.
Future<void> pickAndAddDlc(
  Future<void> Function(List<String> files) add, {
  Future<List<String>> Function(void Function(String why) onError)? pick,
  DlcJob? job,
  String? holding,
}) async {
  if (job != null && !job.hold(holding ?? dlcPickingLine)) return;
  final why = <String>[];
  final List<String> files;
  try {
    files = await (pick ?? ((onError) => pickDlcFiles(onError: onError)))(why.add);
  } finally {
    job?.release();
  }
  // 알림은 더하기가 끝난 뒤에(덧붙임 N1) — 더하기는 새 일이라 시작하며 알림을 비운다(쓸 파일이 하나라도 섞이면 거른 파일 알림이 사라졌다).
  try {
    if (files.isNotEmpty) await add(files);
  } finally {
    for (final line in why) {
      job?.notice(line);
    }
  }
}

/// DLC 일 하나가 갈 길([dlcRoute]).
enum DlcRoute {
  /// 엔진 하나로 제자리에서(add_pack · remove_pack — 휴대폰 · 컴퓨터 모두).
  engine,

  /// 화면에서만 켜고 끈다(저장소 그대로 — 엔진이 빼지 못하는 바탕 DLC · 원본 없이 든 DLC를 끌 때 · 끈 목록에 기억).
  screen,

  /// 이 자리에서는 할 수 없다(까닭은 [dlcRouteRefusal]).
  none,
}

/// 이 일이 갈 길(계획 P4 과제 10b · 판정 R43). [packKeys]는 지금 저장소의 DLC 글자 id(첫째가 바탕 — 엔진은 바탕을 빼지 못한다: 계약 2-7-1),
/// [baseKey]는 동아시아 기본팩.
///   · 메이커 미리보기 → 엔진(add_pack `prefer_given` — 서재의 임시 사본 위에 · 같은 id면 판과 상관없이 작업본이 이김 · 판정 R39).
///   · DLC 파일 더하기 → 엔진(add_pack) — 기본팩을 빼거나 꺼서 지은 옛 서재에도(그 파일이 기본팩이면 첫째가 아니라 뒤에 붙는다).
///   · 빼기 · 끄기 · 켜기 → 바탕(첫 DLC)이나 옛 판에서 뺀 기본팩(`hidden.baseRemoved`)을 건드리지 않으면 엔진(remove_pack · add_pack). 건드리면 끄기 ·
///     켜기는 화면에서만(저장소에 든 것만), 빼기 · 뺀 기본팩 켜기는 못 함. 동아시아 id라도 바탕이 아니면 보통 DLC다(판정 R60 I-1 — 등불 바탕 저장소).
DlcRoute dlcRoute({
  required List<String> packKeys,
  required DlcHidden hidden,
  required String baseKey,
  String? removeKey,
  List<String> offKeys = const [],
  List<String> onKeys = const [],
  bool preview = false,
}) {
  if (preview) return DlcRoute.engine;
  // 저장소에 없는 동아시아 기본팩이 '못 켜는 바탕'인 것은 옛 판의 다시 짓기 길에서 뺐을 때뿐(baseRemoved) — 끈 목록에만 있으면 꺼 둔(보관함) 보통 DLC다
  // (등불 바탕 저장소에 넣은 동아시아 DLC — 판정 R60 I-1).
  final baseAway = !packKeys.contains(baseKey) && hidden.baseRemoved;
  final keys = [?removeKey, ...offKeys, ...onKeys];
  if (packKeys.isEmpty) return DlcRoute.none;
  if (keys.isEmpty) return DlcRoute.engine;
  bool bound(String key) => key == packKeys.first || (key == baseKey && baseAway);
  if (!keys.any(bound)) return DlcRoute.engine;
  if (removeKey != null || onKeys.any((k) => !packKeys.contains(k))) return DlcRoute.none;
  return DlcRoute.screen;
}

/// [DlcRoute.none]의 까닭(알림 글).
String dlcRouteRefusal({String? removeKey}) {
  if (removeKey != null) return '바탕 DLC(저장소의 첫 DLC)는 뺄 수 없습니다 — 끄면 화면에서 가려집니다.';
  return "예전 판에서 뺀 기본팩은 켤 수 없습니다 — 기본팩 파일을 '파일에서 더하기'로 넣어 주세요.";
}

/// 바탕 DLC를 화면에서만 켜고 끌 때의 알림(DLC 관리 창의 위 칸 — [DlcRoute.screen]).
const dlcScreenOnlyNote = '바탕 DLC(저장소의 첫 DLC)는 저장소에서 빼지 못해 화면에서만 켜고 끕니다 — 꺼도 날짜 칸의 시대 · 판 · 렌즈에는 남을 수 있습니다'
    '(끈 것은 앱을 다시 켜도 꺼진 채).';

/// 그 파일 탓의 거절인가(DLC code — 배치 못 함 · 날짜가 달력 범위 밖 · 낮은 판 · 같은 항목이 두 트랙 · 원본을 읽지 못함): 판 올림 뒤 다시 들이기(R32)는
/// 이때만 그 파일을 지문으로 기억해 '다시 해 보지 않음'(파일이나 앱 판이 바뀌면 다시)으로 적는다(판정 R68-3). code 없음(환경 탓) · `path` · `calendar` ·
/// `original` · `base` · `committed`는 그 파일 탓이 아니라 기억하지 않고 다음 열기에서 다시 해 본다.
bool dlcFileFault(String? code) => const {'layout', 'range', 'version', 'dup_uid', 'broken'}.contains(code);

/// 원본 없이 든 DLC(예전 메이커 배치로만 넣은 것) [name]을 화면에서만 끌 때의 알림(고침 1회차 I-1 — 엔진이 빼면 남길 원본이 없어 지워진다 · 어느 DLC인지 — ② Minor 7).
String dlcNoOriginalOffText(String name) =>
    "«$name»은(는) 원본(.htpack)이 없어 화면에서만 끕니다 — 그 DLC의 .htpack을 '파일에서 더하기'로 넣어 원본을 채우면 저장소에서 끌 수 있습니다.";

/// 켜고 끄기가 실패했을 때 앱 틀이 화면을 되돌리는가([ok]가 거짓이고 그사이 뼈대를 다시 읽지 않았을 때만 — [reloaded]면 앞 걸음이 저장소를 고쳐 써 새 뼈대를
/// 읽었으니 옛 자료집 번호를 새 뼈대에 씌우지 않는다 · 고침 1회차 Minor).
bool dlcToggleShouldRestore({required bool ok, required bool reloaded}) => !ok && !reloaded;

/// 열린 저장소가 아닌 곳에 쓰라는 거절(갈래 1 — 요청의 `path`가 엔진이 연 저장소와 다름)의 알림(② Minor 4).
const _pathRefusal = '앱이 연 저장소가 그새 바뀌어 이 일을 하지 않았습니다 — 다시 해 주세요(그래도 안 되면 앱을 다시 켜 주세요).';

/// 휴대폰이 지금 저장소를 지키기로 정한 시드 판의 표식(`<저장소>.seed-kept` — 판정 R34 A): 시드 잇기([SeedCarry] — `ui/seed_carry.dart`)가 적고 지우며,
/// 원본 없는 DLC의 .htpack을 DLC 폴더에 둘 때([DlcJob]) 지워 다음에 켤 때 다시 해 보게 한다. 이름을 한 곳에 둔다(11c 검토).
String seedKeptPath(String db) => '$db.seed-kept';

/// 원본 없이 든 DLC의 원본을 DLC 폴더에 둘 이름(`<id>-v<판>.htpack` — 메이커의 파일 이름 · 시드 잇기가 이 이름을 먼저 찾는다).
String dlcOriginalFileName(String id, String version) {
  String safe(String s) => s.replaceAll(RegExp(r'[^\w.-]'), '_');
  return '${safe(id)}-v${version.isEmpty ? '0' : safe(version)}.htpack';
}

/// 엔진 거절(`archive_call`의 `{"ok":false,"error","code"[,"detail"]}` — 계약 2-7 · 2-7-1)을 사람의 말로(계획 P4 과제 10b — 앱은 글이 아니라 `code`로 가른다).
/// 어느 DLC의 무엇인지는 엔진의 사람 글(`error` — [error])이 말하므로 까닭 뒤에 '(자세히: …)'로 덧붙인다(걷은 길 · 속말은 바꿔서 — [dlcPlainEngineError]).
/// 엔진의 개발자 말(`detail`)은 싣지 않는다(일에 보관 — [DlcJob.lastDetail]). [removing]이면 빼기 · 끄기(`remove_pack`)의 말('빼지 않았습니다' — 남는
/// 조합의 사정이라 겹친 · 범위 밖 DLC를 먼저 빼라고 · 판정 R37), [turningOn]이면 켜기(보관함 · DLC 폴더에서 `add_pack`)의 말('켜지 않았습니다').
String dlcRefusalText(String? code, String error, {bool removing = false, bool turningOn = false}) {
  final which = error.trim().isEmpty ? '' : ' (자세히: ${dlcPlainEngineError(error)})';
  final not = turningOn ? '켜지' : (removing ? '빼지' : '넣지');
  return switch (code) {
    'version' => '지금 든(꺼 둔 것 포함) 것보다 낮은 판이라 $not 않았습니다 — 같거나 더 높은 판의 DLC 파일을 골라 주세요.$which',
    'original' => "원본 파일(.htpack) 없이 예전 메이커 배치로만 넣은 DLC가 있어 지금은 넣거나 뺄 수 없습니다 — 그 DLC의 .htpack을 '파일에서 더하기'로 "
        '함께 골라 넣어 주세요(원본이 채워집니다).$which',
    // 저장소 쪽(달력 표 없음 · 깨짐 · 그 달력 없음 · 아주 옛 저장소 — 판정 R72-6): 무엇인지는 엔진의 글(자세히)이 말한다. '앱을 새 판으로 올리면'은 표가 없을
    // 때만(그 판의 시드 잇기가 표 있는 새 판 저장소로 옮긴다) — 엔진 글로 가른다('달력 표가 없는 옛 저장소').
    'calendar' => '저장소의 달력 표에 문제가 있어 DLC를 넣거나 뺄 수 없습니다'
        '${RegExp('달력 표가? 없').hasMatch(error) ? ' — 앱을 새 판으로 올리면 넣어 둔 DLC와 함께 새 판의 저장소로 옮겨지고, 그 뒤에 할 수 있습니다' : ''}.$which',
    'dup_uid' when removing => '같은 항목이 두 트랙에 들어 있어 빼지 않았습니다 — 이 DLC를 빼면 남는 DLC끼리 겹칩니다: 겹친 DLC를 먼저 빼 주세요.$which',
    'dup_uid' => '같은 항목이 두 트랙에 들어 있어 $not 않았습니다 — DLC를 만든 쪽(메이커)에서 고쳐야 합니다.$which',
    // 그 DLC의 날짜가 앱이 아는 달력 범위 밖(DLC 쪽 잘못 — 판정 R62): 그 DLC 하나의 거절이다(저장소 쪽 `calendar`와 달리 저장소를 옮겨도 소용없다).
    // range · layout · broken은 이번에 받은 DLC 탓일 때만 오므로(판정 R70-4 · R72-3) 빼기 · 끄기(`remove_pack` — 받은 DLC 없음)에서는 나지 않는다.
    'range' => '그 DLC의 날짜가 앱이 아는 달력 범위 밖이라 $not 않았습니다 — 메이커에서 그 DLC의 날짜를 고쳐 다시 저장한 .htpack을 넣어 주세요.$which',
    // 연표에 배치하지 못함(DLC 쪽 잘못 — 갈래 1 · 판정 R61): 어느 DLC인지는 엔진의 글이 말한다.
    'layout' => '그 DLC를 연표에 배치하지 못해 $not 않았습니다 — DLC를 만든 쪽(메이커)에서 고쳐야 합니다.$which',
    // 기본팩이 다름: add_pack · remove_pack에서는 나지 않는다(엔진이 저장소의 바탕으로 배치 — 판정 R72-7). 2-7 `apply`(메이커 배치 — 앱은 과제 11c부터
    // 부르지 않음)의 code라 혹시 오면 읽을 수 있게 남겨 둔다.
    'base' => '기본 DLC(바탕)가 지금 저장소와 달라 $not 않았습니다.$which',
    // 받은 그 DLC 파일이 망가짐(갈래 1 · 판정 R68-1 · R70-1): 같은 파일을 다시 골라도 같으니 메이커에서 다시 저장한 것을(판정 R72-6).
    'broken' => '그 DLC 파일이 망가져 $not 않았습니다 — 메이커에서 다시 저장한 .htpack을 골라 주세요.$which',
    'path' => _pathRefusal,
    _ => '${turningOn ? 'DLC를 켜지 못했습니다' : (removing ? 'DLC를 빼지 못했습니다' : 'DLC를 넣지 못했습니다')} — '
        '${error.trim().isEmpty ? '까닭을 알 수 없습니다.' : dlcPlainEngineError(error)}',
  };
}

/// 엔진 거절 글에서 걷은 길 · 속말을 앱의 말로 바꾼다(판정 R60 M-11 · ② Minor 2): '컴퓨터에서 다시 지어 주세요'(다시 짓기 길은 걷었다 — 바탕 빼기면
/// 끄기, 그 밖은 앱을 새 판으로 올리기) · '새 판 시드로 옮긴 뒤'(시드는 속말) · '보관함'(속말 — 꺼 둔 DLC) · 'delete를 주세요'(요청 칸 이름) ·
/// 열린 저장소가 아닌 곳에 쓰라는 거절(경로 대신 쉬운 말 — ② Minor 4 · 갈래 1 dc0488a의 글과 그 전의 글).
String dlcPlainEngineError(String error) {
  const rebuild = ' — 컴퓨터에서 다시 지어 주세요';
  var text = error.trim();
  if (text.startsWith('지금 열린 저장소가 이 요청의 저장소와 달라') || text.startsWith('열린 저장소가 아닌 곳에 쓰라는 요청')) return _pathRefusal;
  if (text.endsWith(rebuild)) {
    text = text.substring(0, text.length - rebuild.length);
    text += text.contains('뺄 수 없습니다') ? ' — 끄면 화면에서 가려집니다' : ' — 앱을 새 판으로 올린 뒤 다시 해 주세요';
  }
  return text
      .replaceAll('새 판 시드로 옮긴 뒤', '앱을 새 판으로 올린 뒤')
      .replaceAll(' — 지우려면 delete를 주세요', '')
      .replaceAll('꺼 둔(보관함의) DLC', '꺼 둔 DLC')
      .replaceAll('보관함(꺼 둔 DLC)', '꺼 둔 DLC')
      .replaceAll('이 저장소의 보관함', '꺼 둔 DLC')
      .replaceAll('보관함', '꺼 둔 DLC');
}

/// 예외를 알림에 실을 사람의 말로(판정 R60 M-11) — 날 예외 꼴('Bad state: …' · 'FileSystemException: …, path = …')을 싣지 않는다: 파일 일이면
/// 운영체제의 까닭과 파일 이름, 그 밖은 그 예외의 글만.
String dlcErrorText(Object error) {
  if (error is FileSystemException) {
    final why = (error.osError?.message ?? '').trim();
    final path = error.path ?? '';
    return '${why.isEmpty ? error.message : why}${path.isEmpty ? '' : ' (${path.split(RegExp(r'[\\/]')).last})'}';
  }
  if (error is StateError) return error.message;
  if (error is ProcessException) return error.message.trim().isEmpty ? '${error.executable}을(를) 실행하지 못했습니다' : error.message.trim();
  if (error is FormatException) return error.message;
  if (error is ArgumentError) return '${error.message ?? error}';
  return '$error'.replaceFirst(RegExp(r'^(Exception|Bad state|Invalid argument\(s\)|FormatException|FileSystemException): '), '');
}

/// 화면에서만 끈 DLC를 끈 목록(`DLC/hidden.json` — 컴퓨터와 같은 꼴 · 원자적)에 기억한다(휴대폰 — 8 검토 2회차 Minor 1): 저장소에 든 DLC 가운데 지금
/// 꺼진 것을 `off`에 넣고 켜진 것은 뺀다. 저장소에 없는 끈 DLC(카드)와 기본팩 뺌 표시는 그대로 둔다. 앱은 열 때 끈 목록에 있는 DLC를 끈 채로 연다
/// ([dlcOffAtOpen]). [cards](글자 id → `hiddenCard`)를 주면 꺼진 저장소 DLC의 카드도 적는다 — 판 올림으로 그 DLC가 저장소에서 빠져도 창에 남게(판정 R60 M-6) ·
/// 켠 DLC의 카드는 뺀다. 바뀐 것이 없으면 쓰지 않는다. 쓰지 못하면 던진다(깨진 목록은 덮지 않는다 — [DlcHidden.save]).
/// [busy]: 지금 엔진이 켜거나 끄거나 빼는 중인 DLC(화면에서 먼저 접혔을 뿐) — 그 DLC의 끈 기억은 그대로 둔다(엔진이 끝나면 그 일이 적는다 · 실패하면
/// 다음 실행에 화면에서만 꺼진 채 열리지 않게 — ② Minor 3).
void rememberScreenOff(String db, SceneLayout layout, {Map<String, Map<String, dynamic>> cards = const {}, Set<String> busy = const {}}) {
  final before = DlcHidden.read(db);
  final stored = {for (final p in layout.packs) if (p.key.isNotEmpty) p.key};
  final off = {
    // 저장소에 없는 끈 DLC는 카드가 있는 것(저장소에 있다가 빠진 것)만 둔다 — 카드 없는 낡은 id는 버린다(덧붙임 N2).
    for (final key in before.off) if (!stored.contains(key) && before.cards.containsKey(key)) key,
    for (final p in layout.packs) if (p.key.isNotEmpty && !busy.contains(p.key) && !layout.isPackEnabled(p.id)) p.key,
    for (final key in busy) if (stored.contains(key) && before.off.contains(key)) key,
  };
  final nextCards = {
    for (final e in before.cards.entries) if (off.contains(e.key)) e.key: e.value,
    for (final key in off) if (stored.contains(key) && cards[key] != null) key: cards[key]!,
  };
  String text(Map<String, Map<String, dynamic>> m) => jsonEncode({for (final k in [...m.keys]..sort()) k: m[k]});
  if (setEquals(off, before.off) && text(nextCards) == text(before.cards)) return;
  DlcHidden.save(db, {'version': 1, 'off': [...off]..sort(), 'baseRemoved': before.baseRemoved, 'cards': nextCards});
}

/// 옛 판(Node 다시 짓기 길)에서 동아시아 기본팩을 뺀 기억(`hidden.baseRemoved`)을, 그 기본팩이 다시 든 저장소(판 올림으로 새 판의 저장소가 덮음)를 처음 열 때
/// 화면에서 끈 목록(`off`)으로 한 번 옮긴다(판정 R60 M-3 — 엔진은 바탕을 빼지 못하므로 화면에서만 끈 채로 연다 · 켜면 그대로 켜짐). 옮겼으면 참.
/// 그 기본팩이 저장소에 없으면 그대로 둔다(켤 길은 그 .htpack을 '파일에서 더하기'). 쓰지 못하면 던진다.
bool migrateBaseRemoved(String db, SceneLayout layout, {required String baseKey}) {
  final before = DlcHidden.read(db);
  if (!before.baseRemoved || !layout.packs.any((p) => p.key == baseKey)) return false;
  DlcHidden.save(db, {'version': 1, 'off': [...{...before.off, baseKey}]..sort(), 'baseRemoved': false, 'cards': before.cards});
  return true;
}

/// 저장소를 열 때 끈 채로 둘 자료집 번호 — 끈 목록에 글자 id가 있는 저장소의 DLC(옛 길에서 다 꺼서 짓지 않은 것 · 휴대폰에서 화면에서만 끈 것).
Set<int> dlcOffAtOpen(SceneLayout layout, DlcHidden hidden) => {for (final p in layout.packs) if (p.key.isNotEmpty && hidden.off.contains(p.key)) p.id};

Future<List<String>> _pickWindows() async {
  const ps = r'''
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
$d = New-Object System.Windows.Forms.OpenFileDialog
$d.Filter = "DLC 파일 (*.htpack)|*.htpack"
$d.Multiselect = $true
$d.Title = "더할 DLC 파일 고르기"
if ($d.ShowDialog() -eq "OK") { $d.FileNames | ForEach-Object { [Console]::Out.WriteLine($_) } }
''';
  // 글을 -Command로 넘기면 안의 겹따옴표가 명령줄 해석에서 벗겨진다 — UTF-16LE base64(-EncodedCommand)로 넘겨 그대로 전한다.
  final bytes = <int>[];
  for (final unit in ps.codeUnits) {
    bytes..add(unit & 0xff)..add(unit >> 8);
  }
  final run = await Process.run('powershell', ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', base64.encode(bytes)], stdoutEncoding: utf8, stderrEncoding: utf8);
  return const LineSplitter().convert(run.stdout as String).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
}

Future<List<String>> _pickLinux() async {
  final tries = <List<String>>[
    ['zenity', '--file-selection', '--multiple', '--separator=\n', '--title=더할 DLC 파일 고르기', '--file-filter=DLC 파일 | *.htpack'],
    ['kdialog', '--multiple', '--separate-output', '--title', '더할 DLC 파일 고르기', '--getopenfilename', '.', '*.htpack|DLC 파일'],
  ];
  for (final command in tries) {
    try {
      final run = await Process.run(command.first, command.sublist(1), stdoutEncoding: utf8, stderrEncoding: utf8);
      return const LineSplitter().convert(run.stdout as String).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    } on ProcessException {
      continue; // 그 창이 없다 — 다음 것을 본다
    }
  }
  return const [];
}

/// 끈 DLC의 목록 — 저장소 옆 `DLC/hidden.json`(2026-10-16 감독 건의 "숨기면 연표에서 아예 나오지 않게").
/// DLC를 끄면 그 DLC를 **저장소에서 빼므로**(엔진 `remove_pack` — 원본은 보관함) 끈 DLC는 저장소에 없다 — 카드는 여기 적힌 값으로 그린다([cards]).
/// 엔진이 끝난 뒤 앱이 적는다([save]). 화면에서만 끈 DLC(바탕 · 원본 없이 든 것)와 예전 길에서 다 꺼서 짓지 않았을 때는 저장소에 남은 DLC도 [off]에
/// 들어 있다(앱이 처음부터 끈 채로 연다).
class DlcHidden {
  const DlcHidden({this.off = const {}, this.baseRemoved = false, this.cards = const {}});
  static const none = DlcHidden();

  /// 끈 DLC의 글자 id.
  final Set<String> off;

  /// 기본팩을 뺐는가(되살리려면 기본팩의 .htpack을 더한다).
  final bool baseRemoved;

  /// 끈 DLC의 카드(글자 id → `{name, version, category, events, periods, tracks:[{key,name,color,rows}], shared:[{key,name,color,owner}]}`).
  final Map<String, Map<String, dynamic>> cards;

  static File _file(String db) => File('${File(db).parent.path}${Platform.pathSeparator}DLC${Platform.pathSeparator}hidden.json');

  /// 저장소([db]) 옆 `DLC/hidden.json`을 읽는다. 없거나 깨졌으면 [none].
  static DlcHidden read(String? db) {
    if (db == null) return none;
    try {
      final file = _file(db);
      if (!file.existsSync()) return none;
      return fromJson(jsonDecode(file.readAsStringSync()));
    } catch (_) {
      return none;
    }
  }

  /// 도구가 낸 새 끈 목록(`{"version":1,"off":[…],"baseRemoved":…,"cards":{…}}`)을 그대로 적는다(도구와 같은 꼴 — 한 칸 들여쓰기 · 끝 줄바꿈).
  /// 원자적으로(임시 파일 → 이름 바꾸기 — 쓰다 멈춰도 반쯤 쓴 끈 목록이 남지 않게 · 판정 R33).
  /// **있는데 읽지 못하는(깨진) 목록은 덮지 않고 던진다**(판정 R60 I-3): 깨진 목록을 지금 것만으로 덮으면 거기 적힌 끈 DLC가 사라져 판 올림 뒤 다시 들이기(R32 —
  /// 깨진 동안은 [DlcFolderSync.blocked]가 막는다)가 그 DLC를 켜진 채 되들인다. 사용자가 그 파일을 지우거나 고치면 다시 적는다.
  static void save(String db, Map<String, dynamic> raw) {
    if (unreadable(db)) throw StateError('끈 DLC 목록(hidden.json)이 깨져 덮어쓰지 않았습니다 — 그 파일(${_file(db).path})을 지우거나 고쳐 주세요');
    writeFileAtomic(_file(db), '${const JsonEncoder.withIndent(' ').convert(raw)}\n');
  }

  /// `DLC/hidden.json`이 **있는데** 읽지 못하는가(깨짐) — 그때 [read]는 빈 목록을 주므로, 꺼 둔 DLC를 모두 켜진 것으로 볼 일(판 올린 뒤 다시 들이기)은 멈춘다.
  static bool unreadable(String db) {
    final file = _file(db);
    if (!file.existsSync()) return false;
    try {
      return jsonDecode(file.readAsStringSync()) is! Map;
    } catch (_) {
      return true;
    }
  }

  static DlcHidden fromJson(Object? raw) {
    if (raw is! Map) return none;
    final cards = raw['cards'];
    return DlcHidden(
      off: {if (raw['off'] is List) for (final id in raw['off'] as List) '$id'},
      baseRemoved: raw['baseRemoved'] == true,
      cards: {if (cards is Map) for (final e in cards.entries) if (e.value is Map) '${e.key}': Map<String, dynamic>.from(e.value as Map)},
    );
  }
}

/// 글을 원자적으로 쓴다 — 같은 폴더의 임시 파일에 다 쓰고(flush) 이름을 바꿔 덮는다. 도중에 멈추거나 실패해도 옛 파일은 온전하다. 실패하면 던진다.
/// 이름 바꾸기가 막히면(Windows에서 백신 · 색인 · 동기화가 그 파일을 잠깐 쥠) 30ms씩 쉬며 세 번 더 해 본다(8 검토 — 길어야 0.1초 남짓).
/// [rename]은 검사가 막힘을 흉내 낼 때만 준다.
void writeFileAtomic(File target, String text, {@visibleForTesting void Function(File temp, String target)? rename}) {
  target.parent.createSync(recursive: true);
  final temp = File('${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
  final move = rename ?? (File from, String to) => from.renameSync(to);
  try {
    temp.writeAsStringSync(text, flush: true);
    for (var retry = 0; ; retry++) {
      try {
        move(temp, target.path);
        break;
      } on FileSystemException {
        if (retry >= 3) rethrow;
        sleep(const Duration(milliseconds: 30));
      }
    }
  } catch (_) {
    try {
      if (temp.existsSync()) temp.deleteSync();
    } catch (_) {}
    rethrow;
  }
}

/// 엔진 `add_pack` 답의 `notes` 가운데 달력 건너뜀 알림(`packs.rs`의 `calendar_notes` — 옛 저장소(달력 표 다섯)에 없는 달력으로 날짜를 적은 DLC: 그 날짜의
/// 항목은 빼고 넣었고 날짜 칸에도 그 달력 줄이 없다 · 감독 결정 2026-10-25)의 줄들 — 엔진 글이 이미 쉬운 말(`«DLC 이름»: …`)이라 그대로 알린다. 없으면 빈 목록.
/// 같은 `notes`의 형식 4 내림 알림(`lay/pack.rs` · `f4.rs`)은 알리지 않는다 — 리메이크 5단계 과제 10이 달던 "이 앱 판은 사람 띠 · 빌린 직위 줄 · 문화권 줄을
/// 아직 그리지 않습니다" 줄은 4단계에서 앱이 그 장치를 그리게 되어 걷었다(0.1.0 · 4단계 계획 과제 10 · 메이커 점검 n23).
List<String> dlcCalendarNotes(Object? notes) {
  if (notes is! List) return const [];
  return [for (final n in notes) if (n is String && n.contains(dlcCalendarMark)) n];
}

/// 달력 건너뜀 알림을 가르는 글(엔진 `calendar_notes`의 글 — 바꿀 때 함께).
const dlcCalendarMark = '그 달력으로 적은 날짜를 읽지 못했습니다';

/// 메이커 미리보기의 서재 사본(앱 틀의 `_previewStore`): 저장소([library])와 그 일지(`-wal` · `-journal` — 앱이 쓰다 멈춘 거래가 남긴 되감기 일지도 함께
/// 가야 사본이 열 때 되감긴다 · 판정 R60 M-10), 옆 `DLC/` 폴더의 파일을 [dir]에 복사한다. 사본 저장소의 경로를 돌려준다.
Future<String> copyLibraryForPreview(String library, Directory dir) async {
  final sep = Platform.pathSeparator;
  await Directory('${dir.path}${sep}DLC').create(recursive: true);
  final db = '${dir.path}${sep}archive.db';
  await File(library).copy(db);
  for (final tail in const ['-wal', '-journal']) {
    final side = File('$library$tail');
    if (side.existsSync()) await side.copy('$db$tail');
  }
  final dlc = Directory('${File(library).parent.path}${sep}DLC');
  if (dlc.existsSync()) {
    for (final f in dlc.listSync().whereType<File>()) {
      // 반쯤 쓴 임시 파일(*.tmp — 원자적 쓰기가 멈추며 남김)은 옮기지 않는다(① m-5).
      if (f.path.toLowerCase().endsWith('.tmp')) continue;
      await f.copy('${dir.path}${sep}DLC$sep${f.path.split(sep).last}');
    }
  }
  return db;
}

/// 파일을 원자적으로 복사한다 — 같은 폴더의 임시 파일에 다 쓰고(flush) 이름을 바꿔 놓는다(판정 R60 I-2: 판 올림 뒤 다시 들이기가 믿는 DLC 폴더 사본이
/// 복사 도중 꺼짐으로 반쯤 남지 않게). 같은 파일이면 아무것도 하지 않는다. 실패하면 던진다(옛 파일은 그대로).
void copyFileAtomic(String source, String target) {
  if (File(source).absolute.path.toLowerCase() == File(target).absolute.path.toLowerCase()) return;
  final temp = File('$target.${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    final bytes = File(source).readAsBytesSync();
    temp.writeAsBytesSync(bytes, flush: true);
    for (var retry = 0; ; retry++) {
      try {
        temp.renameSync(target);
        break;
      } on FileSystemException {
        if (retry >= 3) rethrow;
        sleep(const Duration(milliseconds: 30));
      }
    }
  } catch (_) {
    try {
      if (temp.existsSync()) temp.deleteSync();
    } catch (_) {}
    rethrow;
  }
}

/// 파일의 지문 — 팩 파일이면 머리의 SHA-256(본문까지 덮는 지문 · 52바이트만 읽음) + 크기, 아니면 크기 + 고친 시각. 읽지 못하면 빈 글.
String dlcFileFingerprint(String path) {
  try {
    final file = File(path);
    final size = file.lengthSync();
    final raf = file.openSync();
    try {
      final head = raf.readSync(52);
      const magic = [72, 84, 80, 65, 67, 75, 13, 10];
      final pack = head.length == 52 && [for (int i = 0; i < magic.length; i++) head[i] == magic[i]].every((same) => same);
      if (pack) return '${[for (final b in head.sublist(20, 52)) b.toRadixString(16).padLeft(2, '0')].join()}:$size';
    } finally {
      raf.closeSync();
    }
    return '$size:${file.lastModifiedSync().microsecondsSinceEpoch}';
  } catch (_) {
    return '';
  }
}

/// DLC 폴더 맞추기의 기억 — 저장소 옆 `DLC/sync.json`(판정 R33 · 원자적으로 씀). 판을 올린 뒤 폴더에서 다시 들일 때(`DlcFolderSync`) 읽는다.
///   · [removed] 묘비 — 뺀 DLC의 글자 id(고쳐 쓰기의 COMMIT 직후 적음). 폴더에 그 파일이 남아도(지우기 실패 — 백신 · 동기화가 잡음) 다시 들이지 않고,
///     다음 열기에서 남은 파일을 마저 지운다(다 지우면 뺌). 그 DLC가 다시 저장소에 들면(사용자가 다시 넣음) 뺀다.
///   · [off] 끈 DLC의 글자 id(COMMIT 직후 — 끈 목록 쓰기가 실패해도 다시 들이지 않게). 켜거나 다시 넣으면 뺀다. 파일은 지우지 않는다(다시 켤 원본).
///   · [skip] 다시 들이지 못한 파일 — 파일 이름 → 지문([dlcFileFingerprint]). 같은 지문이면 다시 읽거나 알리지 않는다(실행마다 같은 알림이 되풀이되지 않게).
///   · [skipApp] 그 거절을 기억한 때의 앱 판(파일 이름 → [dlcAppVersion] — 판정 R63-3): 앱 판이 다르면 그 파일을 한 번 다시 본다(판 올림이 달력 범위 ·
///     배치 잘못을 고쳤을 수 있다). 앱 판이 적히지 않은 옛 기억도 다른 판으로 본다.
class DlcFolderState {
  const DlcFolderState({this.removed = const {}, this.off = const {}, this.skip = const {}, this.skipApp = const {}});
  static const empty = DlcFolderState();

  final Set<String> removed, off;
  final Map<String, String> skip, skipApp;

  static File file(String db) => File('${File(db).absolute.parent.path}${Platform.pathSeparator}DLC${Platform.pathSeparator}sync.json');

  /// 읽는다 — 없으면 [empty], **있는데 읽지 못하면 null**(그때는 폴더에서 다시 들이지 않는다).
  static DlcFolderState? read(String db) {
    final f = file(db);
    if (!f.existsSync()) return empty;
    try {
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return null;
      Set<String> words(Object? v) => {for (final x in (v as List?) ?? const []) '$x'};
      Map<String, String> names(Object? v) => {if (v is Map) for (final e in v.entries) '${e.key}': '${e.value}'};
      return DlcFolderState(removed: words(raw['removed']), off: words(raw['off']), skip: names(raw['skip']), skipApp: names(raw['skipApp']));
    } catch (_) {
      return null;
    }
  }

  /// 원자적으로 쓴다. 실패하면 던진다.
  void write(String db) {
    Map<String, String> sorted(Map<String, String> m) => Map.fromEntries([...m.entries]..sort((a, b) => a.key.compareTo(b.key)));
    writeFileAtomic(file(db), '${const JsonEncoder.withIndent(' ').convert({
      'version': 1, 'removed': [...removed]..sort(), 'off': [...off]..sort(), 'skip': sorted(skip), 'skipApp': sorted(skipApp),
    })}\n');
  }

  /// 읽고 바꿔 쓴다. 바뀐 것이 없으면 쓰지 않는다. 쓰지 못하면 던진다 — 있는데 읽지 못하면(깨짐) 덮지 않고 던진다(깨진 기억을 지금 것만으로 덮으면
  /// 거기 적혀 있던 묘비가 사라져 뺀 DLC가 되살아날 수 있다. 깨진 동안은 폴더에서 다시 들이기도 멈춘다 — `DlcFolderSync.blocked`).
  static void update(String db, DlcFolderState Function(DlcFolderState state) change) {
    final before = read(db);
    if (before == null) throw StateError('DLC 폴더 기억(sync.json)을 읽지 못합니다');
    final after = change(before);
    if (_same(before, after)) return;
    after.write(db);
  }

  /// 저장소에 든 DLC(다시 넣음)는 묘비에서 뺀다 — 넣거나 뺀 일이 끝난 뒤 앱 틀이 새 뼈대의 DLC 열쇠로 부른다. 쓰지 못하면 조용히 둔다(다음에 다시).
  static void forgetStored(String db, Iterable<String> keys) {
    final stored = keys.toSet();
    try {
      update(db, (s) => s.copyWith(removed: s.removed.difference(stored), off: s.off.difference(stored)));
    } catch (_) {}
  }

  DlcFolderState copyWith({Set<String>? removed, Set<String>? off, Map<String, String>? skip, Map<String, String>? skipApp}) =>
      DlcFolderState(removed: removed ?? this.removed, off: off ?? this.off, skip: skip ?? this.skip, skipApp: skipApp ?? this.skipApp);

  /// 판 올림 뒤 다시 들이기(R32)가 셈한 기억([imported] — 파일 지문 skip · 남은 파일을 다 지워 뺀 묘비)을 지금 파일의 기억([current])에 합친다(판정 R60 M-7):
  /// skip은 [imported]의 것, 묘비는 지금 것을 두되 들이기를 시작할 때([initial]) 있었는데 [imported]에서 빠진 것만 뺀다 — 들이는 동안 넣고 빼고 끈 DLC 일이
  /// 적은 묘비(removed · off)를 들이기가 시작할 때의 옛 값으로 덮지 않게.
  static DlcFolderState mergeImport(DlcFolderState current, {required DlcFolderState initial, required DlcFolderState imported}) => current.copyWith(
    removed: {for (final id in current.removed) if (!initial.removed.contains(id) || imported.removed.contains(id)) id},
    skip: imported.skip,
    skipApp: imported.skipApp,
  );

  /// 그 파일을 건너뛸 것으로 적는다(지금 지문 · 앱 판 [app]으로 — 판정 R63-3).
  DlcFolderState skipping(String path, {String app = dlcAppVersion}) {
    final name = path.split(RegExp(r'[\\/]')).last;
    return copyWith(skip: {...skip, name: dlcFileFingerprint(path)}, skipApp: {...skipApp, name: app});
  }

  /// 열 때(판 올림 뒤 다시 들이기 전) 낡은 끄기 묘비를 치운다(판정 R63-5): 저장소에 든([stored]) 채 끈 목록([hidden] — `hidden.json`)에 없는 id는 `off`에서
  /// 뺀다 — 엔진 앞에 적은 끄기 묘비(판정 R60 M-1)가 COMMIT 전에 멈춘 끄기에서 남으면, 다음 판 올림 뒤 다시 들이기가 그 DLC를 끈 것으로 보고 건너뛰어 카드도
  /// 없이 사라진다. 끈 목록이 깨졌으면(무엇이 낡았는지 모름) 그대로 둔다. 쓰지 못하면 조용히 둔다(다음 열기에서 다시).
  static void dropStaleOff(String db, {required Iterable<String> stored, required DlcHidden hidden}) {
    if (DlcHidden.unreadable(db)) return;
    final inStore = stored.toSet();
    try {
      update(db, (s) => s.copyWith(off: {for (final id in s.off) if (!inStore.contains(id) || hidden.off.contains(id)) id}));
    } catch (_) {}
  }

  static bool _same(DlcFolderState a, DlcFolderState b) =>
      setEquals(a.removed, b.removed) && setEquals(a.off, b.off) && mapEquals(a.skip, b.skip) && mapEquals(a.skipApp, b.skipApp);
}

/// 이 앱의 판(pubspec의 `version` — Flutter가 짓기마다 넣는 `FLUTTER_BUILD_NAME` + `FLUTTER_BUILD_NUMBER`). 기억한 거절(sync.json `skip`)이 어느 판의 것인지
/// 적는다(판정 R63-3 — 판이 바뀌면 한 번 다시 본다). 짓기 정의가 없으면(옛 도구) 빈 글.
const dlcAppVersion = String.fromEnvironment('FLUTTER_BUILD_NAME') == ''
    ? ''
    : '${String.fromEnvironment('FLUTTER_BUILD_NAME')}+${String.fromEnvironment('FLUTTER_BUILD_NUMBER')}';

/// 열 때 저장소 옆 DLC 폴더를 맞추는가(앱 틀의 `_syncDlcFolder` — 고침 2회차 Minor 6): 메이커 미리보기(서재의 임시 사본) · 저장소를 주지 않은 재기 ·
/// 그림만([leaveStore] — 판정 R50) · 재기 · 그림만([leaveDlcFolder] — 저장소를 주었어도 · 판정 R63-4)이면 하지 않는다.
bool dlcFolderSyncAllowed({required bool preview, required bool leaveStore, required bool leaveDlcFolder}) => !preview && !leaveStore && !leaveDlcFolder;

/// 열 때(판 올림 뒤 다시 들이기 앞 · 도구가 없는 휴대폰도) DLC 폴더 앞정리: 낡은 끄기 묘비([DlcFolderState.dropStaleOff] — 판정 R63-5)와 오래된 임시
/// 파일([cleanDlcTemps] — ① m-5). [stored]는 지금 저장소에 든 DLC 글자 id.
void dlcOpenTidy(String db, {required Iterable<String> stored, required DlcHidden hidden}) {
  DlcFolderState.dropStaleOff(db, stored: [for (final k in stored) if (k.isNotEmpty) k], hidden: hidden);
  cleanDlcTemps(db);
}

/// 보관함 카드로 세우지 않을 id — 지운 DLC의 묘비(`sync.json`의 removed · ① m-4). 저장소가 없거나 기억을 읽지 못하면 빈 것.
Set<String> dlcKeptGone(String? db) => db == null ? const {} : (DlcFolderState.read(db)?.removed ?? const {});

/// 열 때 저장소 옆 DLC 폴더의 오래된 임시 파일(`*.tmp` — 원자적 복사 · 쓰기([copyFileAtomic] · [writeFileAtomic] · 원본 꺼내기)가 멈추며 남긴 것)을
/// 지운다(① m-5). 막 생긴 것([olderThan] 안 — 다른 창이 쓰는 중일 수 있다)은 둔다. 지운 파일 이름들(실패는 조용히).
List<String> cleanDlcTemps(String db, {Duration olderThan = const Duration(minutes: 10), DateTime? now}) {
  final dir = Directory('${File(db).absolute.parent.path}${Platform.pathSeparator}DLC');
  final gone = <String>[];
  try {
    if (!dir.existsSync()) return gone;
    final limit = (now ?? DateTime.now()).subtract(olderThan);
    final temps = [for (final f in dir.listSync(followLinks: false)) if (f is File && f.path.toLowerCase().endsWith('.tmp')) f]..sort((a, b) => a.path.compareTo(b.path));
    for (final f in temps) {
      try {
        if (f.lastModifiedSync().isAfter(limit)) continue;
        f.deleteSync();
        gone.add(f.path.split(RegExp(r'[\\/]')).last);
      } catch (_) {}
    }
  } catch (_) {}
  return gone;
}

/// 뺀 · 끈 · 켠 DLC를 폴더 기억에 적는다(판정 R33 — 저장소를 고쳐 쓴 COMMIT 직후): 뺀 DLC는 [DlcFolderState.removed],
/// 끈 DLC는 [DlcFolderState.off]에 넣고 켠 DLC는 둘에서 뺀다. 쓰지 못하면 던진다.
void rememberDlcChange(String db, {String? removeKey, List<String> offKeys = const [], List<String> onKeys = const []}) {
  if (removeKey == null && offKeys.isEmpty && onKeys.isEmpty) return;
  DlcFolderState.update(db, (s) => s.copyWith(
    removed: {...s.removed.difference(onKeys.toSet()), ?removeKey},
    off: {...s.off.difference({...onKeys, ?removeKey}), ...offKeys},
  ));
}

/// 엔진 걸음 하나가 끝난 뒤 맞출 DLC 폴더와 끈 목록([DlcJob._stepPlan] → [DlcJob._settle]).
class DlcApplyPlan {
  const DlcApplyPlan({this.copy = const [], this.drop = const [], this.tomb = const [], this.hidden, this.dropNeeds = const {}});

  /// 고쳐 쓰기가 끝난 뒤 DLC/ 폴더에 들일 것(원본 → 폴더 자리)과 지울 것(같은 id 낮은 판 · 뺀 DLC).
  final List<(String, String)> copy;
  final List<String> drop;

  /// [drop]의 파일 → 그 파일을 지우기 전에 놓여 있어야 할 새 사본(같은 id — [copy]의 폴더 자리). 그 사본을 두지 못했으면 옛 사본을 지우지 않는다(① m-1 —
  /// 판 올림 뒤 다시 들일 원본이 폴더에 하나도 없게 되지 않게).
  final Map<String, String> dropNeeds;

  /// [drop] 가운데 묘비 DLC(이번에 빼는 DLC · 앞서 뺀 DLC — `DLC/sync.json`의 removed)의 파일 — 못 지우면 다음에 앱을 열 때 다시 지운다.
  /// 나머지(같은 DLC의 낮은 판 · 기본팩 파일)는 이미 든 DLC와 겹치는 남은 파일이라 다시 들이지 않을 뿐 열 때 지우지는 않는다(8 검토).
  final List<String> tomb;

  /// 끝난 뒤 `DLC/hidden.json`에 적을 새 끈 목록(바뀌지 않으면 null).
  final Map<String, dynamic>? hidden;
}

/// 고쳐 쓰기 한 번의 끝([DlcJob.apply]).
class DlcApplied {
  const DlcApplied({required this.ok, this.data = const {}, this.storeChanged = false, this.reopen = false, this.firstPos = 0, this.restart = false});

  /// 저장소는 고쳐 썼는데 앱이 다시 열거나 새 뼈대를 읽지 못했다 — 화면이 옛 뼈대 그대로라 앱을 다시 켜야 한다([DlcApplyFlow]가 적는다).
  final bool restart;

  DlcApplied _needsRestart() => DlcApplied(ok: false, data: data, storeChanged: storeChanged, reopen: reopen, firstPos: firstPos, restart: true);

  /// 부탁한 일을 해냈는가(아니면 까닭은 [DlcJob.lastLine]).
  final bool ok;

  /// 마지막 엔진 답(`rewrote · added · removed · globals · first_pos · rows_before · rows_after · names · ms · steps` — 계약 2-7).
  final Map<String, dynamic> data;

  /// 저장소가 바뀌었는가 — 참이면 앱 틀이 뼈대를 다시 읽는다(실패한 일도 앞 걸음이 이미 고쳐 썼을 수 있다 — 모두 끄기의 앞 걸음).
  final bool storeChanged;

  /// COMMIT은 끝났는데 엔진이 저장소를 다시 열지 못했다(`committed` — 계약 2-7) — 앱 틀이 `{"op":"open"}`으로 다시 연다.
  final bool reopen;

  /// 앱이 이 자리부터 타일을 버린다(엔진의 `first_pos` — −1이면 바뀐 트랙 없음 · 0이면 모두). 고쳐 쓰기가 둘 이상이면 가장 앞.
  final int firstPos;
}

/// 뒷일의 상태 — DLC 관리 창의 위 칸과 앱의 알림 줄이 듣는다.
enum DlcJobPhase { idle, running, failed, done }

/// 뼈대를 다시 읽은 뒤 켤 DLC(자료집 번호 — 앱 틀의 `_reloadStore`): 끈 목록([off])에 없고, 전에 켜져 있었거나([wasOn]) · 새로 들었거나([known]에 없음 —
/// 더한 DLC · 판을 올린 뒤 DLC 폴더에서 다시 들인 DLC) · 이번에 켜는 것([turnOn]). [packOf]는 DLC 열쇠 → 새 뼈대의 자료집 번호.
Set<int> dlcEnabledAfterReload({
  required Map<String, int> packOf,
  required Set<String> off,
  required Set<String> wasOn,
  required Set<String> known,
  Set<String> turnOn = const {},
}) => {
  for (final e in packOf.entries)
    if (!off.contains(e.key) && (wasOn.contains(e.key) || !known.contains(e.key) || turnOn.contains(e.key))) e.value,
};

/// 뼈대를 다시 읽을 때 켤 DLC 열쇠(앱 틀의 고쳐 쓰기 → [dlcEnabledAfterReload]의 turnOn): 켜기 부탁([onKeys]) · 더하기로 끈 목록에서 뺀 DLC([turnedOn]) ·
/// **끄기 부탁**([offKeys]) — 끝까지 끈 DLC는 저장소에서 빠져(뼈대에 없음) 켜지지 않고, 모두 끄기가 도중에 멈춰 아직 저장소에 남은 DLC는 끈 목록에도 없어
/// 다음 실행에 켜진 채 열리므로 지금 화면에서도 켠다(앱 틀이 쓰기 전에 화면에서 먼저 접어 옮겨 적을 것의 wasOn에서 빠졌다 — 11c 검토).
Set<String> dlcTurnOnAfterReload({required List<String> onKeys, required List<String> offKeys, required Set<String> turnedOn}) => {...onKeys, ...turnedOn, ...offKeys};

/// 뒤에서 도는 DLC 넣기 · 빼기 하나. 한 번에 하나만 돈다([running]이면 다음 부탁은 거절한다).
/// 도구 · 엔진의 말(표준 출력 · 오류 · 거절 글)을 줄줄이 [lines]에 모으고 줄마다 알린다.
class DlcJob extends ChangeNotifier {
  DlcJobPhase phase = DlcJobPhase.idle;
  final lines = <String>[];

  /// 지금 빼는 중인 DLC의 글자 id(없으면 빈 글) — 창이 그 카드를 `삭제하는 중…`으로 보인다.
  String removingKey = '';

  /// 끝난 뒤에도 남기는 알림(`원본 없음` · 폴더를 덜 맞춤 …). 다음 일을 시작할 때 비운다([reset]은 남긴다).
  final notes = <String>[];

  /// 지금 저장소의 판 · 원본(글자 id마다 — `{"op":"layout"}`의 packs[]). 앱 틀이 열 때와 뼈대를 다시 읽을 때마다 [factsFrom]으로 채운다.
  /// DLC 관리 창의 카드(`원본 없음`)와 원본 없이 든 DLC의 .htpack을 알아보기([_stashOriginals])가 읽는다.
  final packFacts = <String, DlcPackFacts>{};

  /// 새 뼈대(`{"op":"layout"}`의 답)의 판 · 원본으로 [packFacts]를 바꾸고 알린다(떠 있는 DLC 관리 창의 카드가 바로 따라온다 — 원본을 채우면 `원본 없음`이 빠진다).
  void factsFrom(Map<String, dynamic> layout) {
    packFacts
      ..clear()
      ..addAll(DlcPackFacts.fromLayoutJson(layout));
    notifyListeners();
  }

  /// 끈 DLC의 목록(`DLC/hidden.json`) — 앱 틀이 저장소를 열 때와 일이 끝날 때 [loadHidden]으로 읽는다. 창이 끈 카드를 그린다.
  DlcHidden hidden = DlcHidden.none;

  /// 저장소의 보관함(`{"op":"kept_packs"}` — 꺼 둔 DLC의 원본) — 앱 틀이 열 때와 뼈대를 다시 읽을 때 [keptFrom]으로 채운다. 끈 목록에 카드가 없는 꺼 둔
  /// DLC도 창이 카드로 그린다(판정 R60 I-3 덤).
  List<({String id, String name, String version})> kept = const [];

  /// `{"op":"kept_packs"}`의 답(겉 `data`가 있든 없든)으로 [kept]를 바꾸고 알린다. 읽지 못하면 비운다. [gone]: 지운 DLC의 묘비(`sync.json`의 removed) —
  /// 예전 판 앱이 꺼 둔 채 지워 보관함에 원본만 남은 것은 카드로 세우지 않는다(① m-4).
  void keptFrom(Object? answer, {Set<String> gone = const {}}) {
    final list = answer is Map ? answer['data'] : answer;
    kept = [
      if (list is List)
        for (final p in list)
          if (p is Map && '${p['id'] ?? ''}'.isNotEmpty && !gone.contains('${p['id']}'))
            (id: '${p['id']}', name: '${p['name'] ?? p['id']}', version: '${p['version'] ?? ''}'),
    ];
    notifyListeners();
  }

  /// 지금 켜거나 끄는 중인 DLC(글자 id → 켜는가). 도는 동안 창의 스위치가 부탁한 쪽으로 서 있다.
  Map<String, bool> toggling = const {};

  /// 저장소 옆의 끈 목록을 다시 읽고 알린다.
  void loadHidden(String? db) {
    hidden = DlcHidden.read(db);
    notifyListeners();
  }

  /// 엔진에 고쳐 쓰기를 맡기는 길 — 요청은 `{"op":"add_pack" | "remove_pack", …}`(계약 2-7-1). 앱 틀이 따로 된 일꾼을 넣는다(`ArchiveEngine.write`) ·
  /// 검사는 흉내. 답의 겉은 `archive_call` 그대로(`{"ok":true,"data":{…}}` · `{"ok":false,"error",["code"],["committed":true]}`).
  Future<Map<String, dynamic>> Function(Map<String, dynamic> request)? applier;

  /// 엔진의 읽기 일꾼(`{"op":"kept_packs"}` — 켤 DLC가 보관함에 있는지). 없거나 실패하면 보관함을 모르는 것으로 본다(DLC 폴더의 파일 → 없으면 보관함).
  Future<Map<String, dynamic>> Function(Map<String, dynamic> query)? reader;

  /// 휴대폰인가([DlcTools.phone]) — 할 수 없는 일의 알림을 휴대폰의 말로.
  bool get phone => _phone ?? (DlcTools.find()?.phone ?? false);
  bool? _phone;
  @visibleForTesting
  set phone(bool? value) => _phone = value;

  /// 쉬는 동안 창의 위 칸에 알림 하나를 더한다(고르기 창을 못 연 까닭 · 거른 파일 · 화면에서만 켜고 끈 사정). 앞의 알림은 지우지 않고(같은 알림은 한 번 —
  /// 다음 일을 시작할 때 비운다), 실패로 끝나 있었으면 그 까닭도 알림으로 옮겨 남긴다(8 검토 2회차). 도는 중이면 버리지 않고 끝난 뒤의 알림에 더해 둔다
  /// (창의 위 칸은 도는 일의 진행 그대로 — ② Minor 3).
  void notice(String line) {
    if (running) {
      // 따로 두었다가 일이 끝날 때 합친다 — 잡아 둔 일이 이어서 넣기로 가면 시작하며 [notes]를 비우므로(R32 · 고침 2회차 ② Minor 3).
      if (!_pendingNotes.contains(line)) _pendingNotes.add(line);
      return;
    }
    if (failed && lastLine.isNotEmpty && !notes.contains(lastLine)) notes.add(lastLine);
    phase = DlcJobPhase.idle;
    lines.clear();
    if (!notes.contains(line)) notes.add(line);
    notifyListeners();
  }

  /// 시작하기 전에 거절한다(앱 틀 — 이 자리에서 할 수 없는 일: [dlcRouteRefusal]) — 창의 위 칸에 실패와 까닭을 남긴다. 도는 중이면(잡아 둔 것 말고) 거짓.
  bool refuse(String why) {
    if (running && !_held) return false;
    _held = false;
    _start();
    _say(why);
    _finish(false);
    return true;
  }

  bool get running => phase == DlcJobPhase.running;

  /// 마지막 [apply]가 엔진의 거절로 끝났으면 그 기계용 `code`(계약 2-7 · 2-7-1) — 성공했거나 code가 없으면 null. 판 올림 뒤 다시 들이기(R32)가
  /// 저장소 쪽 거절(파일 탓이 아님 — [dlcFileFault]가 거짓)이면 그 파일을 '다시 해 보지 않음'으로 적지 않는다(고침 1회차 Minor).
  String? lastCode;

  /// 마지막 엔진 거절 · 다시 열기 실패의 개발자 말(`detail` · `committed`의 글 — 계약 2-7) — 알림에는 싣지 않고 보관한다(기록 · 자세히 보기 — ② Minor 4 · 5).
  String? lastDetail;
  bool get failed => phase == DlcJobPhase.failed;
  String get lastLine => lines.isEmpty ? '' : lines.last;

  /// 마지막 줄 — 도구 · 엔진이 남긴 까닭(실패) 또는 진행(도는 중). 창의 위 칸이 이것을 적는다.
  String get status => switch (phase) {
    DlcJobPhase.running => lines.isEmpty ? '준비하는 중…' : lines.last,
    DlcJobPhase.failed => lines.isEmpty ? '실패했습니다.' : lines.last,
    _ => '',
  };

  /// 마지막 일에서 끈 목록에서 빼 켠 DLC(글자 id) — 앱 틀이 뼈대를 다시 읽을 때 켠다(덧붙임 N2).
  Set<String> turnedOn = const {};

  /// 잡아 둔 동안 참([hold]) — 잡은 쪽만 [apply]로 이어 넣을 수 있다.
  bool _held = false;

  /// 다른 일이 끼지 못하게 잡아 둔다(판을 올린 뒤 DLC 폴더를 살피는 동안 — 고침 2회차 Minor 4): 창의 위 칸에 [line]을 적고 [running]이 참이 되어
  /// 다른 부탁은 '아직 도는 중'으로 거절된다. 잡은 쪽은 이어서 [apply]를 부르거나(그 일이 잡음을 이어받는다) [release]로 푼다. 이미 돌면 거짓.
  bool hold(String line) {
    if (running) return false;
    _start();
    _say(line);
    _held = true;
    return true;
  }

  /// [hold]를 푼다(이어 넣지 않을 때).
  void release() {
    if (!_held) return;
    _held = false;
    phase = DlcJobPhase.idle;
    lines.clear();
    _takePending();
    notifyListeners();
  }

  /// 도는 동안 온 알림([notice]) — 일이 끝나거나 잡음을 풀 때 [notes]에 합친다.
  final _pendingNotes = <String>[];

  void _takePending() {
    for (final line in _pendingNotes) {
      if (!notes.contains(line)) notes.add(line);
    }
    _pendingNotes.clear();
  }

  void _start({String? removeKey, List<String> offKeys = const [], List<String> onKeys = const []}) {
    lines.clear();
    notes.clear();
    stashedNote = null;
    lastDetail = null;
    turnedOn = const {};
    phase = DlcJobPhase.running;
    removingKey = removeKey ?? '';
    toggling = {for (final k in offKeys) k: false, for (final k in onKeys) k: true};
    notifyListeners();
  }

  void _say(String line) {
    final text = line.trimRight();
    if (text.isEmpty || text.startsWith('    at ')) return;
    lines.add(text);
    notifyListeners();
  }

  /// 끝난 뒤에도 남길 알림 — 같은 알림은 한 번(sync.json이 깨졌으면 엔진 앞 · COMMIT 뒤에 같은 실패가 두 번 난다 — ② Minor 7).
  void _note(String line) {
    if (notes.contains(line)) return;
    notes.add(line);
    _say(line);
  }

  void _finish(bool ok) {
    phase = ok ? DlcJobPhase.done : DlcJobPhase.failed;
    removingKey = '';
    _takePending();
    // 켜고 끄는 중 표시는 성공이면 앱 틀이 뼈대를 다시 읽은 뒤([reset])까지 둔다 — 그 사이 스위치가 옛 저장소의 값으로 되튀지 않게.
    if (!ok) toggling = const {};
    notifyListeners();
  }

  /// **고쳐 쓰기(계약 2-7-1)**: 저장소를 바꿔 넣지 않고 엔진이 제자리에서 바뀐 트랙만 한 거래로 고쳐 쓴다(실패하면 저장소 그대로) — DLC 파일 넣기 ·
  /// [removeKey] · [offKeys] · [onKeys]를 **엔진 하나로**([_applyWithEngine] — add_pack · remove_pack). 예전 배치 파일(.htlayout)은 엔진에 닿기 전에
  /// 알린다([dlcOldLayoutText] — 계획 P4 과제 11c).
  /// [stored]: 지금 저장소에 든 DLC 글자 id(빼기 · 끄기 · 켜기가 엔진에 갈 것인지 — null이면 모름: 빼기 · 끄기는 엔진에, 켜기는 보관함 · DLC 폴더에서).
  /// [offCards]: 끄는 DLC의 카드(끈 목록 `hidden.json`에 적어 저장소에서 빠진 뒤에도 DLC 관리 창이 그린다 — 앱 틀이 지금 뼈대로 뜬다).
  /// [preferGiven]: 메이커 미리보기(판정 R39) — 같은 id면 판과 상관없이 고른 파일(작업본)이 이긴다(`add_pack`의 `prefer_given` — 엔진이 판 대조를 건너뜀).
  /// 서재의 임시 사본에서만 쓴다(앱 틀 `_previewStore` — 폴더 · 끈 목록 맞추기도 그 사본 옆에서).
  /// 엔진은 [applier]로 부른다. 고쳐 쓰기가 끝난 뒤에만 DLC/ 폴더 · 끈 목록을 맞춘다(얹힌 몫 2). 늘 답을 돌려준다(던지지 않는다).
  Future<DlcApplied> apply({
    required String db,
    List<String> files = const [],
    String? removeKey,
    List<String> offKeys = const [],
    List<String> onKeys = const [],
    Set<String>? stored,
    Map<String, Map<String, dynamic>> offCards = const {},
    bool preferGiven = false,
  }) async {
    if (running && !_held) return const DlcApplied(ok: false);
    _held = false;
    _start(removeKey: removeKey, offKeys: offKeys, onKeys: onKeys);
    final run = _ApplyRun();
    try {
      await _applyWithEngine(run, db: db, files: files, removeKey: removeKey, offKeys: offKeys, onKeys: onKeys, stored: stored, offCards: offCards, preferGiven: preferGiven);
    } catch (e) {
      _say('${removeKey != null || offKeys.isNotEmpty ? 'DLC를 빼지 못했습니다' : 'DLC를 넣지 못했습니다'}: ${dlcErrorText(e)}');
      run.ok = false;
    }
    lastCode = run.ok ? null : run.code;
    _finish(run.ok);
    return DlcApplied(ok: run.ok, data: run.data, storeChanged: run.changed, reopen: run.reopen, firstPos: run.firstPos);
  }

  /// DLC 파일 · 빼기 · 지우기 · 끄기 · 켜기를 **엔진 하나로**(계획 P4 과제 10b · 계약 2-7-1 — Node 없음 · 휴대폰과 컴퓨터가 같다):
  ///   1) 고른 파일의 머리를 본다([readDlcFileHead] — DLC가 아니거나 읽지 못하면 엔진에 닿기 전에 멈춘다 · 저장소 그대로).
  ///   2) 엔진 요청을 차례로 — 넣기 `add_pack files`(경로 여럿이면 한 번) · 지우기 `remove_pack delete:true` · 끄기 `remove_pack delete:false`(DLC마다 —
  ///      원본은 저장소의 보관함) · 켜기 `add_pack ids`(보관함에 있으면) + `files`(없으면 DLC 폴더의 그 파일). 꺼 둔(저장소에 없는) DLC 지우기는
  ///      보관함에 있으면 `remove_pack delete:true`(보관함의 원본까지 — 판정 R42 · 뼈대 그대로라 다시 읽지 않음), 보관함에 없으면 · 저장소에 든 채
  ///      화면에서만 끈 DLC를 켜면 엔진에 쓸 것이 없다.
  ///   3) 요청마다 COMMIT 직후 묘비(`sync.json` — 판정 R33) → DLC 폴더(넣은 파일 들이기 · 같은 id의 다른 파일 · 지운 DLC의 파일 지우기) → 끈 목록.
  ///      한 요청이 실패하면 거기서 멈춘다(앞 요청은 이미 고쳐 썼다 — 그 몫의 폴더 · 끈 목록은 맞춘다).
  /// 거절은 엔진의 `code`로 갈라 쉬운 말로([dlcRefusalText]). 같은 판의 다른 파일로 바꿨으면(`replaced`) 알린다.
  Future<void> _applyWithEngine(
    _ApplyRun run, {
    required String db,
    List<String> files = const [],
    String? removeKey,
    List<String> offKeys = const [],
    List<String> onKeys = const [],
    Set<String>? stored,
    Map<String, Map<String, dynamic>> offCards = const {},
    bool preferGiven = false,
  }) async {
    final heads = <DlcFileHead>[];
    for (final file in files) {
      final read = readDlcFileHead(file);
      final head = read.head;
      if (head == null) {
        _say(read.problem!);
        run.ok = false;
        return;
      }
      heads.add(head);
    }
    bool inStore(String key) => stored?.contains(key) ?? true;
    // 꺼 둔(저장소에 없는) DLC를 지울 때는 보관함을 본다(판정 R42): 거기 있으면 엔진이 그 원본까지 버리고(`remove_pack delete:true` — 조합 그대로라 배치 없이),
    // 없거나(예전 길로 끈 것 — 원본은 DLC 폴더에만) 모르면 엔진에 쓸 것이 없다(없는 id는 엔진이 거절해 지우기가 막히므로 보내지 않는다).
    final shelved = removeKey != null && !inStore(removeKey) && ((await _keptIds())?.contains(removeKey) ?? false);
    final steps = <_EngineStep>[
      if (heads.isNotEmpty) _EngineStep.add(heads, preferGiven: preferGiven),
      if (removeKey != null) _EngineStep.remove(removeKey, inStore: inStore(removeKey), shelved: shelved),
      for (final key in offKeys) _EngineStep.off(key, inStore: inStore(key), card: offCards[key]),
    ];
    if (onKeys.isNotEmpty) {
      final away = [for (final k in onKeys) if (stored != null && !stored.contains(k)) k];
      final kept = away.isEmpty ? const <String>{} : await _keptIds();
      final ids = <String>[], from = <DlcFileHead>[], lost = <String>[];
      for (final key in away) {
        final local = kept != null && kept.contains(key) ? null : _folderFile(db, key);
        if (local != null) {
          from.add(local);
        } else if (kept == null || kept.contains(key)) {
          ids.add(key);
        } else {
          lost.add(key);
        }
      }
      // 원본이 보관함에도 DLC 폴더에도 없는 DLC만 건너뛰고 나머지는 켠다(모두 켜기 — ② Minor 6). 모두 그렇다면 엔진에 닿지 않고 멈춘다.
      if (lost.isNotEmpty) {
        final names = lost.map((k) => '«${hidden.cards[k]?['name'] ?? k}»').join(' · ');
        final line = "켤 DLC $names의 원본이 저장소에도 DLC 폴더에도 없어 켜지 않았습니다 — 그 DLC 파일을 '파일에서 더하기'로 다시 넣어 주세요.";
        if (lost.length == onKeys.length) {
          _say(line);
          run.ok = false;
          return;
        }
        _note(line);
      }
      steps.add(_EngineStep.on([for (final k in onKeys) if (!lost.contains(k)) k], ids: ids, files: from));
    }
    // 모두 끄기가 도중에 멈추면 끈 것과 멈춘 자리를 함께 알린다(② Minor 6).
    final turnedOff = <String>[];
    String nameOf(String key) => '«${offCards[key]?['name'] ?? hidden.cards[key]?['name'] ?? key}»';
    for (final (index, step) in steps.indexed) {
      // 요청마다 쓸 저장소(`path` — 지금 연 저장소)를 싣는다(판정 R59 M-4 앱 몫): 엔진(갈래 1)은 열린 저장소와 다르면 쓰지 않고 거절한다 — 앱이 다른 저장소를
      // 연 뒤 늦게 닿은 요청이 엉뚱한 저장소를 고쳐 쓰지 않게(이 칸을 모르는 엔진은 무시).
      final request = step.request == null ? null : {...step.request!, 'path': db};
      if (request != null) {
        _say(step.progress(hidden));
        // 빼기 · 끄기의 묘비는 엔진에 맡기기 **전에**(판정 R60 M-1) — COMMIT 뒤 묘비를 적기 전에 꺼지면 DLC 폴더의 그 파일을 판 올림 뒤 다시 들이기가
        // 되살린다. 거절되면(저장소 그대로) 되돌린다.
        final tombBefore = step.removing ? DlcFolderState.read(db) : null;
        if (step.removing) _remember(db, removeKey: step.removeKey, offKeys: step.offKeys);
        if (!await _engine(run, request, quiet: true)) {
          if (tombBefore != null) {
            try {
              DlcFolderState.update(db, (_) => tombBefore);
            } catch (_) {}
          }
          if (run.error != null) {
            final why = _refusalLine(db, run, step);
            _say(step.kind == _StepKind.off && turnedOff.isNotEmpty ? '${turnedOff.join(' · ')}은(는) 껐고 ${nameOf(step.offKeys.single)}에서 멈췄습니다: $why' : why);
          }
          // 예전 배치로만 든 DLC(원본 없음)의 .htpack을 골랐는데 저장소가 받지 못했으면(표 없는 옛 저장소 · 원본 채우기를 아직 못 받는 엔진) 그 파일을
          // DLC 폴더에 둔다 — 시드 잇기가 새 판 자료로 옮길 때 그 원본으로 함께 넣는다(계획 P4 과제 11c — 판정 R34 A로 지킨 저장소의 길).
          if (step.kind == _StepKind.add && !preferGiven && (run.code == 'calendar' || run.code == 'original')) _stashOriginals(db, heads);
          run.ok = false;
          return;
        }
      }
      // COMMIT 직후 묘비(판정 R33) → DLC 폴더 · 끈 목록. 엔진에 쓸 것이 없던 걸음(보관함에 없는 꺼 둔 DLC 지우기 · 화면에서만 끈 DLC 켜기)도 같은 차례.
      _remember(db, removeKey: step.removeKey, offKeys: step.offKeys, onKeys: step.onKeys);
      _settle(_stepPlan(db, step), db);
      // 넣거나 켠 DLC는 끈 목록에서 빼 켠다(끈 DLC를 다시 더하면 켠다) — 앱 틀이 뼈대를 다시 읽을 때 [turnedOn]을 켠다.
      if (step.onKeys.isNotEmpty) _turnOn(db, step.onKeys.toSet());
      // 미리보기는 판과 상관없이 작업본으로 바꾼다 — '같은 판의 다른 파일' 알림은 맞지 않아 하지 않는다(앱 틀이 '작업본을 얹었습니다'로 알린다).
      // 형식 4 내림 알림(엔진 답의 `notes`)은 알리지 않는다 — 4단계에서 앱이 사람 띠 · 빌린 직위 줄 · 문화권 줄을 그리게 되어 '아직 그리지 않습니다' 줄을 걷었다(0.1.0).
      if (request != null && step.kind == _StepKind.add) {
        // 옛 저장소(달력 표 다섯)에 없는 달력으로 날짜를 적은 DLC — 엔진이 그 달력만 건너뛰고 넣었다는 한 줄(감독 결정 2026-10-25).
        for (final line in dlcCalendarNotes(run.data['notes'])) {
          _note(line);
        }
      }
      if (request != null && step.kind == _StepKind.add && !preferGiven) {
        _sayReplaced(run.data, heads);
        // 휴대폰이 지킴으로 정한 판(`.seed-kept` — 원본 없는 DLC 때문)의 저장소에 넣기가 됐으면(엔진이 원본을 채웠을 수 있다) 표식을 지워 다음에 켤 때
        // 새 판 자료로 옮기기를 다시 해 본다(① m-3 — 여전히 막히면 시드 잇기가 다시 적는다).
        _forgetSeedKept(db);
      }
      // 끄기인데 엔진이 원본을 남기지 못해 지웠으면(원본 없이 든 DLC — 앱은 그런 카드의 끄기를 화면에서만 하지만 뜻밖의 경우) 되찾는 길을 알린다(고침 1회차 I-1).
      if (request != null && step.kind == _StepKind.off) _sayDeleted(run.data, step);
      if (step.kind == _StepKind.off) turnedOff.add(nameOf(step.offKeys.single));
      // 지운 DLC는 보관함 카드에서도 뺀다 — 꺼 둔 DLC를 보관함에서만 지우면 뼈대를 다시 읽지 않아(보관함을 다시 읽을 일도 없어) 카드가 남는다(② I-1).
      if (step.kind == _StepKind.remove && kept.any((k) => k.id == step.removeKey)) {
        kept = [for (final k in kept) if (k.id != step.removeKey) k];
        notifyListeners();
      }
      // COMMIT은 끝났는데 엔진이 저장소를 다시 열지 못했다(`committed`) — 닫힌 저장소에 다음 걸음을 보내지 않고 멈춘다(앱 틀이 다시 연다 · ② Minor 5).
      if (run.reopen && index < steps.length - 1) {
        final rest = [for (final s in steps.skip(index + 1)) ...[...s.offKeys.map(nameOf), ...s.onKeys.map(nameOf), if (s.removeKey != null) nameOf(s.removeKey!)]];
        _say('저장소를 다시 여느라 ${rest.join(' · ')}은(는) ${step.kind == _StepKind.off ? '끄지' : '하지'} 않았습니다 — 다시 해 주세요.');
        run.ok = false;
        return;
      }
    }
    run.ok = true;
    if (run.changed && !run.reopen) _sayDone(run.data);
  }

  /// 엔진 거절의 알림 한 줄([dlcRefusalText] — 걸음의 갈래로 '넣지 · 빼지 · 켜지'). 휴대폰이 지킴으로 정한 저장소(`.seed-kept` — 원본 없는 DLC 때문에 새 판
  /// 자료로 옮기지 못함 · 판정 R34 A)의 `calendar`는 '앱을 새 판으로 올리면'(이미 새 판이다)이 맞지 않아 먼저 할 일을 말한다(② Minor 1).
  String _refusalLine(String db, _ApplyRun run, _EngineStep step) {
    final which = run.error!.trim().isEmpty ? '' : ' (자세히: ${dlcPlainEngineError(run.error!)})';
    if (run.code == 'calendar' && File(seedKeptPath(db)).existsSync() && packFacts.values.any((f) => !f.original)) {
      return "이 저장소는 원본 없는 DLC 때문에 아직 앱의 새 판 자료로 옮기지 못해 DLC를 넣거나 뺄 수 없습니다 — 먼저 '원본 없음' DLC의 .htpack을 "
          "'파일에서 더하기'로 넣어 주세요(앱이 DLC 폴더에 두었다가 다시 켤 때 함께 옮깁니다).$which";
    }
    return dlcRefusalText(run.code, run.error!, removing: step.removing, turningOn: step.kind == _StepKind.on);
  }

  /// 원본 없이 든 DLC([packFacts]의 `original` 거짓 — 예전 메이커 배치로만 넣은 것)의 .htpack(같은 id · 같은 판 — 저장소가 판을 모르면 id만)을 골랐는데
  /// 저장소가 받지 못했으면(`calendar` — 표 없는 옛 저장소 · `original` — 원본 채우기를 아직 못 받는 엔진) 그 파일을 저장소 옆 DLC 폴더에
  /// [dlcOriginalFileName]으로 둔다 — 시드 잇기(`ui/seed_carry.dart` · 판정 R34 D)가 다음에 새 판 자료로 옮길 때 그 원본으로 함께 넣는다. 휴대폰이 이 판을
  /// 지키기로 적어 둔 표식(`<저장소>.seed-kept` — 판정 R34 A)은 지워 다음에 켤 때 다시 해 보게 한다(계획 P4 과제 11c — 예전 배치로만 든 DLC의 길이 막히지
  /// 않게). 둔 것이 있으면 알린다(마지막 줄 — 창의 위 칸 · 앱 틀의 알림). 표식이 있는데 둘 것이 없으면(새 DLC를 넣으려 함) 먼저 할 일을 알린다.
  void _stashOriginals(String db, List<DlcFileHead> heads) {
    final dir = _dlcDir(db);
    final placed = <String>[], otherVersion = <String>[];
    for (final h in heads) {
      final fact = packFacts[h.id];
      if (fact == null || fact.original) continue;
      // 판이 다른 .htpack은 시드 잇기가 그 DLC의 원본으로 쓰지 않는다(같은 id · 판만) — 두지 않고 맞는 판을 말한다(11c 검토).
      if (fact.version.isNotEmpty && compareDlcVersion(fact.version, h.version) != 0) {
        otherVersion.add('«${h.name}»은(는) 저장소에 든 판(v${fact.version})과 달라 원본으로 둘 수 없습니다 — 저장소와 같은 판(v${fact.version})의 .htpack을 골라 주세요.');
        continue;
      }
      final target = '$dir${Platform.pathSeparator}${dlcOriginalFileName(h.id, h.version)}';
      try {
        Directory(dir).createSync(recursive: true);
        copyFileAtomic(h.path, target);
        placed.add(h.name);
      } catch (e) {
        _note('«${h.name}»의 원본(.htpack)을 DLC 폴더에 두지 못했습니다: ${dlcErrorText(e)}');
      }
    }
    otherVersion.forEach(_note);
    // 표식이 있는데 둘 것이 없으면(새 DLC를 넣으려 함) 먼저 할 일은 거절 알림이 이미 말했다([_refusalLine]).
    if (placed.isEmpty) return;
    final kept = File(seedKeptPath(db));
    var retry = false;
    try {
      if (kept.existsSync()) {
        kept.deleteSync();
        retry = true;
      }
    } catch (_) {}
    // 아직 DLC 폴더에도 원본이 없는 원본 없는 DLC — 시드 잇기는 하나라도 원본이 없으면 다시 지킨다(R34 A): 그것도 함께 골라 넣으라고 말한다 — 그때는
    // '다시 켜면 옮깁니다'를 약속하지 않는다(① 넘김).
    final folder = _folderHeads(db);
    bool inFolder(String id, String version) => folder.any((f) => f.id == id && (version.isEmpty || compareDlcVersion(f.version, version) == 0));
    final missing = [for (final e in packFacts.entries) if (!e.value.original && !inFolder(e.key, e.value.version)) e.key];
    final placedNames = placed.map((n) => '«$n»').join(' · ');
    // 휴대폰은 늘 '다시 켜면'(시드 잇기가 켤 때마다 다시 해 본다 — 둘째 원본부터는 표식이 이미 지워져 있다) · 컴퓨터는 지킴 표식을 지웠을 때만.
    final note = missing.isEmpty
        ? '$placedNames의 원본(.htpack)을 DLC 폴더에 두었습니다 — 이 저장소에는 지금 넣을 수 없어 '
              '${phone || retry ? '앱을 다시 켜면' : '앱을 새 판으로 올리면'} 새 판 자료로 옮기며 함께 넣습니다.'
        : '$placedNames의 원본(.htpack)을 DLC 폴더에 두었습니다 — 원본 없는 DLC ${missing.map((id) => '«$id»').join(' · ')}의 .htpack도 있어야 새 판 자료로 '
              '옮길 수 있습니다: 남은 것의 .htpack도 함께 골라 넣어 주세요.';
    _note(note);
    // 앱 틀은 이 알림만 보인다 — 판이 다른 파일 알림을 가리지 않게 함께 싣는다(② Minor 7).
    stashedNote = [...otherVersion, note].join(' ');
  }

  /// 휴대폰의 지킴 표식(`<저장소>.seed-kept`)을 지운다(있으면 · 실패는 조용히).
  static void _forgetSeedKept(String db) {
    try {
      final kept = File(seedKeptPath(db));
      if (kept.existsSync()) kept.deleteSync();
    } catch (_) {}
  }

  /// 마지막 일이 원본 없는 DLC의 .htpack을 DLC 폴더에 두고 끝났으면 그 알림([_stashOriginals]) — 앱 틀은 '더하기에 실패했습니다 — …두었습니다'(모순처럼
  /// 읽힘 — 11c 검토) 대신 이것만 알린다. 아니면 null(다음 일을 시작할 때 비운다).
  String? stashedNote;

  /// 저장소의 보관함(`{"op":"kept_packs"}` — 꺼 둔 DLC의 원본)에 든 DLC 글자 id. 읽을 길이 없거나 실패하면 null(모름).
  Future<Set<String>?> _keptIds() async {
    final ask = reader;
    if (ask == null) return null;
    try {
      final answer = await ask({'op': 'kept_packs'});
      final list = answer['data'];
      if (list is! List) return null;
      return {for (final p in list) if (p is Map && '${p['id'] ?? ''}'.isNotEmpty) '${p['id']}'};
    } catch (_) {
      return null;
    }
  }

  /// DLC 폴더(저장소 옆 `DLC/`)에서 그 id의 파일 — 판이 가장 높은 것. 없으면 null.
  static DlcFileHead? _folderFile(String db, String id) {
    DlcFileHead? best;
    for (final head in _folderHeads(db)) {
      if (head.id == id && (best == null || compareDlcVersion(head.version, best.version) > 0)) best = head;
    }
    return best;
  }

  /// DLC 폴더의 DLC 파일(.htpack)마다의 머리 — 읽지 못하는 파일은 건너뛴다.
  static List<DlcFileHead> _folderHeads(String db) {
    final dir = Directory(_dlcDir(db));
    if (!dir.existsSync()) return const [];
    final out = <DlcFileHead>[];
    try {
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.htpack')) continue;
        final head = readDlcFileHead(entity.path).head;
        if (head != null) out.add(head);
      }
    } catch (_) {}
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  static String _dlcDir(String db) => '${File(db).absolute.parent.path}${Platform.pathSeparator}DLC';

  /// 걸음 하나가 끝난 뒤 맞출 DLC 폴더와 끈 목록([_settle]의 재료).
  ///   · 넣기: 넣은 파일을 폴더로 들이고(같은 이름이면 덮음) 폴더의 같은 id 다른 파일은 지운다 — 폴더는 판을 올린 뒤 다시 들이는 원본(판정 R32)이자 시드 잇기의
  ///     원본 없는 DLC의 원본이라 id마다 하나. 끈 DLC를 다시 더하면 켠다(끈 목록에서 뺌 — [_turnOn]).
  ///   · 지우기: 그 id의 파일을 모두 지운다(묘비의 파일 — 못 지우면 다음에 열 때 다시) · 끈 목록에서 뺀다.
  ///   · 끄기: 파일은 둔다(판을 올려 보관함이 사라져도 다시 켤 원본) · 끈 목록에 카드와 함께 올린다.
  DlcApplyPlan _stepPlan(String db, _EngineStep step) {
    final dir = _dlcDir(db), sep = Platform.pathSeparator;
    switch (step.kind) {
      case _StepKind.add:
        final ids = {for (final h in step.heads) h.id};
        // 사본 이름은 고른 파일의 이름이 아니라 `<id>-v<판>.htpack` — 내려받은 이름이 같은 다른 DLC의 사본을 덮지 않게(판정 R60 I-2).
        final copy = [for (final h in step.heads) (File(h.path).absolute.path, '$dir$sep${dlcOriginalFileName(h.id, h.version)}')];
        final keep = {for (final (_, target) in copy) target.toLowerCase()};
        // 같은 id의 다른 사본은 지운다(폴더는 id마다 하나) — 넣은 판보다 **높은 판**은 남긴다(판정 R60 M-2: 판 올림 뒤 다시 들이기가 쓸 더 새 원본).
        final added = {for (final h in step.heads) h.id: h.version};
        final targetOf = {for (final h in step.heads) h.id: '$dir$sep${dlcOriginalFileName(h.id, h.version)}'};
        final drop = [
          for (final h in _folderHeads(db))
            if (ids.contains(h.id) && !keep.contains(File(h.path).absolute.path.toLowerCase()) && compareDlcVersion(h.version, added[h.id] ?? '') <= 0) h,
        ];
        return DlcApplyPlan(copy: copy, drop: [for (final h in drop) h.path], dropNeeds: {for (final h in drop) h.path: targetOf[h.id]!});
      case _StepKind.remove:
        final gone = [for (final h in _folderHeads(db)) if (h.id == step.removeKey) h.path];
        return DlcApplyPlan(drop: gone, tomb: gone, hidden: _hiddenWith(db, forget: {step.removeKey!}));
      case _StepKind.off:
        final key = step.offKeys.single;
        return DlcApplyPlan(hidden: _hiddenWith(db, off: {key: step.card ?? DlcHidden.read(db).cards[key] ?? {'name': key}}));
      case _StepKind.on:
        return const DlcApplyPlan();
    }
  }

  /// 끈 목록(`hidden.json`)을 바꾼 새 값 — 바뀌지 않으면 null. [forget]은 빼고(카드도), [off]는 카드와 함께 올린다.
  static Map<String, dynamic>? _hiddenWith(String db, {Set<String> forget = const {}, Map<String, Map<String, dynamic>> off = const {}}) {
    final before = DlcHidden.read(db);
    final gone = forget;
    final next = {...before.off.difference(gone), ...off.keys};
    final cards = {
      for (final e in before.cards.entries) if (next.contains(e.key) && !off.containsKey(e.key)) e.key: e.value,
      ...off,
    };
    if (setEquals(next, before.off) && mapEquals(cards.map((k, v) => MapEntry(k, jsonEncode(v))), before.cards.map((k, v) => MapEntry(k, jsonEncode(v))))) return null;
    return {'version': 1, 'off': [...next]..sort(), 'baseRemoved': before.baseRemoved, 'cards': cards};
  }

  /// 같은 판의 다른 파일로 바꿔 넣었으면 알린다 — DLC 이름은 고른 파일의 머리에서. 엔진은 원본이 바뀌면 늘 `replaced`에
  /// `{id, old_version, new_version, old_sha256|null, new_sha256}`을 싣는다(판 올림 · 원본 채우기 포함 — 판정 R43): **앱이 거른다** — 판이 같고
  /// 옛 원본이 있던 것(`old_sha256`이 null이 아님)만 알린다.
  void _sayReplaced(Map<String, dynamic> data, List<DlcFileHead> heads) {
    final replaced = data['replaced'];
    final ids = <String>[
      if (replaced is List)
        for (final r in replaced)
          if (r is Map && r['old_sha256'] != null && compareDlcVersion('${r['old_version'] ?? ''}', '${r['new_version'] ?? ''}') == 0) '${r['id'] ?? ''}',
    ].where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return;
    String name(String id) => heads.where((h) => h.id == id).map((h) => h.name).firstOrNull ?? id;
    _note('${ids.map((id) => '«${name(id)}»').join(' · ')}은(는) 같은 판의 다른 파일로 바꿨습니다.');
  }

  /// 끄기 답의 `deleted`에 그 DLC가 들었으면(남길 원본이 없어 보관함에 두지 못하고 지움) 되찾는 길을 알린다.
  void _sayDeleted(Map<String, dynamic> data, _EngineStep step) {
    final deleted = data['deleted'];
    if (deleted is! List || !deleted.contains(step.offKeys.single)) return;
    final name = step.card?['name'] ?? hidden.cards[step.offKeys.single]?['name'] ?? step.offKeys.single;
    _note("«$name»은(는) 원본(.htpack)이 없어 끄면서 저장소에서 지워졌습니다 — 다시 켜려면 그 DLC 파일을 '파일에서 더하기'로 넣어 주세요.");
  }

  /// 엔진에 한 번 맡긴다 — 성공이면 [run]에 답을 쌓고 참. 실패면 까닭을 말하고 거짓(COMMIT 뒤 다시 열기만 실패했으면 저장소는 바뀌었다 — [run.reopen]).
  Future<bool> _engine(_ApplyRun run, Map<String, dynamic> request, {bool quiet = false}) async {
    final call = applier;
    if (call == null) {
      _say('자료 처리부에 고쳐 쓰기를 맡길 길이 없습니다.');
      return false;
    }
    final Map<String, dynamic> answer;
    try {
      answer = await call(request);
    } catch (e) {
      _say('저장소를 고쳐 쓰지 못했습니다: ${dlcErrorText(e)}');
      return false;
    }
    if (answer['ok'] == true) {
      final data = answer['data'] is Map ? Map<String, dynamic>.from(answer['data'] as Map) : <String, dynamic>{};
      run.took(data);
      return true;
    }
    final why = '${answer['error'] ?? '저장소를 고쳐 쓰지 못했습니다.'}';
    if (answer['committed'] == true) {
      // 쓰기는 끝났다(파일이 바뀜) — 앱 틀이 저장소를 다시 열고 뼈대를 처음부터 읽는다. 폴더 · 끈 목록은 맞춘다(저장소가 바뀌었으므로).
      // 엔진의 '…다시 열어 주세요'는 앱이 스스로 다시 열므로 알리지 않고 보관한다(다시 열기도 실패하면 앱 틀이 알린다 — ② Minor 5).
      run
        ..changed = true
        ..reopen = true
        ..pos = 0;
      lastDetail = why;
      return true;
    }
    if (!quiet) _say(why);
    run
      ..error = why
      ..code = answer['code'] is String ? answer['code'] as String : null;
    // 엔진의 개발자 말(`detail` — 배치 실패의 원래 글 · 갈래 1)은 알림 대신 일에 보관한다(② Minor 4).
    lastDetail = answer['detail'] is String ? answer['detail'] as String : null;
    return false;
  }

  /// [keys]를 끈 목록(`DLC/hidden.json`)에서 빼고(카드도) [turnedOn]에 적는다 — 앱 틀이 뼈대를 다시 읽을 때 켠다. 쓰지 못하면 알린다(저장소는 이미 고쳐 썼다).
  void _turnOn(String db, Set<String> keys) {
    final before = DlcHidden.read(db);
    final on = keys.intersection(before.off);
    if (on.isEmpty) return;
    try {
      DlcHidden.save(db, {
        'version': 1,
        'off': [...before.off.difference(on)]..sort(),
        'baseRemoved': before.baseRemoved,
        'cards': {for (final e in before.cards.entries) if (!on.contains(e.key)) e.key: e.value},
      });
      turnedOn = {...turnedOn, ...on};
    } catch (e) {
      // 저장소에는 들었지만 끈 목록에 남아 다시 읽은 화면에서도 꺼진 채다 — 그 사정과 할 일을 말한다(알림과 화면이 맞게 · ② Minor 7).
      final names = on.map((k) => '«${before.cards[k]?['name'] ?? k}»').join(' · ');
      _note('$names은(는) 저장소에 들었지만 끈 목록(hidden.json)을 고치지 못해 화면에서는 꺼진 채입니다 — 그 파일을 지우거나 고친 뒤 DLC 관리에서 '
          '켜 주세요(${dlcErrorText(e)}).');
    }
  }

  /// 끝난 줄 — 사용자 말로(엔진 속 사정인 '다시 쓴 트랙' 대신 새 · 바뀐 · 빠진 트랙의 수).
  void _sayDone(Map<String, dynamic> data) {
    int count(String key) => (data[key] as List?)?.length ?? 0;
    final ms = data['ms'];
    final parts = [
      if (count('added') > 0) '새 트랙 ${count('added')}개',
      if (count('rewrote') > 0) '바뀐 트랙 ${count('rewrote')}개',
      if (count('removed') > 0) '빠진 트랙 ${count('removed')}개',
    ];
    _say('마쳤습니다 — ${parts.isEmpty ? '바뀐 트랙 없음' : parts.join(' · ')}${ms is num ? ' · ${(ms / 1000).toStringAsFixed(1)}초' : ''}');
  }

  /// COMMIT 직후의 묘비(판정 R33 — `DLC/sync.json` · 원자적): 뺀 DLC는 [DlcFolderState.removed], 끈 DLC는 [DlcFolderState.off]에 적고 켠 DLC는 뺀다.
  /// 폴더 지우기 · 끈 목록 쓰기가 실패해도 판을 올린 뒤 다시 들이기가 그 DLC를 되살리지 않게. 쓰지 못하면 알린다(저장소는 이미 고쳐 썼다).
  void _remember(String db, {String? removeKey, List<String> offKeys = const [], List<String> onKeys = const []}) {
    try {
      rememberDlcChange(db, removeKey: removeKey, offKeys: offKeys, onKeys: onKeys);
    } catch (e) {
      _note('뺀 · 끈 DLC를 DLC 폴더 기억(sync.json)에 적지 못했습니다 — 판을 올린 뒤 그 DLC가 다시 들 수 있습니다: ${dlcErrorText(e)}');
    }
  }

  /// 고쳐 쓰기가 끝난 뒤: DLC/ 폴더를 맞추고(들이기 먼저 · 지우기는 뒤 — 도중에 멈춰도 폴더에서 DLC가 먼저 사라지지 않게) 끈 목록을 적는다(얹힌 몫 2).
  /// 저장소는 이미 고쳐 썼으므로 실패는 알림만 남기고, 파일마다 따로 해 첫 실패에서 멈추지 않는다. 폴더는 판을 올린 뒤 다시 들이는 원본(판정 R32)이다 —
  /// 못 지운 파일은 묘비([_remember])가 다시 들이지 않게 막고 다음에 앱을 열 때 다시 지운다.
  void _settle(DlcApplyPlan plan, String db) {
    String name(String path) => path.split(RegExp(r'[\\/]')).last;
    if (plan.copy.isNotEmpty) {
      try {
        Directory('${File(db).absolute.parent.path}${Platform.pathSeparator}DLC').createSync(recursive: true);
      } catch (_) {}
    }
    final missing = <String>{};
    for (final (source, target) in plan.copy) {
      try {
        copyFileAtomic(source, target);
      } catch (e) {
        missing.add(target);
        _note('${name(source)}을(를) DLC 폴더에 두지 못했습니다 — 저장소에는 들었지만, 판을 올린 뒤 다시 들이려면 그 파일을 DLC 폴더에 넣어 주세요: ${dlcErrorText(e)}');
      }
    }
    for (final gone in plan.drop) {
      // 새 사본을 두지 못한 DLC의 옛 사본은 남긴다(① m-1 — 폴더에 그 DLC의 원본이 하나도 없게 되지 않게).
      if (missing.contains(plan.dropNeeds[gone])) continue;
      try {
        final file = File(gone);
        if (file.existsSync()) file.deleteSync();
      } catch (e) {
        // 열 때 마저 지우는 것은 묘비(뺀 DLC)의 파일뿐이다(`DlcFolderSync.pending`) — 그 밖의 남은 파일에는 그 약속을 하지 않는다(8 검토).
        _note(plan.tomb.contains(gone)
            ? '${name(gone)}을(를) DLC 폴더에서 지우지 못했습니다 — 다음에 앱을 열 때 다시 지웁니다(그동안 다시 들이지 않습니다): ${dlcErrorText(e)}'
            : '${name(gone)}을(를) DLC 폴더에서 지우지 못했습니다 — 이미 든 DLC와 겹치는 남은 파일이라 다시 들이지 않습니다(손으로 지워도 됩니다): ${dlcErrorText(e)}');
      }
    }
    final hidden = plan.hidden;
    if (hidden != null) {
      try {
        DlcHidden.save(db, hidden);
      } catch (e) {
        _note('끈 DLC 목록(hidden.json)을 적지 못했습니다 — 저장소는 고쳐 썼습니다. 끈 DLC가 DLC 관리에 보이지 않으면 '
            "DLC 폴더(${File(db).absolute.parent.path}${Platform.pathSeparator}DLC)의 그 파일을 '파일에서 더하기'로 고르세요(${dlcErrorText(e)}).");
      }
    }
  }

  /// 쉼으로 돌아간다(알림을 치운 뒤). 끝난 뒤의 알림([notes])은 다음 일까지 남긴다.
  void reset() {
    if (running) return;
    phase = DlcJobPhase.idle;
    lines.clear();
    toggling = const {};
    notifyListeners();
  }
}

/// 앱 틀의 고쳐 쓰기 한 번(계약 2-7) — 엔진을 닫았다 다시 열지 않는다: [job]이 배치를 셈하고([DlcJob.apply]) 엔진의 쓰기 일꾼([engineApply])에 맡기는 동안
/// 화면은 옛 저장소로 끌리고, 쓰기 직전부터 뼈대를 다시 읽을 때까지 새 타일 · 빈 줄 접기 물음을 멈춘다([TimelineScene.storeWriting] — COMMIT 뒤의
/// 새 줄 번호가 옛 뼈대에 섞이지 않게). 저장소가 바뀌었으면 [reload](앱 틀의 뼈대 다시 읽기 — `first_pos`부터만 타일을 버림)를 부른다.
/// 엔진이 COMMIT 뒤 다시 열지 못했으면(`committed`) 그때만 [engineCall]로 `open`한다. 실패하면 저장소 · 화면 그대로(까닭은 [job]의 창 위 칸).
class DlcApplyFlow {
  DlcApplyFlow({required this.job, required this.scene, required this.engineCall, required this.engineApply, required this.reload, this.beforeWrite});
  final DlcJob job;
  final TimelineScene scene;

  /// 엔진의 읽기 일꾼(`{"op":"open"}` — 다시 열기가 실패했을 때만).
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> query) engineCall;

  /// 엔진의 쓰기 일꾼(`{"op":"add_pack" | "remove_pack"}` → `archive_call`의 답 — 앱 틀의 `_writeStore`).
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> request) engineApply;

  /// 뼈대를 다시 읽는다(keepBefore = 엔진의 `first_pos`).
  final Future<void> Function(int keepBefore) reload;

  /// 엔진이 쓰기 직전(옛 저장소 · 한 번) — 앱 틀이 다시 읽은 뒤 옮겨 적을 것(옛 띠 번호 → 이름 · uid)을 옛 저장소에서 셈한다(고침 2회차 Minor 2).
  final Future<void> Function()? beforeWrite;

  Future<DlcApplied> run({
    required String db,
    List<String> files = const [],
    String? removeKey,
    List<String> offKeys = const [],
    List<String> onKeys = const [],
    Set<String>? stored,
    Map<String, Map<String, dynamic>> offCards = const {},
    bool preferGiven = false,
  }) async {
    var wrote = false, asked = false;
    // 보관함 읽기(켜기) — 읽기 일꾼의 답 겉(`{"ok","data"}`)은 그대로 · 던지면 모르는 것으로.
    job.reader = (query) async => Map<String, dynamic>.from(await engineCall(query));
    job.applier = (request) async {
      if (!wrote && !asked) {
        asked = true;
        try {
          await beforeWrite?.call();
        } catch (_) {}
      }
      scene.storeWriting = true;
      Map<String, dynamic> answer;
      try {
        answer = await engineApply(request);
      } catch (e) {
        answer = {'ok': false, 'error': '저장소를 고쳐 쓰지 못했습니다: ${dlcErrorText(e)}'};
      }
      if (answer['ok'] == true || answer['committed'] == true) {
        wrote = true;
      } else if (!wrote) {
        // 저장소 그대로 — 멈췄던 물음을 푼다(화면 그대로).
        scene.storeWriting = false;
      }
      return answer;
    };
    final done = await job.apply(db: db, files: files, removeKey: removeKey, offKeys: offKeys, onKeys: onKeys, stored: stored, offCards: offCards, preferGiven: preferGiven);
    // 끈 목록이 바뀌었을 수 있다(끄기 · 켜기 · 끈 DLC를 빼거나 다시 더하기) — 뼈대를 다시 읽기 **전에** 읽는다: 다시 읽기가 이 목록으로 켤 DLC를 정한다
    // (늦게 읽으면 켠 DLC가 저장소에 들고도 화면에서 꺼진 채 들어온다).
    if (done.ok || done.storeChanged) job.loadHidden(db);
    // 엔진도 앱도 다시 열지 못했거나 뼈대를 읽다 던지면 예외를 내보내지 않고 알림으로 끝낸다(고침 2회차 Minor 3 — 닫힌 저장소에 묻지 않게 다시 읽지 않는다).
    var restart = false;
    try {
      if (done.reopen) {
        try {
          await engineCall({'op': 'open', 'path': db});
        } catch (e) {
          restart = true;
          job._note('저장소는 고쳐 썼지만 다시 열지 못했습니다 — 앱을 다시 켜 주세요: ${dlcErrorText(e)}');
        }
      }
      if (!restart && done.storeChanged) {
        try {
          await reload(done.firstPos);
        } catch (e) {
          restart = true;
          job._note('저장소는 고쳐 썼지만 화면을 다시 읽지 못했습니다 — 앱을 다시 켜 주세요: ${dlcErrorText(e)}');
        }
      }
    } finally {
      scene.storeWriting = false;
    }
    if (restart) return done._needsRestart();
    return done;
  }
}

/// 엔진 길([DlcJob._applyWithEngine])의 걸음 갈래.
enum _StepKind { add, remove, off, on }

/// 엔진 길의 걸음 하나 — 엔진 요청([request] — 쓸 것이 없으면 null)과 끝난 뒤의 묘비 · 폴더 · 끈 목록 몫.
class _EngineStep {
  _EngineStep._(this.kind, this.request, {this.heads = const [], this.removeKey, this.offKeys = const [], this.onKeys = const [], this.card});

  /// 넣기 — 고른 파일을 한 번에(`add_pack files` · 경로는 온전하게). [preferGiven]이면 `prefer_given: true`(메이커 미리보기 — 판정 R39).
  factory _EngineStep.add(List<DlcFileHead> heads, {bool preferGiven = false}) => _EngineStep._(
    _StepKind.add,
    {'op': 'add_pack', 'files': [for (final h in heads) File(h.path).absolute.path], if (preferGiven) 'prefer_given': true},
    heads: heads,
    onKeys: [for (final h in heads) h.id],
  );

  /// 지우기 — 저장소에 든 것은 원본까지 버린다(`remove_pack delete:true`). 꺼 둔(저장소에 없는) DLC도 보관함에 있으면([shelved]) 같은 요청으로
  /// 보관함의 원본까지 버린다(판정 R42 — 엔진이 조합 · 배치 없이 보관함에서만 지움). 보관함에도 없으면 엔진에 쓸 것이 없다(폴더 · 끈 목록만 —
  /// 예전 판 앱이 꺼 둔 채 지워 보관함에 남은 원본은 시드 잇기가 묘비 `removed`로 거른다).
  factory _EngineStep.remove(String key, {required bool inStore, bool shelved = false}) =>
      _EngineStep._(_StepKind.remove, inStore || shelved ? {'op': 'remove_pack', 'id': key, 'delete': true} : null, removeKey: key);

  /// 끄기 — 원본은 저장소의 보관함에(`remove_pack delete:false`). 이미 저장소에 없으면 끈 목록만.
  factory _EngineStep.off(String key, {required bool inStore, Map<String, dynamic>? card}) =>
      _EngineStep._(_StepKind.off, inStore ? {'op': 'remove_pack', 'id': key, 'delete': false} : null, offKeys: [key], card: card);

  /// 켜기 — 보관함의 것([ids])과 DLC 폴더의 파일([files])을 한 번에(`add_pack`). 둘 다 없으면(저장소에 든 채 화면에서만 끈 것) 끈 목록만.
  factory _EngineStep.on(List<String> keys, {List<String> ids = const [], List<DlcFileHead> files = const []}) => _EngineStep._(
    _StepKind.on,
    ids.isEmpty && files.isEmpty
        ? null
        : {
            'op': 'add_pack',
            if (files.isNotEmpty) 'files': [for (final h in files) File(h.path).absolute.path],
            if (ids.isNotEmpty) 'ids': ids,
          },
    onKeys: keys,
  );

  final _StepKind kind;
  final Map<String, dynamic>? request;
  final List<DlcFileHead> heads;
  final String? removeKey;
  final List<String> offKeys, onKeys;
  final Map<String, dynamic>? card;

  /// 빼는 쪽의 걸음인가(거절 글이 '빼지 못했습니다').
  bool get removing => kind == _StepKind.remove || kind == _StepKind.off;

  /// 창의 위 칸에 적을 진행 말.
  String progress(DlcHidden hidden) {
    String name(String key) => '«${card?['name'] ?? hidden.cards[key]?['name'] ?? key}»';
    return switch (kind) {
      _StepKind.add => 'DLC ${heads.map((h) => '«${h.name}»').join(' · ')}을(를) 저장소에 넣는 중…',
      _StepKind.remove => 'DLC ${name(removeKey!)}을(를) 지우는 중…',
      _StepKind.off => 'DLC ${name(offKeys.single)}을(를) 끄는 중…',
      _StepKind.on => 'DLC ${onKeys.map(name).join(' · ')}을(를) 켜는 중…',
    };
  }
}

/// 고쳐 쓰기 한 번의 진행(여러 엔진 걸음을 모은다 — 모두 끄기 · 넣고 켜기).
class _ApplyRun {
  bool ok = false, changed = false, reopen = false;
  Map<String, dynamic> data = const {};

  /// 마지막 엔진 거절의 글과 기계용 code(계약 2-7 — 없으면 null).
  String? error, code;

  /// 타일을 버릴 첫 자리 — 아직 고쳐 쓴 것이 없으면 null.
  int? pos;

  void took(Map<String, dynamic> answer) {
    data = answer;
    // 조합 · 배치가 그대로인 답(꺼 둔 DLC를 보관함에서만 지움 — 판정 R42 · 모두 건너뜀): 배치 0번 · 바뀐 트랙 없음 — 뼈대를 다시 읽지 않는다
    // (다시 읽으면 검색 · 묶음 카드가 닫힌다). 저장소 파일은 바뀌었어도 화면이 볼 것은 같다.
    if ((answer['layouts'] as num?)?.toInt() == 0 && (answer['first_pos'] as num?)?.toInt() == -1) return;
    changed = true;
    final first = (answer['first_pos'] as num?)?.toInt() ?? 0;
    final before = pos;
    // 둘 이상이면 가장 앞(−1 = 바뀐 트랙 없음은 무엇과도 견주지 않는다).
    pos = before == null ? first : (before < 0 ? first : (first < 0 ? before : (first < before ? first : before)));
  }

  int get firstPos => reopen ? 0 : pos ?? -1;
}
