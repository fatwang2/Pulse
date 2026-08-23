import { createFileRoute } from "@tanstack/react-router";
import { PrivacyPage } from "../../components/privacy-page";
import { privacyMeta, isLanguage } from "../../i18n";

export const Route = createFileRoute("/$lang/privacy")({
  head: ({ params }) =>
    privacyMeta(isLanguage(params.lang) ? params.lang : "en"),
  component: LocalizedPrivacy,
});

function LocalizedPrivacy() {
  const { lang } = Route.useParams();
  return <PrivacyPage language={isLanguage(lang) ? lang : "en"} />;
}
