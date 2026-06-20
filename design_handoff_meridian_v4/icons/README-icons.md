# Meridian — Icon Assets & Implementation Instructions

Final icon: **“Midnight Sundial.”** A warm sun seated as the 12-o'clock mark of a fan of hour ticks, on a deep midnight-navy sky, above a horizon base line. One color artwork is used everywhere it appears in color (Dock, App Store, Finder, app list); a separate monochrome **template** is used for the menu-bar item.

---

## ⚠️ First, one rename (sandbox limitation)
The export environment couldn't write the `@` character, so every Retina file was saved with **`-2x`** instead of **`@2x`**. macOS `iconutil` and Xcode asset catalogs require the real `@2x`. **Before using the iconset, restore the `@`:**

```bash
cd icons/AppIcon.iconset
for f in *-2x.png; do mv "$f" "${f/-2x/@2x}"; done
cd ../menubar
for f in *-2x.png; do mv "$f" "${f/-2x/@2x}"; done
```

(Or just rename them by hand — `icon_16x16-2x.png` → `icon_16x16@2x.png`, etc.)

---

## What's in this folder

```
icons/
├── AppIcon-source.svg            ← vector master, full-bleed squircle (color)
├── AppIcon-1024.png              ← 1024px master (color)
├── AppIcon.iconset/              ← all 10 macOS sizes (see rename note)
│   ├── icon_16x16.png            icon_16x16@2x.png
│   ├── icon_32x32.png            icon_32x32@2x.png
│   ├── icon_128x128.png          icon_128x128@2x.png
│   ├── icon_256x256.png          icon_256x256@2x.png
│   └── icon_512x512.png          icon_512x512@2x.png
├── MenuBarIcon-template.svg      ← vector master, monochrome menu-bar glyph
└── menubar/                      ← rasterized template PNGs (black + alpha)
    ├── meridian-menubarTemplate-16pt.png   …-16pt@2x.png
    ├── meridian-menubarTemplate-18pt.png   …-18pt@2x.png   ← primary
    └── meridian-menubarTemplate-22pt.png   …-22pt@2x.png
```

---

## Icon 1 — App icon (Dock · App Store · Finder · app list)

**Use:** `AppIcon.iconset` (and/or `AppIcon-source.svg` / `AppIcon-1024.png`).
This single artwork covers **every place the app shows in color** — the Dock, the App Store listing, Finder, and the small application-list / Spotlight rows. macOS scales the one `.icns` to all of those; you do **not** need a separate "small" icon.

**To build the `.icns`** (after the rename above):
```bash
iconutil -c icns icons/AppIcon.iconset -o AppIcon.icns
```
Then either drop `AppIcon.icns` into the app target, **or** add the PNGs to an `AppIcon` image set in `Assets.xcassets` (Xcode reads the `icon_NxN` / `@2x` names automatically).

**Notes**
- The artwork already includes the rounded-squircle shape and transparent corners, so it sits correctly in the Dock. If you want the exact Big Sur grid padding, you can inset the art ~10% on a transparent 1024 canvas — optional; full-bleed reads fine for a menu-bar utility.
- Prefer the SVG (`AppIcon-source.svg`) if you want to regenerate at any size or tweak colors — it's the source of truth. Palette: sky `#0d1538 → #26407a`, sun radial `#fff7df → #ffd373 → #f7a838`, ticks `#ffce6e`, horizon `#ffffff @50%`.

---

## Icon 2 — Menu-bar item (the no-favorites fallback)

> ⚠️ **SUPERSEDED — historical.** The menu-bar glyph below (Midnight Sundial template) has been
> replaced by the partner's **Dial + Sun** glyph (`menubar-dialsun/`). See
> [`../CHANGES-FOR-DESIGN-PARTNER.md` §5b](../CHANGES-FOR-DESIGN-PARTNER.md) for what actually ships.
> *(Icon 1, the app-icon build instructions above, is still accurate.)*

**Use:** `MenuBarIcon-template.svg` (preferred) or the `menubar/` PNGs.
This is the glyph shown in the macOS menu bar **when the user has not starred any city** (when they have favorites, the bar shows those city times instead — see the main design README).

**It is a _template image_** — pure black on transparent. macOS tints it automatically: white on dark menu bars, black on light, accent when the menu is open. **Do not ship it in color.**

**In code:**
```swift
let img = NSImage(named: "MenuBarIcon")!   // the template asset
img.isTemplate = true                       // ← critical; lets macOS tint it
statusItem.button?.image = img
```

**In the asset catalog:**
- Easiest: drop `MenuBarIcon-template.svg` into `Assets.xcassets` as a **Single-Scale** image and set **Render As → Template Image**. (Xcode 12+ rasterizes the SVG for you.)
- Or use the PNGs: create a `MenuBarIcon` image set, assign `…-18pt.png` to **1x** and `…-18pt@2x.png` to **2x**, and set **Render As → Template Image**. The 18 pt pair is the right default for the menu bar; 16 pt and 22 pt pairs are included if you want a tighter or looser fit.

**Important:** the menu-bar glyph stays this single monochrome mark at all times — it does **not** change color with the Dock icon, and it does **not** adopt the user's accent/livery color (the menu bar tints it by system rules).

---

## Quick checklist for Claude Code
1. Run the `@2x` rename commands above.
2. `iconutil -c icns icons/AppIcon.iconset -o AppIcon.icns` → set as the app icon (covers Dock, Finder, app list, App Store).
3. Add `MenuBarIcon-template.svg` to the asset catalog, **Render As → Template Image**; load it with `image.isTemplate = true` for the `NSStatusItem` when no favorites are set.
4. Delete the old v3.x icon assets so they don't linger in the bundle.
