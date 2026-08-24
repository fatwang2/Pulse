import { useEffect } from "react";

declare global {
  interface Window {
    umami?: {
      track: (name: string, data?: Record<string, unknown>) => void;
    };
  }
}

export function AnalyticsEvents() {
  useEffect(() => {
    function trackDownload(event: MouseEvent) {
      if (!(event.target instanceof Element)) {
        return;
      }

      const link = event.target.closest<HTMLAnchorElement>("a[href]");
      if (!link) {
        return;
      }

      const url = new URL(link.href, window.location.href);
      if (
        url.origin !== window.location.origin ||
        url.pathname !== "/download"
      ) {
        return;
      }

      window.umami?.track("file_download", {
        file_extension: "dmg",
        file_name: "Pulse",
        link_domain: url.hostname,
        link_text: link.textContent?.trim() ?? "",
        link_url: url.href,
      });
    }

    document.addEventListener("click", trackDownload, { capture: true });
    return () => {
      document.removeEventListener("click", trackDownload, { capture: true });
    };
  }, []);

  return null;
}
