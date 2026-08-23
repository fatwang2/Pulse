import { createFileRoute } from "@tanstack/react-router";
import { ContactPage } from "../../components/contact-page";
import { contactMeta, isLanguage } from "../../i18n";

export const Route = createFileRoute("/$lang/contact")({
  head: ({ params }) =>
    contactMeta(isLanguage(params.lang) ? params.lang : "en"),
  component: LocalizedContact,
});

function LocalizedContact() {
  const { lang } = Route.useParams();
  return <ContactPage language={isLanguage(lang) ? lang : "en"} />;
}
