#!/usr/bin/env python3
"""Checks site/dist after a build: every internal link and image resolves, every page has a title, a
description, a canonical URL and reciprocal hreflang links, the JSON-LD parses, and no template tag is left.

    python3 site/tools/check.py
"""
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent
DIST = SITE / "dist"
ORIGIN = json.loads((SITE / "site.json").read_text())["origin"].rstrip("/")


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links, self.images, self.alternates, self.ids, self.jsonld = [], [], {}, set(), []
        self.title = self.description = self.canonical = None
        self._in = None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.add(a["id"])
        if tag == "a" and "href" in a:
            self.links.append(a["href"])
        elif tag == "img":
            self.images.append((a.get("src"), a.get("alt")))
        elif tag == "link" and a.get("rel") == "alternate" and "hreflang" in a:
            self.alternates[a["hreflang"]] = a["href"]
        elif tag == "link" and a.get("rel") == "canonical":
            self.canonical = a["href"]
        elif tag == "meta" and a.get("name") == "description":
            self.description = a.get("content")
        elif tag in ("title", "script"):
            self._in = tag if tag == "title" or a.get("type") == "application/ld+json" else None

    def handle_endtag(self, tag):
        self._in = None

    def handle_data(self, data):
        if self._in == "title":
            self.title = (self.title or "") + data
        elif self._in == "script":
            self.jsonld.append(data)


def target(href):
    """The file an internal URL serves, or None for external links."""
    if href.startswith(ORIGIN):
        href = href[len(ORIGIN):] or "/"
    if not href.startswith("/"):
        return None
    path = href.split("#")[0].split("?")[0]
    file = DIST / path.lstrip("/")
    return file / "index.html" if path.endswith("/") else file


def main():
    errors = []
    pages = {p: Page() for p in DIST.rglob("*.html")}
    for path, page in pages.items():
        page.feed(path.read_text())
    for path, page in pages.items():
        text = path.read_text()
        name = path.relative_to(DIST)
        if "{{" in text or re.search(r"\{(name|version)\}", text):
            errors.append(f"{name}: unrendered template tag")
        if not page.title or not page.description:
            errors.append(f"{name}: missing title or description")
        elif len(page.title) > 70 or len(page.description) > 170:
            print(f"note: {name}: title {len(page.title)} chars, description {len(page.description)} chars")
        for src, alt in page.images:
            if alt is None:
                errors.append(f"{name}: image {src} has no alt")
            if not target(src).exists():
                errors.append(f"{name}: missing image {src}")
        for href in page.links:
            t = target(href)
            if t is not None and not t.exists():
                errors.append(f"{name}: broken link {href}")
            if href.startswith("#") and href[1:] not in page.ids:
                errors.append(f"{name}: no anchor {href}")
        for block in page.jsonld:
            try:
                json.loads(block.replace("<\\/", "</"))
            except ValueError as e:
                errors.append(f"{name}: JSON-LD doesn't parse: {e}")
        if path.name == "404.html":
            continue
        if not page.canonical or target(page.canonical) != path:
            errors.append(f"{name}: canonical {page.canonical} doesn't point at itself")
        for lang, href in page.alternates.items():
            other = target(href)
            if not other.exists():
                errors.append(f"{name}: hreflang {lang} points at missing {href}")
            elif page.canonical not in pages[other].alternates.values():
                errors.append(f"{name}: hreflang {lang} page doesn't link back")
    for file in ("sitemap.xml", "robots.txt", "llms.txt", "llms-full.txt", "_headers"):
        if not (DIST / file).exists():
            errors.append(f"missing {file}")
    for e in errors:
        print("error:", e)
    print(f"checked {len(pages)} pages, {len(errors)} errors")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
