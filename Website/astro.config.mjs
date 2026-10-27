// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Static output: `astro build` writes plain HTML/CSS/JS to ./dist with no server
// component of any kind. Starlight's search is Pagefind, which is a static index
// queried in the browser, so the docs stay searchable on any dumb file host.
export default defineConfig({
  // A project page on GitHub Pages. The account's Pages domain is hossain.al, so
  // GitHub serves this repository's site at https://hossain.al/kagami/ (and
  // redirects hossainalhaidari.github.io/kagami/ there). Living under /kagami/,
  // every hand-written link goes through src/lib/url.ts. A domain of its own later
  // means a public/CNAME, `site` set to that domain and `base` removed.
  site: 'https://hossain.al',
  base: '/kagami',
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'Kagami',
      description:
        'Flash disk images to USB drives and SD cards on macOS — bootable, verified, nothing else.',
      // The landing page at src/pages/index.astro owns "/", so Starlight lives
      // under /docs/ — its content is nested one level inside the collection.
      logo: {
        src: './src/assets/mark.svg',
        alt: 'Kagami',
      },
      favicon: '/favicon.svg',
      customCss: ['./src/styles/theme.css', './src/styles/docs.css'],
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/hossainalhaidari/kagami',
        },
      ],
      editLink: {
        baseUrl: 'https://github.com/hossainalhaidari/kagami/edit/main/Website/',
      },
      sidebar: [
        {
          label: 'Start here',
          items: [
            { label: 'Overview', slug: 'docs' },
            { label: 'Install and run', slug: 'docs/install' },
            { label: 'Privacy', slug: 'docs/privacy' },
          ],
        },
        {
          label: 'Using Kagami',
          items: [
            { label: 'Flashing a drive', slug: 'docs/flashing' },
            { label: 'Supported images', slug: 'docs/images' },
            { label: 'Safety', slug: 'docs/safety' },
          ],
        },
        {
          label: 'Help',
          items: [{ label: 'Troubleshooting', slug: 'docs/troubleshooting' }],
        },
        {
          label: 'Project',
          items: [{ label: 'Transparency', slug: 'docs/transparency' }],
        },
      ],
      lastUpdated: false,
      pagination: true,
    }),
  ],
});
