/* 메이커의 작업 기록 · 자동 저장 · 항목 묶음. 연표 배포물에서는 읽지 않습니다. */
(function () {
  'use strict';
  const HT = window.HT;
  const clone = v => JSON.parse(JSON.stringify(v));
  const content = v => JSON.stringify(v, (k, x) => k === '_edited' ? undefined : x);
  const lists = () => HT.makerKit.itemLists();
  const defs = ['tracks', 'categories', 'peoples', 'rankDefs', 'houses'];
  const list = (d, k) => Array.isArray(d && d[k]) ? d[k] : [];

  /** 기록은 현재 시점도 한 장 갖습니다. 오래된 것을 버려도 남은 첫 시점까지 돌아갑니다. */
  class History {
    constructor(raw, { steps = 200, bytes = 64 * 1024 * 1024 } = {}) {
      this.maxSteps = steps; this.maxBytes = bytes; this.reset(raw);
    }
    reset(raw) { this.rows = [{ text: JSON.stringify(raw), name: '처음 시점', at: Date.now() }]; this.index = 0; }
    get canUndo() { return this.index > 0; }
    get canRedo() { return this.index < this.rows.length - 1; }
    get bytes() { return this.rows.reduce((n, r) => n + r.text.length * 2, 0); }
    push(raw, name = '작업본 고침') {
      if (content(raw) === content(JSON.parse(this.rows[this.index].text))) return false;
      this.rows.splice(this.index + 1);
      this.rows.push({ text: JSON.stringify(raw), name, at: Date.now() });
      this.index++;
      while (this.rows.length > 1 && (this.rows.length > this.maxSteps + 1 || this.bytes > this.maxBytes)) {
        this.rows.shift(); this.index--; this.rows[0].name = '남아 있는 첫 시점';
      }
      return true;
    }
    go(index) {
      if (!Number.isInteger(index) || index < 0 || index >= this.rows.length) return undefined;
      this.index = index; return JSON.parse(this.rows[index].text);
    }
    undo() { return this.canUndo ? this.go(this.index - 1) : undefined; }
    redo() { return this.canRedo ? this.go(this.index + 1) : undefined; }
    /** 여러 계산이 끝난 최종 작업본만 기록합니다. 함수가 던지면 기록은 그대로입니다. */
    group(name, fn) { const raw = fn(); this.push(raw, name); return raw; }
  }
  const count = raw => lists().reduce((n, k) => n + list(raw, k).length, 0);
  function difference(a, b) {
    if (!a || !b) return count(a || b);
    let n = 0;
    for (const k of [...HT.draft.LISTS, 'documents']) {
      const map = d => new Map(k === 'documents' ? Object.entries(d.documents || {}) : list(d, k).map((x, i) => [x.id || x.target || i, x]));
      const aa = map(a), bb = map(b);
      for (const id of new Set([...aa.keys(), ...bb.keys()])) if (JSON.stringify(aa.get(id)) !== JSON.stringify(bb.get(id))) n++;
    }
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) if (!k.startsWith('_') && !HT.draft.LISTS.includes(k) && k !== 'documents' && JSON.stringify(a[k]) !== JSON.stringify(b[k])) n++;
    return n;
  }

  /** IndexedDBだけに保管。書き込み完了は要求の成功でなく取引全体の完了で判定します。 */
  function snapshots() {
    let opening;
    const db = () => opening || (opening = new Promise((resolve, reject) => {
      if (!window.indexedDB) return reject(new Error('이 브라우저에서는 자동 저장 기록을 쓸 수 없습니다.'));
      const r = window.indexedDB.open('ht-maker', 1);
      r.onupgradeneeded = () => { const s = r.result.createObjectStore('snapshots', { keyPath: 'key', autoIncrement: true }); s.createIndex('pack', 'pack'); };
      r.onsuccess = () => { r.result.onversionchange = () => r.result.close(); resolve(r.result); };
      r.onerror = () => { opening = null; reject(r.error); };
      r.onblocked = () => { opening = null; reject(new Error('다른 메이커 창을 닫으면 자동 저장 기록을 열 수 있습니다.')); };
    }));
    async function all(pack) {
      const d = await db();
      return new Promise((resolve, reject) => {
        const tx = d.transaction('snapshots', 'readonly');
        const r = tx.objectStore('snapshots').index('pack').getAll(pack);
        tx.oncomplete = () => resolve(r.result.sort((a, b) => b.key - a.key));
        tx.onerror = tx.onabort = () => reject(tx.error || r.error);
      });
    }
    async function save(raw, reason) {
      if (!raw) return null;
      const copy = clone(raw), d = await db();
      return new Promise((resolve, reject) => {
        const tx = d.transaction('snapshots', 'readwrite'), store = tx.objectStore('snapshots');
        const row = { pack: copy.id, name: copy.name, at: Date.now(), reason, count: count(copy), raw: copy };
        const r = store.add(row);
        r.onsuccess = () => {
          row.key = r.result;
          const old = store.index('pack').getAll(copy.id);
          old.onsuccess = () => { for (const x of old.result.sort((a, b) => b.key - a.key).slice(30)) store.delete(x.key); };
        };
        tx.oncomplete = () => resolve(row);
        tx.onerror = tx.onabort = () => reject(tx.error || r.error);
      });
    }
    return { all, save };
  }

  /** 파일 그대로의 값에서 선택한 항목과 필요한 정의를 모읍니다. source는 우선순위대로 넘깁니다. */
  function bundle(sources, uids) {
    const entries = [], temp = HT.draft.blank({ id: 'clipboard', name: '복사한 항목' });
    for (const uid of new Set(uids)) {
      const slash = uid.indexOf('/'), packId = uid.slice(0, slash), id = uid.slice(slash + 1);
      const source = sources.find(p => p.id === packId);
      if (!source) continue;
      const found = HT.draft.findOwn(source, id);
      if (!found) continue;
      const docs = {};
      for (const [k, text] of Object.entries(source.documents || {})) {
        const absolute = HT.docKey.absolute(k, source.id);
        if (absolute === uid || absolute.startsWith(uid + '//') || absolute.startsWith('cell:' + uid + ':')) docs[absolute] = text;
      }
      entries.push({ uid, list: found.list, item: clone(found.item), documents: docs });
      temp[found.list].push(clone(found.item));
    }
    const definitions = Object.fromEntries(defs.map(k => [k, []]));
    let added = true;
    while (added) {
      added = false;
      for (const source of sources) for (const k of defs) for (const x of list(source, k)) {
        if (!x.id || definitions[k].some(d => d.id === x.id)) continue;
        if (!HT.makerKit.findUsers(temp, HT.makerKit.BASE_TABLES[k], x).length) continue;
        const row = clone(x); definitions[k].push(row); temp[k].push(row); added = true;
      }
    }
    return { format: 'history-timeline-items', version: 1, entries, definitions };
  }
  function validBundle(x) {
    return !!x && x.format === 'history-timeline-items' && x.version === 1 && Array.isArray(x.entries) && x.entries.length <= 10000 && x.entries.every(e => e && typeof e.uid === 'string' && lists().includes(e.list) && e.item && typeof e.item === 'object' && !Array.isArray(e.item));
  }
  function insert(raw, packet, { duplicate = false } = {}) {
    if (!validBundle(packet)) throw new Error('메이커 항목 묶음을 읽을 수 없습니다.');
    const draft = clone(raw), used = new Set(lists().flatMap(k => list(draft, k).map(x => x.id)));
    const items = [], rename = new Map();
    for (const e of packet.entries) {
      const item = clone(e.item), own = e.uid.startsWith(draft.id + '/');
      const old = item.id || 'item';
      let id = old, n = 1;
      if (duplicate || used.has(id)) { do { id = `${old}-copy${n === 1 ? '' : n}`; n++; } while (used.has(id)); }
      used.add(id); item.id = id;
      const nameKey = item.title != null ? 'title' : 'name';
      if (duplicate && own && item[nameKey]) item[nameKey] += ' (사본)';
      rename.set(e.uid, { id, uid: `${draft.id}/${id}`, old: e.item, item });
      items.push({ ...e, item });
    }
    const prose = new Set(['id', 'name', 'title', 'description', 'note', 'wiki', 'source', 'label']);
    for (const e of items) {
      const sourceId = e.uid.split('/')[0];
      const rewrite = (v, key, reference = false) => {
        const isRef = reference || ['succeeds', 'partOf', 'host', 'polities', 'members', 'service', 'home', 'polity', 'parent'].includes(key);
        if (typeof v === 'string' && (!prose.has(key) || (key === 'name' && isRef))) {
          const direct = rename.get(v) || rename.get(`${sourceId}/${v}`);
          if (direct) return v.includes('/') ? direct.uid : direct.id;
          for (const [uid, r] of rename) if (uid.startsWith(sourceId + '/') && r.old.name === v && r.item.name !== v) return r.item.name;
        }
        if (Array.isArray(v)) return v.map(x => rewrite(x, key, isRef));
        if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, rewrite(x, k, isRef)]));
        return v;
      };
      draft[e.list].push(rewrite(e.item, ''));
      const uid = rename.get(e.uid).uid;
      for (const [key, text] of Object.entries(e.documents || {})) {
        const mapped = key.startsWith('cell:' + e.uid + ':') ? 'cell:' + uid + key.slice(('cell:' + e.uid).length) : key.startsWith(e.uid) ? uid + key.slice(e.uid.length) : null;
        if (mapped && typeof text === 'string') HT.draft.setDoc(draft, mapped, text);
      }
    }
    for (const k of defs) for (const row of list(packet.definitions, k)) if (row && row.id && !draft[k].some(x => x.id === row.id)) draft[k].push(clone(row));
    return { draft, uids: items.map(e => rename.get(e.uid).uid) };
  }
  const tsv = packet => ['종류\t이름\t시작\t끝\t트랙', ...packet.entries.map(e => [HT.makerKit.listWord(e.list), e.item.title || e.item.name || '', e.item.start ?? '', e.item.end ?? '', e.item.track || ''].map(v => /[\t\r\n"]/.test(String(v)) ? '"' + String(v).replace(/"/g, '""') + '"' : String(v)).join('\t'))].join('\n');
  const clipboardHTML = packet => `<pre data-ht-items="${encodeURIComponent(JSON.stringify(packet))}">${tsv(packet).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c])}</pre>`;
  function fromClipboard(data) {
    try {
      let raw = data.getData('application/x-history-timeline+json');
      if (!raw) { const m = /data-ht-items="([^"]+)"/.exec(data.getData('text/html')); if (m) raw = decodeURIComponent(m[1]); }
      const value = raw && JSON.parse(raw);
      return validBundle(value) ? value : null;
    } catch (_) { return null; }
  }
  HT.makerHistory = { History, snapshots, count, difference, content };
  HT.makerEdit = { bundle, insert, validBundle, tsv, clipboardHTML, fromClipboard };
})();
