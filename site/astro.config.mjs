// @ts-check
import { defineConfig } from 'astro/config';
import { rehypeHeadingIds, unified } from '@astrojs/markdown-remark';
import { rehypeGlint } from './src/lib/rehype-glint.mjs';
import { codeThemes } from './src/lib/code-themes.mjs';

// GitHub Pages project site: every URL lives under /glint/.
export default defineConfig({
  site: 'https://saibarathr.github.io',
  base: '/glint',
  trailingSlash: 'always',
  // Astro 7's HTML compression drops the space between a line of text and an inline element on the next line.
  compressHTML: false,
  build: { format: 'directory', inlineStylesheets: 'auto' },
  markdown: {
    shikiConfig: {
      themes: codeThemes,
      defaultColor: false,
      wrap: false,
    },
    processor: unified({ rehypePlugins: [rehypeHeadingIds, rehypeGlint] }),
  },
  vite: {
    // docs/, gallery/ and App/Resources/Extensions live outside site/.
    server: { fs: { allow: ['..'] } },
  },
});
