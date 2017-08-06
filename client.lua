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
		money = lovr.graphics.newModel('media/moneystack.obj', 'media/money-tex.jpg')
	}
	self.cardGrab = {
		active = false,
		position = 0,
		offset = nil,
		rotation = nil
	}

	self.textures = {}
	for _, emoji in ipairs(config.emoji) do
		self.textures[emoji] = lovr.graphics.newTexture('media/emoji/' .. emoji .. '.png')
	end

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
				angle = math.floor((angle / (2 * math.pi)) * (2 ^ 16)),
				ax = normalize(ax, 1),
				ay = normalize(ay, 1),
				az = normalize(az, 1),
				lx = normalize(lx, config.bounds),
				ly = normalize(ly, config.bounds),
				lz = normalize(lz, config.bounds),
				langle = math.floor((langle / (2 * math.pi)) * (2 ^ 16)),
				lax = normalize(lax, 1),
				lay = normalize(lay, 1),
				laz = normalize(laz, 1),
				rx = normalize(rx, config.bounds),
				ry = normalize(ry, config.bounds),
				rz = normalize(rz, config.bounds),
				rangle = math.floor((rangle / (2 * math.pi)) * (2 ^ 16)),
				rax = normalize(rax, 1),
				ray = normalize(ray, 1),
				raz = normalize(raz, 1),
				emoji = self.emoji.current,
				grabbedCard = self.cardGrab.position
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
		self.shader:send('viewMat', self.viewMat)

		lovr.graphics.setColor(255, 255, 255)
		lovr.graphics.setShader()
		if self.gameState == 'waiting' then
			lovr.graphics.print('Waiting for contestants...', 0, 3, -5, .5)
		elseif self.gameState == 'playing' then
			local t = math.floor(self.timer)
			local seconds = math.floor(t % 60)
			local minutes = math.floor(t / 60)
			if minutes < 10 then minutes = '0' .. minutes end
			if seconds < 10 then seconds = '0' .. seconds end
			lovr.graphics.print(minutes .. ':' .. seconds, 0, 3, -5, .5)
		end

		lovr.graphics.setColor(50, 50, 50)
		lovr.graphics.plane('fill', 0, 0, 0, 10, math.pi / 2, 1, 0, 0)

		lovr.graphics.setShader(self.shader)
		lovr.graphics.setColor(255, 255, 255)

		for i, player in ipairs(self.players) do
			if player.id ~= self.id then
				local x, y, z = denormalize(player.x, config.bounds), denormalize(player.y, config.bounds), denormalize(player.z, config.bounds)
				local angle, ax, ay, az = (player.angle / (2 ^ 16)) * (2 * math.pi), denormalize(player.ax, 1), denormalize(player.ay, 1), denormalize(player.az, 1)
				self.models.head:draw(x, y, z, 1, angle, ax, ay, az)

				if player.emoji > 0 then
					local emojiSize = .08
					lovr.graphics.push()
					lovr.graphics.translate(x, y, z)
					lovr.graphics.rotate(angle, ax, ay, az)
					lovr.graphics.plane(self.textures[config.emoji[player.emoji]], 0, 0, -.01, emojiSize)
					lovr.graphics.pop()
				end

				-- todo this could use self:getControllerTransform
			else
				if self.controllers[1] then
				end

				if self.emoji.active then
					local index = self:getEmojiIndex()
					local x, y, z = self.emoji.position:unpack()
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
					if (player.id == self.id and self.cardGrab.active and self.cardGrab.card == i) or (player.grabbedCard == i) then
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
						if closest == i and closestDistance < .05 then
							lovr.graphics.translate(0, .02, 0)
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
				lovr.graphics.translate(0, 0, .01 + .015 * i)
				lovr.graphics.translate(.12 + .01 * (i - 1), 0, 0)
				lovr.graphics.rotate(math.pi / 2, 1, 0, 0)
				lovr.graphics.rotate(math.pi / 2, 0, 0, 1)
				self.models.money:draw(0, 0, 0, .2, -.1 * i, 0, 1, 0)
				lovr.graphics.pop()
			end
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
			local angle, ax, ay, az = (player.langle / (2 ^ 16)) * (2 * math.pi), denormalize(player.lax, 1), denormalize(player.lay, 1), denormalize(player.laz, 1)
			return x, y, z, angle, ax, ay, az
		else
			local x, y, z = denormalize(player.rx, config.bounds), denormalize(player.ry, config.bounds), denormalize(player.rz, config.bounds)
			local angle, ax, ay, az = (player.rangle / (2 ^ 16)) * (2 * math.pi), denormalize(player.rax, 1), denormalize(player.ray, 1), denormalize(player.raz, 1)
			return x, y, z, angle, ax, ay, az
		end
	end
end

function client:drawCard(player, cardIndex, ...)
	local card = player.cards[cardIndex]
	if card.position <= 0 then return end

	if player.id == self.id then
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
	elseif controller == self.controllers[2] and button == 'trigger' then
		local minCard, minDis, x, y, z, angle, ax, ay, az = self:getClosestCard()
		if minCard and minDis < .05 then
			self.cardGrab.active = true
			self.cardGrab.card = minCard
		end
	end
end

function client:controllerreleased(controller, button)
	if controller == self.controllers[2] and button == 'menu' and self.emoji.active == true then
		local index = self:getEmojiIndex()
		if index and index > 0 then
			self.emoji.current = index
		end
		self.emoji.active = false
	elseif controller == self.controllers[2] and button == 'trigger' and self.cardGrab.active then
		self.cardGrab.active = false
		self.cardGrab.card = nil
	end
end

local tmpTransform = lovr.math.newTransform()
function client:getClosestCard()
	if not self.controllers[2] then return nil end
	local mindis, mincard = 1000000, nil
	local player = self.players[self.id]
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
		return (row - 1) * emojiPerRow + col
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
			p.langle, p.lax, p.lay, p.az = player.langle, player.lax, player.lay, player.az
			p.rx, p.ry, p.rz = player.rx, player.ry, player.rz
			p.rangle, p.rax, p.ray, p.az = player.rangle, player.rax, player.ray, player.az
			p.emoji = player.emoji
			p.grabbedCard = player.grabbedCard
		end
	end
end

function client.messages.server.gamestate(self, data)
	self.gameState = data.state
	self.timer = data.timer
end

return client
