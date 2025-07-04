---@class ShapeClass
Laser = class()
Laser.maxParentCount = 1
Laser.maxChildCount = 0
Laser.connectionInput = sm.interactable.connectionType.logic
Laser.connectionOutput = sm.interactable.connectionType.none

Laser.fireDelay = 8
Laser.maxRange = 1000

Laser.cooldown = 0
Laser.hasAlreadyFired = false

local mirrorBlockUuid = sm.uuid.new("a66c65ac-3a82-4fdd-aeed-d33830d07ad7")
local mirrorWedgeUuid = sm.uuid.new("371c9740-9aec-4199-8105-2cea17a9ec23")

---@param uuid Uuid
---@return boolean
function isMirror(uuid)
	return uuid == mirrorBlockUuid or uuid == mirrorWedgeUuid
end

---@param shape Shape
---@return boolean
function isGlass(shape)
	return shape.material == "Glass"
end

function Laser.server_onCreate(self)
	self:server_init()
end

function Laser.server_onRefresh(self)
	self:server_init()
end

function Laser.server_init(self)
	self.cooldown = 0
	self.hasAlreadyFired = false
end

function Laser.fireOrigin(self)
	return self.shape.worldPosition + self.shape.up * 0.25
end

function Laser.canFire(self)
	return self.cooldown == 0 and not self.hasAlreadyFired
end

---@param position Vec3
---@param direction Vec3
function Laser.attackBlockAt(self, position, direction)
	-- TODO: figure out something more sensible (why do i need this anyway??)
	local source = sm.player.getAllPlayers()[1]

	sm.melee.meleeAttack(sm.uuid.new("d5a446b7-bdf8-4fdc-9269-5353242dd76c"), 20, position, direction, source, 0, 0)
end

---@param position Vec3
---@param direction Vec3
function Laser.attackCharacterAt(self, position, direction)
	-- TODO: figure out something more sensible (why do i need this anyway??)
	local source = sm.player.getAllPlayers()[1]

	sm.melee.meleeAttack(sm.uuid.new("7cf267af-a696-429c-97c4-99a64af6b1e0"), 20, position, direction, source, 0, 0)
end

---@param uuid Uuid
function isExplosive(uuid)
	local data = sm.item.getFeatureData(uuid)
	return data and data.classname == "Explosive"
end

local blockNormals = {
	sm.vec3.new(1, 0, 0),
	sm.vec3.new(0, 1, 0),
	sm.vec3.new(0, 0, 1),
	sm.vec3.new(-1, 0, 0),
	sm.vec3.new(0, -1, 0),
	sm.vec3.new(0, 0, -1),
}

---@param hitShape Shape
---@param inexactNormal Vec3
---@return Vec3
function exactNormal(hitShape, inexactNormal)
	local candidates
	if hitShape.isBlock then
		candidates = blockNormals
	elseif hitShape.isWedge then
		local boundingBox = hitShape:getBoundingBox()
		candidates = {
			sm.vec3.new(0, boundingBox.z, boundingBox.y):normalize(),
			sm.vec3.new(1, 0, 0),
			sm.vec3.new(-1, 0, 0),
			sm.vec3.new(0, -1, 0),
			sm.vec3.new(0, 0, -1),
		}
	else
		return inexactNormal
	end

	local best = nil
	local bestDistance = 999999
	for _, candidate in ipairs(candidates) do
		local rotatedCandidate = hitShape.worldRotation * candidate
		local distance = (rotatedCandidate - inexactNormal):length2()
		if distance < bestDistance then
			best = rotatedCandidate
			bestDistance = distance
		end
	end
	return best
end

---@param startPosition Vec3
---@param direction Vec3
---@param color Color
---@param maxReflections integer
function Laser.server_fireLaserFrom(self, startPosition, direction, color, maxReflections)
	local endPosition = startPosition + direction * self.maxRange

	local hit, raycastResult = sm.physics.raycast(startPosition, endPosition)

	local distance = raycastResult.directionWorld:length() * raycastResult.fraction

	self.network:sendToClients("client_fireLaserFromEvent", { startPosition, direction, color, distance })

	if hit and raycastResult.type == "joint" then
		-- We ignore joints since they will be destroyed anyway if we shoot the shape they're attached to
		-- and this is more consistent with how the rest of the game/physics treats them.
		self:server_fireLaserFrom(raycastResult.pointWorld, direction, color, maxReflections)
	elseif hit and raycastResult.type == "harvestable" then
		self:attackBlockAt(raycastResult.pointWorld, direction)
	elseif hit and raycastResult.type == "character" then
		self:attackCharacterAt(raycastResult.pointWorld, direction)
	elseif hit and raycastResult.type == "body" then
		local hitShape = raycastResult:getShape()

		if isMirror(hitShape.uuid) then
			if maxReflections > 0 then
				local normal = exactNormal(hitShape, raycastResult.normalWorld)

				local newDirection = direction - normal * (direction:dot(normal) * 2)

				local newColor
				if hitShape.color == sm.item.getShapeDefaultColor(hitShape.uuid) then
					newColor = color
				else
					newColor = hitShape.color
				end

				self:server_fireLaserFrom(raycastResult.pointWorld, newDirection, newColor, maxReflections - 1)
			end
		elseif isGlass(hitShape) then
			local newColor

			if hitShape.color == sm.item.getShapeDefaultColor(hitShape.uuid) then
				newColor = color
			else
				newColor = hitShape.color
			end
			self:server_fireLaserFrom(raycastResult.pointWorld, direction, newColor, maxReflections)
		else
			self:attackBlockAt(raycastResult.pointWorld, direction)
		end
	end
end

function Laser.server_fire(self)
	local startPosition = self:fireOrigin()

	self:server_fireLaserFrom(startPosition, self.shape:getUp(), self.shape.color, 50)
end

function Laser.client_fireLaserFromEvent(self, data)
	return self:client_fireLaserFrom(data[1], data[2], data[3], data[4])
end

---@param startPosition Vec3
---@param direction Vec3
---@param distance number
function Laser.client_fireLaserFrom(self, startPosition, direction, color, distance)
	local position = startPosition + direction * (distance / 2)
	-- stupid quaternions
	local rotation = sm.vec3.getRotation(sm.vec3.new(0, 1, 0), direction)

	sm.effect.playEffect("Laser - Beam", position, nil, rotation, nil, {
		Scale = sm.vec3.new(0.25, .25, distance * 4),
		Color = color
	})
end

function Laser.server_onFixedUpdate(self)
	if self.cooldown > 0 then
		self.cooldown = self.cooldown - 1
	end
	local parent = self.interactable:getSingleParent()
	if parent and parent:isActive() and self:canFire() then
		self.cooldown = self.fireDelay
		self.hasAlreadyFired = true
		self:server_fire()
	end
	if not parent or not parent:isActive() then
		self.hasAlreadyFired = false
	end
end
