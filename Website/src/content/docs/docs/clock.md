---
title: Clock
description: The clock at the far end of the bar, its two styles, and the calendar behind it.
---

*Show Clock* puts a clock at the far end of the bar, after the Trash — the corner the eye goes to for
the time.

It is **off by default**, and it is the one thing here that duplicates something macOS already gives
you: the menu bar's own clock survives Eskele hiding the Dock. It earns its place on a full-width
bar, where the far end is empty anyway.

## Two styles

| | |
|---|---|
| **Digital** | Time, or day and time, or day, date and time. |
| **Dial** | A drawn analogue face. |

The 12- or 24-hour choice and the order of day and month come from *System Settings ▸ Language &
Region*, so the reading agrees with the menu bar's own clock rather than with a format of ours.

Digits are **monospaced**. Without that the cell changes width as the minutes tick over, and a
full-width bar reflows every button beside it once a minute.

## On a side bar

A side bar shows the time on **two lines and no date**. A bar one icon wide has nowhere to put
"Thursday 3 September", and an ellipsis where the clock was is worse than no date.

## The calendar

**Hover the clock for the month.** That is an `NSDatePicker` in its graphical style rather than a grid
of our own: it already knows which day the week starts on, how the month is named in your language
and which day today is — all of which a hand-drawn grid would get wrong for somebody.

**Clicking the clock** opens whatever application handles calendar links, which is your calendar app
whether or not it is Apple's.

## Ticking

The clock ticks at the top of each minute rather than every sixty seconds from whenever it started,
so it changes when every other clock on the machine does.

## No custom dials

uBar's timepieces are folders of PNGs described by a plist — a plug-in format, and a plug-in format
with one implementation is a file layout to maintain rather than a feature.

The dial is drawn from the current appearance's own colours instead, which suits a bar that is
already following the system's light and dark.
