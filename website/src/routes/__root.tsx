import {
  createRootRoute,
  HeadContent,
  Outlet,
  Scripts,
  useRouterState,
} from "@tanstack/react-router";
import { AnalyticsEvents } from "../components/analytics-events";
import "@fontsource-variable/geist";
import "@fontsource-variable/geist-mono";
import globalsCss from "../styles/globals.css?url";
import { htmlLang, languageFromPath, siteUrl } from "../i18n";

const googleAnalyticsMeasurementId = "G-J9GLF06LPP";

/**
 * Structured data: SoftwareApplication so search engines and AI assistants
 * can surface Pulse as a macOS app with a download link.
 */
const softwareApplicationJsonLd = JSON.stringify({
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Pulse",
  alternateName: "Pulse — macOS menu bar market tracker",
  applicationCategory: "UtilitiesApplication",
  operatingSystem: "macOS",
  description:
    "Pulse is a lightweight macOS menu bar market tracker for prices, trends, and position P&L.",
  url: siteUrl,
  downloadUrl: `${siteUrl}/download`,
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
  sameAs: ["https://github.com/fatwang2/Pulse"],
  inLanguage: ["en", "zh", "ja", "ko"],
});

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      {
        name: "naver-site-verification",
        content: "ea46d10027817e5163a8cf23a8343610bba79921",
      },
    ],
    links: [
      { rel: "stylesheet", href: globalsCss },
      { rel: "icon", href: "/icon.png", type: "image/png" },
      { rel: "apple-touch-icon", href: "/apple-icon.png" },
      {
        rel: "alternate",
        type: "application/atom+xml",
        href: "/feed.xml",
        title: "Pulse Changelog",
      },
    ],
    scripts: [
      {
        children: `
            window.dataLayer = window.dataLayer || [];
            window.gtag = function gtag(){window.dataLayer.push(arguments);}
            window.gtag("consent", "default", {
              analytics_storage: "granted",
              ad_storage: "denied",
              ad_user_data: "denied",
              ad_personalization: "denied"
            });
            window.gtag("set", "allow_google_signals", false);
            window.gtag("set", "allow_ad_personalization_signals", false);
            window.gtag("js", new Date());
            window.gtag("config", "${googleAnalyticsMeasurementId}");
          `,
      },
      {
        src: `https://www.googletagmanager.com/gtag/js?id=${googleAnalyticsMeasurementId}`,
        async: true,
      },
      {
        type: "application/ld+json",
        children: softwareApplicationJsonLd,
      },
    ],
  }),
  component: RootComponent,
});

function RootComponent() {
  const pathname = useRouterState({
    select: (state) => state.location.pathname,
  });
  const language = languageFromPath(pathname);

  return (
    <html lang={htmlLang(language)}>
      <head>
        <HeadContent />
      </head>
      <body>
        <Outlet />
        <AnalyticsEvents measurementId={googleAnalyticsMeasurementId} />
        <Scripts />
      </body>
    </html>
  );
}
