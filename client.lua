local enet = require 'enet'
local trickle = require 'trickle'
local config = require 'config'
local signatures = require 'signatures'
local maf = require 'maf'
local vec3 = maf.vec3
local quat = maf.quat

local client = {}

local function log(...)
  --print(client.state, ...)
end

local function normalize(x, range)
	return math.floor(((x + range) / (2 * range)) * (2 ^ 16))
end

local function denormalize(x, range)
  return ((x / (2 ^ 16)) - .5) * 2 * range
end

function client:init()
  self:reset()
	self:refreshControllers()
	self.emoji = {
		active = false,
		current = 0,
		hover = 0,
		transform = lovr.math.newTransform()
	}
	self.lastInput = lovr.timer.getTime()
	self.models = {
		head = lovr.graphics.newModel('media/head.obj', 'media/head-tex.png'),
		rock = lovr.graphics.newModel('media/rock-card.obj', 'media/rock-tex.png'),
		paper = lovr.graphics.newModel('media/paper-card.obj', 'media/paper-tex.png'),
		scissors = lovr.graphics.newModel('media/scissor-card.obj', 'media/scissor-tex.png'),
		star = lovr.graphics.newModel('media/star.obj', 'media/star-tex.png'),
		money = lovr.graphics.newModel('media/moneystack.obj', 'media/money-tex.jpg'),
		table = lovr.graphics.newModel('media/table.obj', 'media/table-tex.png'),
		portrait = lovr.graphics.newModel('media/portrait.obj'),
		landscape = lovr.graphics.newModel('media/landscape.obj'),
		rug = lovr.graphics.newModel('media/rug.obj', 'media/rug-tex.jpg')
	}
	self.cardGrab = {
		active = false,
		card = 0,
		position = 0,
		offset = nil,
		rotation = nil
	}

	self.proposition = 0
	self.dueling = 0
	self.duelChoice = 0
	self.duelHover = false
	self.duelTimer = 0

	self.textures = {}
	for _, emoji in ipairs(config.emoji) do
		self.textures[emoji] = lovr.graphics.newTexture('media/emoji/' .. emoji .. '.png')
	end

	self.textures.portrait1 = lovr.graphics.newTexture('media/portrait1-tex.png')
	self.textures.portrait2 = lovr.graphics.newTexture('media/portrait2-tex.png')
	self.textures.landscape1 = lovr.graphics.newTexture('media/landscape1-tex.png')
	self.textures.landscape2 = lovr.graphics.newTexture('media/landscape2-tex.png')
	self.textures.landscape3 = lovr.graphics.newTexture('media/landscape3-tex.png')
	self.textures.landscape4 = lovr.graphics.newTexture('media/landscape4-tex.png')
	self.textures.wall = lovr.graphics.newTexture('media/wall-tex.png')

	self.shader = require('media/shader')
	self.viewMat = lovr.math.newTransform()
end

function client:update(dt)
	while true do
		local event = self.host:service(0)
		if not event then break end
		if self.events[self.state][event.type] then
			self.events[self.state][event.type](self, event)
		end
	end

	if self.state == 'server' then
		if self.gameState == 'playing' then
			self.timer = self.timer - dt
		end

		local index = self.emoji.active and self:getEmojiIndex()
		if index and index ~= self.emoji.hover then
			self.controllers[2]:vibrate(.002)
			self.emoji.hover = index
		end

		if self.controllers[2] and self.controllers[2]:isDown('touchpad') then
			self.proposition = self.controllers[2]:getAxis('touchy') > 0 and 1 or 2
			self:stopGrabbingCard()
		else
			self.proposition = 0
		end

		if self.dueling > 0 and self.duelTimer > 0 then
			self.duelTimer = math.max(self.duelTimer - dt, 0)
			if self.cardGrab.active then
				local tx, ty, tz, angle, slotX, slotY, slotZ = self:getDuelZones()
				local x, y, z = self.controllers[2]:getPosition()
				print(tx, ty, tz, x, y, z, math.sqrt((slotX - x) ^ 2 + (slotY - y) ^ 2 + (slotZ - z) ^ 2), .1)
				if math.sqrt((slotX - x) ^ 2 + (slotY - y) ^ 2 + (slotZ - z) ^ 2) < .1 then
					if not self.duelHover then
						self.duelHover = true
						self.controllers[2]:vibrate(.002)
					end
				else
					self.duelHover = false
				end
			end
		end

		local t = lovr.timer.getTime()
		if self.state == 'server' and self.peer and (t - self.lastInput) >= config.inputRate then
			local x, y, z = lovr.headset.getPosition()
			local angle, ax, ay, az = lovr.headset.getOrientation()
			local lx, ly, lz, rx, ry, rz, langle, lax, lay, laz, rangle, rax, ray, raz = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

			if self.controllers[1] then
				lx, ly, lz = self.controllers[1]:getPosition()
				langle, lax, lay, laz = self.controllers[1]:getOrientation()
			end

			if self.controllers[2] then
				rx, ry, rz = self.controllers[2]:getPosition()
				rangle, rax, ray, raz = self.controllers[2]:getOrientation()
			end

			self:send('input', {
				x = normalize(x, config.bounds),
				y = normalize(y, config.bounds),
				z = normalize(z, config.bounds),
				angle = normalize(angle, 2 * math.pi),
				ax = normalize(ax, 1),
				ay = normalize(ay, 1),
				az = normalize(az, 1),
				lx = normalize(lx, config.bounds),
				ly = normalize(ly, config.bounds),
				lz = normalize(lz, config.bounds),
				langle = normalize(langle, 2 * math.pi),
				lax = normalize(lax, 1),
				lay = normalize(lay, 1),
				laz = normalize(laz, 1),
				rx = normalize(rx, config.bounds),
				ry = normalize(ry, config.bounds),
				rz = normalize(rz, config.bounds),
				rangle = normalize(rangle, 2 * math.pi),
				rax = normalize(rax, 1),
				ray = normalize(ray, 1),
				raz = normalize(raz, 1),
				emoji = self.emoji.current,
				grabbedCard = self.cardGrab.card,
				proposition = self.proposition,
				duelChoice = self.duelChoice
			})
			self.lastInput = t
		end
	end
end

function client:draw()
	if self.state == 'server' then
		self.viewMat:origin()
		self.viewMat:translate(lovr.headset.getPosition())
		self.viewMat:rotate(lovr.headset.getOrientation())
		self.shader:send('viewMat', self.viewMat:inverse())

		--self.models.table:draw(0, 1, 0)

		lovr.graphics.setShader(self.shader)

		-- Ground
		lovr.graphics.setColor(50, 50, 50)
		lovr.graphics.plane('fill', 0, 0, 0, 10, math.pi / 2, 1, 0, 0)

		-- Rug
		lovr.graphics.setColor(255, 255, 255)
		self.models.rug:draw(0, .01, 0)

		-- Left wall
		lovr.graphics.push()
		lovr.graphics.translate(-5, 1.5, 0)
		self.models.landscape:setTexture(self.textures.landscape1)
		self.models.landscape:draw(.05, 0, 0, 1)
		lovr.graphics.scale(1, 3, 10)
		lovr.graphics.plane(self.textures.wall, 0, 0, 0, 1, math.pi / 2, 0, 1, 0)
		lovr.graphics.pop()

		-- Right wall
		lovr.graphics.push()
		lovr.graphics.translate(5, 1.5, 0)
		self.models.landscape:setTexture(self.textures.landscape2)
		self.models.landscape:draw(-.05, 0, 0, 1, math.pi, 0, 1, 0)
		lovr.graphics.scale(1, 3, 10)
		lovr.graphics.plane(self.textures.wall, 0, 0, 0, 1, -math.pi / 2, 0, 1, 0)
		lovr.graphics.pop()

		-- Front wall
		lovr.graphics.push()
		lovr.graphics.translate(0, 1.5, -5)
		self.models.portrait:setTexture(self.textures.portrait1)
		self.models.portrait:draw(-3, 0, .05, 1, -math.pi / 2, 0, 1, 0)
		self.models.portrait:setTexture(self.textures.portrait2)
		self.models.portrait:draw(3, 0, .05, 1, -math.pi / 2, 0, 1, 0)
		lovr.graphics.scale(10, 3, 1)
		lovr.graphics.plane(self.textures.wall, 0, 0, 0, 1)
		lovr.graphics.pop()

		-- Back wall
		lovr.graphics.push()
		lovr.graphics.translate(0, 1.5, 5)
		self.models.landscape:setTexture(self.textures.landscape3)
		self.models.landscape:draw(-3, 0, -.05, 1, math.pi / 2, 0, 1, 0)
		self.models.landscape:setTexture(self.textures.landscape4)
		self.models.landscape:draw(3, 0, -.05, 1, math.pi / 2, 0, 1, 0)
		lovr.graphics.scale(10, 3, 1)
		lovr.graphics.plane(self.textures.wall, 0, 0, 0, 1)
		lovr.graphics.pop()

		for i, player in ipairs(self.players) do
			local hx, hy, hz = lovr.headset.getPosition()
			if player.id ~= self.id then
				local x, y, z = denormalize(player.x, config.bounds), denormalize(player.y, config.bounds), denormalize(player.z, config.bounds)
				local angle, ax, ay, az = denormalize(player.angle, 2 * math.pi), denormalize(player.ax, 1), denormalize(player.ay, 1), denormalize(player.az, 1)
				self.models.head:draw(x, y, z, 1, angle, ax, ay, az)

				if player.emoji > 0 then
					local emojiSize = .08
					lovr.graphics.push()
					lovr.graphics.translate(x, y, z)
					lovr.graphics.rotate(angle, ax, ay, az)
					lovr.graphics.plane(self.textures[config.emoji[player.emoji]], 0, 0, -.01, emojiSize, math.pi, 0, 1, 0)
					lovr.graphics.pop()
				end

				lovr.graphics.setShader()
				local angle, ax, ay, az = lovr.math.lookAt(hx, hy, hz, x, y + .25, z)
				lovr.graphics.print(player.username, x, y + .25, z, .05, angle, ax, ay, az)
				lovr.graphics.setShader(self.shader)
			else
				if self.emoji.active then
					local index, px, py, pz = self:getEmojiIndex()
					local x, y, z = self.emoji.position:unpack()
					local cx, cy, cz = self.controllers[2]:getPosition()
					if index > 0 then
						lovr.graphics.line(cx, cy, cz, px, py, pz)
					end
					local planeSize = .5
					local emojiPerRow = 5
					local emojiSize = planeSize / emojiPerRow
					lovr.graphics.push()
					lovr.graphics.translate(x, y, z)
					lovr.graphics.rotate(unpack(self.emoji.orientation))
					lovr.graphics.setColor(20, 20, 20)
					lovr.graphics.plane('fill', 0, 0, 0, planeSize)
					lovr.graphics.setColor(255, 255, 255)
					for i, emoji in ipairs(config.emoji) do
						if i ~= index then
							local x = -planeSize / 2 + emojiSize / 2 + emojiSize * ((i - 1) % emojiPerRow)
							local y = planeSize / 2 - emojiSize / 2 - emojiSize * math.floor((i - 1) / emojiPerRow)
							lovr.graphics.plane(self.textures[emoji], x, y, .01, emojiSize * .75)
						end
					end
					for i, emoji in ipairs(config.emoji) do
						if i == index then
							local x = -planeSize / 2 + emojiSize / 2 + emojiSize * ((i - 1) % emojiPerRow)
							local y = planeSize / 2 - emojiSize / 2 - emojiSize * math.floor((i - 1) / emojiPerRow)
							lovr.graphics.plane(self.textures[emoji], x, y, .03, emojiSize * .75)
						end
					end
					lovr.graphics.pop()
				end

				lovr.graphics.setShader()
				local angle, ax, ay, az = lovr.headset.getOrientation()
				lovr.graphics.print(player.username, hx, hy + .35, hz, .07, angle, ax, ay, az)
				lovr.graphics.setShader(self.shader)

				if self.dueling > 0 then
					local other = self.players[self.dueling]
					local hx, hy, hz = lovr.headset.getPosition()
					local tx, ty, tz, angle, mySlotX, mySlotY, mySlotZ = self:getDuelZones()
					self.models.table:draw(tx, ty, tz, .5, angle, 0, 1, 0)
					lovr.graphics.setShader()
					local angle, ax, ay, az = lovr.math.lookAt(hx, hy, hz, tx, ty + .8, tz)
					lovr.graphics.print(math.ceil(self.duelTimer), tx, ty + .8, tz, .1, angle, ax, ay, az)
					lovr.graphics.setShader(self.shader)
					lovr.graphics.cube('fill', mySlotX, mySlotY, mySlotZ, .02)
				end
			end

			if self.controllerModel then
				local x, y, z, angle, ax, ay, az = self:getControllerTransform(player, 1)
				self.controllerModel:draw(x, y, z, 1, angle, ax, ay, az)
				local x, y, z, angle, ax, ay, az = self:getControllerTransform(player, 2)
				self.controllerModel:draw(x, y, z, 1, angle, ax, ay, az)
			end

			local cardCount = 0
			for i, card in ipairs(player.cards) do
				if card.position > 0 then
					cardCount = cardCount + 1
				end
			end

			local spread = .075
			local fan = -(cardCount - 1) / 2 * spread
			local closest, closestDistance
			if player.id == self.id then
				closest, closestDistance = self:getClosestCard()
			end

			for i, card in ipairs(player.cards) do
				if player.cards[i].position > 0 then
					if (self.dueling > 0 and player.id == self.id and (self.duelChoice == i or (self.cardGrab.active and self.cardGrab.card == i and self.duelHover))) or (self.dueling == player.id and player.duelChoice == i) then
						local tx, ty, tz, angle, mySlotX, mySlotY, mySlotZ, theirSlotX, theirSlotY, theirSlotZ = self:getDuelZones()
						local x, y, z
						if player.id == self.id then
							x, y, z = mySlotX, mySlotY, mySlotZ
						else
							x, y, z = theirSlotX, theirSlotY, theirSlotZ
						end
						lovr.graphics.push()
						lovr.graphics.translate(x, y, z)
						lovr.graphics.rotate(-math.pi / 2, 1, 0, 0)
						self:drawCard(player, i, 0, 0, 0, .5)
						lovr.graphics.pop()
					elseif (player.id == self.id and self.cardGrab.active and self.cardGrab.card == i) or (player.grabbedCard == i) then
						local x, y, z, angle, ax, ay, az = self:getControllerTransform(player, 2)
						lovr.graphics.push()
						lovr.graphics.translate(x, y, z)
						lovr.graphics.rotate(angle, ax, ay, az)
						lovr.graphics.translate(0, .05, -.05)
						lovr.graphics.rotate(-math.pi / 4, 1, 0, 0)
						self:drawCard(player, i, 0, 0, 0, .5)
						lovr.graphics.pop()
					else
						local x, y, z, angle, ax, ay, az = self:getControllerTransform(player, 1)
						lovr.graphics.push()
						lovr.graphics.translate(x, y, z)
						lovr.graphics.rotate(angle, ax, ay, az)
						lovr.graphics.push()
						lovr.graphics.translate(0, 0, .5)
						lovr.graphics.rotate(-fan, 0, 1, 0)
						lovr.graphics.translate(0, 0, -.65)
						if closest == i and closestDistance < .075 then
							lovr.graphics.translate(0, .02, 0)
							lovr.graphics.rotate(.2, 1, 0, 0)
						end
						lovr.graphics.rotate(-math.pi / 2, 1, 0, 0)
						lovr.graphics.rotate(.1, 0, 1, 0)
						self:drawCard(player, i, 0, 0, 0, .5)
						lovr.graphics.pop()
						lovr.graphics.pop()
					end
					fan = fan + spread
				end
			end

			lovr.graphics.setColor(255, 255, 255)

			for i = 1, player.stars do
				local x, y, z, angle, ax, ay, az = self:getControllerTransform(player, 1)
				lovr.graphics.push()
				lovr.graphics.translate(x, y, z)
				lovr.graphics.rotate(angle, ax, ay, az)
				lovr.graphics.translate(0, 0, .075 * (i - 1))
				lovr.graphics.translate(-.15 + math.min(.02 * (i - 1), .1), 0, 0)
				self.models.star:draw(0, 0, 0, 1, math.pi / 4, 0, 0, 1)
				lovr.graphics.pop()
			end

			for i = 1, player.money do
				local x, y, z, angle, ax, ay, az = self:getControllerTransform(player, 1)
				lovr.graphics.push()
				lovr.graphics.translate(x, y, z)
				lovr.graphics.rotate(angle, ax, ay, az)
				lovr.graphics.translate(.15, 0, .08)
				lovr.graphics.translate(-.005 * (i - 1), -.01 * (i - 1), 0, 0)
				lovr.graphics.rotate(math.pi / 2, 0, 1, 0)
				self.models.money:draw(0, 0, 0, .2, -.2 * i, 0, 1, 1)
				lovr.graphics.pop()
			end

			if (player.id == self.id and self.proposition > 0) or player.proposition > 0 then
				local prop = (player.id == self.id and self.proposition) or player.proposition
				local str = prop == 1 and 'Trade?' or 'Duel?'
				local x, y, z = self:getControllerTransform(player, 2)
				local hx, hy, hz = lovr.headset.getPosition()
				local angle, ax, ay, az = lovr.math.lookAt(hx, hy, hz, x, y + .2, z)
				lovr.graphics.sphere(x, y, z, .08, 0, 0, 0)
				lovr.graphics.setShader()
				lovr.graphics.print(str, x, y + .2, z, .05, angle, ax, ay, az)
				lovr.graphics.setShader(self.shader)
			end
		end

		lovr.graphics.setShader()
		if self.gameState == 'waiting' then
			lovr.graphics.print('Waiting for contestants...', 0, 3, -5, .5)
		elseif self.gameState == 'playing' then
			local t = math.floor(self.timer)
			local seconds = math.floor(t % 60)
			local minutes = math.floor(t / 60)
			if minutes < 10 then minutes = '0' .. minutes end
			if seconds < 10 then seconds = '0' .. seconds end
			lovr.graphics.setColor(0, 0, 0)
			lovr.graphics.print(minutes .. ':' .. seconds, 0, 2, -4.99, .5)
		end
	end
end

function client:getControllerTransform(player, index)
	if player.id == self.id then
		if not self.controllers[index] then return 0, 0, 0, 0, 0, 0, 0 end
		local x, y, z = self.controllers[index]:getPosition()
		return x, y, z, self.controllers[index]:getOrientation()
	else
		if index == 1 then
			local x, y, z = denormalize(player.lx, config.bounds), denormalize(player.ly, config.bounds), denormalize(player.lz, config.bounds)
			local angle, ax, ay, az = denormalize(player.langle, 2 * math.pi), denormalize(player.lax, 1), denormalize(player.lay, 1), denormalize(player.laz, 1)
			return x, y, z, angle, ax, ay, az
		else
			local x, y, z = denormalize(player.rx, config.bounds), denormalize(player.ry, config.bounds), denormalize(player.rz, config.bounds)
			local angle, ax, ay, az = denormalize(player.rangle, 2 * math.pi), denormalize(player.rax, 1), denormalize(player.ray, 1), denormalize(player.raz, 1)
			return x, y, z, angle, ax, ay, az
		end
	end
end

function client:drawCard(player, cardIndex, ...)
	local card = player.cards[cardIndex]
	if card.position <= 0 then return end

	if player.id == self.id or (cardIndex == player.grabbedCard and self.dueling ~= player.id) or (self.dueling == player.id and self.duelChoice > 0 and player.duelChoice > 0) then
		lovr.graphics.setColor(255, 255, 255)
	else
		lovr.graphics.setColor(0, 0, 0)
	end

	if card.type == 1 then
		self.models.rock:draw(...)
	elseif card.type == 2 then
		self.models.paper:draw(...)
	elseif card.type == 3 then
		self.models.scissors:draw(...)
	end
end

function client:quit()
  if self.host and self.peer then
    self.peer:disconnect_now()
    self.host:flush()
  end
end

function client:controlleradded()
	self:refreshControllers()
end

function client:controllerremoved()
	self:refreshControllers()
end

function client:controllerpressed(controller, button)
	if self.state ~= 'server' then return end
	if controller == self.controllers[2] and button == 'menu' then
		self.emoji.active = true
		self.emoji.vector = vec3(0, 0, -1):rotate(quat():angleAxis(self.controllers[2]:getOrientation()))
		self.emoji.vector.y = 0
		self.emoji.vector:normalize()
		self.emoji.position = vec3(self.controllers[2]:getPosition()) + self.emoji.vector * .1
		self.emoji.orientation = { quat():between(vec3(0, 0, -1), self.emoji.vector):getAngleAxis() }

		self.emoji.transform:origin()
		self.emoji.transform:translate(self.emoji.position:unpack())
		self.emoji.transform:rotate(unpack(self.emoji.orientation))
	elseif controller == self.controllers[2] and button == 'trigger' and not (self.dueling > 0 and self.duelChoice > 0) then
		local minCard, minDis, x, y, z, angle, ax, ay, az = self:getClosestCard()
		if minCard and minDis < .075 then
			self.cardGrab.active = true
			self.cardGrab.card = minCard
		end
	end
end

function client:controllerreleased(controller, button)
	if self.state ~= 'server' then return end
	if controller == self.controllers[2] and button == 'menu' and self.emoji.active == true then
		local index = self:getEmojiIndex()
		if index and index > 0 then
			self.emoji.current = index
		end
		self.emoji.active = false
	elseif controller == self.controllers[2] and button == 'trigger' and self.cardGrab.active then
		if self.dueling > 0 and self.duelHover then
			self.duelChoice = self.cardGrab.card
		end

		self:stopGrabbingCard()
	end
end

-- 2.2m, 1.1m
function client:getDuelZones()
	if self.dueling == 0 then return nil end
	local tableHeight = .9
	local tableLength = 2.2
	local other = self.players[self.dueling]
	local hx, hy, hz = lovr.headset.getPosition()
	local ox, oy, oz = denormalize(other.x, config.bounds), denormalize(other.y, config.bounds), denormalize(other.z, config.bounds)
	local tx, ty, tz = (hx + ox) / 2, tableHeight, (hz + oz) / 2
	local angle = -math.atan2((hz - oz), (hx - ox))
	local mySlotX, mySlotY, mySlotZ = tx + math.cos(-angle) * tableLength * .5 / 2 * .8, tableHeight + .2, tz + math.sin(-angle) * tableLength * .5 / 2 * .8
	local theirSlotX, theirSlotY, theirSlotZ = tx - math.cos(-angle) * tableLength * .5 / 2 * .8, tableHeight + .2, tz - math.sin(-angle) * tableLength * .5 / 2 * .8
	return tx, ty, tz, angle, mySlotX, mySlotY, mySlotZ, theirSlotX, theirSlotY, theirSlotZ
end

function client:stopGrabbingCard()
	self.cardGrab.active = false
	self.cardGrab.card = 0
end

local tmpTransform = lovr.math.newTransform()
function client:getClosestCard()
	if not self.controllers[2] then return nil end
	local mindis, mincard = 1000000, nil
	local player = self.players[self.id]
	if not player then return nil end
	local cardCount = 0
	for i = 1, #player.cards do if player.cards[i].position > 0 then cardCount = cardCount + 1 end end
	local spread = .075
	local fan = -(cardCount - 1) / 2 * spread
	local x, y, z = self.controllers[2]:getPosition()
	local angle, ax, ay, az = self.controllers[2]:getOrientation()
	for i, card in ipairs(player.cards) do
		if card.position > 0 then
			tmpTransform:origin()
			tmpTransform:translate(self.controllers[1]:getPosition())
			tmpTransform:rotate(self.controllers[1]:getOrientation())
			tmpTransform:translate(0, 0, .5)
			tmpTransform:rotate(-fan, 0, 1, 0)
			tmpTransform:translate(0, 0, -.65)
			local cx, cy, cz = tmpTransform:transformPoint(0, 0, 0)
			local dx, dy, dz = (cx - x), (cy - y), (cz - z)
			local dis = math.sqrt(dx * dx + dy * dy + dz * dz)
			if dis < mindis then
				mindis, mincard = dis, i
			end
			fan = fan + spread
		end
	end
	return mincard, mindis
end

function client:getEmojiIndex()
	if not self.emoji.active then return end

	-- Project controller onto emoji plane
	local v = vec3(self.controllers[2]:getPosition()) - self.emoji.position
	local n = -self.emoji.vector:normalize()
	local dist = v:dot(n)
	local p = (vec3(self.controllers[2]:getPosition()) - n:scale(dist))

	-- Transform into emojiplane-space
	local x, y, z = self.emoji.transform:inverseTransformPoint(p.x, p.y, p.z)

	-- Calculate row/column
	local planeSize = .5
	local emojiPerRow = 5
	local emojiSize = planeSize / emojiPerRow
	local row = 1 + math.floor((planeSize - (y + (planeSize / 2))) / emojiSize)
	local col = 1 + math.floor((x + planeSize / 2) / emojiSize)
	if row >= 1 and row <= math.floor(#config.emoji / emojiPerRow) and col >= 1 and col <= emojiPerRow then
		return (row - 1) * emojiPerRow + col, p.x, p.y, p.z
	end

	return 0
end

function client:refreshControllers()
	self.controllers = {}

	local controllers = lovr.headset.getControllers()
	for i = 1, lovr.headset.getControllerCount() do
		local controller = controllers[i]
		self.controllerModel = self.controllerModel or controller:newModel()
		self.controllers[i] = controller
	end
end

function client:connect(address)
  if self.host and self.peer then
    self.peer:disconnect_now()
    self.host:flush()
    self.host = nil
  end

  self.host = enet.host_create()
  self.host:connect(address)

  self.upload = trickle.create()
  self.download = trickle.create()
end

function client:reset()
  self.state = 'lobby'
  self.id = nil
  self.players = {}
  self:connect(config.remote .. ':12512')
end

function client:send(message, data)
	log('send', message)
  self.upload:clear()
  self.upload:write(signatures.client[message].id, '4bits')
  self.upload:pack(data, signatures.client[message])
  self.peer:send(tostring(self.upload))
end

client.events = {}

client.events.lobby = {}
function client.events.lobby.connect(self, event)
  log('event', 'connect')
  self.peer = event.peer
  self:send('queue')
end

function client.events.lobby.disconnect(self, event)
  log('event', 'disconnect')
  self.peer = nil
end

function client.events.lobby.receive(self, event)
  self.download:load(event.data)

  while true do
    local messageId = self.download:read('4bits')
    local message = messageId and signatures.lobby[messageId]
    local signature = message and signatures.lobby[message]

    if not signature or not self.messages.lobby[message] then break end

    log('event', 'receive', message)
    self.messages.lobby[message](self, self.download:unpack(signature))
  end
end

client.events.server = {}
function client.events.server.connect(self, event)
  log('event', 'connect')
	self.gameState = 'waiting'
  self.peer = event.peer
	self:send('join')
end

function client.events.server.disconnect(self, event)
  log('event', 'disconnect')
  self:reset()
end

function client.events.server.receive(self, event)
  self.download:load(event.data)

  while true do
    local messageId = self.download:read('4bits')
    local message = messageId and signatures.server[messageId]
    local signature = message and signatures.server[message]

    if not signature or not self.messages.server[message] then break end

    log('event', 'receive', message)
    self.messages.server[message](self, self.download:unpack(signature))
  end
end

client.messages = {}

client.messages.lobby = {}
function client.messages.lobby.start(self, data)
  self.state = 'server'
  self:connect(config.remote .. ':' .. data.port)
end

client.messages.server = {}
function client.messages.server.join(self, data)
	self.id = data.id
	self.gameState = data.state
	self.timer = data.timer
end

function client.messages.server.player(self, data)
	self.players[data.id] = data

	if data.id == self.id then
		print('Oh hey!  My username is ' .. data.username)
		print('I have ' .. data.stars .. ' stars!')
		print('I have $' .. data.money .. '000!')
	end
end

function client.messages.server.sync(self, data)
	for i, player in ipairs(data.players) do
		if player.id ~= self.id and self.players[player.id] then
			local p = self.players[player.id]
			p.x, p.y, p.z = player.x, player.y, player.z
			p.angle, p.ax, p.ay, p.az = player.angle, player.ax, player.ay, player.az
			p.lx, p.ly, p.lz = player.lx, player.ly, player.lz
			p.langle, p.lax, p.lay, p.laz = player.langle, player.lax, player.lay, player.laz
			p.rx, p.ry, p.rz = player.rx, player.ry, player.rz
			p.rangle, p.rax, p.ray, p.raz = player.rangle, player.rax, player.ray, player.raz
			p.emoji = player.emoji or p.emoji
			p.grabbedCard = player.grabbedCard or p.grabbedCard
			p.proposition = player.proposition or p.proposition
			p.duelChoice = player.duelChoice or p.duelChoice
		end
	end
end

function client.messages.server.gamestate(self, data)
	self.gameState = data.state
	self.timer = data.timer
end

function client.messages.server.duel(self, data)
	if data.first == self.id then
		self.dueling = data.second
		self.duelChoice = 0
		self.duelTimer = 30
		self.proposition = 0
	elseif data.second == self.id then
		self.dueling = data.first
		self.duelChoice = 0
		self.duelTimer = 30
		self.proposition = 0
	end
end

function client.messages.server.outcome(self, data)
	local p1 = self.players[data.first]
	local p2 = self.players[data.second]

	if p1 then
		p1.stars = data.firstStars
		p1.cards = data.firstCards
	end

	if p2 then
		p2.stars = data.secondStars
		p2.cards = data.secondCards
	end

	if (p1 and p1.id == self.id) or (p2 and p2.id == self.id) then
		self.dueling = 0
		self.duelChoice = 0
		self.duelTimer = 0
	end
end

return client
