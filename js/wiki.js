/* 역사 연표 — 위키 문서 렌더러 (나무위키 문법의 자주 쓰는 부분)
   HT.namu.render(원문, { link(이름) → { uid, missing } }) → { html, toc, categories }
   지원: == 제목 ==, '''굵게''', ''기울임'', ~~취소~~, --취소--, __밑줄__, ^^위첨자^^, ,,아래첨자,,,
         [[문서]] [[문서|표시]] [[http://…|링크]] [[분류:…]], [* 각주] [*이름 각주], [목차] [각주] [br] [age(…)] [date],
         {{{#!folding 제목 …}}}, {{{#!wiki style="…" …}}}, {{{#!syntax …}}}, {{{+2 크게}}} {{{-1 작게}}} {{{#색 글자}}} {{{코드}}},
         * 목록, 1. 번호 목록, > 인용, ---- 가로줄, || 표 || (<-2> <|2> <bgcolor=…> <(> <:> <)> 등) */
(function () {
  'use strict';
  const HT = (window.HT = window.HT || {});
  const esc = HT.escapeHtml || (s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])));
  const namu = (HT.namu = {});

  const safeStyle = s => String(s || '').replace(/url\s*\(|expression|javascript:|@import|behavior\s*:/gi, '').replace(/[^\w\s#%.,:;()\-'"!]/g, '').slice(0, 300);
  const safeColor = c => (/^#[0-9a-f]{3,8}$/i.test(c) || /^[a-z]{3,20}$/i.test(c) ? c : '');
  const slug = (s, i) => `wk-h${i}`;

  /** 여는 문자열 open으로 시작하는 위치에서 짝이 맞는 close까지의 끝 인덱스(닫는 문자열 뒤)를 찾습니다 */
  function matchEnd(text, from, open, close) {
    let depth = 0;
    for (let i = from; i < text.length; i++) {
      if (text.startsWith(open, i)) {
        depth++;
        i += open.length - 1;
      } else if (text.startsWith(close, i)) {
        depth--;
        i += close.length - 1;
        if (depth === 0) return i + 1;
      }
    }
    return -1;
  }

  /* ---------- 문서 그림 (형식 3 — 10건 D3 · 16건 15번 · docs/설계-10건/4-5-메이커-블록과-묶음.md 결정 8 · 9) ----------
   * [[파일:이름]] · [[파일:이름|width=50%]] · [[파일:이름|align=center]] — 이름(또는 id)은 그 문서 글을 적은 팩의 그림 사전(images)에서 찾습니다(HT.docImageOf).
   * 그림 고리가 든 줄은 그 앞에서 문단을 끊고 그림을 놓은 뒤 나머지 글을 이어 씁니다(줄 가운데의 그림도 그 줄 앞으로).
   * 자리(결정 9 B): 기본은 오른쪽에 띄우고 글(문단 · 목록)이 왼쪽으로 흐름 — 제목 · 가로줄 · 표 · 인용 · 상자 · 접기 · 코드는 그림 아래에서 시작(겹치지 않음).
   * align=center는 본문 폭 가운데 · align=left는 왼쪽 정렬(띄우지 않음). 본문이 좁으면(600px 아래) 띄우지 않고 본문 폭 가운데(결정 9 A — css/viewer.css의 그릇 물음).
   * 목록 · 표 칸 안의 그림 고리는 예전처럼 지웁니다. opts.image가 없으면(그림을 모르는 곳) 예전처럼 그림 고리를 조용히 지웁니다.
   * 새 앱(prototype/app/lib/ui/doc_window.dart의 DocFigure · DocFlow)이 같은 규칙으로 그립니다 — 줄마다 폭을 따로 셈함 */
  const FILE_RE = /\[\[((?:파일|이미지|file)\s*:[^\]]*?)\]\]/gi;
  /** 그림 기본 폭(오른쪽에 띄울 때) · 띄울 때 글에 남기는 가장 작은 폭 · 띄우는 본문의 가장 작은 폭 — 새 앱의 DocUi.figure* 와 같은 값 */
  namu.FIGURE = { width: 340, gap: 24, minText: 280, narrow: 600 };
  /** [[파일:이름|width=…|align=…]]의 속(대괄호 안) → { name, width: '' | 'Npx' | 'N%', align: '' | 'left' | 'center' | 'right' } — 나무위키 꼴의 선택 가운데 크기와 자리만 읽습니다 */
  namu.fileSpec = inner => {
    const parts = String(inner).split('|');
    const o = { name: parts[0].replace(/^(파일|이미지|file)\s*:\s*/i, '').trim(), width: '', align: '' };
    for (const p of parts.slice(1)) {
      const m = p.trim().match(/^(width|align)\s*=\s*(.+)$/i);
      if (!m) continue;
      const v = m[2].trim().toLowerCase();
      if (m[1].toLowerCase() === 'width' && /^\d{1,4}(px|%)?$/.test(v) && parseInt(v, 10) > 0) o.width = /%$/.test(v) ? `${Math.min(100, parseInt(v, 10))}%` : `${parseInt(v, 10)}px`;
      else if (m[1].toLowerCase() === 'align' && /^(left|center|right)$/.test(v)) o.align = v;
    }
    return o;
  };
  /** 본문의 그림 고리 목록 [{ name, width, align }] — 적힌 차례(같은 그림을 두 번 적으면 두 번) */
  namu.files = src => {
    const out = [];
    String(src || '').replace(FILE_RE, (m, inner) => {
      out.push(namu.fileSpec(inner));
      return m;
    });
    return out;
  };
  /** 그림 한 장의 HTML — g = 그림 사전의 그림(HT.docImageOf의 답 — 없으면 '그림 없음' 자리) */
  namu.figureHTML = (spec, g) => {
    const pos = spec.align === 'center' ? 'is-center' : spec.align === 'left' ? 'is-left' : 'is-right';
    if (!g || !g.src) return `<figure class="wk-fig is-missing" data-wiki-img-missing="${esc(spec.name)}"><span class="wk-fig-none">그림 없음 — ${esc(spec.name)}</span></figure>`;
    const vars = [];
    if (spec.width) vars.push(`--fig-w:${spec.width}`);
    if (g.width) vars.push(`--fig-nat:${g.width}px`);
    const caption = g.caption || '';
    const cap = caption || g.credit ? `<figcaption>${esc(caption)}${g.credit ? `<span class="wk-fig-credit">${caption ? ' · ' : ''}${esc(g.credit)}</span>` : ''}</figcaption>` : '';
    const size = g.width && g.height ? ` width="${g.width}" height="${g.height}"` : '';
    return `<figure class="wk-fig ${pos}"${vars.length ? ` style="${vars.join(';')}"` : ''} data-wiki-img="${esc(g.uid || g.id || spec.name)}"><button type="button" class="wk-fig-img" data-wiki-zoom title="누르면 크게"><img src="${esc(g.src)}" alt="${esc(g.alt || caption || g.name || spec.name)}"${size} decoding="async"></button>${cap}</figure>`;
  };
  /** 그림 줄이기(넣을 때 · 설치할 때): 긴 변을 maxSide 이하로, 비율 그대로(자르지 않음) — webp(안 되는 브라우저면 jpeg), 품질 0.85.
      돌려주는 것: { src, width, height } — 이미 작고 바꿀 까닭이 없으면 원본 그대로(keep: true). 캔버스가 없는 곳(노드)이면 원본 그대로 */
  namu.fitImage = async (src, maxSide = 1600, { force = false } = {}) => {
    if (typeof Image === 'undefined' || typeof document === 'undefined' || typeof document.createElement !== 'function') return { src, width: 0, height: 0, keep: true };
    const img = await new Promise((res, rej) => {
      const i = new Image();
      i.onload = () => res(i);
      i.onerror = () => rej(new Error('그림을 읽지 못했습니다.'));
      i.src = src;
    });
    const W = img.naturalWidth;
    const H = img.naturalHeight;
    if (!W || !H) throw new Error('그림의 크기를 읽지 못했습니다.');
    const scale = Math.min(1, maxSide / Math.max(W, H));
    if (scale === 1 && !force && /^data:image\/(png|jpeg|webp);base64,/.test(src)) return { src, width: W, height: H, keep: true };
    const c = document.createElement('canvas');
    c.width = Math.max(1, Math.round(W * scale));
    c.height = Math.max(1, Math.round(H * scale));
    const g = c.getContext('2d');
    g.imageSmoothingQuality = 'high';
    if (!/^data:image\/(jpeg|webp)/.test(src)) {
      g.fillStyle = '#ffffff'; // 투명한 바탕(png · svg)은 흰 바탕 위에 (jpeg로 떨어져도 검게 되지 않게)
      g.fillRect(0, 0, c.width, c.height);
    }
    g.drawImage(img, 0, 0, c.width, c.height);
    const webp = c.toDataURL('image/webp', 0.85);
    return { src: webp.startsWith('data:image/webp') ? webp : c.toDataURL('image/jpeg', 0.85), width: c.width, height: c.height, keep: false };
  };

  namu.render = function (src, opts = {}) {
    const linkFn = opts.link || (() => ({}));
    const imageFn = typeof opts.image === 'function' ? opts.image : null;
    const foot = []; // { id, label, html }
    const toc = []; // { level, id, text }
    const categories = [];
    const blocks = []; // 자리표시자 → HTML
    const keep = html => {
      blocks.push(html);
      return `${blocks.length - 1}`;
    };
    const restore = html => html.replace(/(\d+)/g, (_, i) => blocks[Number(i)]);

    /* ---------- 인라인 ---------- */
    function inline(raw) {
      let s = esc(raw);
      // {{{ ... }}} 인라인 (크기·색·코드)
      s = s.replace(/\{\{\{([\s\S]*?)\}\}\}/g, (m, body) => keep(braceInline(body)));
      // [* 각주] — 대괄호 짝 맞추기
      let out = '';
      let i = 0;
      while (i < s.length) {
        if (s.startsWith('[*', i)) {
          const end = matchEnd(s, i, '[', ']');
          if (end > 0) {
            const inner = s.slice(i + 2, end - 1);
            const m = inner.match(/^(\S*)\s?([\s\S]*)$/);
            const label = m && m[1] ? m[1] : String(foot.length + 1);
            const existing = m && m[1] ? foot.find(f => f.label === m[1]) : null;
            const id = existing ? existing.id : foot.length + 1;
            if (!existing) foot.push({ id, label, html: inlineNoFoot(m ? m[2] : inner) });
            out += `<sup class="wk-fn" id="wk-rfn-${id}"><a href="#wk-fn-${id}" data-wiki-fn="${id}" title="${esc(m ? m[2].replace(/<[^>]+>/g, '') : '')}">[${esc(label)}]</a></sup>`;
            i = end;
            continue;
          }
        }
        out += s[i];
        i++;
      }
      return inlineNoFoot(out, true);
    }
    function inlineNoFoot(s, alreadyEscaped = false) {
      if (!alreadyEscaped) s = s; // 각주 안 글은 이미 이스케이프된 조각입니다
      // 링크 [[...]]
      s = s.replace(/\[\[([^\]|]+?)(?:\|([^\]]*?))?\]\]/g, (m, target, label) => {
        target = target.trim();
        const text = (label != null ? label : target.replace(/^인물\s*:\s*/, '')).trim() || target; // [[인물:이름]]은 이름만 보입니다 (인물을 가리키는 꼴 — 뷰어의 링크 해석)
        if (/^(분류|category):/i.test(target)) {
          categories.push(target.split(':')[1].trim());
          return '';
        }
        if (/^(파일|이미지|file):/i.test(target)) return '';
        if (/^https?:\/\//i.test(target) || /^\/\//.test(target)) return `<a class="wk-ext" href="${target}" target="_blank" rel="noopener noreferrer">${text}</a>`;
        const anchor = target.split('#');
        const name = anchor[0].trim();
        if (!name) return `<a class="wk-link" href="#${esc(anchor[1] || '')}">${text}</a>`;
        const r = linkFn(name) || {};
        // is-missing: 연표에 그런 항목이 없음(빨강) · is-empty: 항목은 있지만 아직 문서가 없음(점선)
        const cls = r.missing || !r.uid ? ' is-missing' : r.empty ? ' is-empty' : '';
        return `<a class="wk-link${cls}" data-wiki-link="${esc(r.uid || name)}" data-wiki-name="${esc(name)}" title="${esc(r.title || name)}${r.missing || !r.uid ? ' — 연표에 없는 항목' : r.empty ? ' — 아직 문서 없음' : ''}">${text}</a>`;
      });
      // 따옴표는 이미 &#39;로 이스케이프되어 있습니다
      s = s
        .replace(/&#39;&#39;&#39;([\s\S]+?)&#39;&#39;&#39;/g, '<b>$1</b>')
        .replace(/&#39;&#39;([\s\S]+?)&#39;&#39;/g, '<i>$1</i>')
        .replace(/~~([^~\n]+?)~~/g, '<s>$1</s>')
        .replace(/(^|[^-])--([^-\n][^\n]*?[^-\n]|[^-\n])--(?!-)/g, '$1<s>$2</s>')
        .replace(/__([^_\n]+?)__/g, '<u>$1</u>')
        .replace(/\^\^([^^\n]+?)\^\^/g, '<sup>$1</sup>')
        .replace(/,,([^,\n]+?),,/g, '<sub>$1</sub>')
        .replace(/\[br\]/gi, '<br>')
        .replace(/\[(?:date|datetime)\]/gi, () => esc(new Date().toISOString().slice(0, 10)))
        .replace(/\[age\((\d{4})-(\d{1,2})-(\d{1,2})\)\]/gi, (m, y, mo, d) => {
          const b = new Date(Number(y), Number(mo) - 1, Number(d));
          const now = new Date();
          let age = now.getFullYear() - b.getFullYear();
          if (now < new Date(now.getFullYear(), b.getMonth(), b.getDate())) age--;
          return String(age);
        })
        .replace(/\[(?:include|youtube|nicovideo|kakaotv|vimeo|navertv|ruby)\([^\]]*\)\]/gi, '')
        .replace(/\[(?:목차|tableofcontents)\]/gi, 'TOC')
        .replace(/\[(?:각주|footnote)\]/gi, 'FOOT');
      return s;
    }
    function braceInline(body) {
      // body는 이미 이스케이프된 상태
      let m;
      if ((m = body.match(/^([+-])(\d)\s([\s\S]*)$/))) return `<span class="wk-size ${m[1] === '+' ? 'p' : 'm'}${m[2]}">${inlineNoFoot(m[3])}</span>`;
      if ((m = body.match(/^#([0-9a-fA-F]{3,8}|[a-zA-Z]{3,20})(?:,#[0-9a-fA-F]{3,8})?\s([\s\S]*)$/))) {
        const color = /^[0-9a-fA-F]{3,8}$/.test(m[1]) ? `#${m[1]}` : m[1];
        if (safeColor(color)) return `<span style="color:${color}">${inlineNoFoot(m[2])}</span>`;
      }
      if (body.includes('\n')) return `<pre class="wk-pre">${body}</pre>`;
      return `<code class="wk-code">${body}</code>`;
    }

    /* ---------- 블록: {{{#!folding / #!wiki / #!syntax / 여러 줄 코드 ---------- */
    function extractBlocks(text) {
      let out = '';
      let i = 0;
      while (i < text.length) {
        const at = text.indexOf('{{{', i);
        if (at < 0) {
          out += text.slice(i);
          break;
        }
        const end = matchEnd(text, at, '{{{', '}}}');
        if (end < 0) {
          out += text.slice(i);
          break;
        }
        const body = text.slice(at + 3, end - 3);
        const head = body.match(/^#!(folding|wiki|syntax|html)\b([^\n]*)\n?([\s\S]*)$/);
        let html = null;
        if (head) {
          const kind = head[1];
          const arg = head[2].trim();
          const inner = head[3];
          if (kind === 'folding') html = `<details class="wk-fold"><summary>${inline(arg || '펼치기')}</summary><div class="wk-fold-body">${block(inner)}</div></details>`;
          else if (kind === 'wiki') {
            const st = (arg.match(/style="([^"]*)"/) || [])[1];
            html = `<div class="wk-box" style="${esc(safeStyle(st))}">${block(inner)}</div>`;
          } else if (kind === 'syntax') html = `<pre class="wk-pre" data-lang="${esc(arg)}">${esc(inner)}</pre>`;
          else html = `<pre class="wk-pre">${esc(inner)}</pre>`; // #!html은 안전을 위해 그대로 보여 줍니다
        } else if (body.includes('\n')) {
          const m = body.match(/^([+-])(\d)\s([\s\S]*)$/);
          html = m ? `<div class="wk-size ${m[1] === '+' ? 'p' : 'm'}${m[2]}">${block(m[3])}</div>` : `<pre class="wk-pre">${esc(body)}</pre>`;
        }
        if (html == null) {
          out += text.slice(i, end); // 인라인 {{{ }}}는 inline()이 처리
        } else out += text.slice(i, at) + keep(html);
        i = end;
      }
      return out;
    }

    /* ---------- 표 ---------- */
    function table(lines) {
      // 셀이 여러 줄이면 ||로 끝나지 않은 줄을 다음 줄과 잇습니다
      const rows = [];
      let cur = '';
      for (const l of lines) {
        cur = cur ? `${cur}\n${l}` : l;
        if (cur.trimEnd().endsWith('||')) {
          rows.push(cur);
          cur = '';
        }
      }
      if (cur) rows.push(cur);
      const tableAttr = { style: '', align: '' };
      let html = '';
      const rowspans = [];
      for (const r of rows) {
        let cells = r.trim().slice(2, -2).split('||');
        let rowStyle = '';
        let tds = '';
        for (let ci = 0; ci < cells.length; ci++) {
          let cell = cells[ci];
          const attrs = { colspan: 1, rowspan: 1, style: '', align: '' };
          let m;
          while ((m = cell.match(/^<([^<>\n]*)>/))) {
            const opt = m[1].trim();
            cell = cell.slice(m[0].length);
            let mm;
            if ((mm = opt.match(/^-(\d+)$/))) attrs.colspan = Number(mm[1]);
            else if ((mm = opt.match(/^\|(\d+)$/))) attrs.rowspan = Number(mm[1]);
            else if ((mm = opt.match(/^(?:\^\||v\|)(\d+)$/))) attrs.rowspan = Number(mm[1]);
            else if (opt === '(') attrs.align = 'left';
            else if (opt === ':') attrs.align = 'center';
            else if (opt === ')') attrs.align = 'right';
            else if ((mm = opt.match(/^bgcolor=(.+)$/i)) && safeColor(mm[1])) attrs.style += `background:${mm[1]};`;
            else if ((mm = opt.match(/^color=(.+)$/i)) && safeColor(mm[1])) attrs.style += `color:${mm[1]};`;
            else if ((mm = opt.match(/^width=(\d+%?|\d+px)$/i))) attrs.style += `width:${mm[1]};`;
            else if ((mm = opt.match(/^height=(\d+%?|\d+px)$/i))) attrs.style += `height:${mm[1]};`;
            else if ((mm = opt.match(/^rowbgcolor=(.+)$/i)) && safeColor(mm[1])) rowStyle += `background:${mm[1]};`;
            else if ((mm = opt.match(/^rowcolor=(.+)$/i)) && safeColor(mm[1])) rowStyle += `color:${mm[1]};`;
            else if ((mm = opt.match(/^table\s*bgcolor=(.+)$/i)) && safeColor(mm[1])) tableAttr.style += `background:${mm[1]};`;
            else if ((mm = opt.match(/^table\s*bordercolor=(.+)$/i)) && safeColor(mm[1])) tableAttr.style += `border-color:${mm[1]};`;
            else if ((mm = opt.match(/^table\s*width=(\d+%?|\d+px)$/i))) tableAttr.style += `width:${mm[1]};`;
            else if ((mm = opt.match(/^table\s*align=(left|center|right)$/i))) tableAttr.align = mm[1];
            else if (/^(nopad|table)/i.test(opt)) {
              /* 무시 */
            } else {
              cell = m[0] + cell; // 옵션이 아니면 글자로 되돌립니다
              break;
            }
          }
          // 앞뒤 공백으로 정렬 (나무위키 관행)
          if (!attrs.align) {
            const l = /^\s/.test(cell);
            const rr = /\s$/.test(cell);
            attrs.align = l && rr ? 'center' : l ? 'right' : '';
          }
          const style = `${attrs.style}${attrs.align ? `text-align:${attrs.align};` : ''}`;
          tds += `<td${attrs.colspan > 1 ? ` colspan="${attrs.colspan}"` : ''}${attrs.rowspan > 1 ? ` rowspan="${attrs.rowspan}"` : ''}${style ? ` style="${esc(style)}"` : ''}>${inline(cell.trim()).replace(/\n/g, '<br>')}</td>`;
        }
        html += `<tr${rowStyle ? ` style="${esc(rowStyle)}"` : ''}>${tds}</tr>`;
      }
      return `<div class="wk-table-wrap${tableAttr.align ? ` is-${tableAttr.align}` : ''}"><table class="wk-table"${tableAttr.style ? ` style="${esc(tableAttr.style)}"` : ''}>${html}</table></div>`;
    }

    /* ---------- 블록 ---------- */
    function block(text) {
      const lines = extractBlocks(String(text).replace(/\r\n?/g, '\n')).split('\n');
      let html = '';
      let para = [];
      const flush = () => {
        if (para.length) html += `<p>${para.map(l => inline(l)).join('<br>')}</p>`;
        para = [];
      };
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        let m;
        if (!line.trim()) {
          flush();
          continue;
        }
        // 한 줄이 통째로 블록(접기·상자·코드) 자리표시자이거나 [각주]·[목차]면 문단 밖에 둡니다
        if (/^\s*\d+\s*$/.test(line)) {
          flush();
          html += line.trim();
          continue;
        }
        if (/^\s*\[(각주|footnote)\]\s*$/i.test(line)) {
          flush();
          html += 'FOOT';
          continue;
        }
        if (/^\s*\[(목차|tableofcontents)\]\s*$/i.test(line)) {
          flush();
          html += 'TOC';
          continue;
        }
        if ((m = line.match(/^(={1,6})(#?) (.+?) \2\1\s*$/))) {
          flush();
          const level = m[1].length;
          const id = slug(m[3], toc.length + 1);
          toc.push({ level, id, text: m[3].replace(/\[\[([^\]|]+?)(?:\|([^\]]*?))?\]\]/g, (a, t, l) => l || t) });
          html += `<h${Math.min(level + 1, 6)} class="wk-h" id="${id}"><span class="wk-hnum" data-toc="${toc.length}"></span>${inline(m[3])}</h${Math.min(level + 1, 6)}>`;
          continue;
        }
        if (/^-{4,9}\s*$/.test(line)) {
          flush();
          html += '<hr class="wk-hr">';
          continue;
        }
        if (/^\s*\|\|/.test(line)) {
          flush();
          const tl = [];
          while (i < lines.length && (/^\s*\|\|/.test(lines[i]) || (tl.length && !tl[tl.length - 1].trimEnd().endsWith('||')))) tl.push(lines[i++]);
          i--;
          html += table(tl);
          continue;
        }
        if (/^>/.test(line)) {
          flush();
          const ql = [];
          while (i < lines.length && /^>/.test(lines[i])) ql.push(lines[i++].replace(/^>\s?/, ''));
          i--;
          html += `<blockquote class="wk-quote">${block(ql.join('\n'))}</blockquote>`;
          continue;
        }
        if ((m = line.match(/^( +)(\*|1\.(?:#\d+)?|a\.|A\.|i\.|I\.)\s?(.*)$/))) {
          flush();
          const items = [];
          while (i < lines.length && (m = lines[i].match(/^( +)(\*|1\.(?:#\d+)?|a\.|A\.|i\.|I\.)\s?(.*)$/))) {
            items.push({ indent: m[1].length, marker: m[2], text: m[3] });
            i++;
            // 들여쓴 이어지는 줄은 같은 항목의 계속
            while (i < lines.length && /^ {2,}\S/.test(lines[i]) && !/^( +)(\*|1\.(?:#\d+)?|a\.|A\.|i\.|I\.)\s?/.test(lines[i])) items[items.length - 1].text += `\n${lines[i++].trim()}`;
          }
          i--;
          html += list(items);
          continue;
        }
        if (imageFn && /\[\[(?:파일|이미지|file)\s*:/i.test(line)) {
          // 문서 그림: 그 줄 앞에서 문단을 끊고 그림을 놓은 뒤, 그림 고리를 뺀 나머지 글을 새 문단으로 이어 씁니다
          flush();
          const rest = line.replace(FILE_RE, (m, inner) => {
            const spec = namu.fileSpec(inner);
            html += namu.figureHTML(spec, spec.name ? imageFn(spec.name) : null);
            return '';
          });
          if (rest.trim()) para.push(rest);
          continue;
        }
        para.push(line);
      }
      flush();
      return html;
    }
    function list(items) {
      let html = '';
      const stack = []; // { indent, tag }
      const typeOf = mk => (mk === '*' ? 'ul' : mk.startsWith('a') ? 'ol type="a"' : mk.startsWith('A') ? 'ol type="A"' : mk.startsWith('i') ? 'ol type="i"' : mk.startsWith('I') ? 'ol type="I"' : 'ol');
      for (const it of items) {
        while (stack.length && stack[stack.length - 1].indent > it.indent) html += `</li></${stack.pop().tag}>`;
        // 같은 깊이인데 목록 종류가 바뀌면(* → 1.) 새 목록을 시작합니다
        if (stack.length && stack[stack.length - 1].indent === it.indent && stack[stack.length - 1].tag !== typeOf(it.marker).split(' ')[0]) html += `</li></${stack.pop().tag}>`;
        if (!stack.length || stack[stack.length - 1].indent < it.indent) {
          const tag = typeOf(it.marker);
          const start = (it.marker.match(/#(\d+)/) || [])[1];
          html += `<${tag}${start ? ` start="${start}"` : ''} class="wk-list">`;
          stack.push({ indent: it.indent, tag: tag.split(' ')[0] });
        } else html += '</li>';
        html += `<li>${inline(it.text).replace(/\n/g, '<br>')}`;
      }
      while (stack.length) html += `</li></${stack.pop().tag}>`;
      return html;
    }

    let html = block(src || '');
    /* 목차 번호 */
    /* 목차 번호는 문서에서 가장 큰 제목 단계를 1로 잡습니다 (== ==로 시작하면 1. 2. 3.) */
    const counters = [];
    const minL = toc.length ? Math.min(...toc.map(h => h.level)) : 1;
    toc.forEach(h => {
      const lv = h.level - minL + 1;
      h.lv = lv;
      counters.length = lv;
      counters[lv - 1] = (counters[lv - 1] || 0) + 1;
      for (let k = 0; k < lv - 1; k++) counters[k] = counters[k] || 1;
      h.num = counters.slice(0, lv).join('.');
    });
    const tocHtml = toc.length
      ? `<nav class="wk-toc"><b>목차</b><ol>${toc.map(h => `<li class="lv${h.lv}"><a href="#${h.id}" data-wiki-anchor="${h.id}"><span>${h.num}.</span> ${esc(h.text)}</a></li>`).join('')}</ol></nav>`
      : '';
    html = html.replace(/<span class="wk-hnum" data-toc="(\d+)"><\/span>/g, (m, n) => `<span class="wk-hnum">${toc[Number(n) - 1].num}.</span> `);
    const footHtml = foot.length
      ? `<ol class="wk-footnotes">${foot.map(f => `<li id="wk-fn-${f.id}"><a href="#wk-rfn-${f.id}" data-wiki-anchor="wk-rfn-${f.id}">[${esc(f.label)}]</a> ${f.html}</li>`).join('')}</ol>`
      : '';
    const hasFootTag = html.includes('FOOT');
    html = html.replace(/TOC/g, () => tocHtml).replace(/FOOT/g, () => footHtml);
    if (!hasFootTag && footHtml) html += footHtml;
    if (categories.length) html += `<div class="wk-cats">분류: ${categories.map(c => `<span>${esc(c)}</span>`).join(' · ')}</div>`;
    return { html: restore(restore(html)), toc, categories };
  };

  /** 문서 안의 [[링크]] 이름 목록 (역링크용) */
  namu.links = src => {
    const out = new Set();
    String(src || '').replace(/\[\[([^\]|]+?)(?:\|[^\]]*?)?\]\]/g, (m, t) => {
      const name = t.split('#')[0].trim();
      if (name && !/^(분류|파일|이미지|category|file|https?:)/i.test(name)) out.add(name);
      return m;
    });
    return [...out];
  };

  /** 문법 도움말 (작은 창) */
  namu.HELP = `== 제목 == (=의 개수로 단계, 2~6개)
'''굵게''' ''기울임'' ~~취소~~ __밑줄__ ^^위첨자^^ ,,아래첨자,,
[[다른 문서]] · [[문서|표시할 글자]] · [[https://…|바깥 링크]]
[[조선/역사]] 하위 문서 · [[/역사]] 지금 문서의 하위 문서 · [[김홍집 내각]] 내각·지도자·연호 칸 문서
[* 각주 내용] · [*가 이름 있는 각주] · [각주] 자리에 각주 목록
 * 목록 (앞에 띄어쓰기 한 칸 이상)
 1. 번호 목록 · 1.#5 5부터
> 인용문
---- 가로줄
|| 칸 || 칸 || (표) · <-2> 가로 합치기 · <|2> 세로 합치기 · <bgcolor=#eee> 배경 · <(> <:> <)> 정렬
{{{#!folding 제목
접히는 내용 }}}
{{{+2 크게}}} {{{-1 작게}}} {{{#red 빨강}}} {{{코드}}}
[목차] [br] [age(1900-01-01)] [date]
[[분류:이름]] 문서 분류
[[파일:그림 이름]] 문서 그림 (오른쪽에 띄움) · |align=center 가운데 · |width=50% 크기`;
  namu.SHORTCUTS = [
    ['Ctrl+B', '굵게'], ['Ctrl+I', '기울임'], ['Ctrl+U', '밑줄'], ['Ctrl+D', '취소선'], ['Ctrl+K', '[[링크]] (이름 자동 완성)'], ['Ctrl+Shift+K', '바깥 링크'],
    ['Ctrl+1 · 2 · 3', '== 제목 == · === === · ==== ===='], ['Ctrl+L', ' * 목록'], ['Ctrl+Shift+L', ' 1. 번호 목록'], ['Ctrl+Q', '> 인용'],
    ['Ctrl+Shift+F', '[* 각주]'], ['Ctrl+Shift+T', '|| 표 ||'], ['Ctrl+Shift+D', '{{{#!folding 접기}}}'], ['Ctrl+E', '{{{코드}}}'], ['Ctrl+S', '저장'],
    ['[[ 입력', '연표의 시대·사건·민족·칸 이름 자동 완성 (↑↓ Enter)'], ['Tab · Shift+Tab', '목록 들여쓰기 · 내어쓰기'], ['Enter', '목록·인용 줄에서 다음 줄도 이어 감 (빈 항목에서 Enter면 끝)'],
  ];
  namu.showHelp = () => {
    let dlg = document.querySelector('#wikiHelpDialog');
    if (!dlg) {
      dlg = document.createElement('dialog');
      dlg.id = 'wikiHelpDialog';
      dlg.innerHTML = `<div class="dlg"><div class="dlg-head"><h2>위키 문법 · 편집 단축키</h2><button class="icon-btn" data-close aria-label="닫기">✕</button></div><div class="dlg-body wk-help-body"><h3>단축키</h3><table class="wk-keys">${namu.SHORTCUTS.map(([k, d]) => `<tr><td><kbd>${esc(k)}</kbd></td><td>${esc(d)}</td></tr>`).join('')}</table><h3>문법</h3><pre class="wk-pre wk-help">${esc(namu.HELP)}</pre></div></div>`;
      dlg.addEventListener('click', e => (e.target === dlg || e.target.closest('[data-close]')) && dlg.close());
      document.body.appendChild(dlg);
    }
    dlg.showModal();
  };

  /* ---------- 편집기: 문법 단축키 · 툴바 · [[ 자동 완성 ----------
   * namu.editor(textarea, { names: () => [문서 이름…], onSave, onChange }) → { insert(kind), destroy() }
   * namu.toolbarHTML() → 툴바 단추 (data-wiki-insert). 툴바 요소를 opts.toolbar로 넘기면 단추 클릭도 처리합니다. */
  const SNIP = {
    h2: ['== ', ' =='], h3: ['=== ', ' ==='], h4: ['==== ', ' ===='],
    b: ["'''", "'''"], i: ["''", "''"], s: ['~~', '~~'], u: ['__', '__'], sup: ['^^', '^^'], sub: [',,', ',,'],
    link: ['[[', ']]'], ext: ['[[https://', '|링크 이름]]'], fn: ['[* ', ']'], code: ['{{{', '}}}'],
    table: ['|| 칸 || 칸 ||\n|| 칸 || 칸 ||', ''], fold: ['{{{#!folding 제목\n', '\n}}}'], list: [' * ', ''], olist: [' 1. ', ''], quote: ['> ', ''],
    hr: ['----', ''], toc: ['[목차]', ''], big: ['{{{+1 ', '}}}'], small: ['{{{-1 ', '}}}'], color: ['{{{#c0392b ', '}}}'], br: ['[br]', ''],
  };
  const LINE_KINDS = { list: ' * ', olist: ' 1. ', quote: '> ', h2: null, h3: null, h4: null };
  const PLACEHOLDER = { link: '문서 이름', h2: '제목', h3: '제목', h4: '제목', b: '굵게', i: '기울임', fn: '각주 내용', code: '코드' };
  const TOOLBAR = [
    ['h2', '제목', 'Ctrl+1'], ['b', '<b>굵게</b>', 'Ctrl+B'], ['i', '<i>기울임</i>', 'Ctrl+I'], ['u', '<u>밑줄</u>', 'Ctrl+U'], ['s', '<s>취소</s>', 'Ctrl+D'],
    ['link', '[[링크]]', 'Ctrl+K'], ['fn', '각주', 'Ctrl+Shift+F'], ['list', '목록', 'Ctrl+L'], ['olist', '1. 번호', 'Ctrl+Shift+L'], ['quote', '인용', 'Ctrl+Q'],
    ['table', '표', 'Ctrl+Shift+T'], ['fold', '접기', 'Ctrl+Shift+D'], ['code', '코드', 'Ctrl+E'], ['toc', '목차', ''], ['hr', '가로줄', ''],
  ];
  /* image: 문서 그림 단추('표' 옆 — 메이커의 문서 편집기만, js/maker-images.js가 opts.onImage로 받음) */
  namu.toolbarHTML = ({ compact = false, image = false } = {}) =>
    TOOLBAR.filter(([k]) => !compact || !['toc', 'hr', 'code'].includes(k))
      .map(([k, label, key]) => `<button type="button" class="btn btn-sm wk-tb" data-wiki-insert="${k}" title="${esc((SNIP[k][0] + SNIP[k][1]).replace(/\n/g, ' ').trim())}${key ? ` (${key})` : ''}">${label}</button>` + (image && k === 'table' ? '<button type="button" class="btn btn-sm wk-tb" data-wiki-image title="그림 넣기 — 파일을 골라 줄여 담고 커서 자리에 [[파일:이름]] (글 칸에 끌어다 놓거나 붙여넣어도 됨)">그림</button>' : ''))
      .join('') + `<button type="button" class="btn btn-sm wk-tb" data-wiki-help title="문법과 단축키">?</button>`;

  namu.editor = function (ta, opts = {}) {
    const names = typeof opts.names === 'function' ? opts.names : () => opts.names || [];
    ta.htNamuOpts = opts; // 큰 입력 창(js/fieldpop.js)이 이 칸을 크게 열 때 같은 이름 목록으로 편집기를 붙이도록 남겨 둡니다
    /* 자동 완성 상자와 재는 거울은 칸이 든 대화상자 안에 (모달 대화상자는 맨 위 층이라 body에 붙이면 그 아래에 깔림) */
    const host = () => ta.closest('dialog') || ta.ownerDocument.body;
    const fire = () => {
      ta.dispatchEvent(new Event('input', { bubbles: true }));
      if (opts.onChange) opts.onChange(ta.value);
    };
    const lineRange = (s, e) => {
      const a = ta.value.lastIndexOf('\n', s - 1) + 1;
      let b = ta.value.indexOf('\n', e);
      if (b < 0) b = ta.value.length;
      return [a, b];
    };
    /** 문법 넣기: 줄 단위 문법은 선택한 줄들 앞에 붙이거나(이미 있으면) 떼고, 나머지는 선택 글자를 감쌉니다 */
    function insert(kind) {
      const [a, b] = SNIP[kind] || ['', ''];
      let s = ta.selectionStart;
      let e = ta.selectionEnd;
      if (kind in LINE_KINDS) {
        const [ls, le] = lineRange(s, e);
        const lines = ta.value.slice(ls, le).split('\n');
        let out;
        if (LINE_KINDS[kind]) {
          const mark = LINE_KINDS[kind];
          const re = kind === 'quote' ? /^>\s?/ : kind === 'list' ? /^ +\* ?/ : /^ +1\. ?/;
          const allOn = lines.every(l => re.test(l));
          out = lines.map(l => (allOn ? l.replace(re, '') : re.test(l) ? l : mark + l));
        } else {
          const level = { h2: 2, h3: 3, h4: 4 }[kind];
          const eq = '='.repeat(level);
          out = lines.map(l => {
            const m = l.match(/^(={2,6})\s(.*?)\s\1\s*$/);
            const text = m ? m[2] : l.trim() || PLACEHOLDER[kind];
            return m && m[1].length === level ? text : `${eq} ${text} ${eq}`;
          });
        }
        const joined = out.join('\n');
        ta.setRangeText(joined, ls, le, 'select');
        if (lines.length === 1 && !LINE_KINDS[kind] && /^={2,6} /.test(joined)) {
          const level = { h2: 2, h3: 3, h4: 4 }[kind];
          ta.setSelectionRange(ls + level + 1, ls + joined.length - level - 1); // 제목 글자만 선택
        }
      } else if (kind === 'table' || kind === 'hr' || kind === 'toc' || kind === 'fold') {
        const [ls] = lineRange(s, s);
        const atLineStart = s === ls;
        const sel = ta.value.slice(s, e);
        const text = kind === 'fold' ? `${a}${sel || '접히는 내용'}${b}` : a;
        const pre = atLineStart ? '' : '\n';
        ta.setRangeText(pre + text + '\n', s, e, 'end');
        if (kind === 'fold') ta.setSelectionRange(s + pre.length + 12, s + pre.length + 14);
      } else {
        const sel = ta.value.slice(s, e);
        const inner = sel || PLACEHOLDER[kind] || '';
        ta.setRangeText(a + inner + b, s, e, 'preserve');
        ta.setSelectionRange(s + a.length, s + a.length + inner.length);
        if (kind === 'link' && !sel) openAc(s + a.length);
      }
      ta.focus();
      fire();
    }

    /* [[ 자동 완성 */
    let ac = null; // { box, from, items, idx }
    const acBox = document.createElement('div');
    acBox.className = 'wk-ac';
    acBox.hidden = true;
    host().appendChild(acBox);
    const caretXY = pos => {
      const mirror = document.createElement('div');
      const cs = getComputedStyle(ta);
      for (const k of ['fontFamily', 'fontSize', 'fontWeight', 'lineHeight', 'letterSpacing', 'paddingTop', 'paddingLeft', 'paddingRight', 'borderLeftWidth', 'borderTopWidth', 'boxSizing', 'tabSize']) mirror.style[k] = cs[k];
      Object.assign(mirror.style, { position: 'absolute', visibility: 'hidden', whiteSpace: 'pre-wrap', wordBreak: 'break-word', overflowWrap: 'anywhere', top: '0', left: '0', width: `${ta.clientWidth}px` });
      mirror.textContent = ta.value.slice(0, pos);
      const span = document.createElement('span');
      span.textContent = ta.value.slice(pos, pos + 1) || '.';
      mirror.appendChild(span);
      host().appendChild(mirror);
      const r = ta.getBoundingClientRect();
      const xy = { x: r.left + span.offsetLeft - ta.scrollLeft, y: r.top + span.offsetTop - ta.scrollTop + parseFloat(cs.lineHeight || '18') };
      mirror.remove();
      return xy;
    };
    function openAc(from) {
      ac = { from, items: [], idx: 0 };
      updateAc();
    }
    function closeAc() {
      ac = null;
      acBox.hidden = true;
    }
    function updateAc() {
      if (!ac) return;
      const pos = ta.selectionStart;
      const typed = ta.value.slice(ac.from, pos);
      if (pos < ac.from || /[\]\n|]/.test(typed) || ta.value.slice(ac.from - 2, ac.from) !== '[[') return closeAc();
      const q = typed.trim().toLowerCase();
      const all = names();
      const list = (q ? all.filter(n => String(n).toLowerCase().includes(q)) : all).slice(0, 8);
      // 앞글자 일치를 앞에
      list.sort((x, y) => (String(y).toLowerCase().startsWith(q) ? 1 : 0) - (String(x).toLowerCase().startsWith(q) ? 1 : 0));
      ac.items = list;
      ac.idx = 0;
      if (!list.length) {
        acBox.hidden = true;
        return;
      }
      acBox.innerHTML = list.map((n, i) => `<button type="button" class="wk-ac-item${i === 0 ? ' is-active' : ''}" data-i="${i}">${esc(n)}</button>`).join('');
      acBox.hidden = false;
      const { x, y } = caretXY(pos);
      acBox.style.left = `${Math.min(x, innerWidth - acBox.offsetWidth - 8)}px`;
      acBox.style.top = `${y + acBox.offsetHeight > innerHeight ? y - acBox.offsetHeight - 22 : y + 4}px`;
    }
    function pickAc(i) {
      if (!ac || !ac.items[i]) return;
      const name = ac.items[i];
      const pos = ta.selectionStart;
      const after = ta.value.slice(pos, pos + 2) === ']]' ? 2 : 0;
      ta.setRangeText(`${name}]]`, ac.from, pos + after, 'end');
      closeAc();
      ta.focus();
      fire();
    }
    acBox.addEventListener('mousedown', e => e.preventDefault());
    acBox.addEventListener('click', e => {
      const b = e.target.closest('[data-i]');
      if (b) pickAc(Number(b.dataset.i));
    });

    const onKey = e => {
      if (ac && !acBox.hidden) {
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
          e.preventDefault();
          ac.idx = (ac.idx + (e.key === 'ArrowDown' ? 1 : -1) + ac.items.length) % ac.items.length;
          acBox.querySelectorAll('.wk-ac-item').forEach((el, i) => el.classList.toggle('is-active', i === ac.idx));
          return;
        }
        if (e.key === 'Enter' || e.key === 'Tab') {
          e.preventDefault();
          return pickAc(ac.idx);
        }
        if (e.key === 'Escape') {
          e.preventDefault();
          return closeAc();
        }
      }
      const ctrl = e.ctrlKey || e.metaKey;
      const k = e.key.toLowerCase();
      if (ctrl) {
        const map = e.shiftKey
          ? { k: 'ext', f: 'fn', t: 'table', d: 'fold', l: 'olist' }
          : { b: 'b', i: 'i', u: 'u', d: 's', k: 'link', l: 'list', q: 'quote', e: 'code', 1: 'h2', 2: 'h3', 3: 'h4' };
        if (map[k]) {
          e.preventDefault();
          return insert(map[k]);
        }
        if (k === 's' && !e.shiftKey && opts.onSave) {
          e.preventDefault();
          return opts.onSave();
        }
        return;
      }
      if (e.key === 'Tab') {
        const s = ta.selectionStart;
        const [ls, le] = lineRange(s, ta.selectionEnd);
        const lines = ta.value.slice(ls, le).split('\n');
        const isList = lines.every(l => /^ +(\*|1\.)/.test(l));
        e.preventDefault();
        if (isList) {
          const out = lines.map(l => (e.shiftKey ? l.replace(/^ /, '') : ` ${l}`)).join('\n');
          ta.setRangeText(out, ls, le, 'select');
          if (ta.selectionEnd - ta.selectionStart <= out.length && lines.length === 1) ta.setSelectionRange(Math.max(ls, s + (e.shiftKey ? -1 : 1)), Math.max(ls, s + (e.shiftKey ? -1 : 1)));
        } else if (!e.shiftKey) ta.setRangeText('  ', s, ta.selectionEnd, 'end');
        return fire();
      }
      if (e.key === 'Enter' && !e.shiftKey && !e.altKey) {
        // Alt+Enter는 큰 입력 창 (목록 이어쓰기가 먹지 않게)
        const s = ta.selectionStart;
        const [ls] = lineRange(s, s);
        const line = ta.value.slice(ls, s);
        const m = line.match(/^( +)(\*|1\.)\s?(.*)$/) || line.match(/^(>)\s?(.*)$/);
        if (m) {
          e.preventDefault();
          const empty = m.length === 4 ? !m[3].trim() : !m[2].trim();
          if (empty) {
            ta.setRangeText('', ls, s, 'end'); // 빈 항목에서 Enter → 목록 끝
          } else {
            const prefix = m.length === 4 ? `${m[1]}${m[2]} ` : '> ';
            ta.setRangeText(`\n${prefix}`, s, ta.selectionEnd, 'end');
          }
          return fire();
        }
      }
    };
    const onInput = e => {
      if (e.htMirror) {
        // 큰 입력 창이 비춰 준 글 — 자동 완성은 그 창에서 열리므로 여기서는 열지 않습니다
        if (opts.onChange) opts.onChange(ta.value);
        return;
      }
      const pos = ta.selectionStart;
      if (e.inputType === 'insertText' && e.data === '[' && ta.value.slice(pos - 2, pos) === '[[' && ta.value.slice(pos, pos + 2) !== ']]') {
        ta.setRangeText(']]', pos, pos, 'start');
        openAc(pos);
      } else if (e.inputType === 'insertText' && e.data === '{' && ta.value.slice(pos - 3, pos) === '{{{' && ta.value.slice(pos, pos + 3) !== '}}}') {
        ta.setRangeText('}}}', pos, pos, 'start');
      } else {
        /* 커서가 닫히지 않은 [[ 안에 있으면(붙여넣기·한글 조합 입력 포함) 자동 완성을 엽니다 */
        const lineStart = ta.value.lastIndexOf('\n', pos - 1) + 1;
        const before = ta.value.slice(lineStart, pos);
        const m = before.match(/\[\[([^\]\n|]*)$/);
        if (m) {
          const from = pos - m[1].length;
          if (!ac || ac.from !== from) openAc(from);
          else updateAc();
        } else if (ac) closeAc();
      }
      if (opts.onChange) opts.onChange(ta.value);
    };
    const onBlur = () => setTimeout(closeAc, 120);
    const onTb = e => {
      const b = e.target.closest('[data-wiki-insert],[data-wiki-help],[data-wiki-image]');
      if (!b) return;
      e.preventDefault();
      if ('wikiHelp' in b.dataset) return namu.showHelp();
      if ('wikiImage' in b.dataset) return opts.onImage && opts.onImage();
      insert(b.dataset.wikiInsert);
    };
    ta.addEventListener('keydown', onKey);
    ta.addEventListener('input', onInput);
    ta.addEventListener('blur', onBlur);
    if (opts.toolbar) opts.toolbar.addEventListener('click', onTb);
    /** 커서 자리에 글 한 줄을 넣습니다(앞뒤 줄과 붙어 있으면 줄을 바꿔 — 문서 그림 [[파일:이름]] 줄) */
    function insertLine(text) {
      const s = ta.selectionStart;
      const e = ta.selectionEnd;
      const before = ta.value.slice(0, s);
      const after = ta.value.slice(e);
      const pre = before && !before.endsWith('\n') ? '\n' : '';
      const post = after.startsWith('\n') ? '' : '\n';
      ta.setRangeText(pre + text + post, s, e, 'end');
      ta.focus();
      fire();
    }
    return {
      insert,
      insertLine,
      textarea: ta,
      destroy() {
        ta.removeEventListener('keydown', onKey);
        ta.removeEventListener('input', onInput);
        ta.removeEventListener('blur', onBlur);
        if (opts.toolbar) opts.toolbar.removeEventListener('click', onTb);
        acBox.remove();
        if (ta.htNamuOpts === opts) delete ta.htNamuOpts;
      },
    };
  };
  /** 폼 안의 문서 칸(textarea[name=wiki])에 툴바와 편집기를 붙입니다. 폼이 다시 그려질 때마다 호출해도 됩니다 */
  namu.attach = (form, opts = {}) => {
    const ta = form.querySelector('textarea[name="wiki"]');
    if (!ta || ta.dataset.wkEditor) return null;
    ta.dataset.wkEditor = '1';
    const bar = document.createElement('div');
    bar.className = 'wiki-toolbar is-inline';
    bar.innerHTML = namu.toolbarHTML({ compact: true });
    ta.parentNode.insertBefore(bar, ta);
    return namu.editor(ta, Object.assign({ toolbar: bar }, opts));
  };
})();
