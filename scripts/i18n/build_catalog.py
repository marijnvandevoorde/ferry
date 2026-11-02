"""Writes App/Localizable.xcstrings and App/InfoPlist.xcstrings from mac_translations.py."""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from mac_translations import T, PLURALS, VERBATIM, INFO_PLIST

LANGS = ["fr", "es", "it", "de", "nl"]
root = os.path.join(os.path.dirname(__file__), "..", "..", "App")

def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}

def plural_sub(one, other):
    return {"items": {"argNum": 1, "formatSpecifier": "lld",
                      "variations": {"plural": {"one": unit(one), "other": unit(other)}}}}

strings = {}
for key, values in T.items():
    strings[key] = {"localizations": {lang: unit(v) for lang, v in zip(LANGS, values)}}
for key in VERBATIM:
    strings[key] = {"shouldTranslate": False}
for key, (en_format, forms, formats) in PLURALS.items():
    locs = {"en": {**unit(en_format), "substitutions": plural_sub(*forms["en"])}}
    for lang in LANGS:
        fmt = formats[lang] if formats else "%#@items@"
        locs[lang] = {**unit(fmt), "substitutions": plural_sub(*forms[lang])}
    strings[key] = {"localizations": locs}

with open(os.path.join(root, "Localizable.xcstrings"), "w") as f:
    json.dump({"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}, f, ensure_ascii=False, indent=2)

info = {key: {"localizations": {"en": unit(en), **{lang: unit(v) for lang, v in zip(LANGS, values)}}}
        for key, (en, values) in INFO_PLIST.items()}
info["CFBundleDisplayName"] = {"shouldTranslate": False}
info["CFBundleName"] = {"shouldTranslate": False}
with open(os.path.join(root, "InfoPlist.xcstrings"), "w") as f:
    json.dump({"sourceLanguage": "en", "strings": info, "version": "1.0"}, f, ensure_ascii=False, indent=2)
print(f"{len(strings)} strings, {len(info)} Info.plist strings")
