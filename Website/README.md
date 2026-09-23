# Eskele — Website

The homepage and documentation for Eskele, built with [Astro](https://astro.build) and
[Starlight](https://starlight.astro.build).

`astro build` emits plain HTML, CSS and JS into `dist/` — **no server-side rendering, no backend, no
runtime dependencies**. The docs search is [Pagefind](https://pagefind.app), a static index queried
in the browser, so the whole site works on any file host: GitHub Pages, Netlify, Cloudflare Pages, S3,
or a directory served by nginx.

## Commands

From the repository root, via the `Makefile` — these install dependencies on first use:

```bash
make docs        # build, then serve it and open a browser
make docs-stop   # stop that server
make docs-dev    # hot-reloading server, for editing the site itself
make docs-build  # static build only, into Website/dist
```

`make docs` serves on port 4321; override with `make docs DOCS_PORT=4400`. It hands the prompt back
with the server running in the background, because `astro preview` daemonises — hence `make docs-stop`.
`make docs-dev` blocks instead, so stop it with ^C. `make clean` removes `Website/dist` along with the
Swift build directory.

Or from this directory, directly:

```bash
npm install
npm run dev      # dev server with hot reload
npm run build    # static build into dist/
npm run preview  # serve dist/ locally, exactly as it will be deployed
npm run check    # type-check .astro and .ts
```

## Layout

```
astro.config.mjs          site config, Starlight setup, docs sidebar
src/
  pages/index.astro       the single-page homepage — owns "/"
  components/
    DesktopMock.astro     the drawn macOS desktop and the Dock/Classic/Unity switcher
  content/
    docs/docs/*.md(x)     every documentation page -> /docs/<slug>/
    docs/404.md           the not-found page
    i18n/en.json          UI string overrides
  styles/
    theme.css             design tokens, shared by the homepage and the docs
    landing.css           the homepage
    docs.css              Starlight theming
  lib/url.ts              base-aware internal links
  assets/mark.svg         the app icon, flattened to one file
public/favicon.svg        the same mark, served as the favicon
```

**Documentation pages live in `src/content/docs/docs/`.** The extra level is deliberate: Starlight maps
`src/content/docs/<path>` onto `/<path>`, so nesting the content one folder deep is what puts the docs
under `/docs/` and leaves `/` free for the hand-written homepage.

To add a page, drop a Markdown file in that folder with `title` and `description` frontmatter, then
add it to the `sidebar` in `astro.config.mjs`.

## The homepage's illustration

`DesktopMock.astro` is not a screenshot. The desktop, the menu bar, the window and the bar are real
elements styled with CSS, sized in container-query units so everything scales with the frame. That
keeps it sharp at any size, lets it follow the page's light and dark themes, and lets the three
design buttons genuinely reshape the bar rather than swap images.

If the app's designs change, the geometry to edit is in the `design: Dock` / `design: Classic` /
`design: Unity` sections of `src/styles/landing.css`.

## Deploying

`.github/workflows/website.yml` builds this directory and publishes it to GitHub Pages on every push
to `main` that touches it. The site has a domain of its own and sits at the root of it:

```js
site: 'https://eskele.app',
```

`public/CNAME` claims that domain for the repository, and the repository's Pages settings say the
same. There is no `base`, because nothing is served under a path.

**Moving it under one** — a project site at `<user>.github.io/eskele/`, say — means adding
`base: '/eskele'` back. Every internal link on the hand-written pages goes through `src/lib/url.ts`
and Starlight handles its own, so that line does almost all of it. Two places cannot route through a
helper and need the prefix written out:

- the `hero.actions` links in `src/content/docs/404.md` (frontmatter, not code);
- the URL that `make docs` echoes, in the repository root `Makefile`.

To publish to GitHub Pages, build and serve `dist/` — for example with `actions/deploy-pages`, or by
pushing `dist/` to a `gh-pages` branch.

## Known build warning

```
[WARN] [build] Could not render `/404` from route `/[...slug]` as it conflicts with
                higher priority route `/404`.
```

That one is expected and harmless. Starlight injects a dedicated `/404` route and also enumerates
every docs entry through its catch-all; the dedicated route wins, which is the one we want, and
`dist/404.html` is correct. It is the price of having a custom 404 page rather than the default.

## Checking links after an edit

The documentation cross-references itself heavily, including deep links to specific headings. Two
throwaway scripts are worth re-running after a restructure — one that resolves every internal `href`
against `dist/`, and one that checks every `#fragment` against the target page's real heading IDs.
Both are a short walk over `dist/**/*.html`; there is no dependency to install.
