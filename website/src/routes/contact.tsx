import { createFileRoute } from "@tanstack/react-router";
import { ContactPage } from "../components/contact-page";
import { contactMeta } from "../i18n";

export const Route = createFileRoute("/contact")({
  head: () => contactMeta("en"),
  component: () => <ContactPage language="en" />,
});
