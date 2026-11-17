# luanti-world-api

The **Archcraft Standard** template world for Luanti: a flat world on the
Mineclonia game, with lamps and buttons that Lua can read and drive by channel number.

```
archcraft-standard/              the world (copy this folder)
├── world.mt                     world settings (gameid = mineclonia)
├── map_meta.txt                 flat mapgen settings, ground at y = 8
└── worldmods/archcraft_io/      the I/O mod (always loaded with the world)
    ├── mod.conf
    └── init.lua
```

## Requirements

- Luanti 5.8 or newer
- The **Mineclonia** game installed as `mineclonia` in your games folder
  (install it from ContentDB, or copy the game folder into `games/`).

## Loading the world

1. Find your Luanti user data folder's `worlds/` directory. On Linux this is
   usually `~/.minetest/worlds/` (Luanti 5.x keeps the old name on many installs).
2. Copy the `archcraft-standard` folder into it. Copy it; do not open the repository
   copy in place, because Luanti writes map data into the world folder.
3. Start Luanti, choose **Single Player**, and select **Archcraft Standard**.

The world starts in creative mode with damage disabled. Its I/O mod loads automatically
because it sits in `worldmods/`, so there is nothing to enable.

## Using lamps and buttons

| Block | Give yourself one | Right-click | Sneak + right-click |
|---|---|---|---|
| Lamp | `/give <you> archcraft_io:lamp_off` | opens the channel form | opens the channel form |
| Button | `/give <you> archcraft_io:button_off` | presses (toggles) the button | opens the channel form |

Set a channel in the form (0 to 65535). Lamps and buttons with the same channel are wired
together. A button toggles between pressed and released, and a lamp shows the state Lua writes to it.

Chat commands for testing:

```
/io list                  count lamps and buttons, list the channels in use
/io read <ch>             is a button on channel <ch> pressed?
/io write <ch> <0|1>      switch every lamp on channel <ch> off or on
/io press <ch> <0|1>      release or press every button on channel <ch>
```

## Lua API

Use these from any mod in the world. Channels are integers from 0 to 65535.

| Call | What it does |
|---|---|
| `archcraft_io.read(ch)` | Returns true if any button on channel `ch` is pressed. |
| `archcraft_io.write(ch, on)` | Sets all lamps on channel `ch`. Returns how many were set. |
| `archcraft_io.press(ch, pressed)` | Sets all buttons on channel `ch`. Returns how many were found. |
| `archcraft_io.on_button(fn)` | Calls `fn(channel, pressed, pos)` whenever a button changes. |
| `archcraft_io.index(pos)` | Registers an I/O node you placed with `minetest.set_node`. |

Example: mirror a button on channel 1 onto a lamp on channel 2.

```lua
archcraft_io.on_button(function(ch, pressed)
	if ch == 1 then
		archcraft_io.write(2, pressed)
	end
end)
```

If you place a lamp or button with `minetest.set_node`, set its channel in the
metadata and then call `archcraft_io.index(pos)`. Placing with the normal
player action registers it automatically.

## Limits

- Only lamps and buttons in **loaded map blocks** respond. A player must be nearby, or the
  area must be force-loaded, for `read` and `write` to reach a block far away.
- The I/O index lives in memory. It is rebuilt from the world when blocks load, so no
  setup is needed after a restart.
- Lamps and buttons are not craftable in this template. Get them from creative mode
  or `/give`.
