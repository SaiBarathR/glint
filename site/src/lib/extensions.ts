// Reads Glint extensions at build time: the ones bundled with the app (App/Resources/Extensions) and the
// website gallery (gallery/). This is a small JavaScript mirror of the engine's loader (GlintCore's
// ExtensionLoader / ManifestParser), enough to show names, descriptions, icons and actions. The engine itself is
// the authority; GalleryExtensionsTests.swift loads every gallery item with it.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import YAML from 'yaml';
import { webIcon, type WebIcon } from './icons';

export const repoRoot = path.resolve(process.cwd(), '..');
const bundledDir = path.join(repoRoot, 'App/Resources/Extensions');
const galleryDir = path.join(repoRoot, 'gallery');

export interface ExtAction {
  title: string;
  icon: WebIcon;
  kind: string;
  description?: string;
}

export interface ExtFile {
  name: string;
  lang: string;
  content: string;
}

export interface Example {
  action: string;
  input: string;
  output?: string;
  display?: string;
  displayOutput?: string;
  note?: string;
}

export interface ExtInfo {
  slug: string;
  name: string;
  identifier: string;
  description: string;
  icon: WebIcon;
  actions: ExtAction[];
  kinds: string[];
  format: string;
  options: { label: string; type: string; values?: string[] }[];
  files: ExtFile[];
  snippet?: string;
  folderName: string;
  category?: string;
  examples: Example[];
  source: 'bundled' | 'gallery';
  repoPath: string;
}

const norm = (k: string) => k.toLowerCase().replace(/[^a-z0-9]/g, '');

class Config {
  private map = new Map<string, unknown>();
  constructor(dict: Record<string, unknown>) {
    for (const [k, v] of Object.entries(dict ?? {})) this.map.set(norm(k), v);
  }
  get(...keys: string[]): unknown {
    for (const k of keys) if (this.map.has(norm(k))) return this.map.get(norm(k));
    return undefined;
  }
  str(...keys: string[]): string | undefined {
    const v = this.get(...keys);
    return typeof v === 'string' ? v : typeof v === 'number' ? String(v) : undefined;
  }
  list(...keys: string[]): Record<string, unknown>[] | undefined {
    const v = this.get(...keys);
    return Array.isArray(v) ? (v.filter((x) => x && typeof x === 'object') as Record<string, unknown>[]) : undefined;
  }
}

function langLabel(lang: string | undefined): string {
  const l = norm(lang ?? 'shell');
  const map: Record<string, string> = {
    javascript: 'JavaScript', js: 'JavaScript', applescript: 'AppleScript', shell: 'Shell', sh: 'Shell', bash: 'Shell',
    zsh: 'Shell', python: 'Python', python3: 'Python', ruby: 'Ruby', perl: 'Perl', node: 'Node', nodejs: 'Node',
    swift: 'Swift', php: 'PHP',
  };
  return map[l] ?? lang ?? 'Shell';
}

function actionKind(c: Config, inlineLanguage?: string): string | null {
  if (c.str('url') !== undefined) return 'URL';
  if (c.str('shell script') !== undefined) {
    const interp = c.str('interpreter');
    return interp ? langLabel(interp.split(/\s+/)[0].split('/').pop()) : 'Shell';
  }
  if (c.str('shell script file', 'script file') !== undefined) return 'Shell';
  if (c.str('applescript', 'apple script', 'applescript file', 'apple script file') !== undefined) return 'AppleScript';
  if (c.str('javascript', 'java script', 'javascript file', 'java script file') !== undefined) return 'JavaScript';
  if (c.get('key combos') !== undefined || c.get('key combo', 'keyboard shortcut') !== undefined) return 'Key combo';
  if (c.str('service name', 'service') !== undefined) return 'Service';
  if (c.str('shortcut name', 'shortcut') !== undefined) return 'Shortcut';
  if (inlineLanguage) return langLabel(inlineLanguage);
  return null;
}

/** Evaluates a JavaScript module (trusted repository files only) to read its config and action list. */
function evalModule(source: string, dir: string | null): Record<string, unknown> {
  const load = (src: string, from: string | null): unknown => {
    const module = { exports: {} as Record<string, unknown> };
    const require = (p: string) => {
      if (!from || !p.startsWith('.')) return {};
      let file = path.resolve(from, p);
      if (!fs.existsSync(file) && fs.existsSync(file + '.js')) file += '.js';
      if (file.endsWith('.json')) return JSON.parse(fs.readFileSync(file, 'utf8'));
      return load(fs.readFileSync(file, 'utf8'), path.dirname(file));
    };
    const stub = new Proxy(() => stub, { get: () => stub, apply: () => stub }) as unknown;
    const context = vm.createContext({
      module, exports: module.exports, require, console: { log() {}, error() {}, warn() {}, info() {} },
      glint: stub, popclip: stub, util: stub, pasteboard: stub, print() {},
    });
    vm.runInContext(src, context, { timeout: 1000 });
    return module.exports;
  };
  const out = load(source, dir);
  return (out && typeof out === 'object' ? out : {}) as Record<string, unknown>;
}

interface Parsed {
  name: string;
  identifier: string;
  description: string;
  icon?: string;
  actions: { title: string; icon?: string; kind: string; description?: string }[];
  options: { label: string; type: string; values?: string[] }[];
}

function parseOptions(c: Config) {
  return (c.list('options') ?? []).map((o) => {
    const oc = new Config(o);
    const type = norm(oc.str('type', 'option type') ?? 'string');
    const labels = oc.get('value labels', 'option value labels');
    const values = oc.get('values', 'option values');
    return {
      label: oc.str('label', 'option label') ?? oc.str('identifier', 'id') ?? '',
      type,
      values: (Array.isArray(labels) ? labels : Array.isArray(values) ? values : undefined)?.map(String),
    };
  }).filter((o) => o.type !== 'heading');
}

function parseDict(dict: Record<string, unknown>, opts: { inlineLanguage?: string; moduleActions?: Record<string, unknown>[] } = {}): Parsed {
  const c = new Config(dict);
  const name = c.str('name', 'extension name', 'title') ?? 'Extension';
  const icon = c.str('icon', 'image file', 'extension image file');
  const actions: Parsed['actions'] = [];
  const list = opts.moduleActions ?? c.list('actions');
  if (list) {
    for (const a of list) {
      const ac = new Config(a);
      const kind = opts.moduleActions ? 'JavaScript' : actionKind(ac);
      if (!kind) continue;
      actions.push({ title: ac.str('title', 'name') ?? name, icon: ac.str('icon', 'image file') ?? icon, kind,
                     description: ac.str('description') });
    }
  }
  if (actions.length === 0) {
    const kind = actionKind(c, opts.inlineLanguage);
    if (kind) actions.push({ title: name, icon, kind, description: undefined });
  }
  return {
    name,
    identifier: c.str('identifier', 'extension identifier') ?? 'snippet.' + name.toLowerCase().replace(/[^a-z0-9]+/g, '-'),
    description: c.str('description', 'extension description') ?? '',
    icon,
    actions,
    options: parseOptions(c),
  };
}

const headerRegex = /^\s*(#|\/\/|--|;|%)?\s*#\s*(glint|popclip)\b/i;

export function isSnippet(text: string): boolean {
  const first = text.split(/\r?\n/).find((l) => l.trim() !== '');
  return !!first && headerRegex.test(first);
}

/** Mirrors ExtensionLoader.parseSnippet. */
function parseSnippet(text: string): Parsed & { format: string } {
  const lines = text.split(/\r?\n/);
  while (lines.length && lines[0].trim() === '') lines.shift();
  const m = lines[0].match(headerRegex);
  if (!m) throw new Error('not a snippet');
  const prefix = m[1];
  const rest = lines[0].slice(m[0].length).trim();
  if (prefix) {
    const config: string[] = rest.includes(':') ? [rest] : [];
    let i = 1;
    while (i < lines.length && lines[i].trim().startsWith(prefix)) {
      let content = lines[i].trim().slice(prefix.length);
      if (content.startsWith(' ')) content = content.slice(1);
      config.push(content);
      i++;
    }
    const code = lines.slice(i).join('\n');
    const dict = (YAML.parse(config.join('\n')) ?? {}) as Record<string, unknown>;
    const c = new Config(dict);
    const language = c.str('language') ?? (prefix === '//' ? 'javascript' : prefix === '--' ? 'applescript' : 'shell');
    const label = langLabel(language);
    const isModule = label === 'JavaScript' &&
      (/^(true|yes|1)$/i.test(String(c.get('module') ?? '')) || /exports\.actions|exports\.action |module\.exports/.test(code));
    if (isModule) {
      const exp = evalModule(code, null);
      const merged = { ...exp, ...dict } as Record<string, unknown>;
      const acts = Array.isArray(exp.actions) ? (exp.actions as Record<string, unknown>[]) : [];
      return { ...parseDict(merged, { moduleActions: acts }), format: 'JavaScript module snippet' };
    }
    return { ...parseDict(dict, { inlineLanguage: language }), format: `${label} snippet` };
  }
  let yaml = lines.slice(1).join('\n');
  if (rest.includes(':')) yaml = rest + '\n' + yaml;
  return { ...parseDict((YAML.parse(yaml) ?? {}) as Record<string, unknown>), format: 'YAML snippet' };
}

const configNames = ['Config.yaml', 'Config.yml', 'Config.json', 'Config.plist', 'config.yaml', 'config.yml',
  'config.json', 'config.plist', 'Config.js', 'Config.ts', 'config.js'];

function langOf(file: string): string {
  const ext = path.extname(file).toLowerCase();
  return ({ '.yaml': 'yaml', '.yml': 'yaml', '.json': 'json', '.js': 'js', '.sh': 'sh', '.applescript': 'applescript',
            '.txt': 'text', '.py': 'python', '.rb': 'ruby', '.pl': 'perl' } as Record<string, string>)[ext] ?? 'text';
}

/** Language of a snippet's text, for syntax highlighting. */
export function snippetLang(text: string): string {
  const first = text.split(/\r?\n/).find((l) => l.trim() !== '') ?? '';
  if (/^\s*\/\//.test(first)) return 'js';
  if (/^\s*--/.test(first)) return 'applescript';
  if (/^\s*#\s+#/.test(first)) return /language:\s*perl/.test(text) ? 'perl' : 'sh';
  return 'yaml';
}

function loadBundle(dir: string): Parsed & { format: string; files: ExtFile[] } {
  const files = fs.readdirSync(dir).filter((f) => !f.startsWith('.')).sort((a, b) => {
    const ca = configNames.indexOf(a), cb = configNames.indexOf(b);
    return (ca < 0 ? 99 : ca) - (cb < 0 ? 99 : cb) || a.localeCompare(b);
  });
  const fileList: ExtFile[] = files
    .filter((f) => fs.statSync(path.join(dir, f)).isFile())
    .map((f) => ({ name: f, lang: langOf(f), content: fs.readFileSync(path.join(dir, f), 'utf8') }));
  if (files.includes('Snippet.txt')) {
    const text = fs.readFileSync(path.join(dir, 'Snippet.txt'), 'utf8');
    return { ...parseSnippet(text), files: fileList };
  }
  const cfg = configNames.find((n) => files.includes(n));
  if (!cfg) throw new Error(`No config in ${dir}`);
  const src = fs.readFileSync(path.join(dir, cfg), 'utf8');
  if (cfg.endsWith('.js') || cfg.endsWith('.ts')) {
    const exp = evalModule(src, dir);
    const acts = Array.isArray(exp.actions) ? (exp.actions as Record<string, unknown>[]) : [];
    return { ...parseDict(exp, { moduleActions: acts }), format: `Folder with ${cfg}`, files: fileList };
  }
  const dict = (cfg.endsWith('.json') ? JSON.parse(src) : YAML.parse(src)) as Record<string, unknown>;
  const c = new Config(dict);
  const moduleFile = c.str('module');
  if (moduleFile && fs.existsSync(path.join(dir, moduleFile))) {
    const exp = evalModule(fs.readFileSync(path.join(dir, moduleFile), 'utf8'), dir);
    const acts = Array.isArray(exp.actions) ? (exp.actions as Record<string, unknown>[]) : [];
    return { ...parseDict({ ...exp, ...dict }, { moduleActions: acts }), format: `Folder with ${cfg} + module`, files: fileList };
  }
  return { ...parseDict(dict), format: `Folder with ${cfg}`, files: fileList };
}

function finish(p: Parsed & { format: string }, extra: Omit<ExtInfo, 'name' | 'identifier' | 'description' | 'icon' | 'actions' | 'kinds' | 'format' | 'options'>): ExtInfo {
  return {
    ...extra,
    name: p.name,
    identifier: p.identifier,
    description: p.description,
    icon: webIcon(p.icon ?? p.actions[0]?.icon, p.name),
    actions: p.actions.map((a) => ({ ...a, icon: webIcon(a.icon, a.title) })),
    kinds: [...new Set(p.actions.map((a) => a.kind))],
    format: p.format,
    options: p.options,
  };
}

function loadItem(full: string, source: 'bundled' | 'gallery', repoRel: string): ExtInfo {
  const base = path.basename(full);
  const stat = fs.statSync(full);
  let parsed: Parsed & { format: string; files: ExtFile[] };
  let snippet: string | undefined;
  if (stat.isDirectory()) {
    parsed = loadBundle(full);
  } else {
    const text = fs.readFileSync(full, 'utf8');
    if (isSnippet(text)) {
      snippet = text;
      parsed = { ...parseSnippet(text), files: [{ name: base, lang: snippetLang(text), content: text }] };
    } else {
      const dict = (base.endsWith('.json') ? JSON.parse(text) : YAML.parse(text)) as Record<string, unknown>;
      parsed = { ...parseDict(dict), format: base.endsWith('.json') ? 'JSON file' : 'YAML file',
                 files: [{ name: base, lang: langOf(base), content: text }] };
    }
  }
  const slug = parsed.identifier.split('.').pop()!.toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const folderName = stat.isDirectory() ? base : slug + '.glintext';
  return finish(parsed, { slug, files: parsed.files, snippet, folderName, examples: [], source, repoPath: repoRel });
}

let bundledCache: ExtInfo[] | null = null;
export function bundledExtensions(): ExtInfo[] {
  if (bundledCache) return bundledCache;
  const items = fs.readdirSync(bundledDir).filter((f) => !f.startsWith('.')).sort();
  bundledCache = items
    .filter((f) => /\.(ya?ml|txt|json)$/i.test(f) || fs.statSync(path.join(bundledDir, f)).isDirectory())
    .map((f) => loadItem(path.join(bundledDir, f), 'bundled', 'App/Resources/Extensions/' + f))
    .sort((a, b) => {
      // Translate first (on by default), then the transforms, then the web searches.
      const rank = (e: ExtInfo) => (e.slug === 'translate' ? 0 : e.kinds.length === 1 && e.kinds[0] === 'URL' ? 2 : 1);
      return rank(a) - rank(b) || a.name.localeCompare(b.name);
    });
  return bundledCache;
}

export interface Catalog {
  categories: string[];
  extensions: ExtInfo[];
}

let galleryCache: Catalog | null = null;
export function galleryExtensions(): Catalog {
  if (galleryCache) return galleryCache;
  const catalog = JSON.parse(fs.readFileSync(path.join(galleryDir, 'catalog.json'), 'utf8')) as {
    categories: string[];
    extensions: { path: string; category: string; examples?: (Example & { hidden?: boolean })[] }[];
  };
  const extensions = catalog.extensions.map((entry) => {
    const info = loadItem(path.join(galleryDir, entry.path), 'gallery', 'gallery/' + entry.path);
    info.category = entry.category;
    info.examples = (entry.examples ?? []).filter((e) => !e.hidden);
    return info;
  });
  galleryCache = { categories: catalog.categories, extensions };
  return galleryCache;
}

/** Install link for a snippet; Glint registers the glint:// scheme. */
export function installLink(snippet: string): string {
  return 'glint://install?snippet=' + encodeURIComponent(snippet);
}
