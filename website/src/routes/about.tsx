import { createFileRoute } from "@tanstack/react-router";
import { AboutPage } from "../components/about-page";
import { aboutMeta } from "../i18n";

export const Route = createFileRoute("/about")({
  head: () => aboutMeta("en"),
  component: () => <AboutPage language="en" />,
});
