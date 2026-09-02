#!/usr/bin/env python3
"""Turn a release-notes Markdown file into the HTML fragment Sparkle embeds.

Usage: release-notes-html.py NOTES.md > Pulse-X.Y.Z.html

The notes are written for the GitHub release, so two parts are dropped for
the update alert: the "Pulse X.Y.Z" headline (Sparkle names the version
itself) and the first-install paragraph (the reader is already updating).
The output carries no DOCTYPE or <body>; that is what makes generate_appcast
embed it in the item's <description> instead of linking to it.
"""
import html
import re
import sys


def bullets(lines):
    """The block as list items, wrapped continuation lines folded in; None if it is not a list."""
    items = []
    for line in lines:
        text = line.strip()
        if text.startswith("- "):
            items.append(text[2:].strip())
        elif items and text:
            items[-1] += " " + text
        else:
            return None
    return items or None


def unordered_list(items):
    return "<ul>" + "".join(f"<li>{html.escape(item, quote=False)}</li>" for item in items) + "</ul>"


def render(markdown):
    blocks = [block for block in re.split(r"\n\s*\n", markdown.strip()) if block.strip()]
    fragments = []
    for index, block in enumerate(blocks):
        lines = block.strip("\n").splitlines()
        if index == 0 and len(lines) == 1 and re.fullmatch(r"Pulse \d+\.\d+\.\d+", lines[0].strip()):
            continue
        if lines[0].strip().startswith("For first-time installation"):
            continue
        items = bullets(lines)
        if items:
            fragments.append(unordered_list(items))
            continue
        heading = lines[0].strip()
        items = bullets(lines[1:]) if heading.endswith(":") else None
        if items:
            fragments.append(f"<h3>{html.escape(heading.rstrip(':'), quote=False)}</h3>")
            fragments.append(unordered_list(items))
            continue
        paragraph = " ".join(line.strip() for line in lines)
        fragments.append(f"<p>{html.escape(paragraph, quote=False)}</p>")
    return "\n".join(fragments) + "\n"


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: release-notes-html.py NOTES.md")
    with open(sys.argv[1], encoding="utf-8") as notes:
        sys.stdout.write(render(notes.read()))


if __name__ == "__main__":
    main()
