# luanti-world-api

The **Archcraft Standard** template world for Luanti: an empty superflat world on the
Mineclonia game, ready for redstone circuits, that logs what players do for research analysis.

```
archcraft-standard/              the world (copy this folder)
├── world.mt                     world settings (gameid = mineclonia)
├── map_meta.txt                 classic superflat mapgen settings
└── worldmods/                   mods that always load with the world
    ├── archcraft_flat/          keeps the superflat ground empty
    └── archcraft_log/           logs player activity to archcraft_log/*.jsonl
tools/
└── log-viewer.html              replays a log in the browser
```

## The ground

The world uses Mineclonia's classic superflat mode. Every column is the same:

| y | Block |
|---|---|
| 9 and up | air (you stand at y = 9) |
| 8 | grass block |
| 6 to 7 | dirt |
| 5 | bedrock |

The world has no trees, plants, caves, water, villages or other structures, so circuits
have a level, empty surface. Superflat mode handles the trees, plants and caves. The
`archcraft_flat` mod turns off the remaining Mineclonia generators (pools, fallen trees,
villages, mineshafts and dungeons), and `map_meta.txt` turns off the newer structure
generator, which the mod cannot reach. One side effect: `/spawnstruct` does nothing in
this world.

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

The world starts in creative mode with damage disabled. Its mods load automatically
because they sit in `worldmods/`, so there is nothing to enable.

## Activity log

The `archcraft_log` mod records what players do. Each time the world starts, it creates a new
file in the world folder:

```
archcraft-standard/archcraft_log/20261118-143000.jsonl
```

The file is in JSON Lines format: one JSON object per line. Every line has `t` (Unix time in
seconds, with milliseconds) and `event`. The mod writes to disk once a second and on exit.

| Event | When | Other fields |
|---|---|---|
| `session_start` | the world starts | `luanti`, `game`, `world`, `mapgen`, `singleplayer`, `start` (UTC) |
| `session_end` | the world shuts down normally | none |
| `join`, `leave` | a player joins or leaves | `player`, `pos` (join), `timed_out` (leave) |
| `move` | every 0.5 s, if the player moved at least 0.05 blocks or turned at least 1 degree | `player`, `pos`, `yaw`, `pitch` (degrees) |
| `wield` | the player switches the item in their hand | `player`, `item` |
| `place` | a block is placed | `player`, `pos`, `node`, `param2`, `replaced` |
| `dig` | a block is dug | `player`, `pos`, `node` |
| `punch` | a block is punched (left-click) | `player`, `pos`, `node` |
| `rightclick` | a block is right-clicked: buttons, levers, repeaters, comparators, doors and so on | `player`, `pos`, `node`, `after` (new node, if it changed), `item` |
| `redstone` | a circuit switches a component: a lamp lights, a button releases, a torch or repeater turns on or off | `pos`, `from`, `to` |
| `command` | the player runs a chat command | `player`, `command`, `params` |

For example, flipping a lever next to a lamp logs:

```json
{"t":1794983404.881,"event":"rightclick","after":"mcl_lever:lever_on","node":"mcl_lever:lever_off","pos":{"x":0,"y":9,"z":0}}
{"t":1794983404.983,"event":"redstone","from":"mcl_redstone_lamp:lamp_off","pos":{"x":1,"y":9,"z":0},"to":"mcl_redstone_lamp:lamp_on"}
```

Notes:

- `redstone` events have no `player`: a circuit changed the block, not a person. Match them to
  the `rightclick`, `place` or `dig` just before them to find the cause.
- Redstone wire power levels are not logged. Only components that switch state are.
- In singleplayer, every player is named `singleplayer`. To tell students apart, collect each
  student's `archcraft_log/` folder separately.
- The log does not record chat messages. It does record chat commands, with their parameters.
- Other mods can add events with `archcraft_log.log("my_event", {key = value})`.

### Collecting the logs

After a session, copy the `archcraft_log/` folder out of the student's installed world, for
example `~/.minetest/worlds/archcraft-standard/archcraft_log/`. Each file is one session.

### Viewing a log

Open `tools/log-viewer.html` in a web browser and drop a `.jsonl` file onto it. The page runs
entirely on your computer: nothing is uploaded, and it works offline.

- **Top, Front and Side** show the build from above, from the south and from the east. Use Front
  or Side for tall circuits. The two number boxes limit the view to a slice: in the top view,
  setting both to 9 shows only the y = 9 layer.
- **The timeline** at the bottom replays the session. Blocks appear, switch and disappear as
  they did in the game, and recent placements, digs, clicks and redstone changes flash. "Skip
  idle gaps" jumps over stretches where nothing happened.
- **The player** is drawn as a dot with a line showing where they were looking, plus a trail of
  where they walked or flew.
- **Click a block** to list every event at that position. Click any event to jump to that moment.
  The arrow keys step between events and Space plays or pauses.
- **Export CSV** saves the log as a spreadsheet-friendly file, one row per event.

The viewer only knows about blocks that appear in the log. The superflat ground is assumed, and
blocks that existed before logging started show up only if someone uses them during the session.
