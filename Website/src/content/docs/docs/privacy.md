---
title: Privacy
description: What Kagami collects (nothing), and exactly what an update check sends.
---

Kagami **collects nothing and sends nothing about you.** There is no telemetry, no analytics, no
crash reporting and no account. The images you flash and the drives you flash them to never leave
your Mac.

## The one time it goes online

Kagami goes online only to look for an update, and out of the box only when you ask — *Check for
Updates…* in the Kagami menu, or *Check Now* in Settings. Choosing *Install Automatically* or *Ask
Before Installing* in Settings makes it check once a day.

A check is one request to GitHub for `appcast.xml` on the latest release, and — if there is a newer
version and you choose to install it — a second one for the DMG. Both send the same two headers from
every copy of Kagami:

| Header | Value |
|---|---|
| `User-Agent` | `Sparkle` |
| `Accept-Language` | `*` |

So the request does not name your version of Kagami or of macOS, or the languages you use. Sparkle's
optional *system profile* — anonymous statistics about your Mac — is never offered and never sent,
even if a `defaults write` turns it on.

GitHub, which hosts the releases, sees the request like any other web request, including your IP
address. Its [privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
applies to that.

## What stays on your Mac

Kagami stores only Sparkle's own preferences — whether to check automatically, and when it last did —
in `~/Library/Preferences/de.alhaidari.Kagami.plist`.
