export const SITE = {
  name: 'Glint',
  url: 'https://saibarathr.github.io/glint/',
  repo: 'https://github.com/SaiBarathR/glint',
  releases: 'https://github.com/SaiBarathR/glint/releases',
  latestRelease: 'https://github.com/SaiBarathR/glint/releases/latest',
  releasesApi: 'https://api.github.com/repos/SaiBarathR/glint/releases/latest',
  description:
    'Glint is a native macOS menu-bar app: select text in any app and a small bar of actions appears next to it. Free and open source.',
};

/** Prefix a site path with the base path (/glint/). */
export function url(p = ''): string {
  const base = import.meta.env.BASE_URL.replace(/\/?$/, '/');
  return base + p.replace(/^\//, '');
}
