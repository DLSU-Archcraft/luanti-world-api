-- archcraft_log: record what players do in the world, for research analysis.
--
-- Each server start (or singleplayer session) writes one JSON Lines file:
--   <world>/archcraft_log/<YYYYMMDD-HHMMSS>.jsonl
-- Every line is one JSON object with at least:
--   t      Unix time in seconds, with millisecond precision
--   event  what happened (see the README for the full list)
--
-- Other mods can add their own events with archcraft_log.log(event, fields).

archcraft_log = {}
local api = archcraft_log

local MOVE_INTERVAL = 0.5 -- seconds between movement samples
local FLUSH_INTERVAL = 1.0 -- seconds between writes to disk
local MIN_MOVE = 0.05 -- nodes; smaller position changes are not logged
local MIN_TURN = 1.0 -- degrees; smaller look changes are not logged

local start_unix = os.time()
local start_us = minetest.get_us_time()

local dir = minetest.get_worldpath() .. "/archcraft_log"
minetest.mkdir(dir)
local path = dir .. "/" .. os.date("%Y%m%d-%H%M%S", start_unix) .. ".jsonl"
local file, open_err = io.open(path, "a")
if not file then
	minetest.log("error", "[archcraft_log] cannot open " .. path .. ": " .. tostring(open_err))
end

local function now()
	return start_unix + (minetest.get_us_time() - start_us) / 1e6
end

local function round(x, places)
	local m = 10 ^ (places or 0)
	return math.floor(x * m + 0.5) / m
end

local function node_pos(pos)
	return {x = pos.x, y = pos.y, z = pos.z}
end

local function player_name(obj)
	if obj and obj.is_player and obj:is_player() then
		return obj:get_player_name()
	end
	return nil
end

-- Minimal JSON encoder. minetest.write_json prints floats with 17 significant
-- digits (3.14 becomes 3.1400000000000001), so numbers are formatted here with
-- at most 3 decimals. Object keys are sorted so lines are easy to diff.
local ESCAPES = {['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}

local function encode(v)
	local kind = type(v)
	if kind == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c)
			return ESCAPES[c] or string.format("\\u%04x", c:byte())
		end) .. '"'
	elseif kind == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		if v == math.floor(v) then
			return string.format("%.0f", v)
		end
		return (string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", ""))
	elseif kind == "boolean" then
		return tostring(v)
	elseif kind == "table" then
		local keys = {}
		for k in pairs(v) do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		local parts = {}
		for _, k in ipairs(keys) do
			table.insert(parts, encode(k) .. ":" .. encode(v[k]))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

-- Write one event. fields may contain strings, numbers, booleans and tables of those.
function api.log(event, fields)
	if not file then
		return
	end
	local rest = encode(fields or {})
	file:write('{"t":', encode(round(now(), 3)), ',"event":', encode(event),
		rest == "{}" and "}" or "," .. rest:sub(2), "\n")
end

api.path = path

-- Session ---------------------------------------------------------------------

local game = minetest.get_game_info and minetest.get_game_info() or {}
local version = minetest.get_version()

api.log("session_start", {
	file = path,
	luanti = version.string,
	game = game.id,
	world = minetest.get_worldpath():match("([^/\\]+)$"),
	mapgen = minetest.get_mapgen_setting("mg_name"),
	singleplayer = minetest.is_singleplayer(),
	start = os.date("!%Y-%m-%dT%H:%M:%SZ", start_unix),
})

minetest.register_on_joinplayer(function(player)
	local pos = player:get_pos()
	api.log("join", {player = player:get_player_name(), pos = {x = round(pos.x, 2), y = round(pos.y, 2), z = round(pos.z, 2)}})
end)

minetest.register_on_leaveplayer(function(player, timed_out)
	api.log("leave", {player = player:get_player_name(), timed_out = timed_out and true or false})
end)

minetest.register_on_shutdown(function()
	api.log("session_end", {})
	if file then
		file:close()
		file = nil
	end
end)

-- Movement and held item ------------------------------------------------------

local last = {} -- player name -> last logged {pos, yaw, pitch, wield}

-- Log movement and wield changes for one player. Exposed for testing.
function api._sample(player)
	local name = player:get_player_name()
	local pos = player:get_pos()
	local yaw = round(math.deg(player:get_look_horizontal()), 1)
	local pitch = round(math.deg(player:get_look_vertical()), 1)
	local wield = player:get_wielded_item():get_name()
	local prev = last[name]

	if not prev
			or vector.distance(pos, prev.pos) >= MIN_MOVE
			or math.abs(yaw - prev.yaw) >= MIN_TURN
			or math.abs(pitch - prev.pitch) >= MIN_TURN then
		api.log("move", {
			player = name,
			pos = {x = round(pos.x, 2), y = round(pos.y, 2), z = round(pos.z, 2)},
			yaw = yaw,
			pitch = pitch,
		})
		prev = prev or {}
		prev.pos, prev.yaw, prev.pitch = vector.copy(pos), yaw, pitch
		last[name] = prev
	end

	if prev.wield ~= wield then
		api.log("wield", {player = name, item = wield})
		prev.wield = wield
	end
end

minetest.register_on_leaveplayer(function(player)
	last[player:get_player_name()] = nil
end)

local move_timer, flush_timer = 0, 0
minetest.register_globalstep(function(dtime)
	move_timer = move_timer + dtime
	if move_timer >= MOVE_INTERVAL then
		move_timer = 0
		for _, player in ipairs(minetest.get_connected_players()) do
			api._sample(player)
		end
	end
	flush_timer = flush_timer + dtime
	if flush_timer >= FLUSH_INTERVAL and file then
		flush_timer = 0
		file:flush()
	end
end)

-- Blocks ----------------------------------------------------------------------

minetest.register_on_placenode(function(pos, newnode, placer, oldnode)
	api.log("place", {
		player = player_name(placer),
		pos = node_pos(pos),
		node = newnode.name,
		param2 = newnode.param2,
		replaced = oldnode and oldnode.name or nil,
	})
end)

minetest.register_on_dignode(function(pos, oldnode, digger)
	api.log("dig", {player = player_name(digger), pos = node_pos(pos), node = oldnode.name})
end)

minetest.register_on_punchnode(function(pos, node, puncher)
	api.log("punch", {player = player_name(puncher), pos = node_pos(pos), node = node.name})
end)

-- Interactions (right-click) and redstone ----------------------------------------

minetest.register_on_mods_loaded(function()
	-- Wrap every node's right-click handler. This covers buttons, levers,
	-- repeater and comparator settings, doors, note blocks, chests and so on.
	for name, def in pairs(minetest.registered_nodes) do
		local orig = def.on_rightclick
		if orig then
			minetest.override_item(name, {
				on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
					local result = orig(pos, node, clicker, itemstack, pointed_thing)
					local after = minetest.get_node(pos)
					api.log("rightclick", {
						player = player_name(clicker),
						pos = node_pos(pos),
						node = node.name,
						after = after.name ~= node.name and after.name or nil,
						item = clicker and clicker.get_wielded_item and clicker:get_wielded_item():get_name() or nil,
					})
					return result
				end,
			})
		end
	end

	-- Mineclonia applies every circuit-driven state change (a lamp lighting,
	-- a button releasing, a torch or repeater switching) and then calls
	-- mcl_redstone._update_neighbours. Wrapping it logs those changes.
	-- Wire power levels change elsewhere and are not logged.
	local redstone = rawget(_G, "mcl_redstone")
	if redstone and redstone._update_neighbours then
		local orig_update = redstone._update_neighbours
		redstone._update_neighbours = function(pos, oldnode, newnode)
			if oldnode and newnode and oldnode.name ~= newnode.name then
				api.log("redstone", {pos = node_pos(pos), from = oldnode.name, to = newnode.name})
			end
			return orig_update(pos, oldnode, newnode)
		end
	else
		minetest.log("warning", "[archcraft_log] mcl_redstone not found; redstone changes will not be logged")
	end
end)

-- Chat commands ---------------------------------------------------------------

minetest.register_on_chatcommand(function(name, command, params)
	api.log("command", {player = name, command = command, params = params})
end)

minetest.log("action", "[archcraft_log] writing to " .. path)
