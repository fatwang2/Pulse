/**
 * Language routing for the Pulse website.
 *
 * The site is served at three locales, one of which lives at the root:
 *   en -> /, /changelog
 *   zh -> /zh, /zh/changelog
 *   ja -> /ja, /ja/changelog
 *
 * The bare paths `/` and `/changelog` redirect to the visitor's preferred
 * locale (cookie first, then Accept-Language) when it is not English; English
 * is the canonical default and stays at the root.
 */

export const languages = ["en", "zh", "ja"] as const;
export type Language = (typeof languages)[number];

export const defaultLanguage: Language = "en";
export const languageCookieName = "pulse-lang";
export const siteUrl = "https://www.pulseticker.app";

export type PageKind = "home" | "changelog";

export function isLanguage(value: unknown): value is Language {
  return value === "en" || value === "zh" || value === "ja";
}

export function homePath(language: Language): string {
  return language === "en" ? "/" : `/${language}`;
}

export function changelogPath(language: Language): string {
  return language === "en" ? "/changelog" : `/${language}/changelog`;
}

export function pagePath(kind: PageKind, language: Language): string {
  return kind === "home" ? homePath(language) : changelogPath(language);
}

export function htmlLang(language: Language): string {
  return language === "zh" ? "zh-CN" : language === "ja" ? "ja" : "en";
}

const pathLanguagePattern = /^\/(zh|ja)(\/|$)/;

/** Language implied by a path; English when there is no language prefix. */
export function languageFromPath(pathname: string): Language {
  const match = pathname.match(pathLanguagePattern);
  if (match?.[1] === "zh") return "zh";
  if (match?.[1] === "ja") return "ja";
  return "en";
}

export function parseLanguageCookie(
  cookieHeader: string | null,
): Language | undefined {
  if (!cookieHeader) return undefined;
  const prefix = `${languageCookieName}=`;
  const entry = cookieHeader
    .split(";")
    .map((part) => part.trim())
    .find((part) => part.startsWith(prefix));
  if (!entry) return undefined;
  const value = entry.slice(prefix.length);
  return isLanguage(value) ? value : undefined;
}

export function detectLanguageFromAcceptLanguage(
  header: string | null,
): Language | undefined {
  if (!header) return undefined;
  for (const part of header.split(",")) {
    const [tag] = part.split(";");
    const primary = tag?.trim().toLowerCase().split("-")[0];
    if (primary === "zh" || primary === "ja" || primary === "en") {
      return primary;
    }
  }
  return undefined;
}

/** Cookie preference wins; falls back to the browser's accepted languages. */
export function preferredLanguage(
  cookieHeader: string | null,
  acceptLanguage: string | null,
): Language | undefined {
  return (
    parseLanguageCookie(cookieHeader) ??
    detectLanguageFromAcceptLanguage(acceptLanguage)
  );
}

/** Persist an explicit language choice in a cookie the server can read. */
export function rememberLanguage(language: Language): void {
  if (typeof document === "undefined") return;
  document.cookie = `${languageCookieName}=${language}; Max-Age=31536000; Path=/; SameSite=Lax`;
}

// --- Per-locale SEO metadata ---

type PageCopy = {
  title: string;
  description: string;
  socialDescription: string;
  imageAlt: string;
};

const pageCopyByLanguage: Record<PageKind, Record<Language, PageCopy>> = {
  home: {
    en: {
      title: "Pulse — Your market, at a glance",
      description:
        "Pulse is a lightweight macOS menu bar market tracker for prices, trends, and position P&L.",
      socialDescription:
        "Prices, trends, and position P&L—right from your macOS menu bar.",
      imageAlt: "Pulse macOS menu bar market tracker",
    },
    zh: {
      title: "Pulse — 你的市场，一眼掌握",
      description:
        "Pulse 是一款轻量的 macOS 菜单栏行情工具，价格、走势与持仓盈亏一眼掌握。",
      socialDescription: "价格、走势与持仓盈亏——就在你的 macOS 菜单栏。",
      imageAlt: "Pulse macOS 菜单栏行情工具",
    },
    ja: {
      title: "Pulse — あなたのマーケットを、ひと目で",
      description:
        "Pulse は、価格・トレンド・評価損益を macOS メニューバーで確認できる軽量な株価トラッカーです。",
      socialDescription: "価格・トレンド・評価損益——macOS メニューバーで。",
      imageAlt: "Pulse macOS メニューバー株価トラッカー",
    },
  },
  changelog: {
    en: {
      title: "Pulse Changelog — Every release at a glance",
      description:
        "Follow the Pulse release timeline and see what changed in every version of the macOS menu bar market tracker.",
      socialDescription: "New features, improvements, and fixes in every Pulse release.",
      imageAlt: "Pulse macOS menu bar market tracker",
    },
    zh: {
      title: "Pulse 更新日志 — 每一次更新都清楚可见",
      description:
        "从首次公开发布到最新版本，按时间查看 Pulse 的新功能、体验改进与问题修复。",
      socialDescription: "Pulse 每次发布的新功能、体验改进与问题修复。",
      imageAlt: "Pulse macOS 菜单栏行情工具",
    },
    ja: {
      title: "Pulse 更新履歴 — すべてのリリースをひと目で",
      description:
        "初回公開から最新バージョンまで、Pulse の新機能・改善・修正を時系列でたどれます。",
      socialDescription: "Pulse の毎回のリリースにおける新機能・改善・修正。",
      imageAlt: "Pulse macOS メニューバー株価トラッカー",
    },
  },
};

export function pageMeta(kind: PageKind, language: Language) {
  const copy = pageCopyByLanguage[kind][language];
  const canonicalPath = pagePath(kind, language);
  const englishPath = kind === "home" ? "/" : "/changelog";

  return {
    meta: [
      { title: copy.title },
      { name: "description", content: copy.description },
      { property: "og:title", content: copy.title },
      { property: "og:description", content: copy.socialDescription },
      { property: "og:type", content: "website" },
      { property: "og:image", content: `${siteUrl}/og-v2.png` },
      { property: "og:image:width", content: "1536" },
      { property: "og:image:height", content: "1024" },
      { property: "og:image:alt", content: copy.imageAlt },
      { name: "twitter:card", content: "summary_large_image" },
      { name: "twitter:title", content: copy.title },
      { name: "twitter:description", content: copy.socialDescription },
      { name: "twitter:image", content: `${siteUrl}/og-v2.png` },
    ],
    links: [
      { rel: "canonical", href: `${siteUrl}${canonicalPath}` },
      {
        rel: "alternate",
        hreflang: "x-default",
        href: `${siteUrl}${englishPath}`,
      },
      ...languages.map((candidate) => ({
        rel: "alternate",
        hreflang: candidate,
        href: `${siteUrl}${pagePath(kind, candidate)}`,
      })),
    ],
  };
}

export function homeMeta(language: Language) {
  return pageMeta("home", language);
}

export function changelogMeta(language: Language) {
  return pageMeta("changelog", language);
}
