--[[
	Plain-table 3D vectors ({x=, y=, z=}) for the engine-independent game core.
	Server glue converts them to Vector3 at the boundary.
]]

local Vec = {}

function Vec.new(x: number, y: number, z: number)
	return { x = x, y = y, z = z }
end

function Vec.sub(a, b)
	return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

function Vec.add(a, b)
	return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end

function Vec.scale(a, s: number)
	return { x = a.x * s, y = a.y * s, z = a.z * s }
end

function Vec.length(a): number
	return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
end

function Vec.distance(a, b): number
	return Vec.length(Vec.sub(a, b))
end

-- Horizontal (XZ) distance; the Presenter and players share a floor plane.
function Vec.flatDistance(a, b): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

function Vec.lerp(a, b, t: number)
	return {
		x = a.x + (b.x - a.x) * t,
		y = a.y + (b.y - a.y) * t,
		z = a.z + (b.z - a.z) * t,
	}
end

function Vec.copy(a)
	return { x = a.x, y = a.y, z = a.z }
end

return Vec
