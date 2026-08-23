import { createFileRoute } from "@tanstack/react-router";
import { AboutPage } from "../../components/about-page";
import { aboutMeta, isLanguage } from "../../i18n";

export const Route = createFileRoute("/$lang/about")({
  head: ({ params }) =>
    aboutMeta(isLanguage(params.lang) ? params.lang : "en"),
  component: LocalizedAbout,
});

function LocalizedAbout() {
  const { lang } = Route.useParams();
  return <AboutPage language={isLanguage(lang) ? lang : "en"} />;
}
