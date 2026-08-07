import { createFileRoute } from "@tanstack/react-router";
import { ChangelogPage } from "../../components/changelog-page";
import { changelogMeta, isLanguage } from "../../i18n";

export const Route = createFileRoute("/$lang/changelog")({
  head: ({ params }) =>
    changelogMeta(isLanguage(params.lang) ? params.lang : "en"),
  component: LocalizedChangelog,
});

function LocalizedChangelog() {
  const { lang } = Route.useParams();
  return <ChangelogPage language={isLanguage(lang) ? lang : "en"} />;
}
