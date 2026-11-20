// Rehype plugin for every Markdown file the site renders (docs/EXTENSIONS.md, docs/releases/*.md, guides):
//  - adds a "#" anchor link to h2–h4 (ids come from rehypeHeadingIds, which runs first)
//  - demotes headings in release notes by one level (their "# Glint 1.1.0" sits under the page's h1)
//  - points relative links to repository files at GitHub, and links between guides at their pages
//  - makes tables scroll horizontally on narrow screens instead of overflowing
const REPO = 'https://github.com/SaiBarathR/glint/blob/main/';
const BASE = '/glint/';

function walk(node, fn, parent = null, index = 0) {
  fn(node, parent, index);
  if (node.children) {
    // copy: fn may replace children
    node.children.slice().forEach((child) => walk(child, fn, node, node.children.indexOf(child)));
  }
}

const docPages = {
  'EXTENSIONS.md': 'docs/reference/',
  'getting-started.md': 'docs/',
  'writing-extensions.md': 'docs/writing-extensions/',
  'safety-and-limits.md': 'docs/safety-and-limits/',
};

export function rehypeGlint() {
  return (tree, file) => {
    const path = String(file?.path || file?.history?.[0] || '');
    const isRelease = /[\\/]docs[\\/]releases[\\/]/.test(path);
    const sourceDir = path.includes('/docs/') ? 'docs/' : '';

    walk(tree, (node, parent, index) => {
      if (node.type !== 'element') return;

      if (isRelease && /^h[1-5]$/.test(node.tagName)) {
        node.tagName = 'h' + (Number(node.tagName[1]) + 1);
      }

      if (/^h[2-4]$/.test(node.tagName) && node.properties?.id) {
        node.children.push({
          type: 'element',
          tagName: 'a',
          properties: { className: ['anchor'], href: '#' + node.properties.id, ariaLabel: 'Link to this section' },
          children: [{ type: 'text', value: '#' }],
        });
      }

      if (node.tagName === 'a' && typeof node.properties?.href === 'string') {
        const href = node.properties.href;
        if (/^[a-z]+:/i.test(href) || href.startsWith('#') || href.startsWith('/')) {
          if (/^https?:/i.test(href)) {
            node.properties.rel = ['noopener'];
          }
          return;
        }
        const [file, hash = ''] = href.split('#');
        const name = file.split('/').pop();
        if (docPages[name]) {
          node.properties.href = BASE + docPages[name] + (hash ? '#' + hash : '');
        } else {
          const clean = (sourceDir + file).replace(/^docs\/\.\.\//, '').replace(/^\.\//, '');
          node.properties.href = REPO + clean + (hash ? '#' + hash : '');
        }
      }

      // An empty header cell (e.g. "| Property | |") still needs a name for screen readers.
      if (node.tagName === 'th' && !node.children.some((c) => c.type !== 'text' || c.value.trim())) {
        node.children = [{ type: 'element', tagName: 'span', properties: { className: ['visually-hidden'] }, children: [{ type: 'text', value: 'Description' }] }];
      }

      if (node.tagName === 'table' && parent && parent.tagName !== 'div') {
        parent.children[index] = {
          type: 'element',
          tagName: 'div',
          properties: { className: ['table-wrap'], tabIndex: 0 },
          children: [node],
        };
      }
    });
  };
}
