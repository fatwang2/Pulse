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
import { htmlLang, languageFromPath } from "../i18n";

const googleAnalyticsMeasurementId = "G-J9GLF06LPP";

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
    ],
    links: [
      { rel: "stylesheet", href: globalsCss },
      { rel: "icon", href: "/icon.png", type: "image/png" },
      { rel: "apple-touch-icon", href: "/apple-icon.png" },
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
