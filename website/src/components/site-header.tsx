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

const headerCopy: Record<
  Language,
  { homeLabel: string; navigationLabel: string; home: string; changelog: string; languageLabel: string }
> = {
  zh: {
    homeLabel: "Pulse 首页",
    navigationLabel: "Pulse 首页",
    home: "首页",
    changelog: "更新日志",
    languageLabel: "切换网站语言",
  },
  en: {
    homeLabel: "Pulse home",
    navigationLabel: "Pulse home",
    home: "Home",
    changelog: "Changelog",
    languageLabel: "Change website language",
  },
  ja: {
    homeLabel: "Pulse ホーム",
    navigationLabel: "Pulse ホーム",
    home: "ホーム",
    changelog: "更新履歴",
    languageLabel: "サイトの言語を切り替え",
  },
  ko: {
    homeLabel: "Pulse 홈",
    navigationLabel: "Pulse 홈",
    home: "홈",
    changelog: "업데이트 내역",
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
