import { Marked } from 'marked';
import { markedHighlight } from 'marked-highlight';
import markedKatex from 'marked-katex-extension';
import hljs from 'highlight.js/lib/common';
import DOMPurify from 'dompurify';
import { EditorView, keymap, drawSelection, placeholder } from '@codemirror/view';
import { EditorState, EditorSelection } from '@codemirror/state';
import { history, historyKeymap, defaultKeymap, indentWithTab } from '@codemirror/commands';
import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import { syntaxHighlighting, HighlightStyle, indentOnInput } from '@codemirror/language';
import { search, searchKeymap, openSearchPanel, highlightSelectionMatches } from '@codemirror/search';
import { tags as t } from '@lezer/highlight';
import { mockNative } from './mock.js';

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

const hasBridge = !!window.webkit?.messageHandlers?.bridge;
const native = (cmd, args = {}) =>
  hasBridge ? window.webkit.messageHandlers.bridge.postMessage({ cmd, args }) : mockNative(cmd, args);

const DEFAULT_PREFS = { font: 'sans', size: 16, width: 'medium' };

const S = {
  path: '',
  home: '',
  content: '',
  mtime: 0,
  mode: 'read',
  isMarkdown: true,
  dirty: false,
  saving: false,
  prefs: { ...DEFAULT_PREFS },
};

// ---------- paths ----------

const basename = (p) => p.split('/').filter(Boolean).pop() || p;
const dirname = (p) => p.replace(/\/[^/]*$/, '') || '/';
const MD_EXT = /\.(md|markdown|mdown|mkdn?|mdx)$/i;
const PLAIN_EXT = new Set(['txt', 'text', 'log', 'csv', 'tsv']);
const stripExt = (name) => name.replace(MD_EXT, '');
const extOf = (p) => (basename(p).match(/\.([^.]+)$/) || [])[1]?.toLowerCase() || '';
const isMarkdownPath = (p) => MD_EXT.test(p);
const fileUrl = (p) => 'file://' + p.split('/').map(encodeURIComponent).join('/');
const prettyPath = (p) => (S.home && p.startsWith(S.home) ? '~' + p.slice(S.home.length) : p);

function normalize(path) {
  const out = [];
  for (const part of path.split('/')) {
    if (!part || part === '.') continue;
    if (part === '..') out.pop();
    else out.push(part);
  }
  return '/' + out.join('/');
}

function resolvePath(fromDir, rel) {
  let r = rel;
  try { r = decodeURIComponent(rel); } catch {}
  if (r.startsWith('file://')) r = r.slice(7);
  if (r.startsWith('~/') && S.home) return normalize(S.home + r.slice(1));
  return normalize(r.startsWith('/') ? r : fromDir + '/' + r);
}

const escapeHtml = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

// ---------- markdown ----------

const marked = new Marked(
  markedHighlight({
    emptyLangClass: 'hljs',
    langPrefix: 'hljs language-',
    highlight(code, lang) {
      try {
        return hljs.getLanguage(lang) ? hljs.highlight(code, { language: lang }).value : hljs.highlightAuto(code).value;
      } catch {
        return escapeHtml(code);
      }
    },
  }),
  markedKatex({ throwOnError: false, nonStandard: true, output: 'htmlAndMathml' }),
  { gfm: true }
);

function splitFrontmatter(src) {
  const m = src.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  if (!m) return { body: src, fm: null };
  const fm = [];
  for (const line of m[1].split(/\r?\n/)) {
    const kv = line.match(/^([\w.-]+):\s*(.*)$/);
    if (kv) fm.push([kv[1], kv[2].replace(/^["']|["']$/g, '')]);
  }
  return { body: src.slice(m[0].length), fm };
}

const slugify = (text) => text.toLowerCase().trim().replace(/[^\w\s-]/g, '').replace(/\s+/g, '-') || 'section';

function renderInto(target, src) {
  const { body, fm } = splitFrontmatter(src);
  const frag = DOMPurify.sanitize(marked.parse(body), { RETURN_DOM_FRAGMENT: true });
  const dir = dirname(S.path);

  if (fm && fm.length) {
    const box = document.createElement('dl');
    box.className = 'frontmatter';
    for (const [k, v] of fm) {
      const dt = document.createElement('dt');
      dt.textContent = k;
      const dd = document.createElement('dd');
      dd.textContent = v;
      box.append(dt, dd);
    }
    frag.prepend(box);
  }

  const used = {};
  for (const h of frag.querySelectorAll('h1,h2,h3,h4,h5,h6')) {
    let id = slugify(h.textContent);
    id = used[id] ? `${id}-${used[id]++}` : ((used[id] = 1), id);
    h.id = id;
  }

  for (const img of frag.querySelectorAll('img[src]')) {
    const src = img.getAttribute('src');
    if (!/^(https?:|data:)/i.test(src)) img.src = fileUrl(resolvePath(dir, src));
  }

  for (const pre of frag.querySelectorAll('pre')) {
    const lang = (pre.querySelector('code')?.className.match(/language-([\w+#-]+)/) || [])[1];
    const wrap = document.createElement('div');
    wrap.className = 'codeblock';
    pre.replaceWith(wrap);
    const head = document.createElement('div');
    head.className = 'codeblock-head';
    head.innerHTML = `<span>${lang && lang !== 'undefined' ? escapeHtml(lang) : ''}</span><button class="copy">Copy</button>`;
    wrap.append(head, pre);
  }

  for (const table of frag.querySelectorAll('table')) {
    const wrap = document.createElement('div');
    wrap.className = 'table-wrap';
    table.replaceWith(wrap);
    wrap.append(table);
  }

  frag.querySelectorAll('input[type=checkbox]').forEach((box, i) => {
    box.removeAttribute('disabled');
    box.dataset.task = i;
    box.closest('li')?.classList.add('task');
  });

  target.replaceChildren(frag);
}

function renderSource(target, src) {
  const ext = extOf(S.path);
  const lang = !PLAIN_EXT.has(ext) && hljs.getLanguage(ext) ? ext : null;
  target.classList.add('source');
  target.classList.toggle('code', !!lang);
  if (!lang) {
    const pre = document.createElement('pre');
    pre.className = 'plaintext';
    pre.textContent = src;
    return target.replaceChildren(pre);
  }
  const code = document.createElement('code');
  code.className = 'hljs';
  if (src.length > 500_000) code.textContent = src;
  else code.innerHTML = hljs.highlight(src, { language: lang, ignoreIllegals: true }).value;
  const pre = document.createElement('pre');
  pre.append(code);
  target.replaceChildren(pre);
}

function taskLineIndexes(src) {
  const out = [];
  let fence = null;
  src.split('\n').forEach((line, i) => {
    const f = line.match(/^\s*(```|~~~)/);
    if (f) {
      if (!fence) fence = f[1];
      else if (f[1] === fence) fence = null;
      return;
    }
    if (!fence && /^\s*(?:[-*+]|\d+[.)])\s+\[[ xX]\]/.test(line)) out.push(i);
  });
  return out;
}

function stats(src) {
  if (!S.isMarkdown) {
    const lines = src ? src.split('\n').length - (src.endsWith('\n') ? 1 : 0) : 0;
    return `${lines.toLocaleString()} lines`;
  }
  const words = (splitFrontmatter(src).body.match(/[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu) || []).length;
  return `${words.toLocaleString()} words · ${Math.max(1, Math.round(words / 230))} min`;
}

// ---------- reader ----------

function renderReader() {
  const rs = $('#reader-scroll');
  const top = rs.scrollTop;
  if (S.isMarkdown) renderInto($('#reader'), S.content);
  else renderSource($('#reader'), S.content);
  rs.scrollTop = top;
  $('#meta').textContent = stats(S.content);
  if (findState.open) runFind(false);
}

$('#reader').addEventListener('click', (e) => {
  const copy = e.target.closest('button.copy');
  if (copy) {
    navigator.clipboard.writeText(copy.closest('.codeblock').querySelector('code').innerText).catch(() => {});
    copy.textContent = 'Copied';
    setTimeout(() => (copy.textContent = 'Copy'), 1200);
    return;
  }

  const box = e.target.closest('input[data-task]');
  if (box) return toggleTask(Number(box.dataset.task), box.checked);

  const a = e.target.closest('a[href]');
  if (!a) return;
  e.preventDefault();
  const href = a.getAttribute('href');
  if (href.startsWith('#')) {
    document.getElementById(decodeURIComponent(href.slice(1)))?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  } else if (/^[a-z][\w+.-]*:/i.test(href) && !href.startsWith('file:')) {
    native('openExternal', { url: href });
  } else {
    native('openPath', { path: resolvePath(dirname(S.path), href.split('#')[0]) });
  }
});

function toggleTask(index, checked) {
  const idx = taskLineIndexes(S.content)[index];
  if (idx == null) return;
  const lines = S.content.split('\n');
  lines[idx] = lines[idx].replace(/\[[ xX]\]/, checked ? '[x]' : '[ ]');
  S.content = lines.join('\n');
  S.dirty = true;
  setEditorDoc(S.content);
  save();
}

// ---------- editor ----------

let editor = null;
let suppressChange = false;
let saveTimer, renderTimer;

const mdHighlight = HighlightStyle.define([
  { tag: t.heading1, fontWeight: '700', fontSize: '1.3em' },
  { tag: t.heading2, fontWeight: '700', fontSize: '1.15em' },
  { tag: t.heading3, fontWeight: '650', fontSize: '1.05em' },
  { tag: [t.heading4, t.heading5, t.heading6], fontWeight: '650' },
  { tag: t.strong, fontWeight: '700' },
  { tag: t.emphasis, fontStyle: 'italic' },
  { tag: t.strikethrough, textDecoration: 'line-through' },
  { tag: [t.link, t.url], color: 'var(--link)' },
  { tag: t.monospace, color: 'var(--code-ink)' },
  { tag: [t.processingInstruction, t.meta, t.contentSeparator], color: 'var(--faint-ink)' },
  { tag: t.quote, color: 'var(--muted)' },
]);

function wrapSelection(before, after = before) {
  return (view) => {
    view.dispatch(
      view.state.changeByRange((range) => {
        const text = view.state.sliceDoc(range.from, range.to);
        if (text.length >= before.length + after.length && text.startsWith(before) && text.endsWith(after)) {
          const inner = text.slice(before.length, text.length - after.length);
          return {
            changes: { from: range.from, to: range.to, insert: inner },
            range: EditorSelection.range(range.from, range.from + inner.length),
          };
        }
        return {
          changes: [{ from: range.from, insert: before }, { from: range.to, insert: after }],
          range: EditorSelection.range(range.from + before.length, range.to + before.length),
        };
      })
    );
    return true;
  };
}

function ensureEditor() {
  if (editor) return editor;
  editor = new EditorView({
    parent: $('#editor-wrap'),
    state: EditorState.create({
      doc: S.content,
      extensions: [
        history(),
        drawSelection(),
        indentOnInput(),
        EditorView.lineWrapping,
        S.isMarkdown ? [markdown({ base: markdownLanguage, extensions: [{ remove: ['SetextHeading'] }] }), syntaxHighlighting(mdHighlight)] : [],
        search({ top: true }),
        highlightSelectionMatches(),
        placeholder('Start writing…'),
        keymap.of([
          { key: 'Mod-b', run: wrapSelection('**') },
          { key: 'Mod-i', run: wrapSelection('*') },
          { key: 'Mod-k', run: wrapSelection('[', '](url)') },
          { key: 'Mod-Shift-x', run: wrapSelection('~~') },
          ...searchKeymap,
          ...historyKeymap,
          ...defaultKeymap,
          indentWithTab,
        ]),
        EditorView.updateListener.of((u) => {
          if (u.docChanged && !suppressChange) onEditorChange(u.state.doc.toString());
        }),
        EditorView.domEventHandlers({ scroll: syncScroll }),
      ],
    }),
  });
  return editor;
}

function setEditorDoc(content) {
  if (!editor) return;
  const cur = editor.state.doc.toString();
  if (cur === content) return;
  suppressChange = true;
  editor.dispatch({
    changes: { from: 0, to: cur.length, insert: content },
    selection: { anchor: Math.min(editor.state.selection.main.head, content.length) },
  });
  suppressChange = false;
}

function onEditorChange(text) {
  S.content = text;
  setDirty(true);
  clearTimeout(saveTimer);
  saveTimer = setTimeout(save, 600);
  clearTimeout(renderTimer);
  renderTimer = setTimeout(() => {
    if (S.mode === 'split') renderReader();
    else $('#meta').textContent = stats(S.content);
  }, 140);
}

function setDirty(on) {
  if (S.dirty === on) return;
  S.dirty = on;
  $('#dirty').classList.toggle('on', on);
  native('setEdited', { edited: on });
}

async function save() {
  clearTimeout(saveTimer);
  if (!S.dirty) return;
  const content = S.content;
  S.saving = true;
  try {
    const res = await native('writeFile', { content });
    S.mtime = res.mtime;
    if (S.content === content) setDirty(false);
  } catch (e) {
    toast('Couldn’t save — ' + e);
  } finally {
    S.saving = false;
  }
}

let syncLock = false;
function syncScroll() {
  if (S.mode !== 'split' || syncLock) return;
  const es = editor.scrollDOM;
  const rs = $('#reader-scroll');
  syncLock = true;
  rs.scrollTop = (es.scrollTop / Math.max(1, es.scrollHeight - es.clientHeight)) * (rs.scrollHeight - rs.clientHeight);
  requestAnimationFrame(() => (syncLock = false));
}

// ---------- modes ----------

function setMode(mode) {
  S.mode = mode;
  document.body.dataset.mode = mode;
  const showEditor = mode !== 'read';
  $('#editor-wrap').hidden = !showEditor;
  $('#reader-scroll').hidden = mode === 'edit';
  $('#edit-btn').title = showEditor ? 'Done  ⌘E' : 'Edit  ⌘E';
  if (showEditor) {
    ensureEditor();
    setEditorDoc(S.content);
    requestAnimationFrame(() => editor.focus());
  } else {
    save();
  }
  if (mode !== 'edit') renderReader();
  if (mode === 'edit' && findState.open) closeFind();
}

// ---------- external changes ----------

async function poll() {
  if (S.dirty || S.saving) return;
  const st = await native('stat');
  if (!st.exists || st.mtime === S.mtime || S.dirty || S.saving) return;
  const res = await native('readFile');
  if (S.dirty || S.saving) return;
  S.mtime = res.mtime;
  if (res.content === S.content) return;
  S.content = res.content;
  setEditorDoc(S.content);
  if (S.mode !== 'edit') renderReader();
}

// ---------- prefs ----------

function applyPrefs() {
  const p = S.prefs;
  const root = document.documentElement;
  root.dataset.font = p.font;
  root.dataset.width = p.width;
  root.style.setProperty('--fs', p.size + 'px');
  $('#size-val').textContent = p.size;
  $$('#prefs [data-pref]').forEach((seg) =>
    $$('button', seg).forEach((b) => b.classList.toggle('active', b.dataset.v === p[seg.dataset.pref]))
  );
}

function updatePrefs(patch) {
  Object.assign(S.prefs, patch);
  applyPrefs();
  native('setPrefs', { json: JSON.stringify(S.prefs) });
}

$$('#prefs [data-pref]').forEach((seg) =>
  seg.addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (b) updatePrefs({ [seg.dataset.pref]: b.dataset.v });
  })
);

$('#prefs-btn').addEventListener('click', () => ($('#prefs').hidden = !$('#prefs').hidden));
document.addEventListener('mousedown', (e) => {
  if (!e.target.closest('#prefs, #prefs-btn')) $('#prefs').hidden = true;
});

const zoom = (d) => updatePrefs({ size: d === 0 ? 16 : Math.max(12, Math.min(26, S.prefs.size + d)) });

// ---------- find ----------

const findState = { open: false, ranges: [], index: 0 };

function openFind() {
  if (S.mode === 'edit') return openSearchPanel(editor);
  findState.open = true;
  $('#findbar').hidden = false;
  const input = $('#find-input');
  const sel = window.getSelection().toString();
  if (sel && !sel.includes('\n')) input.value = sel;
  input.focus();
  input.select();
  runFind(true);
}

function closeFind() {
  findState.open = false;
  $('#findbar').hidden = true;
  CSS.highlights?.clear();
}

function runFind(jump) {
  const q = $('#find-input').value.toLowerCase();
  findState.ranges = [];
  if (q) {
    const walker = document.createTreeWalker($('#reader'), NodeFilter.SHOW_TEXT, {
      acceptNode: (n) =>
        n.parentElement.closest('.katex-mathml, .codeblock-head') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
    });
    for (let node; (node = walker.nextNode()); ) {
      const text = node.data.toLowerCase();
      for (let i = text.indexOf(q); i !== -1; i = text.indexOf(q, i + q.length)) {
        const r = new Range();
        r.setStart(node, i);
        r.setEnd(node, i + q.length);
        findState.ranges.push(r);
      }
    }
  }
  if (jump) findState.index = 0;
  findState.index = Math.min(findState.index, Math.max(0, findState.ranges.length - 1));
  paintFind(jump);
}

function paintFind(scroll) {
  const { ranges, index } = findState;
  $('#find-count').textContent = $('#find-input').value ? (ranges.length ? `${index + 1}/${ranges.length}` : 'None') : '';
  if (!CSS.highlights) return;
  CSS.highlights.set('find', new Highlight(...ranges));
  if (!ranges[index]) return CSS.highlights.delete('find-current');
  CSS.highlights.set('find-current', new Highlight(ranges[index]));
  if (scroll) {
    const rect = ranges[index].getBoundingClientRect();
    const rs = $('#reader-scroll');
    const box = rs.getBoundingClientRect();
    if (rect.top < box.top + 40 || rect.bottom > box.bottom - 40) rs.scrollTop += rect.top - box.top - box.height / 3;
  }
}

function stepFind(dir) {
  const n = findState.ranges.length;
  if (!n) return;
  findState.index = (findState.index + dir + n) % n;
  paintFind(true);
}

$('#find-input').addEventListener('input', () => runFind(true));
$('#find-input').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') { e.preventDefault(); stepFind(e.shiftKey ? -1 : 1); }
  if (e.key === 'Escape') { e.preventDefault(); closeFind(); }
});
$('#find-next').addEventListener('click', () => stepFind(1));
$('#find-prev').addEventListener('click', () => stepFind(-1));
$('#find-close').addEventListener('click', closeFind);

// ---------- chrome ----------

let toastTimer;
function toast(msg) {
  const el = $('#toast');
  el.textContent = msg;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (el.hidden = true), 2600);
}

document.addEventListener('click', (e) => {
  const c = e.target.closest('[data-cmd]');
  if (c) command(c.dataset.cmd);
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    if (findState.open) closeFind();
    $('#prefs').hidden = true;
  }
  if (!hasBridge && e.metaKey) {
    const map = { f: 'find', e: 'toggleEdit', s: 'save', 1: 'modeRead', 2: 'modeEdit', 3: 'modeSplit' };
    if (map[e.key]) { e.preventDefault(); command(map[e.key]); }
  }
});

function reportDragRects() {
  if (!hasBridge) return;
  const rect = (el) => {
    const r = el.getBoundingClientRect();
    return [r.left, r.top, r.width, r.height];
  };
  native('dragRects', {
    drag: $$('.drag').map(rect),
    noDrag: $$('.drag button').filter((el) => el.offsetParent).map(rect),
  });
}
new ResizeObserver(reportDragRects).observe($('#topbar'));

document.addEventListener('scroll', (e) => {
  if (e.target.id === 'reader-scroll' || e.target.classList?.contains('cm-scroller')) {
    document.body.classList.toggle('scrolled', e.target.scrollTop > 4);
  }
}, { capture: true, passive: true });

function command(name) {
  switch (name) {
    case 'save': return save();
    case 'toggleEdit': return setMode(S.mode === 'read' ? 'edit' : 'read');
    case 'modeRead': return setMode('read');
    case 'modeEdit': return setMode('edit');
    case 'modeSplit': return setMode('split');
    case 'find': return openFind();
    case 'zoomIn': return zoom(1);
    case 'zoomOut': return zoom(-1);
    case 'zoomReset': return zoom(0);
  }
}

window.app = {
  command,
  flush: () => save().then(() => true),
  dragState: (on) => ($('#drop-overlay').hidden = !on),
  setFullscreen: (on) => document.body.classList.toggle('fullscreen', on),
  setPrefs: (json) => {
    try { S.prefs = { ...DEFAULT_PREFS, ...JSON.parse(json) }; } catch {}
    applyPrefs();
  },
};

// ---------- boot ----------

async function boot() {
  const init = await native('init');
  S.path = init.path;
  S.isMarkdown = isMarkdownPath(S.path);
  S.home = init.home;
  if (init.prefs) window.app.setPrefs(init.prefs);
  else applyPrefs();

  $('#name').textContent = stripExt(basename(S.path));
  $('#title').title = prettyPath(S.path);
  document.title = basename(S.path);

  try {
    const res = await native('readFile');
    S.content = res.content;
    S.mtime = res.mtime;
  } catch (e) {
    toast('Couldn’t open — ' + e);
  }
  setMode(init.mode || 'read');
  if (init.mode === 'edit') editor.dispatch({ selection: { anchor: editor.state.doc.length } });
  reportDragRects();
  setInterval(poll, 1000);
  window.addEventListener('focus', poll);
}

boot();
