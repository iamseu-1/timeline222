//! 규칙 판의 골든(판정 R61 I1 · R69-3) — 정답지 자료 전부(+ 다른 시각 · 시간대 둘)의 Rust 통째 출력(`lay::export` · `Scope::All` · 잘린 달력 표)과
//! 그 지문(`patch::prints`)을 **판별 이력**으로 커밋해 두고 견준다.
//!
//! - 배치 골든 [`LAYOUT`] = `[(판, [(자료, 입력 지문, 달력 표 지문, 배치 해시, 달력 기록 해시)])]` — 마지막 판은 `lay::rules::LAY_RULES_VERSION`이어야 한다.
//!   입력 지문은 DLC 바이트 · 오늘 · 시간대, 달력 표 지문은 잘린 표(`calendar-slice.json`)의 SHA-256(판정 R71-1 — 둘을 가른다). 배치 해시는 출력에서
//!   내보내기 `calendar` 모듈의 `cal:` 기록을 뺀 것, 달력 기록 해시는 그 기록들만. 입력과 표가 같은데 어느 해시든 바뀌면 **판을 올려야** 한다: 검사가
//!   `LAY_RULES_VERSION = N+1`과 이력 끝에 덧붙일 새 항목을 찍고 멈춘다(마지막 항목의 표만 갈아 끼우면 저장소의 `meta.rules`가 그대로라 엔진을 올린 뒤 S 밖
//!   트랙이 낡는다 — 그래서 새 항목으로). 입력이 바뀐 자료(자료를 고침 · 새 자료)는 '입력 바뀜 — 표만 다시'로 판 올림을 요구하지 않는다(마지막 항목의 표를
//!   찍힌 것으로 바꾼다). **달력 표만 바뀌면**: 보조 달력 날짜를 읽은 자료(이 배치에서 `lay::cal::take_aux_reads` > 0 — 날짜를 읽는 길은 모두 그 셈을
//!   지난다)만 '표만 다시'이고, 읽지 않은 자료는 배치 해시가 그대로여야 한다(달력 기록 해시는 표를 따라 바뀌어도 됨) — 다르면 판 올림.
//! - **`calendar-slice.json`을 다시 뜨는 커밋에는 엔진 고침을 섞지 않는다**(보조 달력을 읽는 자료의 출력 변화가 '표만 다시'에 묻힌다 — ICU 78.3로 다시
//!   뜨기가 곧 옴 · 판정 R66).
//! - 지문 골든 [`PRINTS`] = `[(지문 판, [(자료, 배치 출력 해시, 지문 해시)])]` — 마지막 판은 `patch::PRINT_FORM`. 지문은 규칙 판 글을 고정해(`prints_under`)
//!   셈한다: 배치가 같은데 지문이 바뀌면 `PRINT_FORM`을 올린다(배치가 바뀌었으면 '입력 바뀜').
//! - 선택 자료(`list.json`의 `optional` — 감독 PC의 KTL 따위)는 이 PC에 있는데 골든에 없으면 알리고 건너뛰고, 골든에 있는데 이 PC에 없는 자료는 이름을 찍는다.
mod common;
use archive_engine::lay::{self, rules::LAY_RULES_VERSION, Opts, PackIn};
use archive_engine::patch;
use common::oracle::{fixtures, inputs, seam_opts};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;

/// 배치 골든의 판별 이력 — (판, [(자료, 입력 지문, 달력 표 지문, 배치 해시, 달력 기록 해시)]). 판 1의 표는 16b 고침 2회차에 이 꼴로 다시 찍었다
/// (판정 R71-1 — 꼴만 바뀜 · 출력은 그 앞 판 1과 같음: 지문 골든의 배치 출력 해시가 그대로).
type Row5 = (&'static str, &'static str, &'static str, &'static str, &'static str);
const LAYOUT: &[(u32, &[Row5])] = &[
    (1, &[
        ("lantern", "899addf2b56b087b", "6e77d0d8f94037cc", "62c45d7fe1e08724", "e6688c85207c184b"),
        ("east-asia·2000", "b92ee82c91707c89", "6e77d0d8f94037cc", "2b3ccef9d4828238", "6d2ca3f6b0466b0e"),
        ("east-asia", "4cc878cfe8d4341e", "6e77d0d8f94037cc", "112e5adff2021ecd", "4d9fc7740296a72b"),
        ("east-asia+ktl", "34549852aff2efe6", "6e77d0d8f94037cc", "ebd07630fe84b7e5", "4d9fc7740296a72b"),
        ("east-asia+move", "5dbd65e0b82e3c9b", "6e77d0d8f94037cc", "af65d40674a1a3c6", "4d9fc7740296a72b"),
        ("east-asia+nest", "75ab6ea9594c06cd", "6e77d0d8f94037cc", "9e4e0be08a499247", "4d9fc7740296a72b"),
        ("east-asia+dep", "bb007629d36a63ea", "6e77d0d8f94037cc", "ea7b4cbfde95cee7", "4d9fc7740296a72b"),
        ("east-asia+d7", "f1a2ce2c157c3a80", "6e77d0d8f94037cc", "828bcbb66e5e07be", "4d9fc7740296a72b"),
        ("east-asia+sphere", "13c131de55def103", "6e77d0d8f94037cc", "7d42d0ad733aab35", "4d9fc7740296a72b"),
        ("nest-f4", "9d8be786d827702b", "6e77d0d8f94037cc", "660eea57fc11eb01", "d8f3ecb9b39e9585"),
        ("synth", "03616be48ddc46b9", "6e77d0d8f94037cc", "f2107e3281aa59ae", "0a4b8dfc53cd7073"),
        ("synth+patch·뉴욕", "57fc9d48ac84398e", "6e77d0d8f94037cc", "b15c83e34594763c", "70f7ecd10179cd46"),
        ("synth+patch", "70bd7e2e2081e161", "6e77d0d8f94037cc", "5cdbb4b96476d088", "70f7ecd10179cd46"),
        ("synth-lay", "10ac916c9a540d46", "6e77d0d8f94037cc", "9909125734f7dfad", "61765b3e88c24861"),
        ("synth-lens", "5172cecc14091436", "6e77d0d8f94037cc", "c1ce78f5404c0f86", "aa98082c4e7bfdd0"),
        ("synth-calclip", "c32556fed1833759", "6e77d0d8f94037cc", "d3d444c152309a07", "0d3781657e9b30dd"),
        ("lantern@f4", "3dcffe37ca2f9b53", "6e77d0d8f94037cc", "62c45d7fe1e08724", "e6688c85207c184b"),
        ("east-asia@f4", "a49b2a07b2616e3e", "6e77d0d8f94037cc", "1fc5417388d69324", "4d9fc7740296a72b"),
        ("east-asia+move@f4", "a9770b23f2fe5a0e", "6e77d0d8f94037cc", "b44e2e6caece979d", "4d9fc7740296a72b"),
        ("east-asia+nest@f4", "9316e1c589eb80c4", "6e77d0d8f94037cc", "a726a3ad8606bcd2", "4d9fc7740296a72b"),
        ("east-asia+dep@f4", "24fa6da08ae651f0", "6e77d0d8f94037cc", "e67d82ceb4730b80", "4d9fc7740296a72b"),
        ("east-asia+d7@f4", "0b1cbc541aa6ed41", "6e77d0d8f94037cc", "9918d95dec8ee7f3", "4d9fc7740296a72b"),
        ("east-asia+sphere@f4", "b1566f757088cf09", "6e77d0d8f94037cc", "4e50c5ebff4c4ee0", "4d9fc7740296a72b"),
        ("nest-f4@f4", "15f27e4f8c20548f", "6e77d0d8f94037cc", "cf663b7b156df4fa", "d8f3ecb9b39e9585"),
        ("synth@f4", "ca1e6079ff64b310", "6e77d0d8f94037cc", "76a4f7b3842c5375", "0a4b8dfc53cd7073"),
        ("synth+patch@f4", "b71744ca06ccc45f", "6e77d0d8f94037cc", "0202e06105608dda", "70f7ecd10179cd46"),
        ("synth-lay@f4", "ae6b7e743b2cc075", "6e77d0d8f94037cc", "277c9d21a1bd1a16", "61765b3e88c24861"),
        ("synth-lens@f4", "2ffc1a2ef1d091d3", "6e77d0d8f94037cc", "7e623d760d4b1654", "aa98082c4e7bfdd0"),
    ]),
    // 판 2(2026-10-24): 프로그램에 든 문화권을 걷음 — 문화권 사전은 켠 DLC의 spheres뿐(적지 않은 트랙은 동아시아가 아니라 문화권 없음) · 트랙의 rowLift(서고 밖 0)
    (2, &[
        ("lantern", "27a30d20e01bb2b9", "6e77d0d8f94037cc", "62c45d7fe1e08724", "e6688c85207c184b"),
        ("east-asia·2000", "c782631ae9e347de", "6e77d0d8f94037cc", "2b3ccef9d4828238", "6d2ca3f6b0466b0e"),
        ("east-asia", "478ebde79e3bad9c", "6e77d0d8f94037cc", "112e5adff2021ecd", "4d9fc7740296a72b"),
        ("east-asia+move", "522b6e553253a633", "6e77d0d8f94037cc", "f6a2c72d9fdb31f5", "4d9fc7740296a72b"),
        ("east-asia+nest", "a5e8beaa7347c97d", "6e77d0d8f94037cc", "26d5dd5c2a0f03ce", "4d9fc7740296a72b"),
        ("east-asia+dep", "2447cc3f12e249b6", "6e77d0d8f94037cc", "ea7b4cbfde95cee7", "4d9fc7740296a72b"),
        ("east-asia+d7", "896034dfa307e5a7", "6e77d0d8f94037cc", "ce5e3785066b015e", "4d9fc7740296a72b"),
        ("east-asia+sphere", "e7ad8f3fb028ef6c", "6e77d0d8f94037cc", "771ecc86061aaded", "4d9fc7740296a72b"),
        ("nest-f4", "9d8be786d827702b", "6e77d0d8f94037cc", "b0631ed4d8ba13e8", "d8f3ecb9b39e9585"),
        ("synth", "03616be48ddc46b9", "6e77d0d8f94037cc", "936aa64a1455acd7", "0a4b8dfc53cd7073"),
        ("synth+patch·뉴욕", "57fc9d48ac84398e", "6e77d0d8f94037cc", "06e77b1f761c438a", "70f7ecd10179cd46"),
        ("synth+patch", "70bd7e2e2081e161", "6e77d0d8f94037cc", "f8709da055986cc9", "70f7ecd10179cd46"),
        ("synth-lay", "10ac916c9a540d46", "6e77d0d8f94037cc", "1de9e24dd5412b27", "61765b3e88c24861"),
        ("synth-lens", "5172cecc14091436", "6e77d0d8f94037cc", "5a4d77d78e7567d0", "aa98082c4e7bfdd0"),
        ("synth-calclip", "c32556fed1833759", "6e77d0d8f94037cc", "8c2746b7215372f2", "0d3781657e9b30dd"),
        ("lantern@f4", "0f4cd1708eaf3d3d", "6e77d0d8f94037cc", "62c45d7fe1e08724", "e6688c85207c184b"),
        ("east-asia@f4", "7d503476194f1473", "6e77d0d8f94037cc", "1fc5417388d69324", "4d9fc7740296a72b"),
        ("east-asia+move@f4", "2d706d37ed9de271", "6e77d0d8f94037cc", "ca3c029add2d134d", "4d9fc7740296a72b"),
        ("east-asia+nest@f4", "ff9ec530f8c51566", "6e77d0d8f94037cc", "94e7b26653e3ef49", "4d9fc7740296a72b"),
        ("east-asia+dep@f4", "6cd167a5a91f9ee2", "6e77d0d8f94037cc", "e67d82ceb4730b80", "4d9fc7740296a72b"),
        ("east-asia+d7@f4", "db175897c8ac54d8", "6e77d0d8f94037cc", "d3beff1b6a0f35b6", "4d9fc7740296a72b"),
        ("east-asia+sphere@f4", "5a7ed686eea8b08f", "6e77d0d8f94037cc", "e7f4cea7efe42a00", "4d9fc7740296a72b"),
        ("nest-f4@f4", "169bc8b23926df6e", "6e77d0d8f94037cc", "8af36b86bb90926b", "d8f3ecb9b39e9585"),
        ("synth@f4", "781e895f9c3edc78", "6e77d0d8f94037cc", "462fb813fe44ff19", "0a4b8dfc53cd7073"),
        ("synth+patch@f4", "1759f813871d73ba", "6e77d0d8f94037cc", "483dc990b1bd60bf", "70f7ecd10179cd46"),
        ("synth-lay@f4", "5c9978431e991997", "6e77d0d8f94037cc", "06adb40ceb0bb151", "61765b3e88c24861"),
        ("synth-lens@f4", "2ffc1a2ef1d091d3", "6e77d0d8f94037cc", "f8fd0e061e6efc7f", "aa98082c4e7bfdd0"),
        ("east-asia+ktl", "34549852aff2efe6", "6e77d0d8f94037cc", "ebd07630fe84b7e5", "4d9fc7740296a72b"),
    ]),
    // 판 3(2026-10-24 · 리메이크 3단계 과제 1): Rust 정규화가 5단계의 형식 4 칸(type · status · importance · offices · 빌림 · power · 시대 구분 sphere · yearCycles)을 지킴 — nest-f4의 type(city)이 항목 기록에 실림
    (3, &[
        ("lantern", "27a30d20e01bb2b9", "6e77d0d8f94037cc", "62c45d7fe1e08724", "e6688c85207c184b"),
        ("east-asia·2000", "c782631ae9e347de", "6e77d0d8f94037cc", "2b3ccef9d4828238", "6d2ca3f6b0466b0e"),
        ("east-asia", "478ebde79e3bad9c", "6e77d0d8f94037cc", "112e5adff2021ecd", "4d9fc7740296a72b"),
        ("east-asia+move", "522b6e553253a633", "6e77d0d8f94037cc", "f6a2c72d9fdb31f5", "4d9fc7740296a72b"),
        ("east-asia+nest", "a5e8beaa7347c97d", "6e77d0d8f94037cc", "26d5dd5c2a0f03ce", "4d9fc7740296a72b"),
        ("east-asia+dep", "2447cc3f12e249b6", "6e77d0d8f94037cc", "ea7b4cbfde95cee7", "4d9fc7740296a72b"),
        ("east-asia+d7", "896034dfa307e5a7", "6e77d0d8f94037cc", "ce5e3785066b015e", "4d9fc7740296a72b"),
        ("east-asia+sphere", "e7ad8f3fb028ef6c", "6e77d0d8f94037cc", "771ecc86061aaded", "4d9fc7740296a72b"),
        ("nest-f4", "9d8be786d827702b", "6e77d0d8f94037cc", "621fe50aa1ca153d", "d8f3ecb9b39e9585"),
        ("synth", "03616be48ddc46b9", "6e77d0d8f94037cc", "936aa64a1455acd7", "0a4b8dfc53cd7073"),
        ("synth+patch·뉴욕", "57fc9d48ac84398e", "6e77d0d8f94037cc", "06e77b1f761c438a", "70f7ecd10179cd46"),
        ("synth+patch", "70bd7e2e2081e161", "6e77d0d8f94037cc", "f8709da055986cc9", "70f7ecd10179cd46"),
        ("synth-lay", "10ac916c9a540d46", "6e77d0d8f94037cc", "1de9e24dd5412b27", "61765b3e88c24861"),
        ("synth-lens", "5172cecc14091436", "6e77d0d8f94037cc", "5a4d77d78e7567d0", "aa98082c4e7bfdd0"),
        ("synth-calclip", "c32556fed1833759", "6e77d0d8f94037cc", "8c2746b7215372f2", "0d3781657e9b30dd"),
        ("lantern@f4", "0f4cd1708eaf3d3d", "6e77d0d8f94037cc", "62c45d7fe1e08724", "e6688c85207c184b"),
        ("east-asia@f4", "7d503476194f1473", "6e77d0d8f94037cc", "1fc5417388d69324", "4d9fc7740296a72b"),
        ("east-asia+move@f4", "2d706d37ed9de271", "6e77d0d8f94037cc", "ca3c029add2d134d", "4d9fc7740296a72b"),
        ("east-asia+nest@f4", "ff9ec530f8c51566", "6e77d0d8f94037cc", "94e7b26653e3ef49", "4d9fc7740296a72b"),
        ("east-asia+dep@f4", "6cd167a5a91f9ee2", "6e77d0d8f94037cc", "e67d82ceb4730b80", "4d9fc7740296a72b"),
        ("east-asia+d7@f4", "db175897c8ac54d8", "6e77d0d8f94037cc", "d3beff1b6a0f35b6", "4d9fc7740296a72b"),
        ("east-asia+sphere@f4", "5a7ed686eea8b08f", "6e77d0d8f94037cc", "e7f4cea7efe42a00", "4d9fc7740296a72b"),
        ("nest-f4@f4", "169bc8b23926df6e", "6e77d0d8f94037cc", "3d8a51d5dccbe72b", "d8f3ecb9b39e9585"),
        ("synth@f4", "781e895f9c3edc78", "6e77d0d8f94037cc", "462fb813fe44ff19", "0a4b8dfc53cd7073"),
        ("synth+patch@f4", "1759f813871d73ba", "6e77d0d8f94037cc", "483dc990b1bd60bf", "70f7ecd10179cd46"),
        ("synth-lay@f4", "5c9978431e991997", "6e77d0d8f94037cc", "06adb40ceb0bb151", "61765b3e88c24861"),
        ("synth-lens@f4", "2ffc1a2ef1d091d3", "6e77d0d8f94037cc", "f8fd0e061e6efc7f", "aa98082c4e7bfdd0"),
        ("east-asia+ktl", "34549852aff2efe6", "6e77d0d8f94037cc", "ebd07630fe84b7e5", "4d9fc7740296a72b"),
    ]),
    // 판 4(2026-10-24 · 리메이크 3단계 과제 3 ~ 6): 스키마 4가 더하는 값 — 띠의 form · 칸 종류 9 · 빌린 칸 27비트 · 구역 54 ~ 56 · sphereLines(새 모듈 persons · axis) · 인물의 x_titles.
    // 정답지 자료에 형식 4 가상 팩 다섯(f4-crowns · f4-office3 · f4-sphere · f4-federation · f4-liege)과 f4-federation@f4(알려진 차이)를 더함.
    // 표만 다시(2026-10-24 · 리메이크 6단계 걸음 4 — 달력 다섯): 잘린 달력 표에 히브리력 · 에티오피아력 · 콥트력 · 사카력이 듦 — 모든 자료의 달력 표 지문 · 달력 기록 해시만 바뀌고 배치 해시는 그대로.
    // 새 자료(2026-10-25 · 리메이크 6단계 코드 몫): 형식 4 가상 팩 f4-moves와 그 사본 f4-moves@f4(알려진 차이)를 더함 — 내보내기 옮겨 앉기의 그릇 밖 토막 · 토막 상대 돌리기와
    // 실권 정권 섬김 밑줄(구역 56)은 다른 정답지 자료에 걸리는 객체가 없어 그 자료들의 배치 해시 · 판 4는 그대로(이 고침을 지키는 자료가 f4-moves).
    // 표만 다시(2026-10-25 · 리메이크 6단계 검토 고침): 토막 난 나라가 쥔 남의 실권 줄을 시작 해의 토막 하나에만 — f4-moves에 그 나라(푸른 들 나라의 실권 넷)를 더해 두 줄만 다시(입력이 바뀜 · 다른 자료 그대로).
    (4, &[
        ("lantern", "27a30d20e01bb2b9", "1ff2356329106496", "56563e46a0f7a678", "77e3606a4cc9b171"),
        ("east-asia·2000", "c782631ae9e347de", "1ff2356329106496", "45b09ff795fd6149", "a4ca82d19d0cada2"),
        ("east-asia", "478ebde79e3bad9c", "1ff2356329106496", "295ea4f34b47d82b", "dc255acd221b375b"),
        ("east-asia+move", "522b6e553253a633", "1ff2356329106496", "8c77968f903d6ce6", "dc255acd221b375b"),
        ("east-asia+nest", "a5e8beaa7347c97d", "1ff2356329106496", "e1a30da8e5cbb9d2", "dc255acd221b375b"),
        ("east-asia+dep", "2447cc3f12e249b6", "1ff2356329106496", "f49fe05f596760b0", "dc255acd221b375b"),
        ("east-asia+d7", "896034dfa307e5a7", "1ff2356329106496", "ea2f456967a47de9", "dc255acd221b375b"),
        ("east-asia+sphere", "e7ad8f3fb028ef6c", "1ff2356329106496", "85e21d9c7993b30b", "dc255acd221b375b"),
        ("nest-f4", "9d8be786d827702b", "1ff2356329106496", "861e36b043ef8053", "f7c56ae63491174f"),
        ("synth", "03616be48ddc46b9", "1ff2356329106496", "a49bdca07d8fb311", "13654284aba7feee"),
        ("synth+patch·뉴욕", "57fc9d48ac84398e", "1ff2356329106496", "8516617e7178be09", "24a5f750aaa2a6a0"),
        ("synth+patch", "70bd7e2e2081e161", "1ff2356329106496", "d343f0dac7d89f7d", "24a5f750aaa2a6a0"),
        ("synth-lay", "10ac916c9a540d46", "1ff2356329106496", "5774d921e33b258c", "d4958b41ff41e440"),
        ("synth-lens", "5172cecc14091436", "1ff2356329106496", "a615c376ca67f9e7", "fc44d471bf34ca41"),
        ("f4-crowns", "889891fd7198d2e7", "1ff2356329106496", "a2c5995cca1e3430", "2fb49885bed20e54"),
        ("f4-office3", "401a8e8cae5835f7", "1ff2356329106496", "a882d07e5ba9051b", "27bdca1b5067d473"),
        ("f4-sphere", "1dc4eacfc0c126ab", "1ff2356329106496", "8ccdd22746702024", "b441dabb2de1d177"),
        ("f4-federation", "5cac171cba3089c7", "1ff2356329106496", "0b690fe9b0fd082f", "65c003b688a2c544"),
        ("f4-liege", "4df323390b8198ee", "1ff2356329106496", "9c3d8f495e44dd5f", "f998e1b5094c449d"),
        ("f4-moves", "c17459577d7b6606", "1ff2356329106496", "0d8e8b900a66988b", "2f82c605e5da6f6e"),
        ("f4-federation@f4", "c3f268a307f0e80e", "1ff2356329106496", "d14f713515da0116", "65c003b688a2c544"),
        ("f4-moves@f4", "26ad37c654db1f98", "1ff2356329106496", "4d33d041a2b43f4e", "2f82c605e5da6f6e"),
        ("synth-calclip", "c32556fed1833759", "1ff2356329106496", "f341ddb3bcf5af4f", "2ca42a22f8e732e6"),
        ("lantern@f4", "0f4cd1708eaf3d3d", "1ff2356329106496", "56563e46a0f7a678", "77e3606a4cc9b171"),
        ("east-asia@f4", "7d503476194f1473", "1ff2356329106496", "085a7edc55cf131a", "dc255acd221b375b"),
        ("east-asia+move@f4", "2d706d37ed9de271", "1ff2356329106496", "459fe41ce5c2c4b6", "dc255acd221b375b"),
        ("east-asia+nest@f4", "ff9ec530f8c51566", "1ff2356329106496", "5c53a61844cec43d", "dc255acd221b375b"),
        ("east-asia+dep@f4", "6cd167a5a91f9ee2", "1ff2356329106496", "c77ee812bacd7bda", "dc255acd221b375b"),
        ("east-asia+d7@f4", "db175897c8ac54d8", "1ff2356329106496", "b96322f150de7f2c", "dc255acd221b375b"),
        ("east-asia+sphere@f4", "5a7ed686eea8b08f", "1ff2356329106496", "5a00d3b997c6b92b", "dc255acd221b375b"),
        ("nest-f4@f4", "169bc8b23926df6e", "1ff2356329106496", "3e4473e27bb96fda", "f7c56ae63491174f"),
        ("synth@f4", "781e895f9c3edc78", "1ff2356329106496", "aa6e3ee4591d51a4", "13654284aba7feee"),
        ("synth+patch@f4", "1759f813871d73ba", "1ff2356329106496", "f5846b8630ab06e7", "24a5f750aaa2a6a0"),
        ("synth-lay@f4", "5c9978431e991997", "1ff2356329106496", "5561b1b281495b24", "d4958b41ff41e440"),
        ("synth-lens@f4", "2ffc1a2ef1d091d3", "1ff2356329106496", "83b25a933a9a0d43", "fc44d471bf34ca41"),
        ("east-asia+ktl", "34549852aff2efe6", "6e77d0d8f94037cc", "ebd07630fe84b7e5", "4d9fc7740296a72b"),
    ]),
    // 판 5(2026-10-25 · 리메이크 4단계 배치 갈래 — 감독 결정 G7 가): 직위 줄 더(칸 종류 9)의 줄 높이 비트 — 띠 look 30 · sub 17 ~ 21 · 줄 figWide 21 ~ 25(tracks.mjs 늦은 차례).
    // 직위 줄 더가 있는 f4-office3만 출력이 바뀜 · 정답지 자료에 f4-office4(승계로 이은 띠마다 다른 수 · 직위 줄 더만 칸이 있는 객체 · 없는 이웃)와 f4-office4@f4(알려진 차이)를 더함.
    (5, &[
        ("lantern", "27a30d20e01bb2b9", "6e77d0d8f94037cc", "56563e46a0f7a678", "e6688c85207c184b"),
        ("east-asia·2000", "c782631ae9e347de", "6e77d0d8f94037cc", "45b09ff795fd6149", "6d2ca3f6b0466b0e"),
        ("east-asia", "478ebde79e3bad9c", "6e77d0d8f94037cc", "295ea4f34b47d82b", "4d9fc7740296a72b"),
        ("east-asia+move", "522b6e553253a633", "6e77d0d8f94037cc", "8c77968f903d6ce6", "4d9fc7740296a72b"),
        ("east-asia+nest", "a5e8beaa7347c97d", "6e77d0d8f94037cc", "e1a30da8e5cbb9d2", "4d9fc7740296a72b"),
        ("east-asia+dep", "2447cc3f12e249b6", "6e77d0d8f94037cc", "f49fe05f596760b0", "4d9fc7740296a72b"),
        ("east-asia+d7", "896034dfa307e5a7", "6e77d0d8f94037cc", "ea2f456967a47de9", "4d9fc7740296a72b"),
        ("east-asia+sphere", "e7ad8f3fb028ef6c", "6e77d0d8f94037cc", "85e21d9c7993b30b", "4d9fc7740296a72b"),
        ("nest-f4", "9d8be786d827702b", "6e77d0d8f94037cc", "861e36b043ef8053", "d8f3ecb9b39e9585"),
        ("synth", "03616be48ddc46b9", "6e77d0d8f94037cc", "a49bdca07d8fb311", "0a4b8dfc53cd7073"),
        ("synth+patch·뉴욕", "57fc9d48ac84398e", "6e77d0d8f94037cc", "8516617e7178be09", "70f7ecd10179cd46"),
        ("synth+patch", "70bd7e2e2081e161", "6e77d0d8f94037cc", "d343f0dac7d89f7d", "70f7ecd10179cd46"),
        ("synth-lay", "10ac916c9a540d46", "6e77d0d8f94037cc", "5774d921e33b258c", "61765b3e88c24861"),
        ("synth-lens", "5172cecc14091436", "6e77d0d8f94037cc", "a615c376ca67f9e7", "aa98082c4e7bfdd0"),
        ("f4-crowns", "7ec2682c636e7bcf", "6e77d0d8f94037cc", "64db7de351ffef87", "97b725f9789ba7c2"),
        ("f4-office3", "401a8e8cae5835f7", "6e77d0d8f94037cc", "7bcd48fbbe3b4118", "e814e5d773bba4a6"),
        ("f4-office4", "0d7720fce8a2df38", "6e77d0d8f94037cc", "d5f577cd90370b5c", "784ce2c799fe306f"),
        ("f4-sphere", "1dc4eacfc0c126ab", "6e77d0d8f94037cc", "8ccdd22746702024", "5f5c6bdcb7bf6b3c"),
        ("f4-federation", "5cac171cba3089c7", "6e77d0d8f94037cc", "0b690fe9b0fd082f", "8667d30a430cf582"),
        ("f4-liege", "4df323390b8198ee", "6e77d0d8f94037cc", "9c3d8f495e44dd5f", "b3cbacc0c94bbefd"),
        ("f4-federation@f4", "c3f268a307f0e80e", "6e77d0d8f94037cc", "d14f713515da0116", "8667d30a430cf582"),
        ("f4-office4@f4", "dff2cb0d63ebf20e", "6e77d0d8f94037cc", "affd01e8e526d950", "784ce2c799fe306f"),
        ("synth-calclip", "c32556fed1833759", "6e77d0d8f94037cc", "f341ddb3bcf5af4f", "0d3781657e9b30dd"),
        ("lantern@f4", "0f4cd1708eaf3d3d", "6e77d0d8f94037cc", "56563e46a0f7a678", "e6688c85207c184b"),
        ("east-asia@f4", "7d503476194f1473", "6e77d0d8f94037cc", "085a7edc55cf131a", "4d9fc7740296a72b"),
        ("east-asia+move@f4", "2d706d37ed9de271", "6e77d0d8f94037cc", "459fe41ce5c2c4b6", "4d9fc7740296a72b"),
        ("east-asia+nest@f4", "ff9ec530f8c51566", "6e77d0d8f94037cc", "5c53a61844cec43d", "4d9fc7740296a72b"),
        ("east-asia+dep@f4", "6cd167a5a91f9ee2", "6e77d0d8f94037cc", "c77ee812bacd7bda", "4d9fc7740296a72b"),
        ("east-asia+d7@f4", "db175897c8ac54d8", "6e77d0d8f94037cc", "b96322f150de7f2c", "4d9fc7740296a72b"),
        ("east-asia+sphere@f4", "5a7ed686eea8b08f", "6e77d0d8f94037cc", "5a00d3b997c6b92b", "4d9fc7740296a72b"),
        ("nest-f4@f4", "169bc8b23926df6e", "6e77d0d8f94037cc", "3e4473e27bb96fda", "d8f3ecb9b39e9585"),
        ("synth@f4", "781e895f9c3edc78", "6e77d0d8f94037cc", "aa6e3ee4591d51a4", "0a4b8dfc53cd7073"),
        ("synth+patch@f4", "1759f813871d73ba", "6e77d0d8f94037cc", "f5846b8630ab06e7", "70f7ecd10179cd46"),
        ("synth-lay@f4", "5c9978431e991997", "6e77d0d8f94037cc", "5561b1b281495b24", "61765b3e88c24861"),
        ("synth-lens@f4", "2ffc1a2ef1d091d3", "6e77d0d8f94037cc", "83b25a933a9a0d43", "aa98082c4e7bfdd0"),
        ("east-asia+ktl", "34549852aff2efe6", "6e77d0d8f94037cc", "ebd07630fe84b7e5", "4d9fc7740296a72b"),
    ]),
    // 판 6(2026-10-25 · 리메이크 4단계 배치 갈래 걸음 4 — 감독 결정 LEGIT 가): 정규화 · 모델이 칸(지도자 · 내각 · 직위 줄 더) · 소속 줄 · hosts의 정통성(status)을 지킴.
    // 칸에 status가 있는 f4-office3의 항목 기록이 바뀜 · f4-office4에 칸 · 소속 구간의 정통성과 나루 줄(기간 있는 · 접힌 그릇)을 덧댐(입력이 바뀜 · f4-office4@f4도).
    // 4단계 선반 갈래 걸음 1: 정답지 자료에 구성원 여섯 이상의 그릇 셋(f4-federation-scope · lantern+shelf-flat · lantern+shelf-chain)을 더함(새 자료 — 판은 그대로).
    // 이어서 잘린 달력 표(calendar-slice.json)를 다시 떠 달력 표 지문만 바뀜 — 표(달 · 해 범위)는 그대로이고 입력 목록 · 물은 날 수(단기)만 늘어 배치 · 달력 기록 해시는 그대로(KTL은 옛 줄).
    (6, &[
        ("lantern", "27a30d20e01bb2b9", "5db3a41f3b9ae851", "56563e46a0f7a678", "e6688c85207c184b"),
        ("east-asia·2000", "c782631ae9e347de", "5db3a41f3b9ae851", "45b09ff795fd6149", "6d2ca3f6b0466b0e"),
        ("east-asia", "478ebde79e3bad9c", "5db3a41f3b9ae851", "295ea4f34b47d82b", "4d9fc7740296a72b"),
        ("east-asia+move", "522b6e553253a633", "5db3a41f3b9ae851", "8c77968f903d6ce6", "4d9fc7740296a72b"),
        ("east-asia+nest", "a5e8beaa7347c97d", "5db3a41f3b9ae851", "e1a30da8e5cbb9d2", "4d9fc7740296a72b"),
        ("east-asia+dep", "2447cc3f12e249b6", "5db3a41f3b9ae851", "f49fe05f596760b0", "4d9fc7740296a72b"),
        ("east-asia+d7", "896034dfa307e5a7", "5db3a41f3b9ae851", "ea2f456967a47de9", "4d9fc7740296a72b"),
        ("east-asia+sphere", "e7ad8f3fb028ef6c", "5db3a41f3b9ae851", "85e21d9c7993b30b", "4d9fc7740296a72b"),
        ("nest-f4", "9d8be786d827702b", "5db3a41f3b9ae851", "861e36b043ef8053", "d8f3ecb9b39e9585"),
        ("synth", "03616be48ddc46b9", "5db3a41f3b9ae851", "a49bdca07d8fb311", "0a4b8dfc53cd7073"),
        ("synth+patch·뉴욕", "57fc9d48ac84398e", "5db3a41f3b9ae851", "8516617e7178be09", "70f7ecd10179cd46"),
        ("synth+patch", "70bd7e2e2081e161", "5db3a41f3b9ae851", "d343f0dac7d89f7d", "70f7ecd10179cd46"),
        ("synth-lay", "10ac916c9a540d46", "5db3a41f3b9ae851", "5774d921e33b258c", "61765b3e88c24861"),
        ("synth-lens", "5172cecc14091436", "5db3a41f3b9ae851", "a615c376ca67f9e7", "aa98082c4e7bfdd0"),
        ("f4-crowns", "7ec2682c636e7bcf", "5db3a41f3b9ae851", "64db7de351ffef87", "97b725f9789ba7c2"),
        ("f4-office3", "401a8e8cae5835f7", "5db3a41f3b9ae851", "bde52e7855947cc9", "e814e5d773bba4a6"),
        ("f4-office4", "1581029a5db63066", "5db3a41f3b9ae851", "58eeb0a07bccf9cf", "784ce2c799fe306f"),
        ("f4-sphere", "1dc4eacfc0c126ab", "5db3a41f3b9ae851", "8ccdd22746702024", "5f5c6bdcb7bf6b3c"),
        ("f4-federation", "5cac171cba3089c7", "5db3a41f3b9ae851", "0b690fe9b0fd082f", "8667d30a430cf582"),
        ("f4-liege", "4df323390b8198ee", "5db3a41f3b9ae851", "9c3d8f495e44dd5f", "b3cbacc0c94bbefd"),
        ("f4-federation-scope", "36fa751f34ecbdf7", "5db3a41f3b9ae851", "e9f6c2fb967fde07", "8667d30a430cf582"),
        ("lantern+shelf-flat", "4550234f333f9872", "5db3a41f3b9ae851", "e1e62c1199bf6266", "e6688c85207c184b"),
        ("lantern+shelf-chain", "4d3d260a2a0272c4", "5db3a41f3b9ae851", "19486fd53b32a9df", "e6688c85207c184b"),
        ("f4-federation@f4", "c3f268a307f0e80e", "5db3a41f3b9ae851", "d14f713515da0116", "8667d30a430cf582"),
        ("f4-office4@f4", "ac6f6b1018fea67e", "5db3a41f3b9ae851", "689b67f41f978544", "784ce2c799fe306f"),
        ("synth-calclip", "c32556fed1833759", "5db3a41f3b9ae851", "f341ddb3bcf5af4f", "0d3781657e9b30dd"),
        ("lantern@f4", "0f4cd1708eaf3d3d", "5db3a41f3b9ae851", "56563e46a0f7a678", "e6688c85207c184b"),
        ("east-asia@f4", "7d503476194f1473", "5db3a41f3b9ae851", "085a7edc55cf131a", "4d9fc7740296a72b"),
        ("east-asia+move@f4", "2d706d37ed9de271", "5db3a41f3b9ae851", "459fe41ce5c2c4b6", "4d9fc7740296a72b"),
        ("east-asia+nest@f4", "ff9ec530f8c51566", "5db3a41f3b9ae851", "5c53a61844cec43d", "4d9fc7740296a72b"),
        ("east-asia+dep@f4", "6cd167a5a91f9ee2", "5db3a41f3b9ae851", "c77ee812bacd7bda", "4d9fc7740296a72b"),
        ("east-asia+d7@f4", "db175897c8ac54d8", "5db3a41f3b9ae851", "b96322f150de7f2c", "4d9fc7740296a72b"),
        ("east-asia+sphere@f4", "5a7ed686eea8b08f", "5db3a41f3b9ae851", "5a00d3b997c6b92b", "4d9fc7740296a72b"),
        ("nest-f4@f4", "169bc8b23926df6e", "5db3a41f3b9ae851", "3e4473e27bb96fda", "d8f3ecb9b39e9585"),
        ("synth@f4", "781e895f9c3edc78", "5db3a41f3b9ae851", "aa6e3ee4591d51a4", "0a4b8dfc53cd7073"),
        ("synth+patch@f4", "1759f813871d73ba", "5db3a41f3b9ae851", "f5846b8630ab06e7", "70f7ecd10179cd46"),
        ("synth-lay@f4", "5c9978431e991997", "5db3a41f3b9ae851", "5561b1b281495b24", "61765b3e88c24861"),
        ("synth-lens@f4", "2ffc1a2ef1d091d3", "5db3a41f3b9ae851", "83b25a933a9a0d43", "aa98082c4e7bfdd0"),
        ("east-asia+ktl", "34549852aff2efe6", "6e77d0d8f94037cc", "ebd07630fe84b7e5", "4d9fc7740296a72b"),
    ]),
    // 판 7(2026-10-25 · 리메이크 4단계 — 배치 갈래(remake-4-lay)와 선반 갈래(remake-4-shelf)가 같은 날 따로 올린 판 7을 remake-4-int에 합치며 한 판으로 접음.
    // 두 갈래의 출력을 함께 담은 표는 판 9). 아래 표는 배치 갈래의 판 7 표(판 8이 그 뒤를 이음) — 선반 갈래의 판 7 표(가지 remake-4-shelf 8e02e4b)는 접으며 뺌.
    // (가) 배치 갈래 걸음 5(감독 결정 LEGIT 가): 칸의 정통성(일반 항목 구역 57 — strips.mjs) · 소속 구간의 정통성(구역 58 — bands.mjs).
    // status가 적힌 칸 · 소속이 있는 f4-office3 · f4-office4 · f4-office4@f4만 출력이 바뀜(입력은 그대로).
    // 새 자료 f4-legit · f4-legit@f4(4단계 배치 갈래 둘째 차례 걸음 2 — 다듬기 판 정통성 장면 + 곁 · 몸통 트랙)의 줄을 더함(판 7 그대로 — 표만 다시).
    // (나) 선반 갈래 걸음 3(감독 결정 '선반 = 엔진 변형 길'): 내보내기가 그릇마다 선반 변형(shelf:<그릇 uid> · 갈래 6)을 셈 —
    // 구성원(그 그릇만 켠 배치에서 차지한 띠)이 다섯을 넘는 그릇에만 생겨 변형 목록 끝에 붙는다. 바뀐 것은 그런 그릇이 든 자료 일곱뿐(nest 넷 — 미리 센 결과 바깥
    // 그릇 nest-scene/jp-era 구성 9 · 끝에 덧붙기만 · 새 시험 자료 셋). 그 밖의 자료는 배치 · 달력 기록 해시가 판 6과 같다.
    // 선반 갈래 — 합칠 때 remake-4-lay의 판과 한 판으로(두 갈래가 따로 올린 판을 하나로 모아 이 표를 다시 찍음 — 판 9).
    // 선반 갈래 걸음 4(같은 날): 선반 변형에 숨긴 구성원 꼬리표(구역 59 — 숨은 띠마다 하나 · 가지 끝 줄)가 더 실려 같은 자료 일곱의 배치가 다시 바뀜 —
    // 이 판은 아직 어느 저장소에도 적히지 않은(합치지 않은) 판이라 판 8로 올리지 않고 판 7의 그 줄만 고쳐 찍었다(nest 넷은 여전히 끝에 덧붙기만).
    // 선반 갈래 검토 고침(같은 날 · 같은 까닭으로 판 7 안): 선반이 숨긴 구성원의 사건을 공통 줄('그 밖' 새 줄)로 옮기지 않고 이사 −1로 숨기고, 바탕 문화 조각을
    // 승계국을 따라 옮겨(−1 또는 다시 지은 줄) lantern+shelf-flat의 배치가 바뀜 · lantern+shelf-chain은 바탕 문화 셋을 더해 입력이 바뀜. 그 밖의 자료는 그대로.
    // 렌즈가 있는 자료는 선반 변형이 렌즈 변형(kind 4) 앞에 들어 렌즈 변형 번호가 선반 수만큼 밀린다 — KTL 줄(판 6을 옮긴 것)은 KTL이 있는 PC에서 다시 찍을 것.
    // (remake-4-int: 이 검토 고침은 판 7 · 9가 접힌 뒤에 와서 아래 판 7 표 · 판 9 표에는 없다 — 그 출력은 4단계 1차 합치기의 판 10에 담는다.)
    (7, &[
        ("lantern", "27a30d20e01bb2b9", "6e77d0d8f94037cc", "56563e46a0f7a678", "e6688c85207c184b"),
        ("east-asia·2000", "c782631ae9e347de", "6e77d0d8f94037cc", "45b09ff795fd6149", "6d2ca3f6b0466b0e"),
        ("east-asia", "478ebde79e3bad9c", "6e77d0d8f94037cc", "295ea4f34b47d82b", "4d9fc7740296a72b"),
        ("east-asia+move", "522b6e553253a633", "6e77d0d8f94037cc", "8c77968f903d6ce6", "4d9fc7740296a72b"),
        ("east-asia+nest", "a5e8beaa7347c97d", "6e77d0d8f94037cc", "e1a30da8e5cbb9d2", "4d9fc7740296a72b"),
        ("east-asia+dep", "2447cc3f12e249b6", "6e77d0d8f94037cc", "f49fe05f596760b0", "4d9fc7740296a72b"),
        ("east-asia+d7", "896034dfa307e5a7", "6e77d0d8f94037cc", "ea2f456967a47de9", "4d9fc7740296a72b"),
        ("east-asia+sphere", "e7ad8f3fb028ef6c", "6e77d0d8f94037cc", "85e21d9c7993b30b", "4d9fc7740296a72b"),
        ("nest-f4", "9d8be786d827702b", "6e77d0d8f94037cc", "861e36b043ef8053", "d8f3ecb9b39e9585"),
        ("synth", "03616be48ddc46b9", "6e77d0d8f94037cc", "a49bdca07d8fb311", "0a4b8dfc53cd7073"),
        ("synth+patch·뉴욕", "57fc9d48ac84398e", "6e77d0d8f94037cc", "8516617e7178be09", "70f7ecd10179cd46"),
        ("synth+patch", "70bd7e2e2081e161", "6e77d0d8f94037cc", "d343f0dac7d89f7d", "70f7ecd10179cd46"),
        ("synth-lay", "10ac916c9a540d46", "6e77d0d8f94037cc", "5774d921e33b258c", "61765b3e88c24861"),
        ("synth-lens", "5172cecc14091436", "6e77d0d8f94037cc", "a615c376ca67f9e7", "aa98082c4e7bfdd0"),
        ("f4-crowns", "7ec2682c636e7bcf", "6e77d0d8f94037cc", "64db7de351ffef87", "97b725f9789ba7c2"),
        ("f4-office3", "401a8e8cae5835f7", "6e77d0d8f94037cc", "73e14de2fe956cf9", "e814e5d773bba4a6"),
        ("f4-office4", "1581029a5db63066", "6e77d0d8f94037cc", "7c75bc8931b8a4f8", "784ce2c799fe306f"),
        ("f4-legit", "1797f69a8ca3f17f", "6e77d0d8f94037cc", "2f982898ec87c949", "54f6b68ec919ef3a"),
        ("f4-sphere", "1dc4eacfc0c126ab", "6e77d0d8f94037cc", "8ccdd22746702024", "5f5c6bdcb7bf6b3c"),
        ("f4-federation", "5cac171cba3089c7", "6e77d0d8f94037cc", "0b690fe9b0fd082f", "8667d30a430cf582"),
        ("f4-liege", "4df323390b8198ee", "6e77d0d8f94037cc", "9c3d8f495e44dd5f", "b3cbacc0c94bbefd"),
        ("f4-federation@f4", "c3f268a307f0e80e", "6e77d0d8f94037cc", "d14f713515da0116", "8667d30a430cf582"),
        ("f4-office4@f4", "ac6f6b1018fea67e", "6e77d0d8f94037cc", "5281f61cdcaf996c", "784ce2c799fe306f"),
        ("f4-legit@f4", "e576d604dba8568b", "6e77d0d8f94037cc", "217395250c100695", "54f6b68ec919ef3a"),
        ("synth-calclip", "c32556fed1833759", "6e77d0d8f94037cc", "f341ddb3bcf5af4f", "0d3781657e9b30dd"),
        ("lantern@f4", "0f4cd1708eaf3d3d", "6e77d0d8f94037cc", "56563e46a0f7a678", "e6688c85207c184b"),
        ("east-asia@f4", "7d503476194f1473", "6e77d0d8f94037cc", "085a7edc55cf131a", "4d9fc7740296a72b"),
        ("east-asia+move@f4", "2d706d37ed9de271", "6e77d0d8f94037cc", "459fe41ce5c2c4b6", "4d9fc7740296a72b"),
        ("east-asia+nest@f4", "ff9ec530f8c51566", "6e77d0d8f94037cc", "5c53a61844cec43d", "4d9fc7740296a72b"),
        ("east-asia+dep@f4", "6cd167a5a91f9ee2", "6e77d0d8f94037cc", "c77ee812bacd7bda", "4d9fc7740296a72b"),
        ("east-asia+d7@f4", "db175897c8ac54d8", "6e77d0d8f94037cc", "b96322f150de7f2c", "4d9fc7740296a72b"),
        ("east-asia+sphere@f4", "5a7ed686eea8b08f", "6e77d0d8f94037cc", "5a00d3b997c6b92b", "4d9fc7740296a72b"),
        ("nest-f4@f4", "169bc8b23926df6e", "6e77d0d8f94037cc", "3e4473e27bb96fda", "d8f3ecb9b39e9585"),
        ("synth@f4", "781e895f9c3edc78", "6e77d0d8f94037cc", "aa6e3ee4591d51a4", "0a4b8dfc53cd7073"),
        ("synth+patch@f4", "1759f813871d73ba", "6e77d0d8f94037cc", "f5846b8630ab06e7", "70f7ecd10179cd46"),
        ("synth-lay@f4", "5c9978431e991997", "6e77d0d8f94037cc", "5561b1b281495b24", "61765b3e88c24861"),
        ("synth-lens@f4", "2ffc1a2ef1d091d3", "6e77d0d8f94037cc", "83b25a933a9a0d43", "aa98082c4e7bfdd0"),
        ("east-asia+ktl", "34549852aff2efe6", "6e77d0d8f94037cc", "ebd07630fe84b7e5", "4d9fc7740296a72b"),
    ]),
    // 판 8(2026-10-25 · 배치 갈래 둘째 — remake-4-lay: 겹친 공동 · 주장 지도자 두 단 · 걸음 4의 줄어드는 층도 이 판 · remake-4-shelf의 판과 합칠 때 조정자가 한 판으로 접음).
    // 걸음 3: 지도자 칸의 lane(단) · 딸린 구역 40 ~ 42 · 46 · 57의 b · 단마다의 이음 · 띠 sub 22 ~ 23 · 줄 figWide 26 ~ 27 — 두 단 띠가 있는 f4-legit · f4-legit@f4만 바뀜(입력은 그대로).
    // 걸음 4(과제 8 걸음 3 — 띠마다 제 몸통 높이): 줄 figWide 28 ~ 30(줄어드는 층 수) — 짧은 몸통 줄이 있는 lantern · east-asia+dep · f4-legit(@f4 짝 포함)만 바뀜(입력은 그대로).
    // 이 차례 안에서 두 번 찍음(걸음 3 → 걸음 4): 내보내지 않은 판이라 판 번호는 8 그대로 두고, 걸음 3이 찍은 표를 걸음 4의 표로 갈아 넣음(이 차례에 판은 한 번만 올림).
    // 검토 고침(같은 차례 · 판 8 그대로 세 번째로 찍음): 줄어드는 층이 왕조 · 지위를 세지 않음(새 앱의 흰 사슬) — lantern(@f4 짝)의 baeksa#0이 0으로 ·
    // f4-legit 입력에 몸통 줄 둘(두 층 · 일곱 층에서 자름)을 더함(입력 바뀜). east-asia+dep은 그대로.
    // 합칠 때: remake-4-shelf도 판 7(선반 변형 shelf:<uid>)을 썼다 — 위의 판 7(구역 57 · 58)과 이름만 같고 뜻도 표도 다른 판이다. 두 갈래를 합치면
    // 새 번호 하나(9)로 올려 두 갈래 출력을 함께 담은 표를 찍고, 판 7 두 덩이는 이력으로 남기되 덧글로 갈라 적는다.
    // east-asia+ktl 줄은 이 PC에 KTL이 없어 판 7의 값을 베낀 것이다 — 한국 줄에 짧은 몸통이 있어 바뀔 수 있으니 KTL을 가진 PC에서 다시 찍는다(판은 그대로).
    // (remake-4-int: 위 '합칠 때'는 26f5f64에서 판 9로 접었다. 검토 고침이 판 8 안에서 다시 찍은 lantern · f4-legit(@f4 짝) 줄은 판 9가 접은 뒤에 와서
    // 판 9 표에는 없고, 4단계 1차 합치기(배치 · 선반 갈래 검토 고침)의 판 10에 담는다.)
    (8, &[
        ("lantern", "27a30d20e01bb2b9", "6e77d0d8f94037cc", "5bc60a99b987a897", "e6688c85207c184b"),
        ("east-asia·2000", "c782631ae9e347de", "6e77d0d8f94037cc", "45b09ff795fd6149", "6d2ca3f6b0466b0e"),
        ("east-asia", "478ebde79e3bad9c", "6e77d0d8f94037cc", "295ea4f34b47d82b", "4d9fc7740296a72b"),
        ("east-asia+move", "522b6e553253a633", "6e77d0d8f94037cc", "8c77968f903d6ce6", "4d9fc7740296a72b"),
        ("east-asia+nest", "a5e8beaa7347c97d", "6e77d0d8f94037cc", "e1a30da8e5cbb9d2", "4d9fc7740296a72b"),
        ("east-asia+dep", "2447cc3f12e249b6", "6e77d0d8f94037cc", "537906bea8547fae", "4d9fc7740296a72b"),
        ("east-asia+d7", "896034dfa307e5a7", "6e77d0d8f94037cc", "ea2f456967a47de9", "4d9fc7740296a72b"),
        ("east-asia+sphere", "e7ad8f3fb028ef6c", "6e77d0d8f94037cc", "85e21d9c7993b30b", "4d9fc7740296a72b"),
        ("nest-f4", "9d8be786d827702b", "6e77d0d8f94037cc", "861e36b043ef8053", "d8f3ecb9b39e9585"),
        ("synth", "03616be48ddc46b9", "6e77d0d8f94037cc", "a49bdca07d8fb311", "0a4b8dfc53cd7073"),
        ("synth+patch·뉴욕", "57fc9d48ac84398e", "6e77d0d8f94037cc", "8516617e7178be09", "70f7ecd10179cd46"),
        ("synth+patch", "70bd7e2e2081e161", "6e77d0d8f94037cc", "d343f0dac7d89f7d", "70f7ecd10179cd46"),
        ("synth-lay", "10ac916c9a540d46", "6e77d0d8f94037cc", "5774d921e33b258c", "61765b3e88c24861"),
        ("synth-lens", "5172cecc14091436", "6e77d0d8f94037cc", "a615c376ca67f9e7", "aa98082c4e7bfdd0"),
        ("f4-crowns", "7ec2682c636e7bcf", "6e77d0d8f94037cc", "64db7de351ffef87", "97b725f9789ba7c2"),
        ("f4-office3", "401a8e8cae5835f7", "6e77d0d8f94037cc", "73e14de2fe956cf9", "e814e5d773bba4a6"),
        ("f4-office4", "1581029a5db63066", "6e77d0d8f94037cc", "7c75bc8931b8a4f8", "784ce2c799fe306f"),
        ("f4-legit", "cc00ff445900adab", "6e77d0d8f94037cc", "d060cc212bde8d66", "54f6b68ec919ef3a"),
        ("f4-sphere", "1dc4eacfc0c126ab", "6e77d0d8f94037cc", "8ccdd22746702024", "5f5c6bdcb7bf6b3c"),
        ("f4-federation", "5cac171cba3089c7", "6e77d0d8f94037cc", "0b690fe9b0fd082f", "8667d30a430cf582"),
        ("f4-liege", "4df323390b8198ee", "6e77d0d8f94037cc", "9c3d8f495e44dd5f", "b3cbacc0c94bbefd"),
        ("f4-federation@f4", "c3f268a307f0e80e", "6e77d0d8f94037cc", "d14f713515da0116", "8667d30a430cf582"),
        ("f4-office4@f4", "ac6f6b1018fea67e", "6e77d0d8f94037cc", "5281f61cdcaf996c", "784ce2c799fe306f"),
        ("f4-legit@f4", "47037655b409886f", "6e77d0d8f94037cc", "6018fbeef914a7c5", "54f6b68ec919ef3a"),
        ("synth-calclip", "c32556fed1833759", "6e77d0d8f94037cc", "f341ddb3bcf5af4f", "0d3781657e9b30dd"),
        ("lantern@f4", "0f4cd1708eaf3d3d", "6e77d0d8f94037cc", "5bc60a99b987a897", "e6688c85207c184b"),
        ("east-asia@f4", "7d503476194f1473", "6e77d0d8f94037cc", "085a7edc55cf131a", "4d9fc7740296a72b"),
        ("east-asia+move@f4", "2d706d37ed9de271", "6e77d0d8f94037cc", "459fe41ce5c2c4b6", "4d9fc7740296a72b"),
        ("east-asia+nest@f4", "ff9ec530f8c51566", "6e77d0d8f94037cc", "5c53a61844cec43d", "4d9fc7740296a72b"),
        ("east-asia+dep@f4", "6cd167a5a91f9ee2", "6e77d0d8f94037cc", "ac849fb9ba46cc6a", "4d9fc7740296a72b"),
        ("east-asia+d7@f4", "db175897c8ac54d8", "6e77d0d8f94037cc", "b96322f150de7f2c", "4d9fc7740296a72b"),
        ("east-asia+sphere@f4", "5a7ed686eea8b08f", "6e77d0d8f94037cc", "5a00d3b997c6b92b", "4d9fc7740296a72b"),
        ("nest-f4@f4", "169bc8b23926df6e", "6e77d0d8f94037cc", "3e4473e27bb96fda", "d8f3ecb9b39e9585"),
        ("synth@f4", "781e895f9c3edc78", "6e77d0d8f94037cc", "aa6e3ee4591d51a4", "0a4b8dfc53cd7073"),
        ("synth+patch@f4", "1759f813871d73ba", "6e77d0d8f94037cc", "f5846b8630ab06e7", "70f7ecd10179cd46"),
        ("synth-lay@f4", "5c9978431e991997", "6e77d0d8f94037cc", "5561b1b281495b24", "61765b3e88c24861"),
        ("synth-lens@f4", "2ffc1a2ef1d091d3", "6e77d0d8f94037cc", "83b25a933a9a0d43", "aa98082c4e7bfdd0"),
        ("east-asia+ktl", "34549852aff2efe6", "6e77d0d8f94037cc", "ebd07630fe84b7e5", "4d9fc7740296a72b"),
    ]),
    // 판 9(2026-10-25 · remake-4-int — 배치 갈래 판 8과 선반 갈래 판 7을 합친 출력 · 두 갈래가 같은 판 7을 따로 올려 판 7을 하나로 접고 하나 더 올림):
    // 판 8 표와 견주면 선반 변형이 든 자료(east-asia+nest · nest-f4와 그 @f4 짝)는 선반 갈래 판 7의 값 그대로, f4-federation-scope도 선반 갈래 값 그대로이고,
    // 두 갈래가 함께 바꾼 등불 위의 새 자료 lantern+shelf-flat · lantern+shelf-chain만 새 값(줄어드는 층 + 선반 변형). 그 밖은 판 8과 배치 · 달력 기록 해시가 같다.
    // 달력 표 지문은 선반 갈래가 다시 뜬 잘린 표(5db3a41f3b9ae851 — 표는 그대로 · 입력 목록만) · KTL은 옛 줄.
    // (위 '판 8 표'는 접을 때의 배치 갈래 걸음 4 표다 — 그 뒤 배치 갈래 검토 고침이 판 8 표의 lantern · f4-legit(@f4 짝) 줄을 다시 찍었고 그 출력은 판 10.)
    (9, &[
        ("lantern", "27a30d20e01bb2b9", "5db3a41f3b9ae851", "0506ef8350b19eb9", "e6688c85207c184b"),
        ("east-asia·2000", "c782631ae9e347de", "5db3a41f3b9ae851", "45b09ff795fd6149", "6d2ca3f6b0466b0e"),
        ("east-asia", "478ebde79e3bad9c", "5db3a41f3b9ae851", "295ea4f34b47d82b", "4d9fc7740296a72b"),
        ("east-asia+move", "522b6e553253a633", "5db3a41f3b9ae851", "8c77968f903d6ce6", "4d9fc7740296a72b"),
        ("east-asia+nest", "a5e8beaa7347c97d", "5db3a41f3b9ae851", "1f48eefd28d6c13d", "4d9fc7740296a72b"),
        ("east-asia+dep", "2447cc3f12e249b6", "5db3a41f3b9ae851", "537906bea8547fae", "4d9fc7740296a72b"),
        ("east-asia+d7", "896034dfa307e5a7", "5db3a41f3b9ae851", "ea2f456967a47de9", "4d9fc7740296a72b"),
        ("east-asia+sphere", "e7ad8f3fb028ef6c", "5db3a41f3b9ae851", "85e21d9c7993b30b", "4d9fc7740296a72b"),
        ("nest-f4", "9d8be786d827702b", "5db3a41f3b9ae851", "6785567956b706e1", "d8f3ecb9b39e9585"),
        ("synth", "03616be48ddc46b9", "5db3a41f3b9ae851", "a49bdca07d8fb311", "0a4b8dfc53cd7073"),
        ("synth+patch·뉴욕", "57fc9d48ac84398e", "5db3a41f3b9ae851", "8516617e7178be09", "70f7ecd10179cd46"),
        ("synth+patch", "70bd7e2e2081e161", "5db3a41f3b9ae851", "d343f0dac7d89f7d", "70f7ecd10179cd46"),
        ("synth-lay", "10ac916c9a540d46", "5db3a41f3b9ae851", "5774d921e33b258c", "61765b3e88c24861"),
        ("synth-lens", "5172cecc14091436", "5db3a41f3b9ae851", "a615c376ca67f9e7", "aa98082c4e7bfdd0"),
        ("f4-crowns", "7ec2682c636e7bcf", "5db3a41f3b9ae851", "64db7de351ffef87", "97b725f9789ba7c2"),
        ("f4-office3", "401a8e8cae5835f7", "5db3a41f3b9ae851", "73e14de2fe956cf9", "e814e5d773bba4a6"),
        ("f4-office4", "1581029a5db63066", "5db3a41f3b9ae851", "7c75bc8931b8a4f8", "784ce2c799fe306f"),
        ("f4-legit", "1797f69a8ca3f17f", "5db3a41f3b9ae851", "8fbcd160583e861d", "54f6b68ec919ef3a"),
        ("f4-sphere", "1dc4eacfc0c126ab", "5db3a41f3b9ae851", "8ccdd22746702024", "5f5c6bdcb7bf6b3c"),
        ("f4-federation", "5cac171cba3089c7", "5db3a41f3b9ae851", "0b690fe9b0fd082f", "8667d30a430cf582"),
        ("f4-liege", "4df323390b8198ee", "5db3a41f3b9ae851", "9c3d8f495e44dd5f", "b3cbacc0c94bbefd"),
        ("f4-federation-scope", "36fa751f34ecbdf7", "5db3a41f3b9ae851", "787c92e37bb28e58", "8667d30a430cf582"),
        ("lantern+shelf-flat", "4550234f333f9872", "5db3a41f3b9ae851", "562b4f5bc3928e42", "e6688c85207c184b"),
        ("lantern+shelf-chain", "4d3d260a2a0272c4", "5db3a41f3b9ae851", "3eed1e8ecb74bc7a", "e6688c85207c184b"),
        ("f4-federation@f4", "c3f268a307f0e80e", "5db3a41f3b9ae851", "d14f713515da0116", "8667d30a430cf582"),
        ("f4-office4@f4", "ac6f6b1018fea67e", "5db3a41f3b9ae851", "5281f61cdcaf996c", "784ce2c799fe306f"),
        ("f4-legit@f4", "e576d604dba8568b", "5db3a41f3b9ae851", "06617b8dd3d8e3d1", "54f6b68ec919ef3a"),
        ("synth-calclip", "c32556fed1833759", "5db3a41f3b9ae851", "f341ddb3bcf5af4f", "0d3781657e9b30dd"),
        ("lantern@f4", "0f4cd1708eaf3d3d", "5db3a41f3b9ae851", "0506ef8350b19eb9", "e6688c85207c184b"),
        ("east-asia@f4", "7d503476194f1473", "5db3a41f3b9ae851", "085a7edc55cf131a", "4d9fc7740296a72b"),
        ("east-asia+move@f4", "2d706d37ed9de271", "5db3a41f3b9ae851", "459fe41ce5c2c4b6", "4d9fc7740296a72b"),
        ("east-asia+nest@f4", "ff9ec530f8c51566", "5db3a41f3b9ae851", "538e9b93802b1559", "4d9fc7740296a72b"),
        ("east-asia+dep@f4", "6cd167a5a91f9ee2", "5db3a41f3b9ae851", "ac849fb9ba46cc6a", "4d9fc7740296a72b"),
        ("east-asia+d7@f4", "db175897c8ac54d8", "5db3a41f3b9ae851", "b96322f150de7f2c", "4d9fc7740296a72b"),
        ("east-asia+sphere@f4", "5a7ed686eea8b08f", "5db3a41f3b9ae851", "5a00d3b997c6b92b", "4d9fc7740296a72b"),
        ("nest-f4@f4", "169bc8b23926df6e", "5db3a41f3b9ae851", "d91136cc9a4220e6", "d8f3ecb9b39e9585"),
        ("synth@f4", "781e895f9c3edc78", "5db3a41f3b9ae851", "aa6e3ee4591d51a4", "0a4b8dfc53cd7073"),
        ("synth+patch@f4", "1759f813871d73ba", "5db3a41f3b9ae851", "f5846b8630ab06e7", "70f7ecd10179cd46"),
        ("synth-lay@f4", "5c9978431e991997", "5db3a41f3b9ae851", "5561b1b281495b24", "61765b3e88c24861"),
        ("synth-lens@f4", "2ffc1a2ef1d091d3", "5db3a41f3b9ae851", "83b25a933a9a0d43", "aa98082c4e7bfdd0"),
        ("east-asia+ktl", "34549852aff2efe6", "6e77d0d8f94037cc", "ebd07630fe84b7e5", "4d9fc7740296a72b"),
    ]),
    // 판 10(2026-10-25 · remake-4-int 4단계 1차 합치기 — 앞 갈래 끝 커밋들을 판 9 위에 합친 출력 · 이 묶음에서 한 판으로 올림):
    // 배치 갈래 검토 고침(3168dfc · daef0a4): 줄어드는 층(줄 figWide 28 ~ 30)이 왕조 · 지위를 세지 않음(새 앱의 흰 사슬) — lantern(@f4 짝)과 등불 위의 lantern+shelf-flat · lantern+shelf-chain이 바뀜 ·
    // f4-legit(@f4 짝)은 몸통 줄 둘을 더해 입력이 바뀜(갈래가 판 8 안에서 다시 찍은 값과 같은 배치 해시).
    // 선반 갈래 검토 고침(d4af338 · 같은 판 10 안에서 다시 찍음 — 아직 내보내지 않은 판): 선반이 숨긴 구성원의 사건은 이사 −1 · 바탕 문화 조각은 승계국을 따라감 —
    // lantern+shelf-flat의 배치가 바뀜 · lantern+shelf-chain은 바탕 문화 셋을 더해 입력이 바뀜. 그 밖의 자료는 위 배치 갈래 몫 그대로.
    // main 합침(2026-10-25 · remake-4-int ← main f1bbd2c — 3단계 합치기 두 묶음: 6단계 앞몫 · 코드 몫 · kin-resolve · fix-lantern-succ — 판 10 그대로 · 표만 다시):
    // main은 판 4 그대로 표만 다시 찍었다(달력 아홉 · 형식 더하기 칸 · 새 자료 f4-moves). 합친 출력은 판 10 표와 배치 해시가 모두 같고(보조 달력을 읽는 자료 포함),
    // 달력 아홉 표로 달력 표 지문(잘린 표를 합친 정답지 목록으로 다시 뜸 — 표는 main과 같음 · 입력 목록만) · 달력 기록 해시가 main 판 4와 같은 값으로 바뀜.
    // 입력이 바뀐 f4-crowns(regnal · leaderLabels · faiths)와 새 자료 f4-moves · f4-moves@f4는 main 판 4 표의 배치 해시 그대로(4단계가 바꾸는 비트가 없는 자료).
    // 판 10은 아직 어느 저장소에도 적히지 않은 판이라 올리지 않았다(main 저장소의 meta.rules는 lay 4 — 이 판에서 다시 셈).
    (10, &[
        ("lantern", "27a30d20e01bb2b9", "746f70e54fcae23d", "5bc60a99b987a897", "77e3606a4cc9b171"),
        ("east-asia·2000", "c782631ae9e347de", "746f70e54fcae23d", "45b09ff795fd6149", "a4ca82d19d0cada2"),
        ("east-asia", "478ebde79e3bad9c", "746f70e54fcae23d", "295ea4f34b47d82b", "dc255acd221b375b"),
        ("east-asia+move", "522b6e553253a633", "746f70e54fcae23d", "8c77968f903d6ce6", "dc255acd221b375b"),
        ("east-asia+nest", "a5e8beaa7347c97d", "746f70e54fcae23d", "1f48eefd28d6c13d", "dc255acd221b375b"),
        ("east-asia+dep", "2447cc3f12e249b6", "746f70e54fcae23d", "537906bea8547fae", "dc255acd221b375b"),
        ("east-asia+d7", "896034dfa307e5a7", "746f70e54fcae23d", "ea2f456967a47de9", "dc255acd221b375b"),
        ("east-asia+sphere", "e7ad8f3fb028ef6c", "746f70e54fcae23d", "85e21d9c7993b30b", "dc255acd221b375b"),
        ("nest-f4", "9d8be786d827702b", "746f70e54fcae23d", "6785567956b706e1", "f7c56ae63491174f"),
        ("synth", "03616be48ddc46b9", "746f70e54fcae23d", "a49bdca07d8fb311", "13654284aba7feee"),
        ("synth+patch·뉴욕", "57fc9d48ac84398e", "746f70e54fcae23d", "8516617e7178be09", "24a5f750aaa2a6a0"),
        ("synth+patch", "70bd7e2e2081e161", "746f70e54fcae23d", "d343f0dac7d89f7d", "24a5f750aaa2a6a0"),
        ("synth-lay", "10ac916c9a540d46", "746f70e54fcae23d", "5774d921e33b258c", "d4958b41ff41e440"),
        ("synth-lens", "5172cecc14091436", "746f70e54fcae23d", "a615c376ca67f9e7", "fc44d471bf34ca41"),
        ("f4-crowns", "889891fd7198d2e7", "746f70e54fcae23d", "a2c5995cca1e3430", "2fb49885bed20e54"),
        ("f4-office3", "401a8e8cae5835f7", "746f70e54fcae23d", "73e14de2fe956cf9", "27bdca1b5067d473"),
        ("f4-office4", "1581029a5db63066", "746f70e54fcae23d", "7c75bc8931b8a4f8", "eb120eb6f6ce4156"),
        ("f4-legit", "cc00ff445900adab", "746f70e54fcae23d", "d060cc212bde8d66", "e164970740136a89"),
        ("f4-sphere", "1dc4eacfc0c126ab", "746f70e54fcae23d", "8ccdd22746702024", "b441dabb2de1d177"),
        ("f4-federation", "5cac171cba3089c7", "746f70e54fcae23d", "0b690fe9b0fd082f", "65c003b688a2c544"),
        ("f4-liege", "4df323390b8198ee", "746f70e54fcae23d", "9c3d8f495e44dd5f", "f998e1b5094c449d"),
        ("f4-federation-scope", "36fa751f34ecbdf7", "746f70e54fcae23d", "787c92e37bb28e58", "65c003b688a2c544"),
        ("lantern+shelf-flat", "4550234f333f9872", "746f70e54fcae23d", "77c16b345e7d1d24", "77e3606a4cc9b171"),
        ("lantern+shelf-chain", "f8dca79d6cfbe87d", "746f70e54fcae23d", "80fee43cefc975a8", "77e3606a4cc9b171"),
        ("f4-moves", "c17459577d7b6606", "746f70e54fcae23d", "0d8e8b900a66988b", "2f82c605e5da6f6e"),
        ("f4-federation@f4", "c3f268a307f0e80e", "746f70e54fcae23d", "d14f713515da0116", "65c003b688a2c544"),
        ("f4-office4@f4", "ac6f6b1018fea67e", "746f70e54fcae23d", "5281f61cdcaf996c", "eb120eb6f6ce4156"),
        ("f4-legit@f4", "47037655b409886f", "746f70e54fcae23d", "6018fbeef914a7c5", "e164970740136a89"),
        ("f4-moves@f4", "26ad37c654db1f98", "746f70e54fcae23d", "4d33d041a2b43f4e", "2f82c605e5da6f6e"),
        ("synth-calclip", "c32556fed1833759", "746f70e54fcae23d", "f341ddb3bcf5af4f", "2ca42a22f8e732e6"),
        ("lantern@f4", "0f4cd1708eaf3d3d", "746f70e54fcae23d", "5bc60a99b987a897", "77e3606a4cc9b171"),
        ("east-asia@f4", "7d503476194f1473", "746f70e54fcae23d", "085a7edc55cf131a", "dc255acd221b375b"),
        ("east-asia+move@f4", "2d706d37ed9de271", "746f70e54fcae23d", "459fe41ce5c2c4b6", "dc255acd221b375b"),
        ("east-asia+nest@f4", "ff9ec530f8c51566", "746f70e54fcae23d", "538e9b93802b1559", "dc255acd221b375b"),
        ("east-asia+dep@f4", "6cd167a5a91f9ee2", "746f70e54fcae23d", "ac849fb9ba46cc6a", "dc255acd221b375b"),
        ("east-asia+d7@f4", "db175897c8ac54d8", "746f70e54fcae23d", "b96322f150de7f2c", "dc255acd221b375b"),
        ("east-asia+sphere@f4", "5a7ed686eea8b08f", "746f70e54fcae23d", "5a00d3b997c6b92b", "dc255acd221b375b"),
        ("nest-f4@f4", "169bc8b23926df6e", "746f70e54fcae23d", "d91136cc9a4220e6", "f7c56ae63491174f"),
        ("synth@f4", "781e895f9c3edc78", "746f70e54fcae23d", "aa6e3ee4591d51a4", "13654284aba7feee"),
        ("synth+patch@f4", "1759f813871d73ba", "746f70e54fcae23d", "f5846b8630ab06e7", "24a5f750aaa2a6a0"),
        ("synth-lay@f4", "5c9978431e991997", "746f70e54fcae23d", "5561b1b281495b24", "d4958b41ff41e440"),
        ("synth-lens@f4", "2ffc1a2ef1d091d3", "746f70e54fcae23d", "83b25a933a9a0d43", "fc44d471bf34ca41"),
        ("east-asia+ktl", "34549852aff2efe6", "6e77d0d8f94037cc", "ebd07630fe84b7e5", "4d9fc7740296a72b"),
    ]),
    // 판 11(2026-10-25 · 4단계 마지막 합치기 remake-4-final ← line-routing 725f0b9 — 두 갈래가 따로 올린 판 10을 한 판으로 접음):
    // line-routing 걸음 3이 판 9 위에서 올린 판 10(아래 덧글 — 그 가지에만 있던 표)을 remake-4-int 위 판 10(위 표) 뒤의 판 11로 담는다.
    // (가지 line-routing의 판 10 — 2026-10-25 · 가지 line-routing 걸음 3 — 감독 결정 (2) 트랙을 건너는 승계의 짝 꼬리표 구역 60 · links 모듈 맨 끝에 덧붙임):
    // 트랙 건넘 승계가 있는 자료만 바뀜 — 등불 넷(lantern · lantern@f4 · lantern+shelf-flat · lantern+shelf-chain — 기본 6항목 · 판 변형 66 ~ 84 · 선반 변형 1)과
    // synth-lay(@f4 짝 — 판 변형 2). 그 밖은 판 9와 배치 · 달력 기록 해시가 같다. 정답지는 구역 60과 그 뒤 기본 항목 순번(hides kind 4의 at) 밀림 말고 바이트가 같음.
    // 4단계 전체 합치기에서 다른 갈래가 올린 판과 한 판으로 접는다(remake-4-int 위 판 10).
    (11, &[
        ("lantern", "27a30d20e01bb2b9", "746f70e54fcae23d", "dd3b7f98c721f7ad", "77e3606a4cc9b171"),
        ("east-asia·2000", "c782631ae9e347de", "746f70e54fcae23d", "45b09ff795fd6149", "a4ca82d19d0cada2"),
        ("east-asia", "478ebde79e3bad9c", "746f70e54fcae23d", "295ea4f34b47d82b", "dc255acd221b375b"),
        ("east-asia+move", "522b6e553253a633", "746f70e54fcae23d", "8c77968f903d6ce6", "dc255acd221b375b"),
        ("east-asia+nest", "a5e8beaa7347c97d", "746f70e54fcae23d", "1f48eefd28d6c13d", "dc255acd221b375b"),
        ("east-asia+dep", "2447cc3f12e249b6", "746f70e54fcae23d", "537906bea8547fae", "dc255acd221b375b"),
        ("east-asia+d7", "896034dfa307e5a7", "746f70e54fcae23d", "ea2f456967a47de9", "dc255acd221b375b"),
        ("east-asia+sphere", "e7ad8f3fb028ef6c", "746f70e54fcae23d", "85e21d9c7993b30b", "dc255acd221b375b"),
        ("nest-f4", "9d8be786d827702b", "746f70e54fcae23d", "6785567956b706e1", "f7c56ae63491174f"),
        ("synth", "03616be48ddc46b9", "746f70e54fcae23d", "a49bdca07d8fb311", "13654284aba7feee"),
        ("synth+patch·뉴욕", "57fc9d48ac84398e", "746f70e54fcae23d", "8516617e7178be09", "24a5f750aaa2a6a0"),
        ("synth+patch", "70bd7e2e2081e161", "746f70e54fcae23d", "d343f0dac7d89f7d", "24a5f750aaa2a6a0"),
        ("synth-lay", "10ac916c9a540d46", "746f70e54fcae23d", "db8e41f2dd60ec4c", "d4958b41ff41e440"),
        ("synth-lens", "5172cecc14091436", "746f70e54fcae23d", "a615c376ca67f9e7", "fc44d471bf34ca41"),
        ("f4-crowns", "889891fd7198d2e7", "746f70e54fcae23d", "a2c5995cca1e3430", "2fb49885bed20e54"),
        ("f4-office3", "401a8e8cae5835f7", "746f70e54fcae23d", "73e14de2fe956cf9", "27bdca1b5067d473"),
        ("f4-office4", "1581029a5db63066", "746f70e54fcae23d", "7c75bc8931b8a4f8", "eb120eb6f6ce4156"),
        ("f4-legit", "cc00ff445900adab", "746f70e54fcae23d", "d060cc212bde8d66", "e164970740136a89"),
        ("f4-sphere", "1dc4eacfc0c126ab", "746f70e54fcae23d", "8ccdd22746702024", "b441dabb2de1d177"),
        ("f4-federation", "5cac171cba3089c7", "746f70e54fcae23d", "0b690fe9b0fd082f", "65c003b688a2c544"),
        ("f4-liege", "4df323390b8198ee", "746f70e54fcae23d", "9c3d8f495e44dd5f", "f998e1b5094c449d"),
        ("f4-federation-scope", "36fa751f34ecbdf7", "746f70e54fcae23d", "787c92e37bb28e58", "65c003b688a2c544"),
        ("lantern+shelf-flat", "4550234f333f9872", "746f70e54fcae23d", "81243dacb33c136a", "77e3606a4cc9b171"),
        ("lantern+shelf-chain", "f8dca79d6cfbe87d", "746f70e54fcae23d", "ad78e18ba3e99831", "77e3606a4cc9b171"),
        ("f4-moves", "c17459577d7b6606", "746f70e54fcae23d", "0d8e8b900a66988b", "2f82c605e5da6f6e"),
        ("f4-federation@f4", "c3f268a307f0e80e", "746f70e54fcae23d", "d14f713515da0116", "65c003b688a2c544"),
        ("f4-office4@f4", "ac6f6b1018fea67e", "746f70e54fcae23d", "5281f61cdcaf996c", "eb120eb6f6ce4156"),
        ("f4-legit@f4", "47037655b409886f", "746f70e54fcae23d", "6018fbeef914a7c5", "e164970740136a89"),
        ("f4-moves@f4", "26ad37c654db1f98", "746f70e54fcae23d", "4d33d041a2b43f4e", "2f82c605e5da6f6e"),
        ("synth-calclip", "c32556fed1833759", "746f70e54fcae23d", "f341ddb3bcf5af4f", "2ca42a22f8e732e6"),
        ("lantern@f4", "0f4cd1708eaf3d3d", "746f70e54fcae23d", "dd3b7f98c721f7ad", "77e3606a4cc9b171"),
        ("east-asia@f4", "7d503476194f1473", "746f70e54fcae23d", "085a7edc55cf131a", "dc255acd221b375b"),
        ("east-asia+move@f4", "2d706d37ed9de271", "746f70e54fcae23d", "459fe41ce5c2c4b6", "dc255acd221b375b"),
        ("east-asia+nest@f4", "ff9ec530f8c51566", "746f70e54fcae23d", "538e9b93802b1559", "dc255acd221b375b"),
        ("east-asia+dep@f4", "6cd167a5a91f9ee2", "746f70e54fcae23d", "ac849fb9ba46cc6a", "dc255acd221b375b"),
        ("east-asia+d7@f4", "db175897c8ac54d8", "746f70e54fcae23d", "b96322f150de7f2c", "dc255acd221b375b"),
        ("east-asia+sphere@f4", "5a7ed686eea8b08f", "746f70e54fcae23d", "5a00d3b997c6b92b", "dc255acd221b375b"),
        ("nest-f4@f4", "169bc8b23926df6e", "746f70e54fcae23d", "d91136cc9a4220e6", "f7c56ae63491174f"),
        ("synth@f4", "781e895f9c3edc78", "746f70e54fcae23d", "aa6e3ee4591d51a4", "13654284aba7feee"),
        ("synth+patch@f4", "1759f813871d73ba", "746f70e54fcae23d", "f5846b8630ab06e7", "24a5f750aaa2a6a0"),
        ("synth-lay@f4", "5c9978431e991997", "746f70e54fcae23d", "2ca8523dd3b34002", "d4958b41ff41e440"),
        ("synth-lens@f4", "2ffc1a2ef1d091d3", "746f70e54fcae23d", "83b25a933a9a0d43", "fc44d471bf34ca41"),
        ("east-asia+ktl", "34549852aff2efe6", "6e77d0d8f94037cc", "ebd07630fe84b7e5", "4d9fc7740296a72b"),
    ]),
];

/// 지문 골든의 판별 이력 — (지문 판, [(자료, 배치 출력 해시, 지문 해시)]).
const PRINTS: &[(&str, &[(&str, &str, &str)])] = &[
    ("지문 2", &[
        ("lantern", "3de3d43f2a550966", "f58c188297c20d28"),
        ("east-asia·2000", "33c09d8d7b63ed2b", "909656df85dea4d2"),
        ("east-asia", "65034c7873b40b82", "3d91034b17f5b56b"),
        ("east-asia+move", "8f06c6eec13a6ba4", "fdab22e3f0fcc8cd"),
        ("east-asia+nest", "7acd2a048dc12013", "3a909fd9b6856a52"),
        ("east-asia+dep", "7fb14583b3e83427", "cac24451b73a804a"),
        ("east-asia+d7", "a1cfa234af3339d9", "c0bd3958bb83d870"),
        ("east-asia+sphere", "b85be68313475a8c", "119ef6389d3eb8b3"),
        ("nest-f4", "1e78ef8088e71221", "5fe41a21cd39708e"),
        ("synth", "0895f50a32f10861", "63eb35385343cfbc"),
        ("synth+patch·뉴욕", "efc30eb6fc725bb6", "f598515d45de3894"),
        ("synth+patch", "25718ceebcd41fe9", "601fbb4f86cd2e4e"),
        ("synth-lay", "d9b8f0e0b63a1037", "de6a4bbb06fc1c9d"),
        ("synth-lens", "86ad6224c6bbf66e", "9aa329e9d17364fd"),
        ("f4-crowns", "0405fa02a7a7dcf2", "91deeadd0d151273"),
        ("f4-office3", "4873dd5f19447110", "344238d6e1dbe900"),
        ("f4-sphere", "d1d88f241ae2e7d0", "4b3c538a8d3ca624"),
        ("f4-federation", "4fa18d6048b27e64", "fbbf7e9cd9bbad4e"),
        ("f4-liege", "06799c6ec008f1f7", "e05a2edde0c16626"),
        ("f4-moves", "8eb7b804a95cac19", "5d119b4b89a0d5a3"),
        ("f4-federation@f4", "433f78d376332837", "ef84d6b5e3692598"),
        ("f4-moves@f4", "f19bb1385f13eeed", "88fe65164bb22773"),
        ("synth-calclip", "2ff3e0a7b80bf380", "4a5def5fe5b8d7e8"),
        ("lantern@f4", "3de3d43f2a550966", "f58c188297c20d28"),
        ("east-asia@f4", "c0d7874dab73ec1c", "3d91034b17f5b56b"),
        ("east-asia+move@f4", "40d652fe5497a07b", "fdab22e3f0fcc8cd"),
        ("east-asia+nest@f4", "46a99f81def81b8b", "3a909fd9b6856a52"),
        ("east-asia+dep@f4", "f5b3edf164148efc", "cac24451b73a804a"),
        ("east-asia+d7@f4", "d72f03e1b406652b", "c0bd3958bb83d870"),
        ("east-asia+sphere@f4", "00db85e62d9c2bec", "119ef6389d3eb8b3"),
        ("nest-f4@f4", "4a5d5a9f0f1bb8d2", "5fe41a21cd39708e"),
        ("synth@f4", "4108ff0df5e9ac91", "63eb35385343cfbc"),
        ("synth+patch@f4", "eec0b244dd83603c", "601fbb4f86cd2e4e"),
        ("synth-lay@f4", "4450aed1329f14a1", "37e55d3f9d3e183a"),
        ("synth-lens@f4", "03e0b5434013010b", "9aa329e9d17364fd"),
        ("east-asia+ktl", "b745f1c08e010f99", "3dbc4d9b611cbd37"),
    ]),
    // 지문 3(2026-10-24 · 리메이크 3단계 저장소 걸음 3): 온 판 조각에 문화권 단위 줄(`sphereLines` — 자료집은 글자 id)이 든다. 배치 출력은 그대로이고
    // 줄이 있는 자료(등불 · f4-crowns · f4-sphere · f4-liege)의 지문만 바뀐다. KTL은 이 PC에 없어 옛 줄 그대로(가진 PC에서 다시 찍힘).
    // 표만 다시(2026-10-25 · 통합 가지 remake-int — remake-6 앞몫 0f97162 합침): 달력 아홉 표로 모든 자료의 배치 출력 해시(달력 기록)가 바뀌고, f4-crowns는 형식 더하기 칸(regnal · leaderLabels · faiths)이 더해져 지문도 바뀜. 판(PRINT_FORM)은 그대로 · KTL 줄은 옛 줄 그대로(3단계 계획 '합칠 때 확인' ①).
    // 새 자료(2026-10-25 · 둘째 합치기 묶음 remake-int2 — remake-6-code 100f68d 합침): 형식 4 가상 팩 f4-moves와 사본 f4-moves@f4 두 줄을 더함(시험이 찍은 값 — 지문 2 표에 든 값과 같음). 다른 자료는 입력 · 지문 그대로 · 판(PRINT_FORM)도 그대로.
    // 배치 판 5(2026-10-25 · 4단계 배치 갈래 G7)에서 배치가 바뀐 f4-office3과 새 자료 f4-office4 · f4-office4@f4의 줄을 다시 찍음(배치가 바뀐 것이라 지문 판은 그대로).
    // 배치 판 6(2026-10-25 · 4단계 배치 갈래 걸음 4 — 칸 · 소속 구간의 정통성)에서 항목 기록이 바뀐 f4-office3과 입력이 바뀐 f4-office4 · f4-office4@f4의 줄을 다시 찍음(지문 판은 그대로).
    // 4단계 선반 갈래 걸음 1에서 새 자료 셋(f4-federation-scope · lantern+shelf-flat · lantern+shelf-chain)의 줄을 더함(지문 판은 그대로).
    // 배치 판 7(2026-10-25 · 4단계 선반 갈래 걸음 3 — 선반 변형)에서 배치가 바뀐 자료 일곱(nest 넷 · 새 시험 자료 셋)의 줄을 다시 찍음(지문 판은 그대로).
    // 같은 판 7을 고친 선반 갈래 걸음 4(숨긴 구성원 꼬리표 구역 59)에서 그 일곱의 줄을 한 번 더 찍음(지문 판은 그대로).
    // 배치 판 7(2026-10-25 · 4단계 배치 갈래 걸음 5 — 구역 57 · 58)에서 출력이 바뀐 f4-office3 · f4-office4 · f4-office4@f4의 줄을 다시 찍음(지문 판은 그대로).
    // 배치 판 7 그대로 새 자료 f4-legit · f4-legit@f4(4단계 배치 갈래 둘째 차례 걸음 2)의 줄을 더함(지문 판은 그대로).
    // 배치 판 8(2026-10-25 · 4단계 배치 갈래 둘째 걸음 3 — 지도자 두 단)에서 배치가 바뀐 f4-legit · f4-legit@f4의 줄을 다시 찍음(지문 판은 그대로).
    // 배치 판 8을 걸음 4(줄어드는 층 — 줄 figWide 28 ~ 30)에서 다시 찍어 배치가 바뀐 lantern · east-asia+dep · f4-legit(@f4 짝 포함)의 줄을 다시 찍음(지문 판은 그대로).
    // 배치 판 9(2026-10-25 · remake-4-int — 배치 · 선반 갈래 합침)에서 배치가 바뀐 east-asia+nest · east-asia+nest@f4 · lantern+shelf-flat · lantern+shelf-chain의 줄을 다시 찍음(지문 판은 그대로).
    // 배치 판 8을 검토 고침(줄어드는 층이 왕조 · 지위를 세지 않음 · f4-legit 몸통 줄 둘)에서 다시 찍어 바뀐 lantern · f4-legit(@f4 짝 포함)의 줄을 다시 찍음(지문 판은 그대로 —
    // remake-4-int에서는 판 9 뒤라 배치 판 10으로 담음). east-asia+ktl 줄은 이 PC에 KTL이 없어 옛 줄 그대로 — 가진 PC에서 다시 찍는다.
    // 배치 판 10(2026-10-25 · remake-4-int 4단계 1차 합치기 — 배치 갈래 검토 고침)에서 배치가 바뀐 lantern+shelf-flat · lantern+shelf-chain의 줄을 다시 찍음(지문 판은 그대로).
    // 같은 배치 판 10을 선반 갈래 검토 고침(d4af338)에서 다시 찍어 바뀐 lantern+shelf-flat · lantern+shelf-chain의 줄을 한 번 더 찍음(지문 판은 그대로).
    // remake-4-int ← main 합침(2026-10-25): 위 main 쪽 두 줄(달력 아홉 · f4-crowns 형식 더하기 칸 · 새 자료 f4-moves 둘)과 4단계 쪽 줄을 함께 담아 다시 찍음 —
    // 배치 출력 해시는 달력 기록이 든 것이라 모든 자료가 바뀌고, 지문 해시는 f4-crowns만 바뀜(main 값과 같음 · 지문 판은 그대로).
    // 배치 판 10(2026-10-25 · 가지 line-routing 걸음 3 — 구역 60 트랙 건넘 짝 꼬리표)에서 배치가 바뀐 lantern · lantern@f4 · lantern+shelf-flat · lantern+shelf-chain · synth-lay · synth-lay@f4의 줄을 다시 찍음(지문 판은 그대로 — 4단계 마지막 합치기에서 배치 판 11로 담아 다시 찍음).
    ("지문 3", &[
        ("lantern", "690f252067e81e73", "9cede1854db50b10"),
        ("east-asia·2000", "33c09d8d7b63ed2b", "909656df85dea4d2"),
        ("east-asia", "65034c7873b40b82", "3d91034b17f5b56b"),
        ("east-asia+move", "8f06c6eec13a6ba4", "fdab22e3f0fcc8cd"),
        ("east-asia+nest", "e94df2ec396961e2", "5c4846ec1afd0fdf"),
        ("east-asia+dep", "a7ecf6c032207d1b", "7353278e31c07b09"),
        ("east-asia+d7", "a1cfa234af3339d9", "c0bd3958bb83d870"),
        ("east-asia+sphere", "b85be68313475a8c", "119ef6389d3eb8b3"),
        ("nest-f4", "2bd8059e476a4d4e", "a31a341aff7536ba"),
        ("synth", "0895f50a32f10861", "63eb35385343cfbc"),
        ("synth+patch·뉴욕", "efc30eb6fc725bb6", "f598515d45de3894"),
        ("synth+patch", "25718ceebcd41fe9", "601fbb4f86cd2e4e"),
        ("synth-lay", "ccc12c4c33909290", "7134d852d536d97c"),
        ("synth-lens", "86ad6224c6bbf66e", "9aa329e9d17364fd"),
        ("f4-crowns", "0405fa02a7a7dcf2", "14725d23746cf630"),
        ("f4-office3", "04c440dea4a369d6", "15ee968bc8aa8330"),
        ("f4-office4", "5eaf3784e1276bc9", "c17652a0e92fd751"),
        ("f4-legit", "6ea702e063173c19", "6b041a7d726a089a"),
        ("f4-sphere", "d1d88f241ae2e7d0", "4d29bcc32520ed54"),
        ("f4-federation", "4fa18d6048b27e64", "fbbf7e9cd9bbad4e"),
        ("f4-liege", "06799c6ec008f1f7", "d149bc155e91dca0"),
        ("f4-federation-scope", "a076359ac57a512a", "9d017452892b01c8"),
        ("lantern+shelf-flat", "6c73fd64344a07f5", "b02cc06581b9ed4f"),
        ("lantern+shelf-chain", "ab20ec9c601181fb", "3b903f9c2d50b811"),
        ("f4-moves", "8eb7b804a95cac19", "5d119b4b89a0d5a3"),
        ("f4-federation@f4", "433f78d376332837", "ef84d6b5e3692598"),
        ("f4-office4@f4", "51bcfaa01ea62065", "b818c88772c52aab"),
        ("f4-legit@f4", "6904c867496bea86", "6b041a7d726a089a"),
        ("f4-moves@f4", "f19bb1385f13eeed", "88fe65164bb22773"),
        ("synth-calclip", "2ff3e0a7b80bf380", "4a5def5fe5b8d7e8"),
        ("lantern@f4", "690f252067e81e73", "9cede1854db50b10"),
        ("east-asia@f4", "c0d7874dab73ec1c", "3d91034b17f5b56b"),
        ("east-asia+move@f4", "40d652fe5497a07b", "fdab22e3f0fcc8cd"),
        ("east-asia+nest@f4", "95c2c4de2b3a715f", "5c4846ec1afd0fdf"),
        ("east-asia+dep@f4", "c1b77c7d4b8bc406", "7353278e31c07b09"),
        ("east-asia+d7@f4", "d72f03e1b406652b", "c0bd3958bb83d870"),
        ("east-asia+sphere@f4", "00db85e62d9c2bec", "119ef6389d3eb8b3"),
        ("nest-f4@f4", "728d59cec35f52a7", "a31a341aff7536ba"),
        ("synth@f4", "4108ff0df5e9ac91", "63eb35385343cfbc"),
        ("synth+patch@f4", "eec0b244dd83603c", "601fbb4f86cd2e4e"),
        ("synth-lay@f4", "20e3f02a22683c27", "b8b039c192541a50"),
        ("synth-lens@f4", "03e0b5434013010b", "9aa329e9d17364fd"),
        ("east-asia+ktl", "b745f1c08e010f99", "3dbc4d9b611cbd37"),
    ]),
];

fn h16(bytes: &[u8]) -> String { Sha256::digest(bytes).iter().take(8).map(|b| format!("{b:02x}")).collect() }

/// 견줄 경우 — (이름, 입력, 선택).
fn cases() -> Vec<(String, Vec<PackIn>, Opts)> {
    let base = seam_opts(None);
    let mut out = Vec::new();
    for f in fixtures() {
        let packs = inputs(&f);
        // 다른 시각 · 시간대(판정 R69 · 16b 검토 ② M3): 합성 + 패치를 뉴욕 시간대 · 사흘 뒤로 · 동아시아를 2000년 6월 1일로(진행 중 띠의 끝이 달라진다).
        if f.name == "synth+patch" {
            out.push((format!("{}·뉴욕", f.name), packs.clone(), Opts { now_ms: base.now_ms + 3.0 * 86_400_000.0, tz_min: -300, ..base.clone() }));
        }
        if f.name == "east-asia" {
            out.push((format!("{}·2000", f.name), packs.clone(), Opts { now_ms: 959_817_600_000.0, ..base.clone() }));
        }
        out.push((f.name.clone(), packs, base.clone()));
    }
    out
}

/// 입력 지문 — DLC 바이트(차례대로) · 오늘 · 시간대(달력 표는 [`calendar_print`]로 따로 — 판정 R71-1).
fn input_print(packs: &[PackIn], o: &Opts) -> String {
    let mut h = Sha256::new();
    for p in packs {
        h.update((p.bytes.len() as u64).to_le_bytes());
        h.update(&p.bytes);
    }
    h.update(o.now_ms.to_bits().to_le_bytes());
    h.update(o.tz_min.to_le_bytes());
    h.finalize().iter().take(8).map(|b| format!("{b:02x}")).collect()
}

/// 달력 표 지문 — 준 표 바이트의 SHA-256(없으면 '없음').
fn calendar_print(o: &Opts) -> String {
    o.calendar.as_deref().map_or_else(|| "없음".to_owned(), |c| h16(c))
}

/// 배치 해시 · 달력 기록 해시 — 출력에서 내보내기 `calendar` 모듈의 `cal:` 기록(`entities`의 `kind: "cal"`)을 떼어 따로 셈한다.
fn split_hashes(out: &serde_json::Value) -> (String, String) {
    let mut rest = out.clone();
    let mut cals = Vec::new();
    if let Some(list) = rest["entities"].as_array_mut() {
        list.retain(|e| if e["kind"] == "cal" { cals.push(e.clone()); false } else { true });
    }
    (h16(&serde_json::to_vec(&rest).unwrap()), h16(&serde_json::to_vec(&cals).unwrap()))
}

/// 한 자료의 판정.
#[derive(Debug, PartialEq)]
enum Judge {
    /// 그대로.
    Same,
    /// 입력(또는 보조 달력을 읽는 자료의 달력 표)이 바뀜 — 판은 그대로, 마지막 항목의 표만 다시.
    Moved,
    /// 입력이 같은데 출력이 바뀜 — 판 올림(글은 무엇이 바뀌었나).
    Changed(String),
}

/// 배치 골든의 판정 — `old` · `now` = [입력 지문, 달력 표 지문, 배치 해시, 달력 기록 해시], `reads` = 이 배치가 보조 달력 날짜를 읽었는가(판정 R71-1).
fn judge_layout(old: &[String], now: &[String], reads: bool) -> Judge {
    let (input, cal, core, cals) = (0, 1, 2, 3);
    if old[input] != now[input] {
        return Judge::Moved;
    }
    let core_moved = (old[core] != now[core]).then(|| format!("배치 {} → {}", old[core], now[core]));
    if old[cal] == now[cal] {
        let cals_moved = (old[cals] != now[cals]).then(|| format!("달력 기록 {} → {}", old[cals], now[cals]));
        let what: Vec<String> = [core_moved, cals_moved].into_iter().flatten().collect();
        return if what.is_empty() { Judge::Same } else { Judge::Changed(what.join(" · ")) };
    }
    // 달력 표만 바뀜: 보조 달력을 읽은 자료는 표를 따라 바뀔 수 있다 — 읽지 않은 자료는 `cal:` 기록 밖이 그대로여야 한다.
    match core_moved {
        Some(what) if !reads => Judge::Changed(format!("{what}(달력 표만 바뀌었고 보조 달력을 읽지 않은 자료)")),
        _ => Judge::Moved,
    }
}

/// 지문 골든의 판정 — `old` · `now` = [배치 출력 해시, 지문 해시]: 배치가 바뀌었으면 '입력 바뀜', 배치가 같은데 지문이 바뀌면 판 올림.
fn judge_prints(old: &[String], now: &[String]) -> Judge {
    if old[0] != now[0] {
        Judge::Moved
    } else if old[1] != now[1] {
        Judge::Changed(format!("{} → {}", old[1], now[1]))
    } else {
        Judge::Same
    }
}

/// 선택 자료의 이름(`list.json`의 `optional`).
fn optional_names() -> BTreeSet<String> {
    let manifest = std::fs::canonicalize(env!("CARGO_MANIFEST_DIR")).expect("engine 폴더");
    let list: serde_json::Value = serde_json::from_slice(&std::fs::read(manifest.join("..").join("fixtures").join("oracle").join("list.json")).expect("list.json")).unwrap();
    list.as_array().unwrap().iter().filter(|x| x["optional"].as_bool().unwrap_or(false)).filter_map(|x| x["name"].as_str().map(str::to_owned)).collect()
}

/// 이력 한 줄 — (자료, 칸들).
type Row = (String, Vec<String>);

/// 이력 하나를 견준다 — 실패 글들(없으면 빈 것). `current`는 지금 판의 글, `bump`는 판을 올리라는 안내, `next`는 덧붙일 새 항목의 판 글
/// (16b 고침 2회차 작은 것 3 — 예전엔 `bump`의 끝 낱말을 잘라 썼다), `now`는 지금 셈한 줄, `judge`는 (골든 줄, 지금 줄, 자료 이름) → 판정.
#[allow(clippy::too_many_arguments)]
fn check(what: &str, history: &[(String, Vec<Row>)], current: &str, bump: &str, next: &str, now: &[Row], optional: &BTreeSet<String>,
    judge: &dyn Fn(&[String], &[String], &str) -> Judge) -> Vec<String> {
    let mut fails = Vec::new();
    let Some((last, table)) = history.last() else { return vec![format!("{what}: 이력이 비었습니다")] };
    if last != current {
        fails.push(format!("{what}: 이력의 마지막 판({last})이 지금 판({current})과 다릅니다 — 판을 올렸으면 이력 끝에 그 판의 항목을 덧붙이세요"));
    }
    let (mut changed, mut moved, mut fresh, mut skipped) = (Vec::new(), Vec::new(), Vec::new(), Vec::new());
    for (name, cols) in now {
        match table.iter().find(|(n, _)| n == name) {
            None if optional.contains(name) => skipped.push(name.clone()),
            None => fresh.push(name.clone()),
            Some((_, old)) => match judge(old, cols, name) {
                Judge::Same => {}
                Judge::Moved => moved.push(name.clone()),
                Judge::Changed(how) => changed.push(format!("{name}: {how}")),
            },
        }
    }
    let gone: Vec<&String> = table.iter().map(|(n, _)| n).filter(|n| !now.iter().any(|(m, _)| m == *n)).collect();
    if !skipped.is_empty() { eprintln!("{what}: 골든에 없는 선택 자료 — 건너뜀: {skipped:?}"); }
    if !gone.is_empty() { eprintln!("{what}: 골든에 있으나 이 PC에 없는 자료 — 건너뜀: {gone:?}"); }
    let line = |n: &str, cols: &[String]| format!("        (\"{n}\", {}),", cols.iter().map(|c| format!("\"{c}\"")).collect::<Vec<_>>().join(", "));
    let entry = |ver: &str| -> String {
        // 찍는 표에는 이 PC에 있는 선택 자료도 싣는다(다음부터 견줌) · 골든에만 있고 이 PC에 없는 자료는 옛 줄 그대로 둔다.
        let mut rows: Vec<String> = now.iter().map(|(n, c)| line(n, c)).collect();
        rows.extend(table.iter().filter(|(n, _)| gone.contains(&n)).map(|(n, c)| line(n, c)));
        format!("    ({ver}, &[\n{}\n    ]),", rows.join("\n"))
    };
    if !changed.is_empty() {
        fails.push(format!("{what}: 입력이 같은데 출력이 바뀌었습니다 — 판을 올리세요({bump}) · 이력 끝에 아래 항목을 덧붙임(마지막 항목을 고치지 말 것):\n  {}\n{}",
            changed.join("\n  "), entry(next)));
    } else if !moved.is_empty() || !fresh.is_empty() {
        fails.push(format!("{what}: 입력이 바뀐 자료 {moved:?} · 새 자료 {fresh:?} — 판은 그대로, 마지막 항목의 표만 다시:\n{}", entry(last)));
    }
    fails
}

#[test]
fn lay_output_matches_the_golden() {
    let optional = optional_names();
    let (mut layout_now, mut prints_now, mut readers) = (Vec::new(), Vec::new(), BTreeSet::new());
    for (name, packs, o) in cases() {
        let _ = lay::cal::take_aux_reads();
        let out = lay::export(&packs, &o).unwrap_or_else(|e| panic!("{name}: 내보내기 — {e}"));
        if lay::cal::take_aux_reads() > 0 {
            readers.insert(name.clone());
        }
        let output = h16(&serde_json::to_vec(&out).unwrap());
        let (core, cals) = split_hashes(&out);
        let p = patch::prints_under(&out, "골든").unwrap_or_else(|e| panic!("{name}: 지문 — {e}"));
        let mut text = format!("{}\n", p.globals);
        for k in &p.order { text.push_str(&format!("{k}={}\n", p.tracks[k].print)); }
        prints_now.push((name.clone(), vec![output, h16(text.as_bytes())]));
        layout_now.push((name, vec![input_print(&packs, &o), calendar_print(&o), core, cals]));
    }
    assert!(layout_now.len() >= 25, "견준 경우가 너무 적습니다: {}", layout_now.len());
    // 표지가 헛돌지 않게: 보조 달력을 읽는 자료와 읽지 않는 자료가 둘 다 있다.
    assert!(!readers.is_empty() && readers.len() < layout_now.len(), "보조 달력을 읽는 자료: {readers:?}");
    eprintln!("보조 달력을 읽는 자료(달력 표만 바뀌면 '표만 다시'): {readers:?}");
    let own = |t: &[Vec<&str>]| -> Vec<Row> { t.iter().map(|r| (r[0].to_owned(), r[1..].iter().map(|c| c.to_string()).collect())).collect() };
    let layout: Vec<(String, Vec<Row>)> = LAYOUT.iter().map(|(v, t)| (v.to_string(), own(&t.iter().map(|r| vec![r.0, r.1, r.2, r.3, r.4]).collect::<Vec<_>>()))).collect();
    let prints: Vec<(String, Vec<Row>)> = PRINTS.iter().map(|(v, t)| (format!("\"{v}\""), own(&t.iter().map(|r| vec![r.0, r.1, r.2]).collect::<Vec<_>>()))).collect();
    // 판 번호는 1부터 하나씩 는다(이력은 덧붙이기만).
    for w in LAYOUT.windows(2) { assert_eq!(w[1].0, w[0].0 + 1, "배치 골든의 판은 하나씩 늘어야 합니다"); }
    let next = LAY_RULES_VERSION + 1;
    let mut fails = check("배치 골든", &layout, &LAY_RULES_VERSION.to_string(), &format!("LAY_RULES_VERSION = {next}"), &next.to_string(), &layout_now, &optional,
        &|old, now, name| judge_layout(old, now, readers.contains(name)));
    fails.extend(check("지문 골든", &prints, &format!("\"{}\"", patch::PRINT_FORM), "PRINT_FORM을 새 글로", "\"<새 지문 판>\"", &prints_now, &optional,
        &|old, now, _| judge_prints(old, now)));
    assert!(fails.is_empty(), "{}", fails.join("\n\n"));
}

/// 판정 R71-1: 달력 표만 바뀐 커밋 — 보조 달력을 읽지 않은 자료의 배치가 바뀌면 판 올림(예전엔 표 지문이 입력 지문에 섞여 '표만 다시'로 묻혔다) ·
/// 읽는 자료는 '표만 다시' · 읽지 않은 자료라도 `cal:` 기록만 바뀌면 '표만 다시' · 표가 같으면 어느 해시든 바뀌면 판 올림.
#[test]
fn a_calendar_only_change_still_guards_the_rest() {
    let row = |cal: &str, core: &str, cals: &str| -> Vec<String> { ["입력", cal, core, cals].iter().map(|s| s.to_string()).collect() };
    let old = row("표1", "배치1", "달력1");
    assert!(matches!(judge_layout(&old, &row("표2", "배치2", "달력2"), false), Judge::Changed(_)), "읽지 않은 자료의 배치가 바뀜 → 판 올림");
    assert_eq!(judge_layout(&old, &row("표2", "배치2", "달력2"), true), Judge::Moved, "읽는 자료 → 표만 다시");
    assert_eq!(judge_layout(&old, &row("표2", "배치1", "달력2"), false), Judge::Moved, "읽지 않은 자료의 cal: 기록만 → 표만 다시");
    assert!(matches!(judge_layout(&old, &row("표1", "배치1", "달력2"), false), Judge::Changed(_)), "표가 같은데 cal: 기록이 바뀜 → 판 올림");
    assert!(matches!(judge_layout(&old, &row("표1", "배치2", "달력1"), true), Judge::Changed(_)), "표가 같은데 배치가 바뀜 → 판 올림");
    let mut moved_input = row("표1", "배치2", "달력1");
    moved_input[0] = "새 입력".into();
    assert_eq!(judge_layout(&old, &moved_input, false), Judge::Moved, "DLC · 시각 · 시간대가 바뀜 → 표만 다시");
    assert_eq!(judge_layout(&old, &old, false), Judge::Same);
}
