import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { headers } from "next/headers";
import Script from "next/script";
import { AnalyticsEvents } from "./analytics-events";
import "./globals.css";

const googleAnalyticsMeasurementId = "G-J9GLF06LPP";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host =
    requestHeaders.get("x-forwarded-host") ??
    requestHeaders.get("host") ??
    "localhost:3001";
  const protocol =
    requestHeaders.get("x-forwarded-proto") ??
    (host.startsWith("localhost") ? "http" : "https");
  const metadataBase = new URL(`${protocol}://${host}`);

  return {
    metadataBase,
    title: "Pulse — Your market, at a glance",
    description:
      "Pulse is a lightweight macOS menu bar market tracker for prices, trends, and position P&L.",
    openGraph: {
      title: "Pulse — Your market, at a glance",
      description: "Prices, trends, and position P&L—right from your macOS menu bar.",
      type: "website",
      images: [
        {
          url: new URL("/og-v2.png", metadataBase),
          width: 1536,
          height: 1024,
          alt: "Pulse macOS menu bar market tracker",
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title: "Pulse — Your market, at a glance",
      description: "Prices, trends, and position P&L—right from your macOS menu bar.",
      images: [new URL("/og-v2.png", metadataBase)],
    },
  };
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <head>
        <Script id="google-analytics" strategy="beforeInteractive">
          {`
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
          `}
        </Script>
        <Script
          src={`https://www.googletagmanager.com/gtag/js?id=${googleAnalyticsMeasurementId}`}
          strategy="afterInteractive"
        />
      </head>
      <body className={`${geistSans.variable} ${geistMono.variable}`}>
        {children}
        <AnalyticsEvents measurementId={googleAnalyticsMeasurementId} />
      </body>
    </html>
  );
}
