#!/usr/bin/env python3
"""Builds the marketing site into site/dist: every page in every language, plus sitemap.xml, robots.txt,
llms.txt, llms-full.txt and _headers.

    python3 site/tools/build.py

The app's name, the site's address and the download links come from site/site.json; every string from
site/i18n/<lang>.json, where {name} and {version} are filled in. Templates in site/templates use
{{key.path}} for a value, {{#each key}}…{{/each}} to repeat a block (inside it, {{.field}} or {{.}}), and
{{#if key}}…{{/if}}; nest a block in one of the same kind
by numbering it ({{#each2 .links}}…{{/each2}}). Values are HTML-escaped. Standard library only, so Cloudflare Pages can run it.
"""
import html
import json
import re
import shutil
from datetime import date
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent
DIST = SITE / "dist"
CONFIG = json.loads((SITE / "site.json").read_text())
CAMERAS = json.loads((SITE / "cameras.json").read_text())
LANGS = CONFIG["languages"]
ORIGIN = CONFIG["origin"].rstrip("/")
TODAY = date.today().isoformat()

# Pages: template name -> path below the language prefix ("" is the home page).
PAGES = {"home": "", "cameras": "cameras/", "privacy": "privacy/"}


def fill(value, extra=None):
    """Replaces {name}, {version} and friends in every string of a nested structure."""
    tokens = {"name": CONFIG["name"], "version": CONFIG["version"], **(extra or {})}
    if isinstance(value, str):
        return re.sub(r"\{(\w+)\}", lambda m: str(tokens.get(m.group(1), m.group(0))), value)
    if isinstance(value, list):
        return [fill(v, extra) for v in value]
    if isinstance(value, dict):
        return {k: fill(v, extra) for k, v in value.items()}
    return value


def lookup(ctx, path, scope=None):
    if path == ".":
        return scope
    if path.startswith("."):
        ctx, path = scope, path[1:]
    for part in path.split("."):
        if isinstance(ctx, dict) and part in ctx:
            ctx = ctx[part]
        else:
            raise KeyError(path)
    return ctx


BLOCK = re.compile(r"\{\{#((each|if)\d?) ([\w.]+)\}\}(.*?)\{\{/\1\}\}", re.S)
VALUE = re.compile(r"\{\{(=?)([\w.]+|\.)\}\}")


def render(template, ctx, scope=None):
    """{{x}} is escaped, {{=x}} is inserted as-is (for HTML the build generates)."""
    def block(m):
        _, kind, path, body = m.groups()
        value = lookup(ctx, path, scope)
        if kind == "if":
            return render(body, ctx, scope) if value else ""
        return "".join(render(body, ctx, item) for item in value)

    out = BLOCK.sub(block, template)

    def value(m):
        v = lookup(ctx, m.group(2), scope)
        return str(v) if m.group(1) else html.escape(str(v))

    return VALUE.sub(value, out)


def url(lang, page_path):
    return f"{ORIGIN}/{'' if lang == 'en' else lang + '/'}{page_path}"


def rel(lang, page_path):
    return f"/{'' if lang == 'en' else lang + '/'}{page_path}"


def alternates(page_path):
    links = [f'<link rel="alternate" hreflang="{l}" href="{url(l, page_path)}">' for l in LANGS]
    links.append(f'<link rel="alternate" hreflang="x-default" href="{url("en", page_path)}">')
    return "\n".join(links)


def language_links(lang, page_path, strings):
    return [{"code": l, "name": strings[l]["lang_name"], "href": rel(l, page_path), "current": l == lang} for l in LANGS]


def downloads(t):
    d = CONFIG["downloads"]
    soon = set(CONFIG.get("placeholders", []))

    def link(key, label):
        return {"href": d[key], "label": label, "soon": key in soon}

    return [
        {"os": t["download"]["mac"], "slug": "mac", "req": t["download"]["mac_req"],
         "links": [link("mac_app_store", t["download"]["mac_store"]), link("mac_dmg", t["download"]["mac_dmg"])]},
        {"os": t["download"]["windows"], "slug": "windows", "req": t["download"]["windows_req"],
         "links": [link("windows_msi", t["download"]["windows_msi"])]},
        {"os": t["download"]["linux"], "slug": "linux", "req": t["download"]["linux_req"],
         "links": [link("linux_appimage", t["download"]["linux_appimage"]), link("linux_deb", t["download"]["linux_deb"])]},
    ]


def camera_tables(t):
    return [{
        "brand": b["brand"], "slug": b["slug"],
        "models": [{"model": m, "status": s, "status_label": t["cameras"]["status"][s],
                    "note": t["cameras"]["notes"].get(n, "") if n else ""} for m, s, n in b["models"]],
    } for b in CAMERAS["brands"]]


def jsonld(lang, page, t, page_path):
    graph = [{
        "@type": "WebSite", "@id": f"{ORIGIN}/#website", "url": f"{ORIGIN}/", "name": CONFIG["name"],
        "inLanguage": LANGS,
    }]
    app = {
        "@type": "SoftwareApplication", "@id": f"{ORIGIN}/#app", "name": CONFIG["name"],
        "description": t["meta"]["home_description"], "url": url(lang, ""),
        "applicationCategory": "MultimediaApplication", "operatingSystem": "macOS 14+, Windows 10+, Linux",
        "softwareVersion": CONFIG["version"], "license": "https://opensource.org/licenses/MIT",
        "isAccessibleForFree": True, "codeRepository": CONFIG["repo"],
        "screenshot": [f"{ORIGIN}/img/{n}" for n in ("screenshot-mac.png", "screenshot-desktop.png")],
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "EUR"},
        "inLanguage": LANGS,
    }
    if page == "home":
        graph.append(app)
        graph.append({"@type": "FAQPage", "mainEntity": [
            {"@type": "Question", "name": i["q"], "acceptedAnswer": {"@type": "Answer", "text": i["a"]}}
            for i in t["faq"]["items"]]})
    elif page == "cameras":
        graph.append({"@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": CONFIG["name"], "item": url(lang, "")},
            {"@type": "ListItem", "position": 2, "name": t["cameras"]["h1"], "item": url(lang, page_path)}]})
    data = {"@context": "https://schema.org", "@graph": graph}
    # "</" can't appear inside a script element.
    text = json.dumps(data, ensure_ascii=False, indent=1).replace("</", "<\\/")
    return f'<script type="application/ld+json">\n{text}\n</script>'


def page_context(lang, page, strings):
    t = strings[lang]
    page_path = PAGES.get(page, "")
    title = {"home": t["meta"]["home_title"], "cameras": t["meta"]["cameras_title"],
             "privacy": t["meta"]["privacy_title"], "404": t["meta"]["notfound_title"]}[page]
    description = {"home": t["meta"]["home_description"], "cameras": t["meta"]["cameras_description"],
                   "privacy": t["meta"]["privacy_description"], "404": t["meta"]["home_description"]}[page]
    return {
        **t, "lang": lang, "site": CONFIG, "title": title, "description": description,
        "canonical": url(lang, page_path), "is_404": page == "404",
        "alternates": "" if page == "404" else alternates(page_path),
        "jsonld": "" if page == "404" else jsonld(lang, page, t, page_path),
        "languages": language_links(lang, page_path if page != "404" else "", strings),
        "home": rel(lang, ""), "cameras_url": rel(lang, "cameras/"), "privacy_url": rel(lang, "privacy/"),
        "downloads": downloads(t), "camera_tables": camera_tables(t),
        "year": TODAY[:4],
    }


def build_page(lang, page, strings, base):
    body = (SITE / "templates" / f"{page}.html").read_text()
    ctx = page_context(lang, page, strings)
    ctx["content"] = render(body, ctx)
    return render(base, ctx)


def llms(strings, full=False):
    """llms.txt: what the site says, for a reader that reads rather than browses (llmstxt.org)."""
    t = strings["en"]
    n = CONFIG["name"]
    d = CONFIG["downloads"]
    soon = set(CONFIG.get("placeholders", []))
    lines = [f"# {n}", "", f"> {t['meta']['home_description']}", "",
             t["why"]["p1"], "", t["why"]["p2"], "",
             "## Facts", "",
             f"- Platforms: macOS 14 or later (imports into Apple Photos or a folder), Windows 10 and 11, Linux, and a command-line tool (ferryctl).",
             f"- Price: free. License: MIT. Source code: {CONFIG['repo']}",
             f"- Current version: {CONFIG['version']}.",
             "- Connection: the camera's own Wi-Fi network, or the home network with Fujifilm PC AutoSave. No cable, no card reader, no cloud.",
             "- Fujifilm cameras send JPEG files over Wi-Fi, not RAF raw files.",
             "- The app never deletes photos from the camera, has no account and collects no data.",
             f"- Languages: {', '.join(strings[l]['lang_name'] for l in LANGS)}.",
             "", "## What it is not", ""]
    lines += [f"- {i}" for i in t["not"]["items"]]
    lines += ["", "## Downloads", ""]
    for key, label in [("mac_app_store", "Mac App Store"), ("mac_dmg", "Mac (.dmg)"), ("windows_msi", "Windows installer"),
                       ("linux_appimage", "Linux AppImage"), ("linux_deb", "Linux .deb"), ("cli", "Command line")]:
        lines.append(f"- {label}: {'not released yet' if key in soon else d[key]}")
    lines += ["", "## Supported cameras", ""]
    for b in camera_tables(t):
        for m in b["models"]:
            lines.append(f"- {b['brand']} {m['model']}: {m['status_label']}." + (f" {m['note']}" if m["note"] else ""))
    if full:
        lines += ["", "## How it works", ""]
        lines += [f"{i}. {s['t']}: {s['d']}" for i, s in enumerate(t["how"]["steps"], 1)]
        lines += ["", t["how"]["autosave"], "", "## Features", ""]
        lines += [f"- {f['t']}: {f['d']}" for f in t["features"]["items"]]
        lines += ["", "## Questions", ""]
        for f in t["faq"]["items"]:
            lines += [f"### {f['q']}", "", f["a"], ""]
        lines += ["## Privacy", ""]
        for s in t["privacy"]["sections"]:
            lines += [f"### {s['h']}", "", s["p"], ""]
    lines += ["", "## Pages", ""]
    lines += [f"- [Home]({url('en', '')}): {t['meta']['home_description']}",
              f"- [Supported cameras]({url('en', 'cameras/')}): {t['meta']['cameras_description']}",
              f"- [Privacy]({url('en', 'privacy/')}): {t['meta']['privacy_description']}"]
    if not full:
        lines.append(f"- [Everything on one page]({ORIGIN}/llms-full.txt)")
    lines += ["", "Other languages: " + ", ".join(f"{strings[l]['lang_name']} {url(l, '')}" for l in LANGS if l != "en")]
    return "\n".join(lines).rstrip() + "\n"


def sitemap():
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">']
    for page_path in PAGES.values():
        for lang in LANGS:
            out.append(f"  <url><loc>{url(lang, page_path)}</loc><lastmod>{TODAY}</lastmod>")
            out += [f'    <xhtml:link rel="alternate" hreflang="{l}" href="{url(l, page_path)}"/>' for l in LANGS]
            out.append(f'    <xhtml:link rel="alternate" hreflang="x-default" href="{url("en", page_path)}"/>')
            out.append("  </url>")
    out.append("</urlset>")
    return "\n".join(out) + "\n"


def robots():
    # Search engines and AI assistants are all welcome: being found and being quoted correctly is the point.
    return f"User-agent: *\nAllow: /\n\nSitemap: {ORIGIN}/sitemap.xml\n"


def main():
    strings = {l: fill(json.loads((SITE / "i18n" / f"{l}.json").read_text())) for l in LANGS}
    for lang in LANGS[1:]:
        missing = keys(strings["en"]) - keys(strings[lang])
        if missing:
            raise SystemExit(f"{lang}.json is missing: {', '.join(sorted(missing))}")
    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir()
    for folder in ("css", "fonts", "img"):
        shutil.copytree(SITE / folder, DIST / folder)
    for name in ("_headers", "_redirects"):
        if (SITE / name).exists():
            shutil.copy(SITE / name, DIST / name)
    base = (SITE / "templates" / "base.html").read_text()
    for lang in LANGS:
        prefix = DIST if lang == "en" else DIST / lang
        for page, page_path in PAGES.items():
            target = prefix / page_path / "index.html"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(build_page(lang, page, strings, base))
        (prefix / "404.html").write_text(build_page(lang, "404", strings, base))
    (DIST / "sitemap.xml").write_text(sitemap())
    (DIST / "robots.txt").write_text(robots())
    (DIST / "llms.txt").write_text(llms(strings))
    (DIST / "llms-full.txt").write_text(llms(strings, full=True))
    print(f"Built {len(LANGS) * (len(PAGES) + 1)} pages for {CONFIG['name']} into {DIST.relative_to(SITE.parent)}")


def keys(d, prefix=""):
    out = set()
    for k, v in d.items():
        if isinstance(v, dict):
            out |= keys(v, f"{prefix}{k}.")
        else:
            out.add(f"{prefix}{k}")
    return out


if __name__ == "__main__":
    main()
