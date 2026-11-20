// A zipped extension (.glintextz) for every gallery item, built from gallery/ at build time.
// Glint opens it on double-click: the zip holds one <name>.glintext folder.
import type { APIRoute, GetStaticPaths } from 'astro';
import { zipSync, strToU8 } from 'fflate';
import { galleryExtensions } from '../../lib/extensions';

export const getStaticPaths: GetStaticPaths = () =>
  galleryExtensions().extensions.map((ext) => ({ params: { slug: ext.slug }, props: { slug: ext.slug } }));

const mtime = new Date('2026-01-01T00:00:00Z'); // fixed, so the archives are reproducible

export const GET: APIRoute = ({ props }) => {
  const ext = galleryExtensions().extensions.find((e) => e.slug === props.slug)!;
  const files: Record<string, [Uint8Array, { mtime: Date; os: number; attrs: number }]> = {};
  const add = (name: string, content: string) => {
    const executable = /\.(sh|py|rb|pl)$/.test(name);
    files[`${ext.folderName}/${name}`] = [strToU8(content), { mtime, os: 3, attrs: (executable ? 0o100755 : 0o100644) << 16 }];
  };
  if (ext.snippet) add('Snippet.txt', ext.snippet);
  else for (const f of ext.files) add(f.name, f.content);
  const zip = zipSync(files, { level: 9 });
  return new Response(zip, { headers: { 'Content-Type': 'application/zip' } });
};
