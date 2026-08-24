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
import { htmlLang, languageFromPath, organizationInfo, siteUrl } from "../i18n";

const umamiScriptSrc = "https://umami.fatwang2.com/script.js";
const umamiWebsiteId = "bf5c4531-e265-4858-afd9-ed014426038d";

/**
 * Structured data: SoftwareApplication so search engines and AI assistants
 * can surface Pulse as a macOS app with a download link.
 */
const softwareApplicationJsonLd = JSON.stringify({
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Pulse",
  alternateName: ["PulseTicker", "Pulse — macOS menu bar market tracker"],
  applicationCategory: "UtilitiesApplication",
  operatingSystem: "macOS",
  description:
    "Pulse is a lightweight macOS menu bar market tracker for prices, trends, and position P&L.",
  url: siteUrl,
  downloadUrl: `${siteUrl}/download`,
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
  sameAs: ["https://github.com/fatwang2/Pulse", "https://github.com/superagents-lab"],
  inLanguage: ["en", "zh", "ja", "ko"],
});

/**
 * Structured data: Organization so AI agents can verify business legitimacy
 * and answer contact queries. Includes contactPoint and PostalAddress.
 */
const organizationJsonLd = JSON.stringify({
  "@context": "https://schema.org",
  "@type": "Organization",
  name: organizationInfo.legalName,
  alternateName: organizationInfo.alternateName,
  url: siteUrl,
  logo: `${siteUrl}/icon.png`,
  contactPoint: {
    "@type": "ContactPoint",
    email: organizationInfo.supportEmail,
    contactType: "customer support",
    availableLanguage: ["en", "zh", "ja", "ko"],
  },
  address: {
    "@type": "PostalAddress",
    streetAddress: organizationInfo.address.streetAddress,
    addressLocality: organizationInfo.address.addressLocality,
    addressRegion: organizationInfo.address.addressRegion,
    postalCode: organizationInfo.address.postalCode,
    addressCountry: organizationInfo.address.addressCountry,
  },
  sameAs: ["https://github.com/fatwang2/Pulse", "https://github.com/superagents-lab"],
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
        src: umamiScriptSrc,
        defer: true,
        "data-website-id": umamiWebsiteId,
      },
      {
        type: "application/ld+json",
        children: softwareApplicationJsonLd,
      },
      {
        type: "application/ld+json",
        children: organizationJsonLd,
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
        <AnalyticsEvents />
        <Scripts />
      </body>
    </html>
  );
}
