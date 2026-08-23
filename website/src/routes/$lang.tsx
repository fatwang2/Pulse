import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { isLanguage } from "../i18n";

/**
 * Localized layout. English has no prefix (it lives at the root), so a
 * bare `/en` (or an unknown locale) falls back to the English page that
 * matches the current path.
 */
export const Route = createFileRoute("/$lang")({
  beforeLoad: ({ params, location }) => {
    if (params.lang === "en" || !isLanguage(params.lang)) {
      const path = location.pathname;
      const fallback = path.includes("/changelog")
        ? "/changelog"
        : path.includes("/about")
          ? "/about"
          : path.includes("/contact")
            ? "/contact"
            : path.includes("/privacy")
              ? "/privacy"
              : "/";
      throw redirect({ href: fallback, statusCode: 302 });
    }
  },
  component: () => <Outlet />,
});
