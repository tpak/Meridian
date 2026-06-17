# Meridian 4.0.0 — "Daybreak"

Meridian 4.0 is the biggest release since 3.0 — a complete visual redesign built around a simple idea: a world clock should *feel* like the time of day, not just print it. The new **Daybreak** popover paints the sky for wherever you are right now, and every city shows whether the sun is up or down at a glance.

Your cities, labels, favorites, and preferences all carry over automatically.

---

## A fresh look — the Daybreak redesign

- **A living sky.** The popover's hero shifts through dawn, day, dusk, and night to match the real time of day at your current location, with a sun or moon disc that reflects the current phase.
- **Sun & moon, everywhere.** Every city shows a sun or moon glyph that flips live as that city crosses its own sunrise and sunset.
- **Redesigned city cards.** Each place shows its time, whether it's day or night there, and how far ahead or behind it is *relative to where you are right now*.
- **A reimagined time-travel scrubber** with a tick ruler, day-boundary markers, and a centered handle carrying the current sun/moon.
- **A brand-new native Settings window** with a clean sidebar: **Cities, Menu Bar, Appearance, Time Travel,** and **General**.
- **A new "Midnight Sundial" app icon** and matching menu-bar icons.

## New features

- **Type a time to travel to it.** Double-click any time in the popover, type a new one (`3:30 PM`, `15:30`, `3pm`…), and every other clock instantly shows what it'd be there.
- **Make each city yours.** Give any location a custom **label** and a per-city **color dot**.
- **Home vs. current location.** Pick a **Home** city and let your **current location** follow your Mac's time zone as you travel — Meridian keeps them straight.
- **Five menu-bar density presets** — *Compact, With day, With date, Dense 24h,* and *Mono* (no dots) — so the menu bar shows exactly what you want.
- **New opt-in "Stacked" menu-bar layout** that stacks city name over time so more favorites fit in a narrow or notched menu bar.
- **Accent color themes** to personalize switches, selections, and scrubber highlights.
- **Adjustable text size** for the popover.
- **Configurable time-travel range** and a snap step (5 / 15 / 30 / 60 min).
- **Float the popover on top** and drag it anywhere — it remembers where you parked it.
- **Copy all city times** to the clipboard from the footer as a clean, one-per-line list.

## Improvements

- **Smarter city search** that ranks results and handles UTC, spaces, and place names correctly, with full keyboard and hover navigation.
- Newly added cities now **drop into their correctly sorted position**.
- Your **current time zone is seeded automatically** whenever the city list is empty.
- **Sort your cities** by time difference, name, or label, with a direction toggle.
- The single-line menu-bar item is now **vertically centered**.
- Your current location **stays pinned to system time**, so scrubbing never accidentally moves it.
- **Full localization** of the new interface across all 15 supported languages.
- Cleaner Settings with shaded command buttons and refreshed fresh-install defaults.

## Fixes

- Fixed city rows that could clip in the list.
- Fixed a regression where the current time zone wasn't seeded on first run.
- Fixed inconsistent labels in search results and partial-geocode artifacts.
- Fixed time-travel so it snaps cleanly to the grid and aligns to day boundaries.
- Restored the draggable floating popover and renamed the control from "Pin" to "Float."

---

## Upgrading

Meridian updates itself — you'll be offered 4.0 automatically. Your time zones and settings are preserved across the upgrade. Want early access to future releases? Turn on **Settings → General → Receive beta releases**.

<sub>Key PRs in this release: #140 (Daybreak redesign), #141 (localization), #142 & #143 (stacked menu-bar layout, settings polish, new icons).</sub>
