-- archcraft_flat: keep a classic superflat world empty for circuit building.
--
-- Mineclonia's classic superflat mode (mcl_superflat_classic = true) removes
-- trees, plants and caves, but other generators still run on it: water and
-- lava pools, fallen trees, villages, mineshafts and dungeons. This mod turns
-- them off, and only when the world is classic superflat.
--
-- map_meta.txt also sets mcl_levelgen_enable_ersatz = false. The newer
-- structure generator builds villages in the mapgen thread, where this mod
-- cannot reach; with it off, villages use the older path removed below.
--
-- Side effect: /spawnstruct is also cancelled, since it uses the same
-- placement function as mapgen.

local GENERATORS = {"villages", "railcorridors", "dungeons"}

minetest.register_on_mods_loaded(function()
	local vars = rawget(_G, "mcl_vars")
	if not (vars and vars.superflat) then
		return
	end

	local structures = rawget(_G, "mcl_structures")
	local n = 0
	if structures and structures.registered_structures then
		for _, def in pairs(structures.registered_structures) do
			def.on_place = function()
				return false
			end
			n = n + 1
		end
	end

	local mapgen_core = rawget(_G, "mcl_mapgen_core")
	if mapgen_core and mapgen_core.unregister_generator then
		for _, id in ipairs(GENERATORS) do
			mapgen_core.unregister_generator(id)
		end
	end

	minetest.log("action", string.format(
		"[archcraft_flat] classic superflat: disabled %d structure(s) and generators %s",
		n, table.concat(GENERATORS, ", ")))
end)
