-- undo.lua
-- Undo changes made by WorldEdit
-- @author orwell96

-- Record undo action.
-- Should be called immediately before changing stuff in the world
-- when area_min and area_max are not given, they are assumed to be pos1 and pos2 of the current player.

function worldedit.undo_sphere(name, radius)
	local pos1 = worldedit.pos1[name]
	local tvec = {x=radius, y=radius, z=radius}
	local maxp, minp = vector.add(pos1, tvec), vector.subtract(pos1, tvec)
	worldedit.record_undo(name, minp, maxp)
end
function worldedit.undo_cylinder(name, radius, length, axis)
	local pos1 = worldedit.pos1[name]
	local tvec = {x=radius, y=radius, z=radius}
	local maxp, minp = vector.add(pos1, tvec), vector.subtract(pos1, tvec)
	minp[axis]=pos1[axis]
	maxp[axis]=pos1[axis]+length
	worldedit.record_undo(name, minp, maxp)
end
function worldedit.undo_copymove(name, axis, distance)
	local pos1, pos2 = worldedit.sort_pos(worldedit.pos1[name], worldedit.pos2[name])
	local copyvec = {x=0, y=0, z=0}
	copyvec[axis] = distance
	local tpos1, tpos2 = vector.add(pos1, copyvec), vector.add(pos2, copyvec)
	
	local minp, _ = worldedit.sort_pos(pos1, tpos1)
	local _, maxp = worldedit.sort_pos(pos2, tpos2)
	minetest.chat_send_all("undo copymove minp "..minetest.pos_to_string(minp).." maxp "..minetest.pos_to_string(maxp))
	
	worldedit.record_undo(name, minp, maxp)
end
function worldedit.undo_stack(name, axis, repetitions)
	local pos1, pos2 = worldedit.sort_pos(worldedit.pos1[name], worldedit.pos2[name])
	local stackdst = (pos2[axis] - pos1[axis]) + 1
	local increment = {x=0,y=0,z=0}
	increment[axis]=stackdst
	minetest.chat_send_all("undo stack inc "..minetest.pos_to_string(increment))
	worldedit.undo_stack2(name, increment, repetitions)
end
function worldedit.undo_stack2(name, increment, repetitions)
	local pos1, pos2 = worldedit.sort_pos(worldedit.pos1[name], worldedit.pos2[name])
	local copyvec = vector.multiply(increment, repetitions)
	local tpos1, tpos2 = vector.add(pos1, copyvec), vector.add(pos2, copyvec)
	
	local minp, _ = worldedit.sort_pos(pos1, tpos1)
	local _, maxp = worldedit.sort_pos(pos2, tpos2)
	
	worldedit.record_undo(name, minp, maxp)
end
function worldedit.undo_rotate(name, axis)
	local pos1, pos2 = worldedit.sort_pos(worldedit.pos1[name], worldedit.pos2[name])
	local axes = {x = {"y", "z"}, y = {"x", "z"}, z = {"y", "x"}}
	local axis1, axis2 = unpack(axes[axis])
	
	pos1[axis1] = math.min(pos1[axis1], pos1[axis2])
	pos1[axis2] = pos1[axis1]
	
	pos2[axis1] = math.max(pos2[axis1], pos2[axis2])
	pos2[axis2] = pos2[axis1]
	
	worldedit.record_undo(name, pos1, pos2)
end

function worldedit.undo_transpose(name, axis1, axis2)
-- Note: code copied from manipulations.lua
	local pos1, pos2 = worldedit.sort_pos(worldedit.pos1[name], worldedit.pos2[name])

	local compare
	local extent1, extent2 = pos2[axis1] - pos1[axis1], pos2[axis2] - pos1[axis2]

	if extent1 > extent2 then
		compare = function(extent1, extent2)
			return extent1 > extent2
		end
	else
		compare = function(extent1, extent2)
			return extent1 < extent2
		end
	end

	-- Calculate the new position 2 after transposition
	local new_pos2 = {x=pos2.x, y=pos2.y, z=pos2.z}
	new_pos2[axis1] = pos1[axis1] + extent2
	new_pos2[axis2] = pos1[axis2] + extent1

	local upper_bound = {x=pos2.x, y=pos2.y, z=pos2.z}
	if upper_bound[axis1] < new_pos2[axis1] then upper_bound[axis1] = new_pos2[axis1] end
	if upper_bound[axis2] < new_pos2[axis2] then upper_bound[axis2] = new_pos2[axis2] end
	worldedit.record_undo(name, pos1, upper_bound)
end

function worldedit.record_undo(player_name, area_min, area_max)
	local pos1 = area_min or worldedit.pos1[player_name]
	local pos2 = area_max or worldedit.pos2[player_name]
	if not pos1 or not pos2 then
		worldedit.player_notify(name, "Position 1 or 2 not set, can't record undo!")
		return
	end
	
	pos1, pos2 = worldedit.sort_pos(pos1, pos2)
	
	local count = worldedit.volume(pos1, pos2)
	if count > 20000 then
		return
	end
	
	local result, count = worldedit.serialize(pos1, pos2, true)
	local path = minetest.get_worldpath() .. "/schems"
	-- Create directory if it does not already exist
	minetest.mkdir(path)

	local filename = path .. "/" .. "WEUNDO_"..player_name .. ".we"
	local file, err = io.open(filename, "wb")
	if err ~= nil then
		worldedit.player_notify(name, "Could not save file to \"" .. filename .. "\"")
		return
	end
	
	file:write(minetest.pos_to_string(pos1).."\n")
	file:write(result)
	
	file:flush()
	file:close()
end

function worldedit.restore_undo(name)
	local path = minetest.get_worldpath() .. "/schems"
	local filename = path .. "/" .. "WEUNDO_"..name .. ".we"
	local file, err = io.open(filename, "rb")
	if err ~= nil then
		worldedit.player_notify(name, "Undo failed: nothing to undo! (Could not open undo schematic)")
		return
	end
	
	local pts = file:read("*l")
	if not pts then
		worldedit.player_notify(name, "Undo failed: nothing to undo! (Saved position is invalid)")
		return
	end
	local pos = minetest.string_to_pos(pts)
	local value = file:read("*a")
	file:close()

	local version = worldedit.read_header(value)
	if version == 0 then
		worldedit.player_notify(name, "Undo failed: File is invalid!")
		return
	elseif version > worldedit.LATEST_SERIALIZATION_VERSION then
		worldedit.player_notify(name, "Undo failed: File was created with newer version of WorldEdit!")
		return
	end

	local count = worldedit.deserialize(pos, value)
	
	os.remove(filename)

	worldedit.player_notify(name, count .. " nodes restored")
end
