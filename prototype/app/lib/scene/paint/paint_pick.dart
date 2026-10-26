// 4단계 감독 고름(2026-10-25 · docs/계획-리메이크-4단계.md '감독 고름')을 그림판에 넣는 그림의 스위치.
//
//  · ink    — 그림판 먹 여섯 단계(G5 #8 먹 가 — 85 · 60 · 45 · 25 · 12 · 4 · 토큰 자리 `paint/ink.dart`의 `CanvasInk`)
//  · tag    — form의 종류 갈래로 꼬리표 끝 · 정통성 '대립'의 점선 테(G6 가 · 과제 2)
//  · flaw   — 서고의 흠 셋 고침(G5 #8 흠 라 — 둘째 줄 매듭 꼴 · 고른 띠 선택 테가 받침 카드를 가림 · 접힌 폴더 몸통이 빔)
//  · chain  — 왕조 · 지위를 꼬리표 밑 흰 사슬로(G5 #9 나 — 쌓기 `layout.dart _bandOf` · 그림 · 실 · 왼쪽 칸 사슬 이름)
//  · folder — 소속 펼치기를 서고의 폴더로(과제 8 걸음 2 — 상국 띠가 첫 줄 · 매다는 실 · 가로대 · 그릇 안이면 상자 · 소속선 걷기)
//  · lid    — 그릇 노릇 객체의 꼴(과제 8 걸음 1 — 폴더 첫 줄의 제 꼬리표 · 동맹과 구성원 없는 그릇의 납작한 뚜껑 · 동군연합 폴더 먹)
//  · cycle  — 육십갑자는 머리 단 주기 줄만(감독 결정 2026-10-25 — 같은 주기를 펼친 문화권 머리 단이 그리면 날짜 칸 간지 줄을 가림)
//  · rows   — 칸 층 사이 흐린 가로선(감독 지적 2026-10-25 "등불왕국 명목기 부분에 가로선도 흐릿하게라도" — 그림 `paint/floor_rules.dart`).
//             켬/끔이 아니라 꼴 셋 가운데 하나를 고른다([FloorRule] — 감독 결정 2026-10-25 기본 b · a · c는 견주기용): `--paint-rows=a|b|c|off`.
//             꼴을 고른 동안(off가 아니면) 그림판의 가로 · 세로 구분선이 틈 없이 맞닿는다(감독 결정 '모든 가로세로 구분선은 맞닿게' — strips.dart · bands.dart ·
//             날짜 칸 머리 단 axis.dart · 그릇 폴더 · 상자 · 할거기 경계 scopes.dart).
//  · route  — 이어 주는 선의 새 길(가지 line-routing — 앞 나라 끝에서 나오기 · 굴 문 · 이음매 눈금 · 승계선 다듬기, 명세 04 3-4 · 3-6 (가-0) · 3-9).
//             끄면 그 전 길로 그린다. 읽는 자리는 걸음 2부터 더한다(걸음 1은 스위치와 선 감사만 — 아무 길도 바꾸지 않음).
//             **0.1.1부터 기본 끔**(감독 고름 2026-10-26 다-1 '승계선이 띠 테두리를 건드리지 않게 전처럼 되돌림') — 아래 1배 후보처럼 `--paint-on=route`로만 켠다.
//  · pair   — 트랙을 건너는 승계의 짝 꼬리표(구역 60 · 감독 결정 2026-10-25). 0.1.0에는 route에 묶였으나 0.1.1에서 떼어 제 스위치(기본 켬 — 다-1).
//  · mend   — 선 길이 아닌 0.1.1 고침(감독 고름 2026-10-26 '떼어서 살림' — route 밑에 있다가 다-1의 route 끔과 함께 꺼졌던 것을 떼어 제 스위치 · 기본 켬):
//             레일 좁은 막대 구슬(rails.dart · 조사 결함 49) · 문화권 주기 줄 시대 범위 자르기와 바퀴 칸 문턱(sphere_lines.dart · 46) · 연합 이음줄이 사건
//             이름 상자를 비움(unions.dart · 41) · 실(sphere_threads.dart — 같은 해 같은 x 36 · 실 나눔 35 · 카드 윗변 뿔 37 · 조감 실 47 · 짝 꼬리표 자리 비움 · gutter.dart 머리 단
//             상자 위 다시 찍기 38) · 연도 세로줄 걷기(links.dart · sphere_threads.dart — 이어 주는 선 미룸 1) · 열쇠표가 승계선 세로 획을 비킴(scopes.dart · 11 —
//             획은 그 장면의 길이 그은 세로 기둥 [LinkColumns]이라 route 끔이면 옛 길의 획) · 그릇 펼친 장면의 선대 · 후대 줄 바로잡음(links.dart _endsOf)과
//             띠 위 조각의 바탕 섞기(_paperDoor · _paperRun — 옛 길의 이음매 다리 · 관문에도) — 둘 다 0.1.0 1b72ee0이 route 뒤에 두었던 것.
//             새 길(굴 문 · 실의 굴 문 39 · 꼬리 내림 · 윗변으로 듦 · ⊓ ·
//             이음매 눈금 · 소속선 · 실 비킴)은 그대로 route 뒤 — `--paint-off=mend`로 끄면 다-1(34aab6a)의 그림과 같다.
//  · people — 왼쪽 칸 민족 머리 줄(0.1.1 감독 "민족이 안보여" → 감독 고름 '나 머리 줄' 2026-10-26 — 쌓기 `layout.dart _build` · 그림 `gutter.dart _peopleHeads`).
//             끄면 민족 표시가 없는 0.1.0 꼴(쌓기도 그대로).
//
// 1배 후보(감독 확인 몫 — 위 낱말들과 거꾸로 **기본은 끔**이고 `--paint-on=cross` · `--paint-on=route`로만 켠다):
//  · cross — 굴 문 대신 띠 뒤로 지나는 몫 전체를 띠 위에 옅은 토막(짙기 .75 + 1px 종이 테)으로 긋는 '건넘 토막'(명세 04 3-9 · route가 켜져 있을 때만 뜻이 있다).
//
// 기본은 모두 켬이다(선 길 route만 끔). 먹 · 사슬 · 폴더는 새 값이 없는 옛 저장소(판 3 포함)의 그림도 바꾸므로, '4단계 전과 바이트 같음' 대신
// **스위치를 끈 찍기가 앞 걸음과 바이트 같음**으로 '바뀐 장면은 이 그림 때문뿐'임을 보인다(`prototype/scripts/remake4-shots.mjs --paint-off=…`).
// 그래서 이 스위치는 **찍기 · 증명 전용**이다 — 명령줄(`--paint-off=ink,tag,flaw,chain,folder,lid,cycle,legit,office,body,route,rows,pair,mend,people|all` ·
// `--paint-rows=a|b|c|off` · 1배 후보 `--paint-on=cross,route`)로만 바꾸고, 기억 · 설정에 적지 않으며 앱 안에서 바꾸는 길이 없다.
// 그림판은 장면마다 이 값을 읽는다(그림을 고치는 걸음이 제 스위치를 읽는 자리를 더한다 — folder · lid · cycle은 과제 8 갈래(가지 remake-4-folders)의
// 차례 걸음 81에서 자리를 만들었다. 읽는 곳: folder = 쌓기(layout.dart `_hostFolderOn` — 배치를 지을 때 한 번 · 걸음 2) · lid = 띠 층의 뚜껑
// (paint/lid_tags.dart · bands.dart) · 동군연합 폴더 먹(host_folders.dart `inked` → scopes.dart `_paintFolder` · 걸음 4) · cycle = 쌓기(layout.dart `_cycleOn` ·
// 걸음 5) · rows = 구분선 갈래(가지 remake-4-rows)의 차례 걸음 17 — 칸 층 가로선 `floor_rules.dart` · 맞닿음 strips · bands · axis · scopes).
//
// 칸 그림 갈래(가지 remake-4-cells — 배치 갈래가 저장소에 실은 새 값을 그림판이 읽음)의 스위치 셋:
//  · legit  — 정통성 넷 가 다듬은 꼴(lg2-ga — 칸 · 띠 · 소속 구간의 정통성 무늬)과 지도자 두 단(띠 sub 22 ~ 23 · 칸 종류 1의 lane · 줄 fig_wide 26 ~ 27)
//  · office — G7 가 직위 줄 더 층(띠 look 30 · sub 17 ~ 21 · 줄 fig_wide 21 ~ 25 · 칸 종류 9 · 빌린 층 · 왼쪽 칸 줄 이름)
//  · body   — 띠마다 제 몸통 높이(줄 fig_wide 28 ~ 30 — 줄어드는 층)
// 이 셋은 새 값이 있는 저장소의 그림만 바꾼다(판 3 저장소는 늘 바이트 같음). 그래도 걸음마다 끈 찍기가 앞 걸음과 같음으로 '바뀐 장면은 이 그림 때문뿐'을 보인다.
//
// **합칠 때(같은 바탕에서 이 파일을 고친 갈래 넷 — remake-4-folders folder · lid · cycle · remake-4-cells legit · office · body ·
// remake-4-rows rows(켬/끔이 아니라 꼴 고르기 — `FloorRule` · `--paint-rows`)(이 셋은 합침) · line-routing route(1배 후보 cross는 `--paint-on` · [reset]만) · 0.1.1 people — 낱말 열셋)**:
// 낱말은 [names] · [off] · [allOn] · [reset] · [turnOff]의 'all' 다섯 자리에 모두 들어야 한다 — 한 자리에서 빠지면 `--paint-off=all` 끈 찍기
// ('바탕과 바이트 같음' 증명)가 그 그림을 끄지 못하거나 검사 끝의 [reset]이 스위치 하나를 끈 채 남긴다. test/paint_pick_test.dart가 [names]의 낱말마다
// 다섯 자리를 돈다(낱말을 [names]에 넣는 것은 손으로). rows는 bool이 아니라 꼴이라 끔 = [FloorRule.off] · 켬으로 되돌림 = 기본 [FloorRule.b]이다.

/// 칸 층 사이 가로선의 꼴(감독 지적 2026-10-25 — 감독이 고를 셋 · 그림 `paint/floor_rules.dart`).
///  · [a] 가로 먹 12 실선 1px · 세로 칸 구분선은 그대로(먹 25)
///  · [b] 가로 먹 12 실선 · 세로 칸 구분선도 먹 12로 낮춤(둘이 같게) — 기본(감독 결정 2026-10-25 "b로 하고")
///  · [c] 가로 먹 25 점선(1 긋고 2 띄움) · 세로 그대로
///  · [off] 가로선 없음 · 구분선 맞닿음도 없음(이 갈래 전 그림 그대로 — 끈 찍기가 앞 걸음과 바이트 같음)
/// a · b · c는 모두 가로 · 세로 구분선이 맞닿는다(감독 결정 2026-10-25 "왕 세로선부분이랑 가로선 부분이랑 딱 맞닿게 해줘 틈 없게" ·
/// "모든 가로세로 구분선은 맞닿게").
enum FloorRule { off, a, b, c }

/// 감독 고름 그림 넷 · 그릇 꼴 셋 · 칸 그림 셋 · 선 길의 켬/끔과 칸 층 가로선의 꼴 · 1배 후보(찍기 · 증명 전용 — 기본은 모두 켬 · 가로선은 꼴 b · 후보는 끔).
abstract final class PaintPick {
  /// 그림판 먹 여섯 단계(G5 #8 먹 가).
  static bool ink = true;

  /// form의 종류 갈래로 꼬리표 끝 · 대립 점선 테(G6 가 · 과제 2).
  static bool tag = true;

  /// 서고 흠 셋 고침(G5 #8 흠 라).
  static bool flaw = true;

  /// 왕조 · 지위의 꼬리표 밑 흰 사슬(G5 #9 나).
  static bool chain = true;

  /// 소속 펼치기를 서고의 폴더로(과제 8 걸음 2).
  static bool folder = true;

  /// 그릇 노릇 객체의 꼴 — 첫 줄 제 꼬리표 · 납작한 뚜껑 · 동군연합 폴더 먹(과제 8 걸음 1).
  static bool lid = true;

  /// 같은 주기를 펼친 문화권 머리 단이 그리면 날짜 칸 간지 줄을 가림(감독 결정 2026-10-25 '육십갑자는 머리 단 주기 줄만').
  static bool cycle = true;

  /// 정통성 무늬(칸 · 띠 · 소속 구간 — 정통성 넷 가 다듬은 꼴 lg2-ga)와 지도자 두 단(칸 그림 갈래).
  static bool legit = true;

  /// 직위 줄 더 층(G7 가 — 칸 그림 갈래).
  static bool office = true;

  /// 띠마다 제 몸통 높이 — 줄어드는 층(칸 그림 갈래).
  static bool body = true;

  /// 이어 주는 선의 새 길(가지 line-routing — 명세 04 3-4 · 3-6 (가-0) · 3-9 — 굴 문 · 꼬리 내림 · 윗변으로 듦 · 같은 줄 ⊓ · 이음매 눈금 · 소속선 · 실의 새 길).
  /// **기본 끔**(감독 고름 2026-10-26 다-1 '승계선이 띠 테두리를 건드리지 않게 전처럼 되돌림') — 0.1.0 전 길. 코드는 그대로 두고 `--paint-on=route`로만 켠다
  /// (`--paint-off=route`도 그대로 받는다 — 이미 끔).
  static bool route = false;

  /// 트랙을 건너는 승계의 짝 꼬리표(구역 60 — 감독 결정 2026-10-25). [route]에서 떼어 제 스위치(기본 켬 · 감독 고름 2026-10-26 다-1) — `--paint-off=pair`로 끔.
  static bool pair = true;

  /// 선 길이 아닌 0.1.1 고침(레일 구슬 49 · 주기 줄 46 · 이음줄 이름 비움 41 · 실 35 · 36 · 37 · 38 · 47 · 세로줄 걷기 미룸 1 · 열쇠표 획 비킴 11 ·
  /// 그릇 펼친 장면의 선대 · 후대 줄 바로잡음 · 띠 위 조각의 바탕 섞기 — 0.1.0 1b72ee0이 route 뒤에 두었던 것).
  /// [route]에서 떼어 제 스위치(기본 켬 · 감독 고름 2026-10-26 '떼어서 살림') — `--paint-off=mend`로 끔.
  static bool mend = true;

  /// 칸 층 사이 흐린 가로선의 꼴(감독 지적 2026-10-25 — 감독 결정 기본 [FloorRule.b]). `--paint-off=rows`(· `all`)는 [FloorRule.off]로.
  static FloorRule rows = FloorRule.b;

  /// 1배 후보 '건넘 토막'(명세 04 3-9 — 굴 문 대신 · [route]를 켠 때만 뜻이 있음). **기본 끔** — `--paint-on=cross`로만 켠다.
  static bool cross = false;

  /// 왼쪽 칸 민족 머리 줄(0.1.1 감독 고름 '나' — 2026-10-15 '최대한 목업 반영'에서 뺀 민족 칸 · 딱지를 서고 꼴로 되살림 · 폭 240 그대로).
  /// 두 줄 넘게 보이는 펼친 묶음은 첫 줄 위 머리 줄(▾ + 이름 9 + 가는 선 · 단마다 10 들임 · 누르면 접기 · 내려 볼 때 위에 붙음) · 한 줄짜리는 그 줄 이름 뒤 ·
  /// 딱지는 줄 이름 앞 점 4. 끄면(`--paint-off=people`) 0.1.0 꼴 — 민족 표시 없음 · 쌓기 그대로.
  static bool people = true;

  /// 불확실 표시를 흐림 하나로(감독 지적 2026-10-26 "부정, 실재 논란, 불분명 시기 칠하는 방식이 너무 제각각 — 흐림으로" · 감독 고름 다 "흐린 부분은
  /// 해당하는 기간만 흐리게 해줘. 전체 흐리게 하지말고" — 그림 `paint/bands.dart` [BandLayer.hazePeriod]). 연대 폭 · 미정 끝(끝으로 갈수록 사라짐) · 칸의 연대 폭만
  /// 그 구간을 종이와 섞은 불투명 색으로 · 띠 전체에 붙은 확실성 · 실재성은 띠를 흐리지 않고 글자 표시만. `--paint-off=haze`(· `all`)면 옛 꼴(빗금 · 안개 · 옅은 테 · 무늬 · 회색).
  static bool haze = true;

  /// 켜는 후보의 낱말(`--paint-on` — 기본이 끔인 것만).
  static const candidates = <String>['cross', 'route'];

  /// 후보를 켜는 명령줄 열쇠.
  static const onOption = '--paint-on';

  /// 지금 켜 둔 후보의 낱말(차례대로). 없으면 빈 목록.
  static List<String> get on => [if (cross) 'cross', if (route) 'route'];

  /// 끄는 명령줄의 낱말(기본이 켬인 것) — 차례는 합친 차례(먹 → 꼬리표 → 흠 → 사슬 → 폴더 → 뚜껑 → 주기 → 정통성 → 직위 줄 더 → 몸통 → 가로선 → 짝 꼬리표 → 0.1.1 고침 → 민족 머리 줄 → 흐림).
  /// `all`은 모두(선 길도). 선 길 route는 0.1.1부터 기본 끔이라 여기서 빠지고 [candidates]로 갔다 — `--paint-off=route`(옛 명령줄)는 [turnOff]가 그대로 받는다.
  static const names = <String>['ink', 'tag', 'flaw', 'chain', 'folder', 'lid', 'cycle', 'legit', 'office', 'body', 'rows', 'pair', 'mend', 'people', 'haze'];

  /// 명령줄 열쇠.
  static const option = '--paint-off';

  /// 가로선의 꼴을 고르는 명령줄 열쇠(`--paint-rows=a|b|c|off`).
  static const rowsOption = '--paint-rows';

  /// 지금 꺼 둔 스위치의 낱말(차례대로 · 기본이 끔인 선 길 route는 [on]에서). 모두 켬이면 빈 목록.
  static List<String> get off => [
    if (!ink) 'ink',
    if (!tag) 'tag',
    if (!flaw) 'flaw',
    if (!chain) 'chain',
    if (!folder) 'folder',
    if (!lid) 'lid',
    if (!cycle) 'cycle',
    if (!legit) 'legit',
    if (!office) 'office',
    if (!body) 'body',
    if (rows == FloorRule.off) 'rows',
    if (!pair) 'pair',
    if (!mend) 'mend',
    if (!people) 'people',
    if (!haze) 'haze',
  ];

  /// 모두 켬인가(기본 — 가로선은 꼴이 무엇이든 끄지만 않았으면 켬 · 기본이 끔인 선 길 route는 보지 않음).
  static bool get allOn =>
      ink && tag && flaw && chain && folder && lid && cycle && legit && office && body && rows != FloorRule.off && pair && mend && people && haze;

  /// 모두 기본(낱말은 켬 · 가로선 꼴 b · 1배 후보 · 선 길은 끔)으로 되돌린다(검사가 끝날 때).
  static void reset() {
    ink = tag = flaw = chain = folder = lid = cycle = legit = office = body = pair = mend = people = haze = true;
    rows = FloorRule.b;
    cross = route = false;
  }

  /// 후보 낱말 하나를 켠다. 모르는 낱말이면 거짓(스위치는 그대로).
  static bool turnOn(String name) {
    switch (name) {
      case 'cross':
        cross = true;
      case 'route':
        route = true;
      default:
        return false;
    }
    return true;
  }

  /// 낱말 하나를 끈다. 모르는 낱말이면 거짓(스위치는 그대로).
  static bool turnOff(String name) {
    switch (name) {
      case 'ink':
        ink = false;
      case 'tag':
        tag = false;
      case 'flaw':
        flaw = false;
      case 'chain':
        chain = false;
      case 'folder':
        folder = false;
      case 'lid':
        lid = false;
      case 'cycle':
        cycle = false;
      case 'legit':
        legit = false;
      case 'office':
        office = false;
      case 'body':
        body = false;
      case 'route':
        route = false;
      case 'rows':
        rows = FloorRule.off;
      case 'pair':
        pair = false;
      case 'mend':
        mend = false;
      case 'people':
        people = false;
      case 'haze':
        haze = false;
      case 'all':
        ink = tag = flaw = chain = folder = lid = cycle = legit = office = body = route = pair = mend = people = haze = false;
        rows = FloorRule.off;
      default:
        return false;
    }
    return true;
  }

  /// `--paint-off`의 값(`ink,tag` · `all` — 쉼표로 가름 · 앞뒤 빈칸과 빈 낱말은 건너뜀 · 대소문자 가리지 않음)을 읽어 그 스위치를 끈다.
  /// 켜는 길은 없다(기본이 켬 — 같은 실행에서 다시 켤 일이 없음). 모르는 낱말의 목록을 돌려준다(그 낱말은 무시).
  static List<String> applyOff(String value) {
    final unknown = <String>[];
    for (final raw in value.split(',')) {
      final name = raw.trim().toLowerCase();
      if (name.isEmpty) continue;
      if (!turnOff(name)) unknown.add(raw.trim());
    }
    return unknown;
  }

  /// `--paint-rows`의 값(`a` · `b` · `c` · `off` — 앞뒤 빈칸 · 대소문자 가리지 않음)으로 가로선의 꼴을 고른다.
  /// 모르는 값이면 그 값을 돌려주고 꼴은 그대로. 빈 값은 아무것도 바꾸지 않는다.
  static List<String> applyRows(String value) {
    final name = value.trim().toLowerCase();
    if (name.isEmpty) return const [];
    for (final rule in FloorRule.values) {
      if (rule.name == name) {
        rows = rule;
        return const [];
      }
    }
    return [value.trim()];
  }

  /// 명령줄 인자 가운데 `--paint-rows=…`와 `--paint-off=…`를 모두 읽는다 — 꼴 고르기를 먼저, 끄기를 나중에(`--paint-off=rows`나 `all`이 있으면
  /// 가로선은 꼴과 상관없이 끔). `--paint-off`가 여럿이면 모두 끔(합집합) · `--paint-rows`가 여럿이면 뒤의 것. 열쇠만 있고 값이 없으면 아무것도 바꾸지 않는다.
  /// `--paint-on=cross,route`(기본이 끔인 것 — 쉼표로 가름 · 대소문자 가리지 않음)도 함께 읽어 켠다(이어 주는 선 갈래). 모르는 낱말의 목록을 돌려준다.
  static List<String> applyArguments(List<String> arguments) {
    final unknown = <String>[];
    for (final arg in arguments) {
      if (arg.startsWith('$rowsOption=')) unknown.addAll(applyRows(arg.substring(rowsOption.length + 1)));
    }
    for (final arg in arguments) {
      if (arg.startsWith('$onOption=')) {
        for (final raw in arg.substring(onOption.length + 1).split(',')) {
          final name = raw.trim().toLowerCase();
          if (name.isNotEmpty && !turnOn(name)) unknown.add(raw.trim());
        }
        continue;
      }
      if (!arg.startsWith('$option=')) continue;
      unknown.addAll(applyOff(arg.substring(option.length + 1)));
    }
    return unknown;
  }
}
