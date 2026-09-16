# Hyprland integration

Two snippets. Both are optional — the plugin works without them — and neither
is installed by `bin/setup`, because your Hyprland config is yours and a
script has no business editing it.

## A shortcut to open the digest

In `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + D", "Wiki digest", "omarchy-shell shell toggle jevido.wiki")
```

Pick a key that is actually free on your machine — `hyprctl binds -j` lists
what is taken. Then set `shortcut` in the widget's layout entry to the same
keys so the tooltip advertises it; that field is display text only.

`SUPER + D` is worth the collision check: the overlay takes plain `d` to switch
between unread and the full briefing, so one finger opens it, switches view,
and closes it again.

To land straight in the full briefing — everything since the last run, read or
not — instead of the unread list:

```lua
o.bind("SUPER + SHIFT + D", "Full wiki digest", "omarchy-shell jevido.wiki everything")
```

## Stop the compositor fading the overlay

In `~/.config/hypr/hyprland.lua`:

```lua
hl.layer_rule({ match = { namespace = "omarchy-wikipulse" }, no_anim = true, animation = "none" })
```

The overlay animates itself in. The compositor's own fade on top of that reads
as a stutter rather than as two effects.
