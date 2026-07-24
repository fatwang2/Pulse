import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Pulse Changelog — Every release at a glance",
  description:
    "Follow the Pulse release timeline and see what changed in every version of the macOS menu bar market tracker.",
  openGraph: {
    title: "Pulse Changelog — Every release at a glance",
    description: "New features, improvements, and fixes in every Pulse release.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Pulse Changelog — Every release at a glance",
    description: "New features, improvements, and fixes in every Pulse release.",
  },
};

export default function ChangelogLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return children;
}
