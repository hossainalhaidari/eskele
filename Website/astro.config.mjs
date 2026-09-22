// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Static output: `astro build` writes plain HTML/CSS/JS to ./dist with no server
// component of any kind. Starlight's search is Pagefind, which is a static index
// queried in the browser, so the docs stay searchable on any dumb file host.
export default defineConfig({
  // The user site carries the custom domain, so every project site of this account is served
  // under it at /<repository> — hence hossain.al plus the base below.
  site: 'https://hossain.al',
  base: '/eskele',
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'Eskele',
      description:
        'A minimal macOS dock, exactly as thick as the system menu bar, that can sit on the left, bottom or right edge.',
      // The landing page at src/pages/index.astro owns "/", so Starlight lives
      // under /docs/ — its content is nested one level inside the collection.
      logo: {
        src: './src/assets/mark.svg',
        alt: 'Eskele',
      },
      customCss: ['./src/styles/theme.css', './src/styles/docs.css'],
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/hossainalhaidari/eskele',
        },
      ],
      editLink: {
        baseUrl: 'https://github.com/hossainalhaidari/eskele/edit/main/Website/',
      },
      sidebar: [
        {
          label: 'Start here',
          items: [
            { label: 'Overview', slug: 'docs' },
            { label: 'Install and run', slug: 'docs/install' },
            { label: 'Permissions', slug: 'docs/permissions' },
            { label: 'Privacy', slug: 'docs/privacy' },
          ],
        },
        {
          label: 'Shaping the bar',
          items: [
            { label: 'Layout and designs', slug: 'docs/layout' },
            { label: 'Appearance', slug: 'docs/appearance' },
            { label: 'Displays and order', slug: 'docs/displays' },
            { label: 'Clock', slug: 'docs/clock' },
          ],
        },
        {
          label: 'Driving it',
          items: [
            { label: 'Clicks and shortcuts', slug: 'docs/gestures' },
            { label: 'The Apps Menu', slug: 'docs/apps-menu' },
            { label: 'Windows', slug: 'docs/windows' },
          ],
        },
        {
          label: 'What a cell can tell you',
          items: [
            { label: 'Badges', slug: 'docs/badges' },
            { label: 'Progress', slug: 'docs/progress' },
            { label: 'Activity overlay', slug: 'docs/activity' },
          ],
        },
        {
          label: 'System',
          items: [
            { label: 'Hiding the system Dock', slug: 'docs/system-dock' },
            { label: 'Files and configuration', slug: 'docs/files' },
          ],
        },
        {
          label: 'Help',
          items: [
            { label: 'Troubleshooting', slug: 'docs/troubleshooting' },
            { label: 'Known gaps', slug: 'docs/known-gaps' },
          ],
        },
        {
          label: 'Project',
          items: [
            { label: 'Translating', slug: 'docs/translating' },
            { label: 'Transparency', slug: 'docs/transparency' },
          ],
        },
      ],
      components: {
        // The landing page is not a docs page; Starlight's header would fight it.
      },
      lastUpdated: false,
      pagination: true,
    }),
  ],
});
