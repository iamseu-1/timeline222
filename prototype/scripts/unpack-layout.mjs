// 아카이브 배치 파일(.htlayout — 메이커의 '아카이브용으로 내보내기'가 만든 팩 파일 종류 3)을 풀어 가져오기 JSON 3판으로 쓴다.
// 나오는 JSON은 노드 도구(export-layout.mjs)가 쓰는 파일과 같은 글(본문 그대로 + 줄바꿈 하나)이라, 엔진 도구가 바로 읽는다:
//   archive-tool import-layout <기본팩.htpack> <풀어 낸.json> <새 저장소.db> [<얹는 DLC.htpack> …]
// 머리 · 지문 · 압축 검사는 웹과 같은 js/packfile.js(parseLayout)가 한다 — DLC(.htpack 종류 1 · 2)를 주면 거절한다.
// 사용: node prototype/scripts/unpack-layout.mjs <파일.htlayout> [<내보낼 .json>]   (내보낼 곳을 비우면 같은 자리에 같은 이름의 .json)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

/** .htlayout 바이트 → { layout, text } (text = 노드 도구의 JSON과 같은 글, 끝 줄바꿈 없음) */
export async function unpackLayout(bytes) {
  if (!globalThis.HT || !globalThis.HT.packFile) {
    globalThis.window = globalThis;
    await import(pathToFileURL(path.join(root, 'js', 'packfile.js')).href);
  }
  return globalThis.HT.packFile.parseLayout(new Uint8Array(bytes));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [src, dst] = process.argv.slice(2);
  if (!src) {
    console.error('쓰는 법: node prototype/scripts/unpack-layout.mjs <파일.htlayout> [<내보낼 .json>]');
    process.exit(2);
  }
  if (!/\.htlayout$/i.test(src)) {
    console.error(`아카이브 배치 파일(.htlayout)이 아닙니다: ${src}`);
    process.exit(1);
  }
  try {
    const { layout, text } = await unpackLayout(fs.readFileSync(src));
    const out = path.resolve(dst || src.replace(/\.htlayout$/i, '.json'));
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, text + '\n');
    console.log(JSON.stringify({
      파일: out, 이름: layout.name, 팩: layout.packs.map(p => p.id), 트랙: layout.tracks.length,
      줄: layout.tracks.reduce((a, t) => a + t.rows.length, 0), 띠: layout.periods.length, 사건: layout.events.length,
    }, null, 1));
  } catch (e) {
    console.error(`풀지 못했습니다: ${(e && e.message) || e}`);
    process.exit(1);
  }
}
