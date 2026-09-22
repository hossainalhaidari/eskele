/**
 * Build a site-absolute URL that survives the `base` in astro.config.mjs.
 *
 * Deploying to a project page on GitHub Pages puts the whole site under
 * /eskele/; deploying to a custom domain puts it at the root. Hard-coded
 * "/docs/" links break on the first of those, so every internal link on the
 * hand-written pages goes through here. Starlight already does this for its own.
 */
const BASE = import.meta.env.BASE_URL;

export function url(path: string): string {
  const base = BASE.endsWith('/') ? BASE.slice(0, -1) : BASE;
  const tail = path.startsWith('/') ? path : `/${path}`;
  return `${base}${tail}`;
}
