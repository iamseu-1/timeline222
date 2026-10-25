//! 화면과 독립된 읽기 전용 자료 처리부. 날짜는 부호 있는 정수 분, 범위 끝도 포함한다.
use rusqlite::{params, Connection, OpenFlags};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{ffi::{CStr, CString, c_char}, fs, io::Read, path::{Path, PathBuf}, sync::{Mutex, OnceLock}, time::Instant};

pub mod bandref;
pub mod builder;
pub mod canon;
pub mod filter;
pub mod generate;
#[cfg(windows)] pub mod glyph;
pub mod lay;
mod layout;
pub mod legacy;
pub mod levels;
pub mod names;
pub mod packs;
pub mod patch;
pub mod query;
pub mod rowmap;
pub mod schema;
pub mod span;
pub mod tile;
pub mod variant;
pub mod verify;
pub mod write;

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;
pub const DAY: i64 = 1440;
pub const MAX_SHAPES: i64 = 1800;

pub fn grams(text: &str) -> Vec<String> {
    let chars: Vec<char> = text.to_lowercase().chars().collect();
    let mut words = std::collections::BTreeSet::new();
    for c in chars.iter().filter(|c| !c.is_whitespace()) { words.insert(format!("u{:x}", *c as u32)); }
    for w in chars.windows(2).filter(|w| !w[0].is_whitespace() && !w[1].is_whitespace()) {
        words.insert(format!("b{:x}x{:x}", w[0] as u32, w[1] as u32));
    }
    words.into_iter().collect()
}

/// base64(표준 글자표 · 끝의 '=' 채움)을 바이트로 — 문서 그림의 가져오기(`blobs[].data`)가 쓴다. 틀린 글자가 있으면 None.
/// 새 크레이트를 들이지 않으려고 여기 둔다(가져오기 한 번에 그림 몇 장 — 빠르기는 문제 되지 않음).
pub fn base64_decode(text: &str) -> Option<Vec<u8>> {
    let body = text.trim_end_matches('=').as_bytes();
    let mut out = Vec::with_capacity(body.len() * 3 / 4 + 3);
    let (mut acc, mut bits) = (0u32, 0u32);
    for &c in body {
        let v = match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => return None,
        } as u32;
        acc = (acc << 6) | v;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
            acc &= (1 << bits) - 1;
        }
    }
    if text.len() - body.len() > 2 || bits >= 6 {
        return None;
    }
    Some(out)
}
/// 바이트를 base64(표준 글자표 · '=' 채움)로 — `{"op":"blob"}`의 답.
pub fn base64_encode(bytes: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let n = (chunk[0] as u32) << 16 | (*chunk.get(1).unwrap_or(&0) as u32) << 8 | *chunk.get(2).unwrap_or(&0) as u32;
        for i in 0..4 {
            out.push(if i <= chunk.len() { T[(n >> (18 - 6 * i) & 63) as usize] as char } else { '=' });
        }
    }
    out
}

pub struct Store {
    pub db: Connection,
    root: PathBuf,
    /// 연 저장소 파일의 경로 — 쓰기 연결을 같은 파일에 따로 열려고(`with_store_write`) 둔다.
    path: PathBuf,
    /// `items.ref_kind`(0 없음 · 1 띠 · 2 사건)가 있는 저장소인가 — 거르개가 쓴다.
    /// 스키마 3을 넓히기 전에 만든 저장소에는 없어서, 그때는 '가리키는 것이 띠인지 사건인지 모름'으로 다룬다.
    pub item_ref_kind: bool,
    /// `names.cell_ref`(칸의 글자 참조)가 있는 저장소인가.
    pub names_cell_ref: bool,
    /// 변형(계약 3-2절)의 표와 열이 있는 저장소인가 — 없으면 `variants`를 받는 요청을 거절한다.
    pub has_variants: bool,
    /// 단계별 요약에 분류별 수(`summaries.cats`)가 있는 저장소인가 — 없으면 성긴 단계의 알약에 분류 비율을 싣지 않는다.
    pub summary_cats: bool,
    /// 관점의 이름 표(`lens_names`)가 있는 저장소인가 — 없으면 `lens_names`가 그때그때 항목 기록을 훑는다(답은 같다).
    pub has_lens_names: bool,
    /// 그림 바이트 표(`blobs` — 문서 그림)가 있는 저장소인가 — 없는 옛 저장소에서는 그림이 '없음'이다.
    pub has_blobs: bool,
    /// 트랙의 문화권 열(`tracks.sphere` — 리메이크 조각 ②)이 있는 저장소인가 — 없는 옛 저장소는 layout 답에 빈 글자를 싣는다.
    pub track_sphere: bool,
    /// 사건의 트랙 안 차례 열(`events.ord` — 계획 P4 판정 R23)이 있는 저장소인가 — 타일 대표의 동률을 (트랙 차례, 이것)으로 깬다. 없는 옛 저장소는 번호로 깬다.
    pub event_ord: bool,
    /// 요약의 대표마다 트랙 안 차례(`summaries.ords` — 판정 R24)가 있는 저장소인가 — 없으면 요약끼리 합칠 때 동률을 번호로 깬다.
    pub summary_ords: bool,
    /// 띠의 형식 4 뜻 열(`periods.form` — 스키마 4 · 계약 1-1)이 있는 저장소인가 — 없는 옛 저장소(판 '3' · '3.1')는 띠마다 0(모름)으로 답한다
    /// (타일 띠 구역의 열 10 · `same_year`의 띠).
    pub period_form: bool,
    /// 문화권 단위 줄 표(`sphere_lines` — 스키마 4 · 계약 1-1)가 있는 저장소인가 — 없는 옛 저장소는 layout 답의 `sphereLines`가 빈 목록이다.
    pub has_sphere_lines: bool,
    /// 줄의 열쇠(`rows.id`)와 자리(밖으로 보이는 전체 줄 번호)를 잇는 표 — 열 때 한 번 읽는다(계획 P4 과제 1a).
    /// 새로 지은 저장소는 열쇠 = 자리(`is_identity`)다. 조회 · 타일이 경계에서 이 표로 바꾼다.
    pub rows: rowmap::RowMap,
}
impl Store {
    /// 저장소를 읽기 전용으로 연다. 제자리 쓰기(`with_store_write`) 도중 프로세스가 죽어 일지(`<파일>-journal`)가 남았으면
    /// 읽기 전용 연결은 그것을 되돌리지 못해 읽을 때 `SQLITE_READONLY_ROLLBACK`(776)로 실패한다 — 그때는 쓰기 연결로 한 번 열어
    /// 되돌림을 일으키고 닫은 뒤 다시 연다(한 번만 · 그래도 실패면 처음 오류를 돌려준다). 열리지 않는 저장소가 남지 않게 하려는 길이다.
    pub fn open(path: &Path) -> Result<Self> {
        match Self::open_read_only(path) {
            Err(first) if first.downcast_ref::<rusqlite::Error>().is_some_and(|e|matches!(e,rusqlite::Error::SqliteFailure(f,_) if f.code==rusqlite::ErrorCode::ReadOnly)) => {
                match Self::recover_journal(path).and_then(|()|Self::open_read_only(path)) {Ok(store)=>Ok(store),Err(_)=>Err(first)}
            }
            other=>other,
        }
    }
    /// 쓰기 연결로 열어 첫 읽기에서 남은 일지를 되돌리게 한다(SQLite는 hot journal을 읽기 시작할 때 되돌린다).
    pub(crate) fn recover_journal(path: &Path) -> Result<()> {
        let db=Connection::open_with_flags(path,OpenFlags::SQLITE_OPEN_READ_WRITE|OpenFlags::SQLITE_OPEN_NO_MUTEX)?;
        db.execute_batch("PRAGMA busy_timeout=5000;")?;
        db.query_row("SELECT count(*) FROM sqlite_master",[],|r|r.get::<_,i64>(0))?;
        Ok(())
    }
    fn open_read_only(path: &Path) -> Result<Self> {
        let db=Connection::open_with_flags(path,OpenFlags::SQLITE_OPEN_READ_ONLY|OpenFlags::SQLITE_OPEN_NO_MUTEX)?;
        // 쓰는 연결(`apply`의 BEGIN IMMEDIATE)이 COMMIT하는 짧은 순간에 읽기가 부딪쳐도 곧바로 실패하지 않고 5초까지 기다린다.
        db.execute_batch("PRAGMA query_only=ON; PRAGMA cache_size=-16384; PRAGMA mmap_size=0; PRAGMA busy_timeout=5000;")?;
        Self::on(db,path)
    }
    /// 쓰기 거래 안에서 **그 거래의 연결 그대로** 읽는 `Store`를 `f`에 빌려준다(계획 P4 과제 5d — `patch::apply`의 "verify"가 COMMIT 전에
    /// 고쳐 쓴 것을 표본 타일로 견준다). 거래가 쓴 것(COMMIT 전)이 보이고, 열 · 표 가림과 `RowMap`은 지금 거래 안의 모양으로 다시 읽는다.
    /// 연결은 빌릴 뿐 닫지 않고 PRAGMA도 바꾸지 않는다 — `Store`는 `f`가 끝나면 놓인다(밖으로 내보낼 수 없다). 크레이트 밖에는 열지 않는다(과제 7a 얹힌 몫 8).
    pub(crate) fn within<T>(db:&Connection,f:impl FnOnce(&Store)->Result<T>)->Result<T> {
        // SAFETY: `from_handle`의 연결은 핸들을 닫지 않는다(소유하지 않음). 빌린 `Store`는 이 함수 안에서만 살아 `db`(빌린 핸들의 주인)보다
        // 먼저 떨어지고, 같은 스레드에서만 쓴다 — 그동안 `db`로 다른 일을 하지 않는다(`f`는 `Store`만 받는다).
        // 또 rusqlite의 `hooks` · `preupdate_hook` 기능이 **꺼져 있어야** 한다(Cargo.toml — 지금은 `bundled`만): 켜지면 빌린 연결이 떨어질 때
        // `remove_hooks`가 같은 핸들에 걸린 바깥 연결(`db`)의 훅까지 지운다. 그 기능을 켜려면 이 길을 먼저 바꾼다.
        let borrowed=unsafe {Connection::from_handle(db.handle())}?;
        let path=PathBuf::from(db.path().ok_or("쓰기 연결의 파일 경로를 모릅니다")?);
        let store=Self::on(borrowed,&path)?;
        f(&store)
    }
    /// 열린 연결로 `Store`를 꾸린다 — 판 확인 · 열 · 표 가림 · `RowMap`.
    fn on(db:Connection,path:&Path) -> Result<Self> {
        let version: String=db.query_row("SELECT value FROM meta WHERE key='schema'",[],|r|r.get(0))?;
        // 여는 판은 `schema::OPENS`뿐 — '4' = 스키마 4(리메이크 3단계 · 계약 1-1) · '3' = 옛 저장소(새 열 · 표가 없을 뿐이라 아래 가림으로 빈 값을 답한다),
        // 소수점 판('3.1' · '4.1') = 줄 열쇠와 자리가 갈린 저장소(트랙을 고쳐 쓴 것 — 계획 P4). 스키마 4 전의 엔진은 '3' · '3.1'만 받아 '4'를 거절한다.
        if !schema::OPENS.contains(&version.as_str()) { return Err("이 저장소는 옛 시제품 형식입니다. 3단계 도구로 다시 만들어야 합니다".into()); }
        let has=|table:&str,column:&str|->bool{
            db.prepare(&format!("SELECT 1 FROM pragma_table_info('{table}') WHERE name='{column}'")).and_then(|mut s|s.exists([])).unwrap_or(false)
        };
        let (item_ref_kind,names_cell_ref)=(has("items","ref_kind"),has("names","cell_ref"));
        let has_variants=has("rows","variant") && has("items","variant")
            && db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='variant_rows'").and_then(|mut s|s.exists([])).unwrap_or(false);
        let summary_cats=has("summaries","cats");
        let has_lens_names=db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='lens_names'").and_then(|mut s|s.exists([])).unwrap_or(false);
        let has_blobs=db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='blobs'").and_then(|mut s|s.exists([])).unwrap_or(false);
        let track_sphere=has("tracks","sphere");
        let (event_ord,summary_ords)=(has("events","ord"),has("summaries","ords"));
        // 스키마 4(계약 1-1)의 열 · 표 — 옛 저장소('3' · '3.1')에는 없어 빈 값(0 · 빈 목록)으로 답한다.
        let period_form=has("periods","form");
        let has_sphere_lines=db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='sphere_lines'").and_then(|mut s|s.exists([])).unwrap_or(false);
        let rows=rowmap::RowMap::load(&db)?;
        Ok(Self{db,root:path.parent().ok_or("자료 폴더 없음")?.to_path_buf(),path:path.to_path_buf(),item_ref_kind,names_cell_ref,has_variants,summary_cats,has_lens_names,has_blobs,track_sphere,event_ord,summary_ords,period_form,has_sphere_lines,rows})
    }
    /// 연 저장소 파일의 경로.
    pub fn path(&self) -> &Path { &self.path }
    pub fn info(&self) -> Result<Value> {
        let mut meta=serde_json::Map::new();
        for row in self.db.prepare("SELECT key,value FROM meta")?.query_map([],|r|Ok((r.get::<_,String>(0)?,r.get::<_,String>(1)?)))? {
            let (k,v)=row?;meta.insert(k,Value::String(v));
        }
        // `cell_lod`는 이 판이 칸을 실을 때 쓴 시험용 손잡이의 나눗수다(계약 5-3절 · 기본 8).
        // 8이 아니면 타일이 예전과 다른 바이트이므로, 재거나 그림을 뜬 결과에 이 값을 함께 적어야 섞이지 않는다.
        Ok(json!({"meta":meta,"cache_mib":16,"max_shapes":MAX_SHAPES,"sqlite":rusqlite::version(),"cell_lod":levels::cell_lod_divisor(),
            "originals":self.db.query_row("SELECT count(*) FROM files",[],|r|r.get::<_,i64>(0))?}))
    }
    /// 사건 한 줄. `lane`은 저장소 안의 줄 **열쇠**다 — 밖으로 내기 전에 [`Store::outward_lanes`]로 자리로 바꾼다(계획 P4).
    pub(crate) fn event_row(r:&rusqlite::Row) -> rusqlite::Result<Value> {
        Ok(json!({"id":r.get::<_,i64>(0)?,"lane":r.get::<_,i64>(1)?,"start":r.get::<_,Option<i64>>(2)?,"end":r.get::<_,Option<i64>>(3)?,"title":r.get::<_,String>(4)?,"body":r.get::<_,String>(5)?,"source":r.get::<_,Option<i64>>(6)?,"lo":r.get::<_,Option<i64>>(7)?,"hi":r.get::<_,Option<i64>>(8)?,"importance":r.get::<_,i64>(9)?,"pack":r.get::<_,i64>(10)?}))
    }
    /// 사건 줄들(`event_row`)의 `lane`(열쇠)을 자리로. 열쇠 = 자리면 아무것도 하지 않는다.
    pub(crate) fn outward_lanes(&self,rows:&mut [Value]) {
        if self.rows.is_identity() {return;}
        for row in rows.iter_mut() {self.rows.outward(row,&["lane"]);}
    }
    /// 옛 줄 범위 조회: 자리 `lane ~ lane+lanes−1`에 놓인 사건(번호 차례 · `after` 다음부터 `limit`개).
    /// 줄은 자리로 받고 자리로 낸다 — 자리 범위를 열쇠 범위들(트랙마다 하나)로 나눠 범위마다 같은 SQL을 돌리고,
    /// 모은 줄을 원래 차례(번호)로 다시 늘어놓아 자른다(계획 P4). 열쇠 = 자리면 범위 하나 — 예전과 같은 물음 · 같은 답이다.
    pub fn range(&self,lo:i64,hi:i64,lane:i64,lanes:i64,after:i64,limit:i64) -> Result<Vec<Value>> {
        if hi<lo || lanes<1 || lanes>32 { return Err("조회 범위 오류".into()); }
        let limit=limit.clamp(1,MAX_SHAPES+1);
        let mut stmt=self.db.prepare_cached("SELECT e.id,e.lane,e.start,e.end,e.title,e.body,e.source,e.lo,e.hi,e.importance,e.pack FROM bounds b JOIN events e ON e.id=b.id WHERE b.lo_day<=?2 AND b.hi_day>=?1 AND b.lane_min<=?4 AND b.lane_max>=?3 AND e.lo<=?6 AND e.hi>=?5 AND e.id>?7 ORDER BY e.id LIMIT ?8")?;
        let ranges=self.rows.ranges_for(lane,lane+lanes-1);
        let mut rows=Vec::new();
        for (k0,k1) in &ranges {
            rows.extend(stmt.query_map(params![lo.div_euclid(DAY),hi.div_euclid(DAY),k0,k1,lo,hi,after,limit],Self::event_row)?.collect::<std::result::Result<Vec<_>,_>>()?);
        }
        if ranges.len()>1 {
            // 범위마다 앞에서 limit개씩 받았다 — 합쳐 번호 차례로 늘어놓고 다시 자른다(사건은 한 줄이라 범위 사이에 겹치지 않는다).
            rows.sort_by_key(|r|r["id"].as_i64());
            rows.dedup_by_key(|r|r["id"].as_i64());
            rows.truncate(limit as usize);
        }
        self.outward_lanes(&mut rows);
        Ok(rows)
    }
    /// 2단계의 옛 모양 그대로인 검색(사건만) + 거르개.
    pub fn search_plain(&self,q:&Value)->Result<Value> {
        let keep=self.filter_of(q)?.map(|f|f.event_keep("e")).unwrap_or_default();
        self.search_of(q["text"].as_str().unwrap_or(""),q["after"].as_i64().unwrap_or(0),&keep)
    }
    pub fn search(&self,text:&str,after:i64)->Result<Value> { self.search_of(text,after,"") }
    fn search_of(&self,text:&str,after:i64,keep:&str)->Result<Value> {
        if text.chars().count()>64 {return Err("검색어는 64자까지 입력하세요".into());}
        let words: Vec<_>=text.split_whitespace().map(str::to_lowercase).collect();
        if words.is_empty() {return Ok(json!({"items":[],"has_more":false}));}
        let terms=grams(&words.join(" ")).join(" AND ");
        if terms.is_empty() {return Ok(json!({"items":[],"has_more":false}));}
        let conditions=(0..words.len()).map(|i| format!(" AND instr(lower(e.title||' '||e.body),?{})>0",i+3)).collect::<String>();
        let sql=format!("SELECT e.id,e.lane,e.start,e.end,e.title,e.body,e.source,e.lo,e.hi,e.importance,e.pack FROM search s JOIN events e ON e.id=s.rowid WHERE search MATCH ?1 AND s.rowid>?2{conditions}{keep} ORDER BY s.rowid LIMIT 51");
        let mut args:Vec<rusqlite::types::Value>=vec![terms.into(),after.into()];
        args.extend(words.into_iter().map(Into::into));
        let mut rows=self.db.prepare(&sql)?.query_map(rusqlite::params_from_iter(args),Self::event_row)?.collect::<std::result::Result<Vec<_>,_>>()?;
        let more=rows.len()>50;rows.truncate(50);
        self.outward_lanes(&mut rows);
        Ok(json!({"next":rows.last().and_then(|r|r["id"].as_i64()),"items":rows,"has_more":more}))
    }
    /// 그림 바이트 하나(문서 그림 — 열쇠 `img:<DLC id>/<그림 id>`) → (종류, 바이트). 없거나 표가 없는 옛 저장소면 None.
    pub fn blob(&self,key:&str)->Result<Option<(String,Vec<u8>)>> {
        if !self.has_blobs {return Ok(None);}
        let mut stmt=self.db.prepare_cached("SELECT mime,bytes FROM blobs WHERE key=?1")?;
        let mut rows=stmt.query([key])?;
        Ok(match rows.next()? {Some(r)=>Some((r.get(0)?,r.get(1)?)),None=>None})
    }
    pub fn source(&self,id:i64)->Result<Value> {
        let (title,body):(String,String)=self.db.query_row("SELECT title,body FROM sources WHERE id=?1",[id],|r|Ok((r.get(0)?,r.get(1)?)))?;
        let mut files=Vec::new();
        for row in self.db.prepare("SELECT kind,path,sha256,bytes FROM files WHERE source=?1 ORDER BY id")?.query_map([id],|r|Ok((r.get::<_,String>(0)?,r.get::<_,String>(1)?,r.get::<_,String>(2)?,r.get::<_,i64>(3)?)))? {
            let (kind,path,sha,bytes)=row?;
            let base=self.root.canonicalize()?;let full=self.root.join(&path).canonicalize()?;
            if !full.starts_with(&base) || !full.is_file() {return Err("원문 경로 오류".into());}
            if fs::metadata(&full)?.len()!=bytes as u64 {return Err("원문 크기 불일치".into());}
            files.push(json!({"kind":kind,"path":full.to_string_lossy(),"sha256":sha,"bytes":bytes}));
        }
        Ok(json!({"id":id,"title":title,"body":body,"files":files}))
    }
    pub fn verify_files(&self)->Result<Value> {
        let mut count=0;let mut bytes=0;
        for row in self.db.prepare("SELECT path,sha256,bytes FROM files")?.query_map([],|r|Ok((r.get::<_,String>(0)?,r.get::<_,String>(1)?,r.get::<_,u64>(2)?)))? {
            let (name,expected,size)=row?;let base=self.root.canonicalize()?;let path=self.root.join(name).canonicalize()?;
            if !path.starts_with(base) {return Err("원문 경로 이탈".into());}
            let mut file=fs::File::open(path)?;let mut hash=Sha256::new();let mut buf=[0u8;65536];let mut actual=0;
            loop {let n=file.read(&mut buf)?;if n==0 {break;} hash.update(&buf[..n]);actual+=n as u64;}
            if format!("{:x}",hash.finalize())!=expected || actual!=size {return Err("원문 지문 불일치".into());}
            count+=1;bytes+=actual;
        }
        Ok(json!({"files":count,"bytes":bytes,"verified":true}))
    }
    pub fn call(&self,q:&Value)->Result<Value> {
        // 화면(Dart)은 분 · 번호를 소수 꼴(`-615360960.0`)로도 보낸다 — 물음의 수는 모두 정수로 읽는다(소수부는 반올림).
        // 정수만 받던 때에는 그런 물음이 "정수 입력 누락"으로 거절되고 부품이 그 실패를 조용히 삼켜, 칸 상세의
        // '이 시기의 사건' · 같은 시기 타국 · 같은 해 보기가 실제 앱에서만 비었다(검사는 정수로만 물었다).
        let whole=whole_numbers(q);let q=&whole;
        match q["op"].as_str().unwrap_or("") {
            "info"=>self.info(),"layout"=>self.layout(),
            // 원어 병기 · 글꼴(10건 3 · 9 — 갈래 D2 · names.rs): 이름 목록이 있는 자료집 · 글꼴 목록, 품은 원본에서 꺼낸 글꼴 파일.
            "names_info"=>self.names_info(),"font_data"=>self.font_data(q),
            // kinds를 주면 넓힌 검색(이름까지), 주지 않으면 2단계의 옛 모양(사건만) 그대로.
            "search"=>if q["kinds"].is_null() {self.search_plain(q)} else {self.search_wide(q)},
            "list"=>self.list_events(q),
            "source"=>self.source(num(q,"id")?),"verify"=>self.verify_files(),
            "rows_near"=>self.rows_near_call(q),
            "row_labels"=>{let rows=q["rows"].as_array().ok_or("줄 목록 누락")?.iter().filter_map(Value::as_i64).collect::<Vec<_>>();let f=self.filter_of(q)?;let v=self.variants_of(q)?;self.row_labels(&rows,f.as_ref(),v.as_ref())},
            "entity"=>self.entity(q["uid"].as_str().ok_or("항목 이름 누락")?),
            "entities"=>self.entities_many(q),"doc_list"=>self.doc_list(q),"uid_of"=>self.uid_of(q),"id_of"=>self.id_of(q),"ids_of"=>self.ids_of(q),
            "search_year"=>self.search_year(q),"events_in"=>self.events_in(q),"same_year"=>self.same_year(q),"echo"=>self.echo(q),
            "table"=>self.table(q),"table_csv"=>self.table_csv(q),"legend_kinds"=>self.legend_kinds(q),"cells_of"=>self.cells_of(q),
            "scopes"=>self.scopes(q),"ganji_years"=>self.ganji_years(q),"lens_names"=>self.lens_names(q),
            // 보관함(빼되 원본을 남긴 DLC — P4 과제 9 `remove_pack`의 delete:false).
            "kept_packs"=>packs::kept_packs(&self.db),
            // 문서 그림 하나를 base64로 — 바이트 그대로 받는 길은 `archive_blob`(JSON에 MB를 싣지 않음). 없으면 오류 글.
            "blob"=>{let key=q["key"].as_str().ok_or("그림 열쇠 누락")?;match self.blob(key)? {
                Some((mime,bytes))=>Ok(json!({"key":key,"mime":mime,"bytes":bytes.len(),"data":base64_encode(&bytes)})),
                None=>Err(format!("그림이 저장소에 없습니다: {key}").into())}},
            "event"=>{let mut row=[self.db.query_row("SELECT id,lane,start,end,title,body,source,lo,hi,importance,pack FROM events WHERE id=?1",[num(q,"id")?],Self::event_row)?];
                self.outward_lanes(&mut row);let [row]=row;Ok(row)},
            _=>Err("알 수 없는 조회 명령".into())
        }
    }
}
/// 물음 안의 소수 꼴 수를 정수로(재귀). 유한하지 않은 수는 그대로 둔다(읽는 쪽이 까닭을 적어 거절한다).
pub fn whole_numbers(v:&Value)->Value {
    match v {
        Value::Number(n) if n.as_i64().is_none() && n.as_u64().is_none() => match n.as_f64() {
            Some(f) if f.is_finite() && f.abs() < 9.0e18 => Value::from(f.round() as i64),
            _ => v.clone(),
        },
        Value::Array(list) => Value::Array(list.iter().map(whole_numbers).collect()),
        Value::Object(map) => Value::Object(map.iter().map(|(k,x)|(k.clone(),whole_numbers(x))).collect()),
        _ => v.clone(),
    }
}
fn num(q:&Value,key:&str)->Result<i64> {q[key].as_i64().ok_or_else(||format!("정수 입력 누락: {key}").into())}
static STORE:OnceLock<Mutex<Option<Store>>>=OnceLock::new();
/// 열린 저장소의 잠금 — 앞선 요청이 패닉으로 잠금을 오염시켰어도 되살려 쓴다(쓰기 길과 같게 · 고침 2회차 M-3). 읽는 쪽 패닉은 저장소를 바꾸지 않으므로
/// 안의 `Store`는 그대로 쓸 수 있다(쓰는 쪽은 COMMIT 뒤 다시 열어 바꿔 놓는다 — `with_store_write`).
fn store_lock()->std::sync::MutexGuard<'static,Option<Store>> {
    let slot=STORE.get_or_init(||Mutex::new(None));
    slot.lock().unwrap_or_else(|poisoned|{slot.clear_poison();poisoned.into_inner()})
}
/// 쓰기 요청의 선택 `path`(고침 2회차 M-4 · 계약 2-7 · 2-7-1): 주면 열린 저장소와 같은 파일이어야 한다 — 앱이 다른 저장소를 연 뒤 옛 요청이 닿아 엉뚱한 저장소를
/// 고쳐 쓰지 않게. 다르면 `code` path(쉬운 글 · 두 경로는 `detail`)로 거절하고 저장소는 그대로다. 여기서는 꼴만 보고, 견줌은 쓰기 차례(`WRITE`)를 잡은 뒤
/// 쓸 파일을 정한 그 자리에서 한다([`with_store_write_at`] — 고침 3회차: 견준 뒤 쓰기 전에 앞 쓰기가 저장소를 바꿔 놓는 틈을 없앰).
fn write_target(q:&Value)->Result<Option<String>> {
    match &q["path"] {
        Value::Null=>Ok(None),
        Value::String(s) if !s.is_empty()=>Ok(Some(s.clone())),
        _=>Err("path는 저장소 경로 글이어야 합니다".into()),
    }
}
fn check_write_path(want:&str,open:&Path)->Result<()> {
    if !same_file(Path::new(want),open) {
        return Err(Box::new(patch::Refusal{code:"path",message:"지금 열린 저장소가 이 요청의 저장소와 달라 쓰지 않았습니다(저장소는 그대로) — 다시 해 주세요".into(),
            detail:Some(format!("요청 {want} · 열린 저장소 {}",open.display()))}));
    }
    Ok(())
}
/// 두 경로가 같은 파일인가 — 둘 다 실제 자리(canonicalize)로 풀리면 그것으로, **한쪽이라도 못 풀면 둘 다 글자 꼴로**(`\\?\` 앞머리를 떼고 구분자를 `/`로 ·
/// Windows는 대소문자 무시) 견준다. 풀린 쪽과 못 푼 쪽을 견주면 같은 파일이어도 늘 달라 거절되기 때문이다(appfix 검토 덧붙임).
fn same_file(a:&Path,b:&Path)->bool {
    match (fs::canonicalize(a),fs::canonicalize(b)) {
        (Ok(x),Ok(y))=>x==y,
        _=>{
            let plain=|p:&Path|{
                let text=p.to_string_lossy();
                let text=text.strip_prefix(r"\\?\").unwrap_or(&text).replace('\\',"/");
                if cfg!(windows) {text.to_lowercase()} else {text}
            };
            plain(a)==plain(b)
        }
    }
}
#[no_mangle]
pub unsafe extern "C" fn archive_call(request:*const c_char)->*mut c_char {
    let start=Instant::now();
    let answer=std::panic::catch_unwind(||->Result<Value>{
        if request.is_null(){return Err("빈 요청".into());}
        let bytes=CStr::from_ptr(request).to_bytes();if bytes.len()>16384{return Err("요청 크기 초과".into());}
        let q:Value=serde_json::from_slice(bytes)?;
        if q["op"]=="last_error" {return Ok(json!({"error":LAST_ERROR.lock().map(|s|s.clone()).unwrap_or_default()}));}
        // ClearType 설정(설계 3-2) — 저장소 없이 답한다. Windows가 아니면 늘 꺼짐.
        if q["op"]=="cleartype" {
            #[cfg(windows)] { return Ok(glyph::info()); }
            #[cfg(not(windows))] { return Ok(json!({"on":false,"bgr":false})); }
        }
        // 넣고 빼기(계약 2-7 · 계획 P4 과제 7a) — `STORE` 잠금 **앞에서** 가른다: `with_store_write`가 그 잠금을 스스로 잠깐씩 쥐므로
        // 잠금을 쥔 채 부르면 같은 스레드에서 교착한다(얹힌 몫 2). 요청은 경로만 실어 16KB 한도면 넉넉하나, 원본 목록이 아주 길면 넘친다.
        if q["op"]=="apply" {return apply_call(&q);}
        // DLC 넣고 빼기를 엔진 하나로(계약 2-7 · 계획 P4 과제 9) — apply와 같은 까닭으로 잠금 앞에서. 배치(틈)는 Rust(`packs::RustLayouter`).
        if q["op"]=="add_pack" || q["op"]=="remove_pack" {return pack_call(&q);}
        let mut guard=store_lock();
        // 저장소를 놓는다(연결을 닫는다) — 앱이 저장소 파일을 바꿔 넣을 때(DLC 더하기 · 빼기) 먼저 부른다. Windows는 열린 파일을 옮기지 못한다.
        // 그 뒤의 조회 · 타일은 "저장소가 열리지 않았습니다"로 실패하고, `open`으로 다시 연다.
        if q["op"]=="close" {let was=guard.take().is_some();return Ok(json!({"closed":was}));}
        if q["op"]=="open" {*guard=Some(Store::open(Path::new(q["path"].as_str().ok_or("저장소 경로 누락")?))?);}
        let db=guard.as_ref().ok_or("저장소가 열리지 않았습니다")?;
        if q["op"]=="open" {db.info()} else {db.call(&q)}
    });
    let value=match answer {
        Ok(Ok(v))=>json!({"ok":true,"data":v,"db_ms":start.elapsed().as_secs_f64()*1000.0}),
        // COMMIT은 끝났는데 다시 열지 못한 실패는 `committed`로 가른다 — 다른 실패는 모두 '저장소 그대로'다(얹힌 몫 4).
        Ok(Err(e)) if e.downcast_ref::<ReopenFailed>().is_some()=>json!({"ok":false,"error":e.to_string(),"committed":true}),
        // 앱이 가르는 거절은 기계용 `code`를 함께 싣는다(계약 2-7 — rebuild · base · original · dup_uid · add_pack · remove_pack의 version · calendar · range · layout · broken · 쓰기 요청의 path · 그 밖은 없음).
        // 배치 실패의 원래 글(개발자 말)은 `detail`(앱의 자세히 보기).
        Ok(Err(e))=>match e.downcast_ref::<patch::Refusal>() {
            Some(r)=>{
                let mut v=json!({"ok":false,"error":e.to_string(),"code":r.code});
                if let Some(detail)=&r.detail {v["detail"]=json!(detail);}
                v
            }
            None=>json!({"ok":false,"error":e.to_string()}),
        },
        Err(_)=>json!({"ok":false,"error":"자료 처리 중 내부 오류"}),
    };
    CString::new(value.to_string()).unwrap().into_raw()
}

/// `{"op":"apply"}`(계약 2-7): 배치 · 원본 파일을 읽고(잠금 없이) 열린 저장소에 한 거래로 고쳐 쓴 뒤 다시 연다. 답의 `ms`는 명령 전체
/// (읽기 · 쓰기 · COMMIT · 다시 열기)의 시간이다.
fn apply_call(q:&Value)->Result<Value> {
    let started=Instant::now();
    let want=early_write_check(q)?;
    let order=patch::order_from_request(q)?;
    let report=with_store_write_at(want.as_deref(),|tx|patch::run_order(tx,&order))?;
    let mut answer=report.to_json();
    answer["ms"]=json!(started.elapsed().as_secs_f64()*1000.0);
    Ok(answer)
}
/// `{"op":"add_pack"}` · `{"op":"remove_pack"}`(계약 2-7 · 계획 P4 과제 9): 열린 저장소에 한 거래로 — 저장소의 원본 · 새 파일 · 판 대조 · 배치(Rust) · 고쳐 쓰기.
/// 배치도 거래 안에서 한다(쓰는 연결의 예약 잠금은 읽기를 막지 않는다 — 그동안 앱의 조회 · 타일은 옛 답). 답의 `ms`는 명령 전체.
fn pack_call(q:&Value)->Result<Value> {
    let started=Instant::now();
    let want=early_write_check(q)?;
    let report=if q["op"]=="add_pack" {
        let order=packs::add_order(q)?;
        with_store_write_at(want.as_deref(),|tx|packs::add_pack(tx,&order,&packs::RustLayouter))?
    } else {
        let order=packs::remove_order(q)?;
        with_store_write_at(want.as_deref(),|tx|packs::remove_pack(tx,&order,&packs::RustLayouter))?
    };
    let mut answer=report.to_json();
    answer["ms"]=json!(started.elapsed().as_secs_f64()*1000.0);
    Ok(answer)
}
#[no_mangle]
pub unsafe extern "C" fn archive_free(value:*mut c_char) {if !value.is_null(){drop(CString::from_raw(value));}}

/// 열린 저장소(`STORE`)에 쓴다 — 쓰는 동안은 `STORE` 잠금을 쥐지 않아 `archive_call` · `archive_tile`이 옛 답을 곧바로 받는다.
/// 차례(계획 P4 과제 3): ① 잠금을 잠깐 쥐어 열린 저장소의 경로를 꺼내 놓는다 → ② 같은 파일에 쓰기 연결을 따로 열어 한 거래로 `step`을 돈다
/// (잠금 없음 — 몇 초가 걸려도 화면은 멈추지 않는다) → ③ COMMIT 바로 앞에서만 잠금을 다시 쥐어 COMMIT한다(COMMIT의 배타 잠금은 읽기를 잠깐 막는다 — 잠금을 쥐면
/// 앱의 조회는 SQLite 잠금에 걸리지 않고 이 잠금 앞에서 기다리므로 COMMIT이 곧바로 끝난다) → ④ 잠금을 쥔 채 `Store`(`RowMap` 포함)를 다시 열어 바꿔 놓고 놓는다.
/// 열린 저장소가 없으면 Err(`step`은 돌지 않는다). `step`이 Err면 거래를 되돌리고 그 Err를 돌려준다(파일 · 열린 저장소 그대로).
/// COMMIT 뒤에는 그때 열려 있는 저장소를 **늘** 제 경로로 다시 연다 — 같은 파일인지 경로 글자로 견주지 않는다(쓰는 동안 앱이 같은 파일을 다른 글자로
/// 다시 열었어도 그 `RowMap`은 COMMIT 전 것이다 · 얹힌 몫 3). 앱이 그새 닫았으면 닫힌 채 둔다. 다시 열기가 실패하면 저장소를 닫고
/// [`ReopenFailed`]를 돌려준다(파일은 이미 바뀌었다 — '실패 = 저장소 그대로'와 다른 갈래 · 얹힌 몫 4).
///
/// 쓰기끼리는 프로세스 전역 잠금(`WRITE`)으로 줄을 선다 — 앞의 쓰기가 SQLite의 기다림(5초)보다 오래 걸려도 뒤의 쓰기는 실패하지 않고 기다린다(얹힌 몫 1).
/// **`STORE` 잠금을 쥔 채 부르지 않는다** — 이 함수가 그 잠금을 스스로 잠깐씩 쥐므로 같은 스레드에서 교착한다. `archive_call`은 `apply`를
/// 잠금 앞에서 가른다(얹힌 몫 2). `step` 안에서 `archive_call`을 부를 수는 있지만 옛 답이다.
pub fn with_store_write<T>(step:impl FnOnce(&rusqlite::Transaction)->Result<T>)->Result<T> {
    with_store_write_at(None,step)
}
/// 요청의 `path`를 미리 본다(꼴 · 지금 열린 저장소와 같은가 — 입력을 읽기 전에 옛 요청을 걸러 냄). 진짜 견줌은 [`with_store_write_at`]이 쓰기 차례를 잡은 뒤 한 번 더.
fn early_write_check(q:&Value)->Result<Option<String>> {
    let want=write_target(q)?;
    if let Some(w)=&want {
        let open=store_lock().as_ref().map(|s|s.path().to_path_buf()).ok_or("저장소가 열리지 않았습니다")?;
        check_write_path(w,&open)?;
    }
    Ok(want)
}
/// [`with_store_write`]에 쓰기 대상 `want`(요청의 `path`)를 더한 것 — 쓰기 차례(`WRITE`)를 잡고 쓸 파일을 정한 바로 그 자리에서 견준다(고침 3회차 — 견준 뒤
/// 쓰기 전에 앞 쓰기 · 앱의 열기가 저장소를 바꿔 놓는 틈 없이). 다르면 `step`을 돌지 않고 `code` path.
pub fn with_store_write_at<T>(want:Option<&str>,step:impl FnOnce(&rusqlite::Transaction)->Result<T>)->Result<T> {
    // 앞선 쓰기가 패닉으로 잠금을 오염시켰어도 그 쓰기는 이미 되돌려졌다 — 그대로 이어 쓴다.
    let _turn=WRITE.lock().unwrap_or_else(|poisoned|poisoned.into_inner());
    let slot=STORE.get_or_init(||Mutex::new(None));
    // 앞서 패닉이 잠금을 오염시켰어도(`archive_call`은 그 뒤 계속 실패한다) 쓰는 쪽은 새 저장소로 바꿔 놓으면서 되살린다.
    let take=||slot.lock().unwrap_or_else(|poisoned|{slot.clear_poison();poisoned.into_inner()});
    let path=take().as_ref().ok_or("저장소가 열리지 않았습니다")?.path().to_path_buf();
    if let Some(w)=want {check_write_path(w,&path)?;}
    let (out,mut guard)=write::write_with(&path,step,take)?;
    if let Some(open)=guard.as_ref() {
        let again=open.path().to_path_buf();
        // 다시 열다가 패닉해도 `ReopenFailed`로(바깥 `catch_unwind`까지 풀려 나가면 `committed`가 빠지고 STORE가 오염된 채 남는다 — 고침 1회차 Minor 1).
        // 검사용 실패 지점: "reopen"은 Err, "reopen-panic"은 패닉(스레드마다 — `write::set_fail_point`).
        let reopened=std::panic::catch_unwind(||{
            if write::fail_point("reopen-panic").is_err() {panic!("실패 주입: reopen-panic");}
            write::fail_point("reopen").and_then(|()|Store::open(&again))
        }).unwrap_or_else(|_|Err("저장소를 다시 여는 중 내부 오류".into()));
        match reopened {
            Ok(fresh)=>*guard=Some(fresh),
            Err(e)=>{*guard=None;return Err(Box::new(ReopenFailed(e.to_string())));}
        }
    }
    Ok(out)
}

/// 쓰기끼리 줄 세우는 프로세스 전역 잠금([`with_store_write`]). 이것을 쥔 채 `STORE`를 잠깐씩 쥐며, 그 반대 차례로 쥐는 곳은 없다.
static WRITE:Mutex<()>=Mutex::new(());

/// COMMIT은 끝났는데(저장소 파일은 바뀜) 저장소를 다시 열지 못한 실패 — 저장소는 닫힌 채다(`{"op":"open"}`으로 다시 연다).
/// `archive_call`의 답에 `"committed":true`가 붙는다(계약 2-7).
#[derive(Debug)]
pub struct ReopenFailed(pub String);
impl std::fmt::Display for ReopenFailed {
    fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result {
        write!(f,"쓰기는 끝나 저장소 파일이 바뀌었지만 저장소를 다시 열지 못해 닫아 두었습니다 — 다시 열어 주세요: {}",self.0)
    }
}
impl std::error::Error for ReopenFailed {}

static LAST_ERROR:Mutex<String>=Mutex::new(String::new());
/// 이진 타일. 요청은 {"level":L,"x":X,"chunk":C,"packs":[…]}. 실패하면 null과 길이 0을 돌려주고 까닭은 {"op":"last_error"}로 읽는다.
#[no_mangle]
pub unsafe extern "C" fn archive_tile(request:*const c_char,len:*mut usize)->*mut u8 {
    let answer=std::panic::catch_unwind(||->Result<Vec<u8>>{
        if request.is_null()||len.is_null(){return Err("빈 요청".into());}
        let bytes=CStr::from_ptr(request).to_bytes();if bytes.len()>16384{return Err("요청 크기 초과".into());}
        let q:Value=whole_numbers(&serde_json::from_slice(bytes)?);
        let packs=q["packs"].as_array().ok_or("켠 자료집 목록 누락")?.iter().map(|v|v.as_i64().ok_or("자료집 번호 오류")).collect::<std::result::Result<Vec<_>,_>>()?;
        let level=usize::try_from(num(&q,"level")?).map_err(|_|"타일 요청의 단계가 범위 밖입니다")?;
        let guard=store_lock();
        let store=guard.as_ref().ok_or("저장소가 열리지 않았습니다")?;
        // 거르개(선택). 없거나 비었으면 None이고, 그때의 바이트는 거르개를 넣기 전과 똑같다.
        let filter=store.filter_of(&q)?;
        // 켠 변형(선택). 없으면 답은 변형을 넣기 전과 바이트까지 같다.
        let variants=store.variants_of(&q)?;
        tile::build_tile(store,&tile::TileRequest{level,x:num(&q,"x")?,chunk:num(&q,"chunk")?,packs,filter,variants})
    });
    match answer {
        Ok(Ok(bytes))=>{let boxed=bytes.into_boxed_slice();*len=boxed.len();Box::into_raw(boxed) as *mut u8},
        other=>{
            if let Ok(mut slot)=LAST_ERROR.lock(){*slot=match other {Ok(Err(e))=>e.to_string(),_=>"타일을 만드는 중 내부 오류".to_owned()};}
            if !len.is_null(){*len=0;}
            std::ptr::null_mut()
        }
    }
}
/// 문서 그림 바이트 하나. 요청은 {"key":"img:<DLC id>/<그림 id>"}. 답은 그림 파일의 바이트 그대로(`archive_free_bytes`로 놓는다).
/// 없거나 실패하면 null과 길이 0을 돌려주고 까닭은 {"op":"last_error"}로 읽는다(`archive_tile`과 같은 꼴).
#[no_mangle]
pub unsafe extern "C" fn archive_blob(request:*const c_char,len:*mut usize)->*mut u8 {
    let answer=std::panic::catch_unwind(||->Result<Vec<u8>>{
        if request.is_null()||len.is_null(){return Err("빈 요청".into());}
        let bytes=CStr::from_ptr(request).to_bytes();if bytes.len()>16384{return Err("요청 크기 초과".into());}
        let q:Value=serde_json::from_slice(bytes)?;
        let key=q["key"].as_str().ok_or("그림 열쇠 누락")?;
        let guard=store_lock();
        let store=guard.as_ref().ok_or("저장소가 열리지 않았습니다")?;
        store.blob(key)?.map(|(_,b)|b).ok_or_else(||format!("그림이 저장소에 없습니다: {key}").into())
    });
    match answer {
        Ok(Ok(bytes)) if !bytes.is_empty()=>{let boxed=bytes.into_boxed_slice();*len=boxed.len();Box::into_raw(boxed) as *mut u8},
        other=>{
            if let Ok(mut slot)=LAST_ERROR.lock(){*slot=match other {Ok(Err(e))=>e.to_string(),Ok(Ok(_))=>"그림이 비어 있습니다".to_owned(),Err(_)=>"그림을 읽는 중 내부 오류".to_owned()};}
            if !len.is_null(){*len=0;}
            std::ptr::null_mut()
        }
    }
}
/// 글자 굽기(설계 3-2 · 계획 P2 과제 1). 요청은 {"font","size","glyphs":[{"rune","phase"}],"mode"}. 답은 "HTGL" 바이트(`archive_free_bytes`로 놓는다).
/// Windows가 아니거나 실패하면 null과 길이 0 — 까닭은 {"op":"last_error"}로 읽는다(`archive_tile`과 같은 꼴). 저장소를 잡지 않는다.
#[no_mangle]
pub unsafe extern "C" fn archive_glyphs(request:*const c_char,len:*mut usize)->*mut u8 {
    let answer=std::panic::catch_unwind(||->Result<Vec<u8>>{
        if request.is_null()||len.is_null(){return Err("빈 요청".into());}
        let bytes=CStr::from_ptr(request).to_bytes();if bytes.len()>262144{return Err("요청 크기 초과".into());}
        let q:Value=serde_json::from_slice(bytes)?;
        #[cfg(windows)] { glyph::bake(&q) }
        #[cfg(not(windows))] { let _=q; Err("이 운영체제에서는 글자를 굽지 않습니다".into()) }
    });
    match answer {
        Ok(Ok(bytes))=>{let boxed=bytes.into_boxed_slice();*len=boxed.len();Box::into_raw(boxed) as *mut u8},
        other=>{
            if let Ok(mut slot)=LAST_ERROR.lock(){*slot=match other {Ok(Err(e))=>e.to_string(),_=>"글자를 굽는 중 내부 오류".to_owned()};}
            if !len.is_null(){*len=0;}
            std::ptr::null_mut()
        }
    }
}
#[no_mangle]
pub unsafe extern "C" fn archive_free_bytes(ptr:*mut u8,len:usize) {if !ptr.is_null(){drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr,len)));}}

/// 팩 파일(`.htpack` 종류 1 · 2, `.htlayout` 종류 3 — `DLC-형식.md` '팩 파일' · `js/packfile.js`)의 공통 포장:
/// 머리 52바이트(표지 8 · 규격 2 · 종류 · 1 · 0 · 풀린 크기 · 압축 크기 · SHA-256 지문) + deflate(zlib) 본문.
pub const PACK_MAGIC:&[u8;8]=b"HTPACK\r\n";
pub const PACK_HEADER:usize=52;
/// 파일 64MB · 풀린 본문 128MB까지(`packfile.js`의 `LIMITS`와 같다).
pub const PACK_FILE_MAX:u64=64*1024*1024;
pub const PACK_PLAIN_MAX:usize=128*1024*1024;
/// 팩 파일 종류(머리 9번 자리): 1 DLC · 2 전체 백업 · 3 아카이브 배치.
pub const KIND_DLC:u8=1;
pub const KIND_LAYOUT:u8=3;

/// `unseal`이 거절한 까닭. 읽는 쪽(`read_htpack` · `read_htlayout`)이 제 글로 바꾼다 — 전용 팩은 예전 글 그대로, 배치는 `packfile.js`의 글 그대로.
#[derive(Debug,Clone,PartialEq,Eq)]
pub enum SealError {
    /// 표지(`HTPACK\r\n`)가 아니다.
    NotPack,
    /// 표지는 맞는데 머리 52바이트가 다 없다.
    Truncated,
    /// 규격(머리 8번)이 2가 아니다.
    Version,
    /// 다른 종류의 팩 파일이다(종류 1 · 2 · 3 가운데 받지 않는 것).
    OtherKind,
    /// 머리의 종류 · 예약 자리가 틀렸다.
    BadHead,
    /// 풀린 크기가 0이거나 128MB를 넘는다.
    PlainSize,
    /// 압축 크기가 0이거나 파일 길이와 맞지 않는다(잘렸거나 꼬리가 붙었다).
    Cut,
    /// 지문이 맞지 않는다(손상 · 바뀜).
    Digest,
    /// 압축을 풀지 못했다(까닭은 풀기 도구의 글).
    Inflate(String),
    /// 풀린 본문이 머리에 적힌 크기를 넘는다(적힌 크기).
    Overflow(usize),
    /// 풀린 본문이 머리에 적힌 크기보다 작다.
    Short,
}

/// 풀린 본문. `rest`는 압축 흐름이 끝난 뒤 남은(읽지 않은) 바이트 수 — 0이 아니면 본문 뒤에 군더더기가 붙었다.
pub struct Unsealed { pub plain:Vec<u8>, pub rest:usize }

/// 팩 파일의 머리 · 크기 · 지문을 검사하고 본문을 푼다(`kind` = 받는 종류). 검사 차례는 `packfile.js`의 `unseal`과 같다.
pub fn unseal(bytes:&[u8],kind:u8)->std::result::Result<Unsealed,SealError> {
    if bytes.len()<PACK_MAGIC.len() || &bytes[..PACK_MAGIC.len()]!=PACK_MAGIC {return Err(SealError::NotPack);}
    if bytes.len()<PACK_HEADER {return Err(SealError::Truncated);}
    if bytes[8]!=2 {return Err(SealError::Version);}
    if bytes[9]!=kind {
        return Err(if matches!(bytes[9],1..=3) && bytes[10]==1 && bytes[11]==0 {SealError::OtherKind} else {SealError::BadHead});
    }
    if bytes[10]!=1 || bytes[11]!=0 {return Err(SealError::BadHead);}
    let plain=u32::from_le_bytes([bytes[12],bytes[13],bytes[14],bytes[15]]) as usize;
    let compressed=u32::from_le_bytes([bytes[16],bytes[17],bytes[18],bytes[19]]) as usize;
    if plain==0 || plain>PACK_PLAIN_MAX {return Err(SealError::PlainSize);}
    // 32비트 기기(휴대폰)에서 넘치지 않게 더하기를 살핀다.
    if compressed==0 || compressed.checked_add(PACK_HEADER)!=Some(bytes.len()) {return Err(SealError::Cut);}
    let mut hash=Sha256::new();hash.update(&bytes[..20]);hash.update(&bytes[PACK_HEADER..]);
    if hash.finalize().as_slice()!=&bytes[20..PACK_HEADER] {return Err(SealError::Digest);}
    let body=&bytes[PACK_HEADER..];
    let mut decoder=flate2::read::ZlibDecoder::new(body);
    let mut decoded=Vec::new();
    (&mut decoder).take((plain+1) as u64).read_to_end(&mut decoded).map_err(|e|SealError::Inflate(e.to_string()))?;
    if decoded.len()>plain {return Err(SealError::Overflow(plain));}
    if decoded.len()<plain {return Err(SealError::Short);}
    let rest=body.len().saturating_sub(decoder.total_in() as usize);
    Ok(Unsealed{plain:decoded,rest})
}

/// DLC 전용 팩(.htpack 종류 1). 거절하는 경우와 글은 `unseal`을 떼기 전 그대로다.
pub fn read_htpack(path:&Path)->Result<Value> {
    if path.extension().and_then(|s|s.to_str()).map(|s|s.eq_ignore_ascii_case("htpack"))!=Some(true){return Err("전용 팩 확장자가 아닙니다".into());}
    let size=fs::metadata(path)?.len();if !(PACK_HEADER as u64..=PACK_FILE_MAX).contains(&size){return Err("전용 팩 크기 오류".into());}
    htpack_raw(&fs::read(path)?)
}
/// 전용 팩의 바이트(파일 · 저장소의 `packs.original`) → DLC 본문.
pub fn htpack_raw(bytes:&[u8])->Result<Value> {
    let open=unseal(bytes,KIND_DLC).map_err(|e|->Box<dyn std::error::Error+Send+Sync>{match e {
        SealError::NotPack|SealError::Truncated|SealError::Version|SealError::OtherKind|SealError::BadHead=>"지원하지 않는 전용 팩 머리".into(),
        SealError::PlainSize|SealError::Cut=>"전용 팩 선언 크기 오류".into(),
        SealError::Digest=>"전용 팩 지문 오류".into(),
        SealError::Inflate(why)=>why.into(),
        SealError::Overflow(_)|SealError::Short=>"전용 팩 풀린 크기 오류".into(),
    }})?;
    let raw:Value=serde_json::from_slice(&open.plain)?;
    if raw["format"]!="history-timeline-dlc" {return Err("DLC 본문이 아닙니다".into());} Ok(raw)
}

/// 아카이브 배치 파일이 아닐 때의 글(`packfile.js` `parseLayout`의 notPack).
pub const LAYOUT_NOT_PACK:&str="아카이브 배치 파일(.htlayout)이 아닙니다.";
/// 종류 3의 내용 — 가져오기 JSON 3판인가(`packfile.js`의 `isLayout`과 같다: `packs`가 비지 않고, 여섯 목록이 배열).
pub fn is_layout(raw:&Value)->bool {
    raw.is_object() && raw["packs"].as_array().is_some_and(|p|!p.is_empty())
        && ["tracks","periods","cells","events","items","entities"].iter().all(|k|raw[*k].is_array())
}
/// 메이커의 아카이브 배치(.htlayout · 팩 파일 종류 3) → 가져오기 JSON 3판. 받는 것: 확장자 `.htlayout` · 파일 64MB · 풀린 본문 128MB까지.
/// 거절하는 글은 웹(`js/packfile.js`의 `parseLayout`)과 같다 — 앱이 그대로 보인다.
pub fn read_htlayout(path:&Path)->Result<Value> {
    if path.extension().and_then(|s|s.to_str()).map(|s|s.eq_ignore_ascii_case("htlayout"))!=Some(true){return Err(LAYOUT_NOT_PACK.into());}
    if fs::metadata(path)?.len()>PACK_FILE_MAX {return Err("파일이 너무 큽니다 (64MB까지).".into());}
    htlayout_raw(&fs::read(path)?)
}
/// 아카이브 배치의 바이트 → 가져오기 JSON 3판(`read_htlayout`의 확장자 · 크기 검사 뒤의 몫).
pub fn htlayout_raw(bytes:&[u8])->Result<Value> {
    if bytes.len() as u64>PACK_FILE_MAX {return Err("파일이 너무 큽니다 (64MB까지).".into());}
    const BROKEN:&str="팩 내용을 풀 수 없습니다. 파일이 손상되었습니다.";
    let open=unseal(bytes,KIND_LAYOUT).map_err(|e|->Box<dyn std::error::Error+Send+Sync>{match e {
        SealError::NotPack=>LAYOUT_NOT_PACK.into(),
        SealError::Truncated=>"팩 파일의 머리 부분이 잘렸습니다.".into(),
        SealError::Version=>"지원하지 않는 팩 형식입니다. 메이커와 연표의 버전을 확인하세요.".into(),
        SealError::OtherKind=>"DLC · 백업 팩(.htpack)입니다 — 아카이브 배치 파일(.htlayout)이 아닙니다.".into(),
        SealError::BadHead=>"팩 파일의 머리 부분이 올바르지 않습니다.".into(),
        SealError::PlainSize=>"팩을 풀면 허용 크기(128MB)를 넘거나 내용이 없습니다.".into(),
        SealError::Cut=>"팩 파일이 잘렸거나 불필요한 내용이 붙었습니다.".into(),
        SealError::Digest=>"팩 파일이 손상되었거나 바뀌었습니다. 원본을 다시 받거나 메이커에서 새로 저장하세요.".into(),
        SealError::Inflate(_)=>BROKEN.into(),
        // 웹은 풀린 크기를 MB로 반올림해 적는다(`mb(n)` = Math.round(n / MB)).
        SealError::Overflow(size)=>format!("팩을 풀면 허용 크기({}MB)를 넘습니다.",(size as f64/(1024.0*1024.0)).round() as u64).into(),
        SealError::Short=>"팩 내용의 크기가 맞지 않습니다.".into(),
    }})?;
    // 압축 흐름 뒤에 군더더기가 붙었으면 웹의 풀기(DecompressionStream)도 실패한다.
    if open.rest>0 {return Err(BROKEN.into());}
    const UNREADABLE:&str="팩 내용을 읽을 수 없습니다. 파일이 손상되었습니다.";
    // 웹의 TextDecoder는 맨 앞의 BOM을 건너뛴다.
    let text=open.plain.strip_prefix(b"\xEF\xBB\xBF".as_slice()).unwrap_or(&open.plain);
    let text=std::str::from_utf8(text).map_err(|_|UNREADABLE)?;
    let raw:Value=serde_json::from_str(text).map_err(|_|UNREADABLE)?;
    if !is_layout(&raw) {return Err("팩 종류와 내용이 맞지 않습니다.".into());}
    Ok(raw)
}

/// 배치(.htlayout · 배치 JSON)를 Node 없이 새 저장소로 짓는다(계약 2-7). 답은 `archive_free`로 놓는다.
/// **`STORE` 잠금을 잡지 않는다** — 몇 초 걸리는 짓기 동안에도 `archive_call` · `archive_tile`이 그대로 답한다.
/// 요청 `{"layout","out","base"?,"originals"?:[…],"from_store"?,"check_only"?}` → `{"ok":true,"data":{…}}` 또는 `{"ok":false,"error":"…"}`.
#[no_mangle]
pub unsafe extern "C" fn archive_import(request:*const c_char)->*mut c_char {
    let answer=std::panic::catch_unwind(||->Result<Value>{
        if request.is_null(){return Err("빈 요청".into());}
        let bytes=CStr::from_ptr(request).to_bytes();if bytes.len()>1024*1024{return Err("요청 크기 초과".into());}
        let q:Value=serde_json::from_slice(bytes)?;
        legacy::import_request(&q)
    });
    let value=match answer {Ok(Ok(v))=>json!({"ok":true,"data":v}),Ok(Err(e))=>json!({"ok":false,"error":e.to_string()}),Err(_)=>json!({"ok":false,"error":"배치를 가져오는 중 내부 오류"})};
    CString::new(value.to_string()).unwrap().into_raw()
}

#[cfg(test)]
mod path_tests {
    use super::same_file;
    use std::path::Path;

    #[test]
    fn write_path_compares_like_with_like() {
        // 쓰기 요청의 path(appfix 검토 덧붙임): 둘 다 풀리면 실제 자리 · 한쪽이라도 못 풀면 둘 다 글자 꼴로 견준다.
        let file=std::env::temp_dir().join(format!("archive-correct-{}-same-file.db",std::process::id()));
        std::fs::write(&file,b"x").unwrap();
        let text=file.to_string_lossy().into_owned();
        assert!(same_file(&file,Path::new(&text.replace('\\',"/"))),"같은 파일 · 다른 구분자");
        assert!(!same_file(&file,&file.with_extension("other")),"없는 파일은 다른 파일");
        assert!(same_file(Path::new("D:/없는/폴더/A.db"),Path::new(if cfg!(windows) {r"d:\없는\폴더\a.db"} else {"D:/없는/폴더/A.db"})),"둘 다 못 풀면 글자 꼴");
        if cfg!(windows) {
            // 한쪽만 못 푸는 같은 파일: `\\?\` 꼴은 `/`를 구분자로 보지 않아 풀리지 않는다 — 풀린 쪽과 견주면 늘 달랐다.
            let verbatim=format!(r"\\?\{}",text.replace('\\',"/"));
            assert!(std::fs::canonicalize(&verbatim).is_err(),"장면: 이 꼴은 풀리지 않는다");
            assert!(same_file(Path::new(&verbatim),&file),"한쪽만 못 풀어도 같은 파일");
        }
        std::fs::remove_file(&file).unwrap();
    }
}
