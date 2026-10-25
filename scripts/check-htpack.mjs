// 전용 팩의 실제 바이트 검사. 개발 전체 검사에서도 호출합니다.
import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {dirname, join} from 'node:path';
import {createHash} from 'node:crypto';
import {deflateSync} from 'node:zlib';

const root=join(dirname(fileURLToPath(import.meta.url)),'..');
export async function checkHTPack() {
  globalThis.window=globalThis;
  await import('../js/packfile.js');
  const PF=HT.packFile;
  assert.equal(PF.VERSION,2);
  let rejectedCount=0;
  const rejected=async (run, label) => {
    rejectedCount++;
    await assert.rejects(run, e=>e.packError===true && /[가-힣]/.test(e.message), label);
  };
  let samples=0;
  for(const file of readdirSync(join(root,'samples')).filter(f=>f.endsWith('.json'))) {
    const raw=JSON.parse(readFileSync(join(root,'samples',file),'utf8'));
    const bytes=await PF.build(raw);
    assert.equal(Buffer.from(bytes.subarray(0,8)).toString(),'HTPACK\r\n');
    assert.deepEqual((await PF.read(new File([bytes],file.replace(/\.json$/,'.htpack')))).raw,raw);
    samples++;
  }
  let builtin=0;
  for(const p of HT.getBuiltinPacks?.() || []) {
    const value=HT.packToJSON(HT.normalizePack(p).pack);
    assert.deepEqual((await PF.parse(await PF.build(value))).raw,value);
    builtin++;
  }
  const raw={format:'history-timeline-dlc',id:'pack-check',name:'바람 들녘',version:'1.0.0',documents:{a:'한글 문서\n별책\t줄'.repeat(200)},cover:'data:image/png;base64,AA==',periods:[{id:'p',name:'푸른 나라',start:1,end:20}]};
  const bytes=await PF.build(raw);
  assert.deepEqual((await PF.parse(bytes)).raw,raw);
  assert.deepEqual((await PF.read(new File([bytes],'한글.HTPACK'))).raw,raw);
  await rejected(()=>PF.read(new File([JSON.stringify(raw)],'옛자료.json')),'JSON 열기 금지');
  await rejected(()=>PF.read(new File([JSON.stringify(raw)],'이름만.htpack')),'확장자만 바꾼 JSON 금지');
  await rejected(()=>PF.read(new File([bytes],'이름만.json')),'전용 팩도 .json으로 열지 않음');
  await rejected(()=>PF.read(new File([readFileSync(join(root,'scripts/fixtures/windows-zip.htpack'))],'옛압축.htpack')),'이전 ZIP 금지');
  await rejected(()=>PF.read({name:'크다.htpack',size:PF.LIMITS.file+1,arrayBuffer(){throw Error('크기 검사 전에 읽음');}}),'읽기 전 파일 한도');
  await rejected(()=>PF.parse(new Uint8Array(PF.LIMITS.file+1)),'바이트 입력 크기 한도');
  for(const n of [0,4,8,30,51,bytes.length-1]) await rejected(()=>PF.parse(bytes.subarray(0,n)),`잘린 파일 ${n}`);
  await rejected(()=>PF.parse(Buffer.concat([bytes,Buffer.from([0])])),'뒤에 붙은 바이트');
  for(const i of [0,8,9,10,11,12,20,51,52,bytes.length-1]) {
    const bad=bytes.slice();bad[i]^=0x7f;
    await rejected(()=>PF.parse(bad),`머리·검사값·본문 변조 ${i}`);
  }
  // 제품 저장기와 독립된 노드 압축기로 잘못된 팩을 조립해, 지문 이후의 검사를 통과하지 못하는지도 봅니다.
  function make(body,{kind=1,size=body.length,version=2}={}) {
    const head=Buffer.alloc(52),packed=deflateSync(body);
    head.write('HTPACK\r\n');head[8]=version;head[9]=kind;head[10]=1;
    head.writeUInt32LE(size,12);head.writeUInt32LE(packed.length,16);
    createHash('sha256').update(head.subarray(0,20)).update(packed).digest().copy(head,20);
    return Buffer.concat([head,packed]);
  }
  const plain=Buffer.from(JSON.stringify(raw));
  assert.deepEqual((await PF.parse(make(plain))).raw,raw,'다른 압축 구현과 호환');
  await rejected(()=>PF.parse(make(plain,{size:1})),'선언한 크기보다 크게 풀리는 본문');
  await rejected(()=>PF.parse(make(plain,{size:plain.length+1})),'선언한 크기보다 작게 풀리는 본문');
  await rejected(()=>PF.parse(make(plain,{size:PF.LIMITS.total+1})),'풀린 크기 한도');
  await rejected(()=>PF.parse(make(plain,{kind:2})),'머리와 본문의 종류 불일치');
  await rejected(()=>PF.parse(make(Buffer.from('{고장'))),'깨진 본문');
  await rejected(()=>PF.parse(make(Buffer.from([0xff,0xfe,0xff]))),'잘못된 글자 바이트');
  await rejected(()=>PF.parse(make(Buffer.from('[]'))),'목록이 팩으로 들어옴');
  await rejected(()=>PF.build({format:'다른 형식'}),'다른 문서 형식');
  // 종류 3 '아카이브 배치'(.htlayout — 옛 메이커가 내보내던 파일 · DLC-형식.md '팩 파일'): 같은 포장, DLC 받기는 거절하고 배치 읽기는 DLC를 거절
  const layout={name:'바람 들녘',packs:[{id:'pack-check',name:'바람 들녘'}],categories:[],tracks:[{key:'t',name:'바람',rows:[{height:30}]}],epochs:[],axis:[],periods:[],cells:[],events:[],items:[],entities:[]};
  const lb=await PF.buildLayout(layout);
  assert.equal(lb[9],3,'종류 바이트 3');
  const opened=await PF.parseLayout(lb);
  assert.deepEqual(opened.layout,layout);
  assert.equal(opened.text,JSON.stringify(layout),'풀린 본문이 JSON 글 그대로');
  assert.deepEqual((await PF.parseLayout(make(Buffer.from(JSON.stringify(layout)),{kind:3}))).layout,layout,'다른 압축 구현의 배치와 호환');
  await rejected(()=>PF.parse(lb),'DLC 받기는 아카이브 배치를 거절');
  await rejected(()=>PF.read(new File([lb],'배치.htpack')),'확장자만 바꾼 아카이브 배치 거절');
  await rejected(()=>PF.parseLayout(bytes),'배치 읽기는 DLC를 거절');
  await rejected(()=>PF.parseLayout(make(plain,{kind:3})),'종류 3 머리에 DLC 본문');
  await rejected(()=>PF.buildLayout(raw),'DLC를 배치로 담지 않음');
  for(const i of [9,20,52,lb.length-1]) {
    const bad=lb.slice();bad[i]^=0x7f;
    await rejected(()=>PF.parseLayout(bad),`배치 머리·검사값·본문 변조 ${i}`);
  }
  const backup={format:'history-timeline-backup',savedAt:'2026-09-20',installed:[raw],packState:{'pack-check':{enabled:false}}};
  assert.deepEqual((await PF.read(new File([await PF.build(backup)],'백업.htpack'))).raw,backup);
  for(const file of ['manifest.webmanifest','maker.webmanifest']) {
    const manifest=JSON.parse(readFileSync(join(root,file),'utf8'));
    assert.deepEqual(manifest.file_handlers.flatMap(h=>Object.values(h.accept).flat()),['.htpack']);
  }
  assert.equal(PF.writeZip,undefined,'제품에 옛 ZIP 편집기를 노출하지 않음');
  return {기본팩왕복:builtin,견본왕복:samples,거절검사:rejectedCount,백업왕복:true,배치왕복:true,파일연결:'두 화면 .htpack 전용'};
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  console.log(await checkHTPack());
}
