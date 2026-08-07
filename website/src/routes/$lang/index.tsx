import { createFileRoute } from "@tanstack/react-router";
import { HomePage } from "../../components/home-page";
import { homeMeta, isLanguage } from "../../i18n";

export const Route = createFileRoute("/$lang/")({
  head: ({ params }) => homeMeta(isLanguage(params.lang) ? params.lang : "en"),
  component: LocalizedHome,
});

function LocalizedHome() {
  const { lang } = Route.useParams();
  return <HomePage language={isLanguage(lang) ? lang : "en"} />;
}
