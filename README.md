# omarchy-plugins

Personal [Omarchy](https://omarchy.org/) shell plugins.

## rubichandrap.audioviz

Audio visualizer for the desktop background: a port of cliamp's Mosaic mode,
driven by cava. Cells along the screen edges light up in a speckled pattern
that tracks the music.

Requires `cava`. Edges are configurable (bottom / top / left / right); every
knob is documented in the plugin README.

Install:

```sh
cp -r rubichandrap.audioviz ~/.config/omarchy/plugins/
omarchy-shell shell rescanPlugins
omarchy plugin enable rubichandrap.audioviz
```

Editing a plugin's files takes effect after `omarchy restart shell`.
