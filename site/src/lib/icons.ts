// Turns a Glint icon spec into something a browser can draw. SF Symbols can't be shipped on the web, so each
// symbol maps to a similar icon from Lucide (ISC license, https://lucide.dev); `text:` icons and short text are
// drawn as text, like Glint does; anything else falls back to the title's initials.
import fs from 'node:fs';
import path from 'node:path';

const symbolToLucide: Record<string, string> = {
  'apple.terminal': 'square-terminal',
  'arrow.down.right.and.arrow.up.left': 'shrink',
  'arrow.right.to.line': 'arrow-right-to-line',
  'arrow.triangle.swap': 'arrow-left-right',
  'arrow.up.and.down.text.horizontal': 'list-x',
  'arrow.up.arrow.down': 'arrow-up-down',
  'arrow.uturn.up': 'undo-2',
  'book.closed': 'book',
  'books.vertical': 'library',
  'bubble.left.and.bubble.right': 'messages-square',
  calendar: 'calendar',
  cart: 'shopping-cart',
  'character.book.closed': 'book-a',
  'character.cursor.ibeam': 'text-cursor-input',
  'character.magnify': 'search-code',
  'chart.bar': 'chart-bar',
  'chart.bar.xaxis': 'chart-no-axes-column',
  checklist: 'list-checks',
  'chevron.left.forwardslash.chevron.right': 'code',
  'chevron.left.slash.chevron.right': 'code',
  clock: 'clock',
  curlybraces: 'braces',
  'curlybraces.square': 'file-code',
  'doc.plaintext': 'file-text',
  'doc.text.magnifyingglass': 'file-search',
  envelope: 'mail',
  key: 'key',
  'line.3.horizontal.decrease': 'list-filter',
  link: 'link',
  'list.bullet': 'list',
  'list.number': 'list-ordered',
  'lock.open': 'lock-open',
  'lock.square': 'lock',
  map: 'map',
  megaphone: 'megaphone',
  'note.text': 'sticky-note',
  'note.text.badge.plus': 'notebook-pen',
  number: 'hash',
  'number.square': 'binary',
  paintpalette: 'palette',
  parentheses: 'parentheses',
  percent: 'percent',
  'play.rectangle': 'square-play',
  'questionmark.bubble': 'message-circle-question',
  'quote.closing': 'quote',
  'quote.opening': 'quote',
  ruler: 'ruler',
  scissors: 'scissors',
  shuffle: 'shuffle',
  'sparkle.magnifyingglass': 'search',
  sparkles: 'sparkles',
  'square.on.square.dashed': 'layers',
  'text.alignleft': 'align-left',
  'text.append': 'wrap-text',
  'text.bubble': 'message-square-text',
  'text.justify.left': 'align-justify',
  textformat: 'case-sensitive',
  'textformat.abc': 'whole-word',
  translate: 'languages',
  'wand.and.stars': 'wand-sparkles',
  magnifyingglass: 'search',
  book: 'book-open',
};

const iconDir = path.resolve(process.cwd(), 'node_modules/lucide-static/icons');
const cache = new Map<string, string | null>();

/** The inner SVG markup of a Lucide icon, or null. */
export function lucide(name: string): string | null {
  if (cache.has(name)) return cache.get(name)!;
  let svg: string | null = null;
  try {
    const raw = fs.readFileSync(path.join(iconDir, name + '.svg'), 'utf8');
    svg = raw.replace(/<!--[\s\S]*?-->/, '').replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '').trim();
  } catch {
    svg = null;
  }
  cache.set(name, svg);
  return svg;
}

export function svgIcon(name: string, size = 20, label?: string): string {
  const inner = lucide(name) ?? '';
  const a11y = label ? `role="img" aria-label="${label}"` : 'aria-hidden="true"';
  return `<svg class="lucide" xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" ${a11y}>${inner}</svg>`;
}

export type WebIcon = { kind: 'svg'; svg: string } | { kind: 'text'; text: string };

const unmapped = new Set<string>();

export function webIcon(spec: string | undefined | null, fallbackTitle: string): WebIcon {
  const initials = () => ({
    kind: 'text' as const,
    text: fallbackTitle.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase() || '?',
  });
  if (!spec) return initials();
  let s = spec.trim();
  // Shape prefixes (square, circle, filled…) don't change which glyph we draw.
  s = s.replace(/^((square|circle|filled|monospaced|strike|flip-x|flip-y|search|shape=\S+)\s+)+/i, '');
  const sym = s.match(/^(?:symbol|sf):(.+)$/i)?.[1] ?? (/^[a-z0-9]+(\.[a-z0-9]+)+$/.test(s) ? s : null);
  if (sym) {
    const name = symbolToLucide[sym];
    if (name && lucide(name)) return { kind: 'svg', svg: svgIcon(name) };
    if (!unmapped.has(sym)) {
      unmapped.add(sym);
      console.warn(`[glint-site] no web icon for SF Symbol "${sym}", using initials`);
    }
    return initials();
  }
  const text = s.match(/^text:(.*)$/i)?.[1];
  if (text !== undefined) return { kind: 'text', text: text.trim() || '?' };
  if (/\.(png|svg|pdf|tiff?|jpe?g|icns)$/i.test(s) || /^iconify:/i.test(s)) return initials();
  if ([...s].length <= 4) return { kind: 'text', text: s };
  return initials();
}

// Brand marks aren't in Lucide. GitHub's mark is from Octicons (MIT).
const brands: Record<string, string> = {
  github:
    '<path fill="currentColor" stroke="none" d="M12 .5a11.5 11.5 0 0 0-3.64 22.41c.58.1.79-.25.79-.56v-2c-3.2.7-3.88-1.37-3.88-1.37-.52-1.33-1.28-1.68-1.28-1.68-1.05-.72.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.7 1.26 3.36.96.1-.75.4-1.26.73-1.55-2.55-.29-5.24-1.28-5.24-5.68 0-1.26.45-2.28 1.19-3.09-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.17 1.18a11 11 0 0 1 5.77 0c2.2-1.49 3.17-1.18 3.17-1.18.63 1.59.23 2.76.11 3.05.74.81 1.19 1.83 1.19 3.09 0 4.41-2.69 5.38-5.25 5.67.41.36.78 1.06.78 2.14v3.17c0 .31.21.67.8.56A11.5 11.5 0 0 0 12 .5Z"/>',
};
const _svgIcon = svgIcon;
export function icon(name: string, size = 20, label?: string): string {
  if (brands[name]) {
    const a11y = label ? `role="img" aria-label="${label}"` : 'aria-hidden="true"';
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 24 24" ${a11y}>${brands[name]}</svg>`;
  }
  return _svgIcon(name, size, label);
}
