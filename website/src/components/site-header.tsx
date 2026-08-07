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
};

const languageLabels: Record<Language, string> = {
  zh: "中文",
  en: "EN",
  ja: "日本語",
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
            aria-current={page === "home" ? "page" : undefined}
          >
            {copy.home}
          </Link>
          <Link
            to={changelogPath(language)}
            aria-current={page === "changelog" ? "page" : undefined}
          >
            {copy.changelog}
          </Link>
        </nav>
        <div className="language-switcher" aria-label={copy.languageLabel}>
          {languages.map((candidate) => (
            <Link
              key={candidate}
              to={page === "home" ? homePath(candidate) : changelogPath(candidate)}
              className={candidate === language ? "active" : undefined}
              aria-current={candidate === language ? "true" : undefined}
              onClick={() => rememberLanguage(candidate)}
            >
              {languageLabels[candidate]}
            </Link>
          ))}
        </div>
      </div>
    </header>
  );
}
