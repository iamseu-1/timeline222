// 감독의 실자료 KoreanTimeLine v1.0.5(KTL — 저장소에 싣지 않는 선택 자료)의 자리 하나(판정 R58 ⑤-5 · 과제 testinfra).
// 검사 · 도구가 KTL을 찾는 곳은 모두 이것을 거친다 — Rust 검사는 tests/common/oracle.rs의 `ktl_path` · `ktl_missing`(같은 규칙).
//   HT_KTL=<파일>        KTL 자리(없으면 감독 PC의 옛 자리 D:/Timeline/KoreanTimeLine-v1.0.5.htpack). list.json의 extra에 그 옛 자리가 적힌 곳도 이 값으로 갈아 낀다.
//   HT_REQUIRE_KTL=1     KTL이 없으면 건너뛰지 않고 실패한다(감독 PC · 공식 검사에서 KTL 검사가 소리 없이 빠지지 않게).
// 감독 실자료는 읽기만 한다(사본으로 — 도구마다 머리말).
import path from 'node:path';

/** list.json · 옛 머리말에 적힌 감독 PC의 자리. */
export const KTL_DEFAULT = 'D:/Timeline/KoreanTimeLine-v1.0.5.htpack';
/** 지금 쓰는 KTL 자리(HT_KTL 또는 옛 자리). */
export const ktlFile = () => path.resolve((process.env.HT_KTL || '').trim() || KTL_DEFAULT);
/** HT_REQUIRE_KTL=1인가. */
export const requireKtl = () => (process.env.HT_REQUIRE_KTL || '').trim() === '1';
/** list.json의 입력 경로 하나를 푼다 — 옛 KTL 자리는 HT_KTL로, 상대 경로는 dir에서. */
export const listFile = (dir, file) => (file === KTL_DEFAULT ? ktlFile() : path.isAbsolute(file) ? file : path.resolve(dir, file));
/** 그 파일이 KTL(지금 자리)인가. */
export const isKtl = file => path.resolve(file) === ktlFile();
/** 선택 자료의 파일이 없을 때 알릴 글 — KTL이 빠졌고 HT_REQUIRE_KTL=1이면 실패로 다루라는 표시(fail)를 함께 돌려준다. */
export function missingNote(name, missing) {
  const fail = requireKtl() && missing.some(isKtl);
  return { fail, text: `${fail ? '실패' : '건너뜀'} ${name} — 선택 자료의 파일이 없습니다: ${missing.join(' · ')}${fail ? ' (HT_REQUIRE_KTL=1 — KTL 자리는 HT_KTL)' : ''}` };
}
