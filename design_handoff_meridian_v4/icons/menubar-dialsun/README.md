# Meridian — Menu-Bar Icon (Dial + Sun)

Replaces the previous menu-bar glyph. This is the **monochrome template** shown in the macOS menu bar when the user has **no favorite cities** set. (The color app icon — Midnight Sundial — is unchanged.)

## ⚠️ Rename first (sandbox limitation)
Retina files were saved with `-2x` instead of `@2x`. Restore the `@`:
```bash
cd meridian-menubar-dialsun
for f in *-2x.png; do mv "$f" "${f/-2x/@2x}"; done
```

## Files
- `MenuBarIcon-template.svg` — vector master (preferred; drop into Assets.xcassets).
- `MenuBarIcon-16pt.png` / `@2x` · `-18pt` / `@2x` · `-22pt` / `@2x` — rasterized PNGs. **18 pt is the default** for the menu bar; 16/22 included for tighter/looser fit.

## Use it (template image — let macOS tint it)
```swift
let img = NSImage(named: "MenuBarIcon")!
img.isTemplate = true          // ← required: white on dark bars, black on light, accent when open
statusItem.button?.image = img
```
In Assets.xcassets: add the SVG as a Single-Scale image (or the PNGs as 1x/2x), then set **Render As → Template Image**. Do not ship it in color, and it should not take the user's accent/livery color — the system tints it by menu-bar rules.

Replace the old `MenuBarIcon` asset with this one.
