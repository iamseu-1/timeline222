// 검사 · 정답지 도구가 공용 달력 표(prototype/results/calendar-cache.json)를 덮어쓰지 않게 하는 사본(판정 R64 넘김 · 과제 testinfra — build-check.mjs와 같은 길).
// 내보내기 calendar 모듈(export/calendar.mjs `cachedTables`)은 표 파일이 자료의 해 범위를 덮지 못하거나 ICU 판이 다르면 넓혀 다시 뜬다 —
// 그 파일이 공용 표면 검사가 공용 표를 소리 없이 넓히거나 다른 ICU로 갈아 쓴다(공용 표는 build-check가 Rust 길에 주는 `--calendar` 기본값이기도 하다).
// 그래서 도구 머리에서 `useCalendarCopy('<도구 이름>')`을 부르면:
//   · 환경 변수 HT_CALENDAR_CACHE가 이미 있으면(부른 쪽이 정함 — build-check 등) 그대로 둔다.
//   · 없으면 제 TMP에 임시 폴더를 만들어 공용 표를 복사하고(없으면 빈 자리 — 처음 쓸 때 거기에 뜬다) HT_CALENDAR_CACHE를 그 사본으로 정한다.
//     이 프로세스의 calendar 모듈과, 이 프로세스가 띄우는 자식(Node 배치 · one.mjs · export-layout.mjs · add-dlc.mjs …)이 모두 그 사본을 쓴다.
//   · 프로세스가 끝나면(실패해도) 임시 폴더를 지운다. 공용 표는 읽기만 한다.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const prototype = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
/** 공용 달력 표의 자리(export/calendar.mjs의 기본 경로와 같다). */
export const sharedCalendar = path.join(prototype, 'results', 'calendar-cache.json');

/** 사본을 정한다(위 머리말). 돌려주는 값: 이 프로세스가 쓰는 표 파일의 자리(HT_CALENDAR_CACHE=off면 'off'). */
export function useCalendarCopy(tag) {
  const given = (process.env.HT_CALENDAR_CACHE || '').trim();
  if (given) return given;
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), `${tag}-cal-`));
  const file = path.join(dir, 'calendar-cache.json');
  if (fs.existsSync(sharedCalendar)) fs.copyFileSync(sharedCalendar, file);
  process.env.HT_CALENDAR_CACHE = file;
  process.on('exit', () => { try { fs.rmSync(dir, { recursive: true, force: true }); } catch { /* 이미 없음 */ } });
  return file;
}
