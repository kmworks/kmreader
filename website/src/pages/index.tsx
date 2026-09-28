import type {ReactNode} from 'react';
import Link from '@docusaurus/Link';
import useBaseUrl from '@docusaurus/useBaseUrl';
import Layout from '@theme/Layout';
import {
  AppleLogo,
  AppStoreLogo,
  ArrowRight,
  BookOpen,
  DeviceMobile,
  DownloadSimple,
  GearSix,
  GithubLogo,
  HardDrives,
  Laptop,
  MagnifyingGlass,
  Television,
} from '@phosphor-icons/react';

import styles from './index.module.css';

const appStoreUrl = 'https://apps.apple.com/app/id6755198424';
const githubUrl = 'https://github.com/kmworks/kmreader';

function Hero(): ReactNode {
  return (
    <header className={styles.hero}>
      <div className={styles.heroBg} />
      <div className="container">
        <div className={styles.heroInner}>
          <div>
            <p className={`${styles.eyebrow} ${styles.rise} ${styles.d1}`}>
              Native Komga client
            </p>
            <h1 className={`${styles.heroTitle} ${styles.rise} ${styles.d2}`}>
              KMReader
            </h1>
            <p className={`${styles.heroSub} ${styles.rise} ${styles.d3}`}>
              Read, download, and manage your Komga library on iPhone, iPad,
              Mac, and Apple TV.
            </p>
            <div className={`${styles.ctaRow} ${styles.rise} ${styles.d4}`}>
              <Link className={styles.btnPrimary} href={appStoreUrl}>
                <AppStoreLogo size={17} weight="bold" /> Download on the App
                Store
              </Link>
              <Link className={styles.btnGhost} href={githubUrl}>
                <GithubLogo size={17} /> View on GitHub
              </Link>
            </div>
            <div className={`${styles.chipRow} ${styles.rise} ${styles.d5}`}>
              <span className={styles.chip}>iOS 17.0+</span>
              <span className={styles.chip}>macOS 14.0+</span>
              <span className={styles.chip}>tvOS 17.0+</span>
            </div>
          </div>
          <div className={`${styles.heroArt} ${styles.rise} ${styles.d5}`}>
            <img
              src={useBaseUrl('assets/icon.svg')}
              alt="KMReader app icon"
              className={styles.heroIcon}
            />
          </div>
        </div>
      </div>
    </header>
  );
}

type Feature = {
  pill: string;
  title: string;
  body: string;
  icon: ReactNode;
};

const features: Feature[] = [
  {
    pill: 'Readers',
    title: 'DIVINA, EPUB, and PDF',
    body: 'DIVINA on every platform, EPUB and PDF on iOS and macOS. Webtoon, spreads, page curl, AI upscaling, and per-book preferences.',
    icon: <BookOpen size={26} weight="duotone" />,
  },
  {
    pill: 'Browse',
    title: 'Find the right book faster',
    body: 'Keep Reading and On Deck dashboards, read lists that continue like series, metadata filters, saved searches, and Spotlight indexing for downloaded content.',
    icon: <MagnifyingGlass size={26} weight="duotone" />,
  },
  {
    pill: 'Offline',
    title: 'Keep reading anywhere',
    body: 'Downloads with per-series policies, offline-first reading, background transfers, and progress sync when you reconnect.',
    icon: <DownloadSimple size={26} weight="duotone" />,
  },
  {
    pill: 'Apple platforms',
    title: 'System integrations',
    body: 'Widgets, Home Screen quick actions, Live Activities, Live Text, and dedicated reader windows on macOS.',
    icon: <AppleLogo size={26} weight="duotone" />,
  },
  {
    pill: 'Multi-server',
    title: 'Switch servers quickly',
    body: 'Save multiple Komga servers, sign in with password or API key, and manage keys in the app.',
    icon: <HardDrives size={26} weight="duotone" />,
  },
  {
    pill: 'Admin',
    title: 'Manage your server in-app',
    body: 'Edit metadata, manage libraries, monitor tasks, and review or export logs.',
    icon: <GearSix size={26} weight="duotone" />,
  },
];

function Features(): ReactNode {
  return (
    <section className={styles.section}>
      <div className="container">
        <div className={`${styles.sectionHead} ${styles.reveal}`}>
          <h2 className={styles.sectionTitle}>
            Everything a Komga reader needs
          </h2>
        </div>
        <div className={styles.cardGrid}>
          {features.map((f) => (
            <article className={`${styles.card} ${styles.reveal}`} key={f.pill}>
              <div className={styles.cardIcon}>{f.icon}</div>
              <span className={styles.pill}>{f.pill}</span>
              <h3 className={styles.cardTitle}>{f.title}</h3>
              <p className={styles.cardBody}>{f.body}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

const platforms = [
  {
    title: 'iOS & iPadOS',
    body: 'All three readers with widgets, quick actions, Spotlight search, background downloads, and Live Activities.',
    icon: <DeviceMobile size={26} weight="duotone" />,
  },
  {
    title: 'macOS',
    body: 'Dedicated reader windows, menu bar actions, and keyboard-first controls.',
    icon: <Laptop size={26} weight="duotone" />,
  },
  {
    title: 'tvOS',
    body: 'Remote-first DIVINA reading with a focused TV browsing experience.',
    icon: <Television size={26} weight="duotone" />,
  },
];

function Platforms(): ReactNode {
  return (
    <section className={styles.section}>
      <div className="container">
        <div className={`${styles.sectionHead} ${styles.reveal}`}>
          <h2 className={styles.sectionTitle}>Built for Apple platforms</h2>
        </div>
        <div className={`${styles.cardGrid} ${styles.cardGridThree}`}>
          {platforms.map((p) => (
            <article
              className={`${styles.card} ${styles.reveal}`}
              key={p.title}>
              <div className={styles.cardIcon}>{p.icon}</div>
              <h3 className={styles.cardTitle}>{p.title}</h3>
              <p className={styles.cardBody}>{p.body}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

const faqs = [
  {
    q: 'Is KMReader an official Komga app?',
    a: 'No. KMReader is an independent open-source client built for Komga users.',
  },
  {
    q: 'Which readers are available?',
    a: 'DIVINA on iOS, macOS, and tvOS. EPUB and PDF on iOS and macOS.',
  },
  {
    q: 'Can I use multiple Komga servers?',
    a: 'Yes. Save and switch between servers, sign in with password or API key, and manage keys in the app.',
  },
  {
    q: 'How does offline mode work?',
    a: 'Downloaded books stay readable offline, and reading progress syncs when you reconnect.',
  },
  {
    q: 'Which server should I run?',
    a: (
      <>
        Any Komga 1.20.0+ server works, including{' '}
        <Link href="https://kmworks.github.io/kmrs/">kmrs</Link>, the
        single-binary Rust server from the same family.
      </>
    ),
  },
  {
    q: 'Can admins manage library data in-app?',
    a: 'Yes. Metadata editing, library and media management, task monitoring, and log review are built in.',
  },
];

function Faq(): ReactNode {
  return (
    <section className={styles.section}>
      <div className="container">
        <div className={`${styles.sectionHead} ${styles.reveal}`}>
          <h2 className={styles.sectionTitle}>Details</h2>
        </div>
        <div className={styles.faqGrid}>
          {faqs.map((f) => (
            <article
              className={`${styles.faqItem} ${styles.reveal}`}
              key={f.q}>
              <h4 className={styles.faqQuestion}>{f.q}</h4>
              <p className={styles.faqAnswer}>{f.a}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function FinalCta(): ReactNode {
  return (
    <section className={styles.final}>
      <div className={styles.finalBg} />
      <div className={`container ${styles.reveal}`}>
        <h2 className={styles.finalTitle}>Start reading your library.</h2>
        <div className={styles.ctaRow}>
          <Link className={styles.btnPrimary} href={appStoreUrl}>
            <AppStoreLogo size={17} weight="bold" /> Download on the App Store
          </Link>
          <Link className={styles.btnGhost} to="/docs">
            Get started <ArrowRight size={16} weight="bold" />
          </Link>
        </div>
      </div>
    </section>
  );
}

export default function Home(): ReactNode {
  return (
    <Layout
      title="Native Komga client for iOS, macOS, and tvOS"
      description="KMReader is a native Komga client for iOS, macOS, and tvOS with DIVINA, EPUB, and PDF readers, offline downloads, multi-server support, and Apple-platform integrations.">
      <div className={styles.page}>
        <Hero />
        <Features />
        <Platforms />
        <Faq />
        <FinalCta />
      </div>
    </Layout>
  );
}
