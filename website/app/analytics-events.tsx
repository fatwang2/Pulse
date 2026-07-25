"use client";

import { useEffect } from "react";

declare global {
  interface Window {
    gtag?: (...args: unknown[]) => void;
  }
}

interface AnalyticsEventsProps {
  measurementId: string;
}

export function AnalyticsEvents({ measurementId }: AnalyticsEventsProps) {
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

      window.gtag?.("event", "file_download", {
        send_to: measurementId,
        file_extension: "dmg",
        file_name: "Pulse",
        link_domain: url.hostname,
        link_text: link.textContent?.trim() ?? "",
        link_url: url.href,
        transport_type: "beacon",
      });
    }

    document.addEventListener("click", trackDownload, { capture: true });
    return () => {
      document.removeEventListener("click", trackDownload, { capture: true });
    };
  }, [measurementId]);

  return null;
}
