// 감독 선택(2026-10-13): 본문·연표·제목은 프리텐다드. Regular 400 / SemiBold 600 / Bold 700 원본을 웹과 앱에 함께 싣는다.
const sceneFontFamily = 'Pretendard';
const sceneTitleFontFamily = sceneFontFamily;
// 기본 글꼴에 없는 문자는 기존 대체 목록에서 찾는다.
const sceneFontFallback = ['ChosunKm', 'Noto Sans KR', 'Malgun Gothic'];

// 글꼴 팩(10건 9 — 감독 선택 D2-4 B · 5 A, 갈래 D2): 지금 쓰는 글꼴 이름과 대체 글꼴 목록. 장면 글(TextLook) · 상세 창의 이름 · 앱의 바탕 글꼴이 읽는다.
// 기본값은 위의 목록이며, 팩이 없으면 이 목록을 유지한다. 바꾸는 곳은 ui/names_display.dart 하나:
//  · 켜진 DLC의 글꼴(FontLoader로 실은 것)은 대체 목록 끝에 — 화면 글꼴에 없는 글자만 채운다(웹 --font의 첫 일반 글꼴 이름 앞).
//  · 화면 글꼴(필터 '표기'의 [글꼴 ▾] · 한글을 덮는 글꼴만)은 앱을 켤 때 장면을 만들기 전에 한 번 맨 앞에 — 글 폭을 재 둔 것이 섞이지 않게.
String sceneFamilyNow = sceneFontFamily;
List<String> sceneFallbackNow = sceneFontFallback;
