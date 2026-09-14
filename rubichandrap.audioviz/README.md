# rubichandrap.audioviz

Desktop-background audio visualizer for omarchy-shell — a port of cliamp's
"Mosaic" mode. Bottom edge, layer-shell `bottom` layer (above the wallpaper,
below windows). Fed by `cava`'s raw ascii output.

## Files

- `Visualizer.qml` — the plugin. All tunable knobs are the properties at the
  top of the file (lines ~15-26). Only change the numbers after `:`.
- `~/.config/cava/config` — cava itself. Keep `bars` equal to the plugin's
  `columns`.
- `~/.config/omarchy/shell.json` — enabled state (`plugins[]`). Toggle with
  `omarchy plugin disable|enable rubichandrap.audioviz`.

## Knobs (Visualizer.qml)

| Property | Current | Effect |
|---|---|---|
| `columns` | 44 | spectrum bands; smaller = bigger dots. Match cava `bars`. |
| `rows` | 3 | cell rows per strip, edge-outward. Total strip depth grows with it. |
| `tileFill` | 0.62 | lit dot size as a fraction of its slot; smaller = sparser. |
| `gain` | 0.85 | band sensitivity; higher = more cells ignite. |
| `decay` | 0.94 | per-frame fade when `binary: false`; lower = cells switch off faster. |
| `binary` | true | cells snap on/off 0-1; false = cliamp-style gradual decay. |
| `tileAlpha` | 0.52 | global opacity. |
| `rowFade` | 0.55 | how much dimmer the inner row is than the edge row. |
| `vignette` | 0.30 | soft shadow behind the strips for contrast on bright wallpapers. |
| `bottomStrip` | false | bottom edge strip. |
| `topStrip` | false | top edge strip. |
| `leftStrip` | true | left edge strip. |
| `rightStrip` | true | right edge strip. |
| `idleFadeout` | 1000 | ms of silence before the strip fades out. |
| `fadeMs` | 0 | show/hide fade duration; 0 = appear and vanish instantly. |
| `cellMs` | 0 | per-cell opacity/size transition; 0 = instant 0-1 jump. |
| `marginTop` / `marginBottom` | 0 / 0 | strip offset from the top/bottom edge; negative pushes it off-screen (tiles cut). |
| `marginLeft` / `marginRight` | -20 / -20 | strip offset from the left/right edge; negative pushes it off-screen (tiles cut). |

## Apply changes

The panel is `keepLoaded`, so saving the file does NOT apply new code.
Restart the shell:

```sh
omarchy restart shell
```

(The bar blinks for about a second. cava respawns with it, so cava config
changes apply on the same command.)

## Verify / debug

```sh
hyprctl layers | grep audioviz        # surface mapped on the bottom layer
journalctl --user --since "1 min ago" | grep omarchy-shell   # QML errors
```

If the QML fails to parse, the strip silently disappears — check the journal,
fix the file, restart again.
