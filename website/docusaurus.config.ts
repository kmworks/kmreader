import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

const config: Config = {
  title: 'KMReader',
  tagline: 'Native Komga client for iOS, macOS, and tvOS',
  favicon: 'assets/icon.svg',

  // Future flags, see https://docusaurus.io/docs/api/docusaurus-config#future
  future: {
    v4: true, // Improve compatibility with the upcoming Docusaurus v4
  },

  url: 'https://kmworks.github.io',
  baseUrl: '/kmreader/',

  organizationName: 'kmworks',
  projectName: 'kmreader',

  onBrokenLinks: 'throw',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          editUrl: 'https://github.com/kmworks/kmreader/tree/main/website/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themes: [
    [
      '@easyops-cn/docusaurus-search-local',
      {
        hashed: true,
        indexBlog: false,
        docsRouteBasePath: '/docs',
      },
    ],
  ],

  themeConfig: {
    colorMode: {
      defaultMode: 'light',
      disableSwitch: false,
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'KMReader',
      logo: {
        alt: 'KMReader',
        src: 'assets/icon.svg',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docs',
          position: 'left',
          label: 'Docs',
        },
        {
          href: 'https://apps.apple.com/app/id6755198424',
          label: 'App Store',
          position: 'right',
        },
        {
          href: 'https://github.com/kmworks/kmreader',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'KMReader',
          items: [
            {label: 'App Store', href: 'https://apps.apple.com/app/id6755198424'},
            {label: 'GitHub', href: 'https://github.com/kmworks/kmreader'},
            {label: 'Feedback', href: 'https://github.com/kmworks/kmreader/issues'},
          ],
        },
        {
          title: 'Support',
          items: [
            {label: 'Support', href: 'mailto:everpcpc@icloud.com'},
            {label: 'Privacy Policy', href: 'https://kmworks.date/kmreader/privacy'},
          ],
        },
        {
          title: 'kmworks',
          items: [
            {label: 'kmworks', href: 'https://kmworks.github.io/'},
            {label: 'kmrs', href: 'https://kmworks.github.io/kmrs/'},
            {label: 'Komga', href: 'https://komga.org'},
          ],
        },
      ],
      copyright: `KMReader is under the MIT License. Not affiliated with the Komga project.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.duotoneDark,
      additionalLanguages: ['bash', 'json'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
