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

function Laser.server_fire(self)
	local startPosition = self.shape.worldPosition
	local endPosition = startPosition + self.shape:getUp() * self.maxRange


	local hit, raycastResult = sm.physics.raycast(startPosition, endPosition)

	if hit and raycastResult.type == "body" then
		local hitShape = raycastResult:getShape()

		if rollShapeDestruction(hitShape) then
			-- TODO: does this handle wedges correctly?
			if hitShape.isBlock then
				hitShape:destroyBlock(hitShape:getClosestBlockLocalPosition(raycastResult.pointWorld))
			else
				hitShape:destroyShape(0)
			end
		end
	end
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
