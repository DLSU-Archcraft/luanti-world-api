-- archcraft_io: lamps and buttons addressed by an integer channel, for Lua I/O.
--
-- Every lamp and button stores its channel (0..65535) in node metadata.
-- Lua reads buttons and drives lamps by channel:
--
--   archcraft_io.read(3)            -> true if a button on channel 3 is pressed
--   archcraft_io.write(3, true)     -> turn every lamp on channel 3 on
--   archcraft_io.press(3, true)     -> press every button on channel 3
--   archcraft_io.on_button(fn)      -> fn(channel, pressed, pos) on every change
--
-- Only nodes in loaded map blocks are reachable.

archcraft_io = {}
local api = archcraft_io

local MOD = "archcraft_io"
local LAMP_OFF = MOD .. ":lamp_off"
local LAMP_ON = MOD .. ":lamp_on"
local BTN_OFF = MOD .. ":button_off"
local BTN_ON = MOD .. ":button_on"
local FORMNAME = MOD .. ":config"
local MAX_CHANNEL = 65535

local TEX = {
	lamp_off = "[fill:16x16:0,0:#3a3a3a",
	lamp_on = "[fill:16x16:0,0:#ffe066",
	btn_up = "[fill:16x16:0,0:#9a9a9a",
	btn_down = "[fill:16x16:0,0:#5c5c5c",
}

local BUTTON_BOX = {type = "fixed", fixed = {-0.25, -0.5, -0.25, 0.25, -0.375, 0.25}}

-- Index of every known I/O node: hash(pos) -> {kind, channel, pos}
local index = {}
-- Player name -> position of the node whose configuration form is open
local pending = {}
-- Callbacks from api.on_button
local listeners = {}

local function kind_of(node_name)
	if node_name == LAMP_OFF or node_name == LAMP_ON then
		return "lamp"
	end
	if node_name == BTN_OFF or node_name == BTN_ON then
		return "button"
	end
	return nil
end

local function register(pos, kind, channel)
	if not kind then
		return
	end
	index[minetest.hash_node_position(pos)] = {
		kind = kind,
		channel = channel,
		pos = vector.copy(pos),
	}
end

local function unregister(pos)
	index[minetest.hash_node_position(pos)] = nil
end

local function members(kind, channel)
	local out = {}
	for _, e in pairs(index) do
		if e.kind == kind and e.channel == channel then
			table.insert(out, e.pos)
		end
	end
	return out
end

local function parse_channel(s)
	local n = tonumber(s)
	if n and n == math.floor(n) and n >= 0 and n <= MAX_CHANNEL then
		return n
	end
	return nil
end

local function set_lamp_node(pos, on)
	local node = minetest.get_node_or_nil(pos)
	if not node or kind_of(node.name) ~= "lamp" then
		return false
	end
	local want = on and LAMP_ON or LAMP_OFF
	if node.name ~= want then
		minetest.swap_node(pos, {name = want, param2 = node.param2})
	end
	return true
end

local function set_button_node(pos, pressed)
	local node = minetest.get_node_or_nil(pos)
	if not node or kind_of(node.name) ~= "button" then
		return false
	end
	local want = pressed and BTN_ON or BTN_OFF
	if node.name ~= want then
		minetest.swap_node(pos, {name = want, param2 = node.param2})
	end
	return true
end

local function notify(channel, pressed, pos)
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, channel, pressed, pos)
		if not ok then
			minetest.log("error", "[archcraft_io] on_button listener failed: " .. tostring(err))
		end
	end
end

-- Public API

-- Re-index one I/O node from its current node name and metadata.
-- Call this after placing a lamp or button with minetest.set_node,
-- which bypasses the placement hooks. Returns true if pos held an I/O node.
function api.index(pos)
	local node = minetest.get_node_or_nil(pos)
	local kind = node and kind_of(node.name)
	if not kind then
		unregister(pos)
		return false
	end
	register(pos, kind, minetest.get_meta(pos):get_int("channel"))
	return true
end

-- True if any loaded button on this channel is pressed.
function api.read(channel)
	for _, pos in ipairs(members("button", channel)) do
		local node = minetest.get_node_or_nil(pos)
		if node and node.name == BTN_ON then
			return true
		end
	end
	return false
end

-- Turn every loaded lamp on this channel on or off. Returns how many were set.
function api.write(channel, on)
	local n = 0
	for _, pos in ipairs(members("lamp", channel)) do
		if set_lamp_node(pos, on and true or false) then
			n = n + 1
		end
	end
	return n
end

-- Press or release every loaded button on this channel. Listeners fire only
-- for buttons that actually change. Returns how many buttons were found.
function api.press(channel, pressed)
	local n = 0
	for _, pos in ipairs(members("button", channel)) do
		local node = minetest.get_node_or_nil(pos)
		if node and kind_of(node.name) == "button" then
			n = n + 1
			if (node.name == BTN_ON) ~= (pressed and true or false) then
				set_button_node(pos, pressed and true or false)
				notify(channel, pressed and true or false, pos)
			end
		end
	end
	return n
end

-- Register fn(channel, pressed, pos), called whenever a button changes state.
function api.on_button(fn)
	table.insert(listeners, fn)
end

-- Node definitions

local function open_config(pos, player)
	local name = player:get_player_name()
	pending[name] = pos
	local ch = minetest.get_meta(pos):get_int("channel")
	minetest.show_formspec(name, FORMNAME,
		string.format("size[4,2.6]field[0.3,0.6;3.4,0.9;channel;Channel (0-%d);%d]button_exit[0.8,1.6;2.4,0.8;save;Save]",
			MAX_CHANNEL, ch))
end

local function common(kind)
	return {
		after_place_node = function(pos)
			register(pos, kind, minetest.get_meta(pos):get_int("channel"))
		end,
		after_dig_node = function(pos)
			unregister(pos)
		end,
	}
end

local function lamp_def(on)
	local def = {
		description = on and "Archcraft Lamp (on)" or "Archcraft Lamp",
		tiles = {on and TEX.lamp_on or TEX.lamp_off},
		groups = {cracky = 3, archcraft_io = 1, not_in_creative_inventory = on and 1 or 0},
		light_source = on and 14 or 0,
		drop = LAMP_OFF,
		on_rightclick = function(pos, _, clicker)
			if clicker and clicker:is_player() then
				open_config(pos, clicker)
			end
		end,
	}
	for k, v in pairs(common("lamp")) do
		def[k] = v
	end
	return def
end

local function button_def(pressed)
	local def = {
		description = pressed and "Archcraft Button (pressed)" or "Archcraft Button",
		drawtype = "nodebox",
		paramtype = "light",
		sunlight_propagates = true,
		node_box = BUTTON_BOX,
		selection_box = BUTTON_BOX,
		collision_box = BUTTON_BOX,
		tiles = {pressed and TEX.btn_down or TEX.btn_up},
		groups = {cracky = 3, archcraft_io = 1, not_in_creative_inventory = pressed and 1 or 0},
		drop = BTN_OFF,
		on_rightclick = function(pos, node, clicker)
			if not clicker or not clicker:is_player() then
				return
			end
			if clicker:get_player_control().sneak then
				open_config(pos, clicker)
				return
			end
			local channel = minetest.get_meta(pos):get_int("channel")
			api.press(channel, node.name ~= BTN_ON)
		end,
	}
	for k, v in pairs(common("button")) do
		def[k] = v
	end
	return def
end

minetest.register_node(LAMP_OFF, lamp_def(false))
minetest.register_node(LAMP_ON, lamp_def(true))
minetest.register_node(BTN_OFF, button_def(false))
minetest.register_node(BTN_ON, button_def(true))

-- Rebuild the index for I/O nodes as their map blocks load.
minetest.register_lbm({
	label = "archcraft_io: index I/O nodes",
	name = MOD .. ":index",
	nodenames = {LAMP_OFF, LAMP_ON, BTN_OFF, BTN_ON},
	run_at_every_load = true,
	action = function(pos)
		api.index(pos)
	end,
})

-- Configuration form: sneak-right-click a button or right-click a lamp to open it.

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORMNAME then
		return false
	end
	local name = player:get_player_name()
	local pos = pending[name]
	pending[name] = nil
	if not pos or not fields.save then
		return true
	end
	local ch = parse_channel(fields.channel)
	if not ch then
		minetest.chat_send_player(name,
			"[archcraft_io] channel must be a whole number from 0 to " .. MAX_CHANNEL)
		return true
	end
	local node = minetest.get_node_or_nil(pos)
	local kind = node and kind_of(node.name)
	if not kind then
		return true
	end
	minetest.get_meta(pos):set_int("channel", ch)
	register(pos, kind, ch)
	minetest.chat_send_player(name, string.format("[archcraft_io] %s set to channel %d", kind, ch))
	return true
end)

-- Chat commands for inspection and testing

local function usage()
	return false, "usage: /io list | read <ch> | write <ch> <0|1> | press <ch> <0|1>"
end

minetest.register_chatcommand("io", {
	params = "list | read <ch> | write <ch> <0|1> | press <ch> <0|1>",
	description = "Inspect or drive Archcraft lamps and buttons (loaded areas only)",
	privs = {interact = true},
	func = function(_, param)
		local args = {}
		for w in param:gmatch("%S+") do
			table.insert(args, w)
		end
		local cmd = args[1]

		if cmd == "list" then
			local lamps, buttons, seen = 0, 0, {}
			local channels = {}
			for _, e in pairs(index) do
				if e.kind == "lamp" then
					lamps = lamps + 1
				else
					buttons = buttons + 1
				end
				if not seen[e.channel] then
					seen[e.channel] = true
					table.insert(channels, e.channel)
				end
			end
			table.sort(channels)
			return true, string.format("lamps=%d buttons=%d channels=%s",
				lamps, buttons, table.concat(channels, ","))
		end

		if cmd == "read" then
			local ch = parse_channel(args[2])
			if not ch then
				return usage()
			end
			return true, string.format("channel %d: %s", ch, api.read(ch) and "pressed" or "released")
		end

		if (cmd == "write" or cmd == "press") and (args[3] == "0" or args[3] == "1") then
			local ch = parse_channel(args[2])
			if not ch then
				return usage()
			end
			local on = args[3] == "1"
			local n
			if cmd == "write" then
				n = api.write(ch, on)
				return true, string.format("set %d lamp(s) on channel %d %s", n, ch, on and "on" or "off")
			end
			n = api.press(ch, on)
			return true, string.format("set %d button(s) on channel %d %s", n, ch, on and "pressed" or "released")
		end

		return usage()
	end,
})

minetest.log("action", "[archcraft_io] loaded")
