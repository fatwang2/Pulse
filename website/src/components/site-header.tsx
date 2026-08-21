import { useEffect, useRef, useState } from "react";
import { Link } from "@tanstack/react-router";
import {
  changelogPath,
  homePath,
  languages,
  type Language,
  type PageKind,
  rememberLanguage,
} from "../i18n";

const repositoryUrl = "https://github.com/fatwang2/Pulse";

const headerCopy: Record<
  Language,
  { homeLabel: string; navigationLabel: string; home: string; changelog: string; githubLabel: string; languageLabel: string }
> = {
  zh: {
    homeLabel: "Pulse 首页",
    navigationLabel: "Pulse 首页",
    home: "首页",
    changelog: "更新日志",
    githubLabel: "在 GitHub 查看 Pulse 源码",
    languageLabel: "切换网站语言",
  },
  en: {
    homeLabel: "Pulse home",
    navigationLabel: "Pulse home",
    home: "Home",
    changelog: "Changelog",
    githubLabel: "View Pulse source on GitHub",
    languageLabel: "Change website language",
  },
  ja: {
    homeLabel: "Pulse ホーム",
    navigationLabel: "Pulse ホーム",
    home: "ホーム",
    changelog: "更新履歴",
    githubLabel: "GitHub で Pulse のソースを見る",
    languageLabel: "サイトの言語を切り替え",
  },
  ko: {
    homeLabel: "Pulse 홈",
    navigationLabel: "Pulse 홈",
    home: "홈",
    changelog: "업데이트 내역",
    githubLabel: "GitHub에서 Pulse 소스 보기",
    languageLabel: "사이트 언어 변경",
  },
};

const languageLabels: Record<Language, string> = {
  zh: "中文",
  en: "EN",
  ja: "日本語",
  ko: "한국어",
};

export function SiteHeader({
  language,
  page,
}: {
  language: Language;
  page: PageKind;
}) {
  const copy = headerCopy[language];

  return (
    <header className="header shell">
      <Link className="brand" to={homePath(language)} aria-label={copy.homeLabel}>
        <span className="brand-mark">
          <img src="/pulse-icon.png" alt="" width={34} height={34} />
        </span>
        <span>Pulse</span>
      </Link>
      <div className="header-actions">
        <nav className="site-nav" aria-label={copy.navigationLabel}>
          <Link
            to={homePath(language)}
            activeOptions={{ exact: true }}
            aria-current={page === "home" ? "page" : undefined}
          >
            {copy.home}
          </Link>
          <Link
            to={changelogPath(language)}
            activeOptions={{ exact: true }}
            aria-current={page === "changelog" ? "page" : undefined}
          >
            {copy.changelog}
          </Link>
        </nav>
        <a
          className="header-github"
          href={repositoryUrl}
          target="_blank"
          rel="noreferrer"
          aria-label={copy.githubLabel}
          title="GitHub"
          data-testid="header-github"
        >
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M12 2.6a9.6 9.6 0 0 0-3 18.7c.5.1.7-.2.7-.5v-1.9c-2.8.6-3.4-1.2-3.4-1.2-.5-1.2-1.1-1.5-1.1-1.5-.9-.6.1-.6.1-.6 1 0 1.6 1.1 1.6 1.1.9 1.6 2.4 1.1 3 .9.1-.7.4-1.1.7-1.4-2.3-.3-4.6-1.1-4.6-4.8 0-1.1.4-1.9 1-2.6-.1-.3-.4-1.3.1-2.6 0 0 .8-.3 2.7 1a9.2 9.2 0 0 1 4.9 0c1.9-1.3 2.7-1 2.7-1 .5 1.3.2 2.3.1 2.6.6.7 1 1.5 1 2.6 0 3.7-2.3 4.5-4.6 4.8.4.3.7.9.7 1.8v2.8c0 .4.2.6.7.5A9.6 9.6 0 0 0 12 2.6Z" />
          </svg>
          <span>GitHub</span>
        </a>
        <LanguageSwitcher language={language} page={page} label={copy.languageLabel} />
      </div>
    </header>
  );
}

function LanguageSwitcher({
  language,
  page,
  label,
}: {
  language: Language;
  page: PageKind;
  label: string;
}) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDetailsElement>(null);

  useEffect(() => {
    if (!open) return;
    function onPointerDown(event: MouseEvent) {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    }
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  return (
    <details
      ref={root}
      className="language-switcher"
      open={open}
      onToggle={(event) => setOpen(event.currentTarget.open)}
    >
      <summary aria-label={label} aria-haspopup="menu">
        {languageLabels[language]}
        <svg viewBox="0 0 10 6" aria-hidden="true" focusable="false">
          <path
            d="M1 1.4 5 5 9 1.4"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.4"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      </summary>
      <div className="language-menu" role="menu">
        {languages.map((candidate) => (
          <Link
            key={candidate}
            role="menuitem"
            to={page === "home" ? homePath(candidate) : changelogPath(candidate)}
            aria-current={candidate === language ? "true" : undefined}
            onClick={() => {
              rememberLanguage(candidate);
              setOpen(false);
            }}
          >
            {languageLabels[candidate]}
          </Link>
        ))}
      </div>
    </details>
  );
}
