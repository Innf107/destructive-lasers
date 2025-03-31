---@class ShapeClass
Laser = class()
Laser.maxParentCount = 1
Laser.maxChildCount = 0
Laser.connectionInput = sm.interactable.connectionType.logic
Laser.connectionOutput = sm.interactable.connectionType.none

Laser.fireDelay = 8
Laser.maxRange = 100

Laser.cooldown = 0
Laser.hasAlreadyFired = false

---@param uuid Uuid
function isMirror(uuid)
	return true
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

---@param shape Shape
---@return boolean
local function rollShapeDestruction(shape)
	if not shape.destructable then
		return false
	end

	return math.random() > 0.5
end


---@param uuid Uuid
function isExplosive(uuid)
	local data = sm.item.getFeatureData(uuid)
	return data and data.classname == "Explosive"
end

---@param hitShape Shape
---@param hitPosition Vec3
function Laser.server_hitShape(self, hitShape, hitPosition)
	if (isExplosive(hitShape.uuid)) then
		-- TODO
		sm.melee.meleeAttack(nil, 10, hitPosition, sm.vec3.zero(), nil)
	elseif rollShapeDestruction(hitShape) then
		-- TODO: does this handle wedges correctly?
		if hitShape.isBlock then
			hitShape:destroyBlock(hitShape:getClosestBlockLocalPosition(hitPosition))
		else
			hitShape:destroyShape(0)
		end
	end
end

---@param startPosition Vec3
---@param direction Vec3
---@param maxReflections integer
function Laser.server_fireLaserFrom(self, startPosition, direction, maxReflections)
	local endPosition = startPosition + direction * self.maxRange

	local hit, raycastResult = sm.physics.raycast(startPosition, endPosition)

	local distance = raycastResult.directionWorld:length() * raycastResult.fraction

	self.network:sendToClients("client_fireLaserFromEvent", { startPosition, direction, distance })

	if hit and raycastResult.type == "body" then
		local hitShape = raycastResult:getShape()

		if isMirror(hitShape.uuid) then
			if maxReflections > 0 then
				local normal = raycastResult.normalWorld
				local rotation = sm.vec3.getRotation(direction, normal)
				local newDirection = rotation * rotation * -direction

				print(direction, "-->", newDirection)
				self:server_fireLaserFrom(raycastResult.pointWorld, newDirection, maxReflections - 1)
			end
		else
			self:server_hitShape(hitShape, raycastResult.pointWorld)
		end
	end
end

function Laser.server_fire(self)
	local startPosition = self:fireOrigin()

	self:server_fireLaserFrom(startPosition, self.shape:getUp(), 20)
end

function Laser.client_fireLaserFromEvent(self, data)
	return self:client_fireLaserFrom(data[1], data[2], data[3])
end

---@param startPosition Vec3
---@param direction Vec3
---@param distance number
function Laser.client_fireLaserFrom(self, startPosition, direction, distance)
	print(startPosition, direction, distance)

	local position = startPosition + direction * (distance / 2)
	-- stupid quaternions
	local rotation = sm.vec3.getRotation(sm.vec3.new(0,1,0), direction)
	sm.effect.playEffect("Laser - Shoot", position, nil, rotation, nil, {
		Scale = sm.vec3.new(0.25, .25, distance * 4),
		Color = self.shape.color
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
