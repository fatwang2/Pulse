import { createFileRoute } from "@tanstack/react-router";
import { PrivacyPage } from "../components/privacy-page";
import { privacyMeta } from "../i18n";

export const Route = createFileRoute("/privacy")({
  head: () => privacyMeta("en"),
  component: () => <PrivacyPage language="en" />,
});
