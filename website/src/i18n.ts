/**
 * Language routing for the Pulse website.
 *
 * The site is served at four locales, one of which lives at the root:
 *   en -> /, /changelog, /about, /contact, /privacy
 *   zh -> /zh, /zh/changelog, /zh/about, /zh/contact, /zh/privacy
 *   ja -> /ja, /ja/changelog, /ja/about, /ja/contact, /ja/privacy
 *   ko -> /ko, /ko/changelog, /ko/about, /ko/contact, /ko/privacy
 *
 * The bare paths (`/`, `/changelog`, `/about`, `/contact`, `/privacy`)
 * redirect to the visitor's preferred locale (cookie first, then
 * Accept-Language) when it is not English; English is the canonical default
 * and stays at the root.
 */

export const languages = ["en", "zh", "ja", "ko"] as const;
export type Language = (typeof languages)[number];

export const defaultLanguage: Language = "en";
export const languageCookieName = "pulse-lang";
export const siteUrl = "https://www.pulseticker.app";

export type PageKind = "home" | "changelog" | "about" | "contact" | "privacy";

/** Organization identity for structured data, llms.txt, and the contact page. */
export const organizationInfo = {
  legalName: "SuperAgents, LLC",
  brandName: "PulseTicker",
  alternateName: "Pulse",
  supportEmail: "hello@pulseticker.app",
  technicalEmail: "sys@pulseticker.app",
  address: {
    streetAddress: "131 Continental Dr, Suite 305",
    addressLocality: "Newark",
    addressRegion: "DE",
    postalCode: "19713",
    addressCountry: "US",
  },
} as const;

export function isLanguage(value: unknown): value is Language {
  return value === "en" || value === "zh" || value === "ja" || value === "ko";
}

export function homePath(language: Language): string {
  return language === "en" ? "/" : `/${language}`;
}

export function changelogPath(language: Language): string {
  return language === "en" ? "/changelog" : `/${language}/changelog`;
}

export function aboutPath(language: Language): string {
  return language === "en" ? "/about" : `/${language}/about`;
}

export function contactPath(language: Language): string {
  return language === "en" ? "/contact" : `/${language}/contact`;
}

export function privacyPath(language: Language): string {
  return language === "en" ? "/privacy" : `/${language}/privacy`;
}

export function pagePath(kind: PageKind, language: Language): string {
  switch (kind) {
    case "home":
      return homePath(language);
    case "changelog":
      return changelogPath(language);
    case "about":
      return aboutPath(language);
    case "contact":
      return contactPath(language);
    case "privacy":
      return privacyPath(language);
  }
}

export function htmlLang(language: Language): string {
  if (language === "zh") return "zh-CN";
  if (language === "ja") return "ja";
  if (language === "ko") return "ko";
  return "en";
}

const pathLanguagePattern = /^\/(zh|ja|ko)(\/|$)/;

/** Language implied by a path; English when there is no language prefix. */
export function languageFromPath(pathname: string): Language {
  const match = pathname.match(pathLanguagePattern);
  if (match?.[1] === "zh") return "zh";
  if (match?.[1] === "ja") return "ja";
  if (match?.[1] === "ko") return "ko";
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
    if (
      primary === "zh" ||
      primary === "ja" ||
      primary === "ko" ||
      primary === "en"
    ) {
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
      title: "Pulse — macOS Menu Bar Stock Tracker",
      description:
        "Pulse is a lightweight macOS menu bar stock and market tracker for watchlists, price trends, and position P&L.",
      socialDescription:
        "Prices, trends, and position P&L—right from your macOS menu bar.",
      imageAlt: "Pulse macOS menu bar market tracker",
    },
    zh: {
      title: "Pulse — macOS 菜单栏股票行情工具",
      description:
        "Pulse 是一款轻量的 macOS 菜单栏股票行情工具，可查看自选价格、走势、持仓盈亏，以及美股、港股、A 股和加密货币行情。",
      socialDescription: "价格、走势与持仓盈亏——就在你的 macOS 菜单栏。",
      imageAlt: "Pulse macOS 菜单栏行情工具",
    },
    ja: {
      title: "Pulse — Mac メニューバー株価アプリ",
      description:
        "Pulse は、株価・暗号資産・トレンド・評価損益を Macのメニューバーで確認できる軽量な株価アプリです。",
      socialDescription: "価格・トレンド・評価損益——macOS メニューバーで。",
      imageAlt: "Pulse macOS メニューバー株価トラッカー",
    },
    ko: {
      title: "Pulse — macOS 메뉴 막대 주식 시세 앱",
      description:
        "Pulse는 관심 종목의 가격과 흐름, 보유 손익을 macOS 메뉴 막대에서 바로 확인하는 가벼운 시세 앱입니다. 한국·미국·일본·홍콩·중국 증시와 암호화폐, 귀금속을 지원합니다.",
      socialDescription: "가격, 흐름, 보유 손익 — macOS 메뉴 막대에서 바로.",
      imageAlt: "Pulse macOS 메뉴 막대 시세 앱",
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
    ko: {
      title: "Pulse 업데이트 내역 — 모든 릴리스를 한눈에",
      description:
        "첫 공개부터 최신 버전까지, Pulse의 새 기능과 개선, 수정 사항을 시간순으로 볼 수 있습니다.",
      socialDescription: "Pulse의 매 릴리스에 담긴 새 기능과 개선, 수정 사항.",
      imageAlt: "Pulse macOS 메뉴 막대 시세 앱",
    },
  },
  about: {
    en: {
      title: "About Pulse — Glanceable market data from the menu bar",
      description:
        "Pulse is a free, open-source macOS menu bar market tracker built by SuperAgents, LLC. Learn the philosophy behind glanceable market data.",
      socialDescription:
        "Pulse solves one problem: seeing your markets in the shortest possible time.",
      imageAlt: "Pulse macOS menu bar market tracker",
    },
    zh: {
      title: "关于 Pulse — 菜单栏里的 glanceable 行情",
      description:
        "Pulse 是由 SuperAgents, LLC 开发的免费开源 macOS 菜单栏行情工具。了解 glanceable 行情背后的设计理念。",
      socialDescription: "Pulse 只解决一个问题：用最短时间看到你关心的市场。",
      imageAlt: "Pulse macOS 菜单栏行情工具",
    },
    ja: {
      title: "Pulse について — メニューバーから一目で分かるマーケット",
      description:
        "Pulse は SuperAgents, LLC が開発する無料・オープンソースの macOS メニューバー株価アプリです。glanceable な行情データの設計思想をご紹介します。",
      socialDescription: "Pulse が解決するのは一つの問題：最短時間で市場を把握すること。",
      imageAlt: "Pulse macOS メニューバー株価トラッカー",
    },
    ko: {
      title: "Pulse 소개 — 메뉴 막대에서 한눈에 보는 시세",
      description:
        "Pulse는 SuperAgents, LLC가 개발한 무료 오픈소스 macOS 메뉴 막대 시세 앱입니다. 한눈에 보는 시세 데이터 철학을 알아보세요.",
      socialDescription: "Pulse가 푸는 문제는 하나: 가장 짧은 시간에 시장을 확인하는 것.",
      imageAlt: "Pulse macOS 메뉴 막대 시세 앱",
    },
  },
  contact: {
    en: {
      title: "Contact Pulse — Get in touch with the team",
      description:
        "Contact the Pulse team for support, feedback, bug reports, or business inquiries. Reach us by email or GitHub.",
      socialDescription: "Support, feedback, and bug reports for the Pulse menu bar market tracker.",
      imageAlt: "Pulse macOS menu bar market tracker",
    },
    zh: {
      title: "联系 Pulse — 与我们取得联系",
      description:
        "通过邮件或 GitHub 联系 Pulse 团队，获取支持、反馈、问题报告或商务咨询。",
      socialDescription: "Pulse 菜单栏行情工具的支持、反馈与问题报告。",
      imageAlt: "Pulse macOS 菜单栏行情工具",
    },
    ja: {
      title: "Pulse お問い合わせ — チームに連絡する",
      description:
        "Pulse チームへのお問い合わせ、フィードバック、バグ報告、ビジネスのご相談はメールまたは GitHub から。",
      socialDescription: "Pulse メニューバー株価トラッカーのサポート・フィードバック・バグ報告。",
      imageAlt: "Pulse macOS メニューバー株価トラッカー",
    },
    ko: {
      title: "Pulse 연락처 — 팀에 문의하기",
      description:
        "Pulse 팀에 지원, 피드백, 버그 신고 또는 비즈니스 문의를 이메일이나 GitHub로 보내주세요.",
      socialDescription: "Pulse 메뉴 막대 시세 앱의 지원, 피드백, 버그 신고.",
      imageAlt: "Pulse macOS 메뉴 막대 시세 앱",
    },
  },
  privacy: {
    en: {
      title: "Privacy — How Pulse handles your data",
      description:
        "Pulse collects anonymous usage analytics only. No watched symbols, positions, credentials, or personal data are sent. Read the full privacy policy.",
      socialDescription: "Anonymous analytics only. Your portfolio data never leaves your Mac.",
      imageAlt: "Pulse macOS menu bar market tracker",
    },
    zh: {
      title: "隐私 — Pulse 如何处理你的数据",
      description:
        "Pulse 仅收集匿名的使用分析数据。你的自选、持仓、凭证和个人数据绝不会上传。阅读完整隐私政策。",
      socialDescription: "仅匿名分析。你的持仓数据绝不离开你的 Mac。",
      imageAlt: "Pulse macOS 菜单栏行情工具",
    },
    ja: {
      title: "プライバシー — Pulse のデータ取り扱い",
      description:
        "Pulse は匿名の利用分析データのみを収集します。ウォッチリスト、評価損益、認証情報、個人データは送信されません。完全なプライバシーポリシーをご確認ください。",
      socialDescription: "匿名分析のみ。ポートフォリオデータは Mac から外に出ません。",
      imageAlt: "Pulse macOS メニューバー株価トラッカー",
    },
    ko: {
      title: "개인정보 — Pulse의 데이터 처리 방침",
      description:
        "Pulse는 익명 사용 분석 데이터만 수집합니다. 관심 종목, 보유 손익, 인증 정보, 개인 데이터는 전송되지 않습니다. 전체 개인정보 처리방침을 확인하세요.",
      socialDescription: "익명 분석만 수집. 포트폴리오 데이터는 Mac 밖으로 나가지 않습니다.",
      imageAlt: "Pulse macOS 메뉴 막대 시세 앱",
    },
  },
};

export function pageMeta(kind: PageKind, language: Language) {
  const copy = pageCopyByLanguage[kind][language];
  const canonicalPath = pagePath(kind, language);
  const englishPath = pagePath(kind, "en");

  // Naver does not support hreflang; the meta content-language tag is the
  // documented workaround for telling its crawler (Yeti) that a page is Korean.
  const naverMeta =
    language === "ko"
      ? [{ httpEquiv: "content-language", content: "ko" }]
      : [];

  return {
    meta: [
      { title: copy.title },
      { name: "description", content: copy.description },
      ...naverMeta,
      { property: "og:title", content: copy.title },
      { property: "og:description", content: copy.socialDescription },
      { property: "og:type", content: "website" },
      { property: "og:image", content: `${siteUrl}/og-v3.png` },
      { property: "og:image:width", content: "1536" },
      { property: "og:image:height", content: "1024" },
      { property: "og:image:alt", content: copy.imageAlt },
      { name: "twitter:card", content: "summary_large_image" },
      { name: "twitter:title", content: copy.title },
      { name: "twitter:description", content: copy.socialDescription },
      { name: "twitter:image", content: `${siteUrl}/og-v3.png` },
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

export function aboutMeta(language: Language) {
  return pageMeta("about", language);
}

export function contactMeta(language: Language) {
  return pageMeta("contact", language);
}

export function privacyMeta(language: Language) {
  return pageMeta("privacy", language);
}
