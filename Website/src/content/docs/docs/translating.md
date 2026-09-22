---
title: Translating Eskele
description: Adding a language is copying one directory and translating the right-hand side of each line.
---

The app is fully localisable and ships in English only. Adding a language is copying one directory
and translating the right-hand side of each line — no code changes, and nothing in the build needs
to be told the language exists.

```bash
cp -R Resources/en.lproj Resources/de.lproj
```

Then translate, in `Resources/de.lproj`:

| File | Holds |
|---|---|
| `Localizable.strings` | every string in the app's own windows, menus and labels |
| `Localizable.stringsdict` | the strings that quote a count, where the number of plural forms is the language's business rather than the sentence's |
| `InfoPlist.strings` | what macOS shows before the app does: the Automation consent prompt, and the Finder Services entry |

In `Localizable.strings` the key on the left is the English text, and it is what the code looks the
string up by — leave it exactly as it is and change only the value on the right. Each entry carries a
note saying where it appears. An untranslated key falls back to English on its own, so a
half-finished language works.

`Localizable.stringsdict` needs a thought rather than a translation. English declares `one` and
`other`; give your language the categories it actually uses — `zero`, `one`, `two`, `few`, `many`,
`other` — and only `other` is required.

## Checking it

`make test` checks the language the same way it checks the code:

- every localisable string in the source has an English entry, named by file and line if it does not;
- the English catalogue has nothing spare, so nobody translates dead text;
- every other language holds exactly the keys English does, and names the missing ones if not.

To see what the catalogue would look like if it were generated from the source right now:

```bash
ESKELE_DUMP_STRINGS=1 swift test --filter everyLocalizableStringHasAnEnglishEntry
```

That writes `/tmp/Eskele-Localizable.strings`.

## What is deliberately not translated

The `--diagnose` reports, the log messages, and the seeded `badges.json`, `progress.json` and
`Icons/README.txt` templates all stay English. They are what you paste into a bug report or a shell,
and a support conversation is worse when the output arrives in a language neither party shares.
