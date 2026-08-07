import { createFileRoute } from "@tanstack/react-router";
import { HomePage } from "../components/home-page";
import { homeMeta } from "../i18n";

export const Route = createFileRoute("/")({
  head: () => homeMeta("en"),
  component: () => <HomePage language="en" />,
});
