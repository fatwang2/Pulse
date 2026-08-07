import { createFileRoute } from "@tanstack/react-router";
import { ChangelogPage } from "../components/changelog-page";
import { changelogMeta } from "../i18n";

export const Route = createFileRoute("/changelog")({
  head: () => changelogMeta("en"),
  component: () => <ChangelogPage language="en" />,
});
