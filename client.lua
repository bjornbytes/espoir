local enet = require 'enet'
local trickle = require 'trickle'
local config = require 'config'
local signatures = require 'signatures'
local maf = require 'maf'
local vec3 = maf.vec3
local quat = maf.quat

local client = {}

local function log(...)
  print(client.state, ...)
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
	self.lastInput = lovr.timer.getTime()
	self.models = {
		head = lovr.graphics.newModel('media/head.obj', 'media/head-tex.png'),
		rock = lovr.graphics.newModel('media/rock-card.obj', 'media/rock-tex.png'),
		paper = lovr.graphics.newModel('media/paper-card.obj', 'media/paper-tex.png'),
		scissors = lovr.graphics.newModel('media/scissor-card.obj', 'media/scissor-tex.png')
	}
end

function client:update(dt)
	while true do
		local event = self.host:service(0)
		if not event then break end
		if self.events[self.state][event.type] then
			self.events[self.state][event.type](self, event)
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
			raz = normalize(raz, 1)
		})
		self.lastInput = t
  end
end

function client:draw()
	if self.state == 'server' then
		lovr.graphics.setColor(50, 50, 50)
		lovr.graphics.plane('fill', 0, 0, 0, 10, math.pi / 2, 1, 0, 0)

		lovr.graphics.setColor(255, 255, 255)
		if self.gameState == 'waiting' then
			lovr.graphics.print('Waiting for contestants...', 0, 3, -5, .5)
		elseif self.gameState == 'playign' then
			local t = math.floor(self.timer)
			local seconds = math.floor(t % 60)
			local minutes = math.floor(t / 60)
			if minutes < 10 then minutes = '0' .. minutes end
			if seconds < 10 then seconds = '0' .. seconds end
			lovr.graphics.print(minutes .. ':' .. seconds, 0, 3, -5, .5)
		end

		for i, player in ipairs(self.players) do
			if player.id ~= self.id then
				local x, y, z = denormalize(player.x, config.bounds), denormalize(player.y, config.bounds), denormalize(player.z, config.bounds)
				local angle, ax, ay, az = (player.angle / (2 ^ 16)) * (2 * math.pi), denormalize(player.ax, 1), denormalize(player.ay, 1), denormalize(player.az, 1)
				self.models.head:draw(x, y, z, 1, angle, ax, ay, az)

				if self.controllerModel then
					local x, y, z = denormalize(player.lx, config.bounds), denormalize(player.ly, config.bounds), denormalize(player.lz, config.bounds)
					local angle, ax, ay, az = (player.langle / (2 ^ 16)) * (2 * math.pi), denormalize(player.lax, 1), denormalize(player.lay, 1), denormalize(player.laz, 1)
					self.controllerModel:draw(x, y, z, 1, angle, ax, ay, az)
					local x, y, z = denormalize(player.rx, config.bounds), denormalize(player.ry, config.bounds), denormalize(player.rz, config.bounds)
					local angle, ax, ay, az = (player.rangle / (2 ^ 16)) * (2 * math.pi), denormalize(player.rax, 1), denormalize(player.ray, 1), denormalize(player.raz, 1)
					self.controllerModel:draw(x, y, z, 1, angle, ax, ay, az)
				end
			else
				if self.controllers[1] then
					local cardCount = 0
					for i, card in ipairs(player.cards) do
						if card.position > 0 then
							cardCount = cardCount + 1
						end
					end

					local spread = .075
					local fan = -(cardCount - 1) / 2 * spread
					for i, card in ipairs(player.cards) do
						local x, y, z = self.controllers[1]:getPosition()
						local angle, ax, ay, az = self.controllers[1]:getOrientation()
						lovr.graphics.push()
						lovr.graphics.translate(x, y, z)
						lovr.graphics.rotate(angle, ax, ay, az)
						lovr.graphics.push()
						lovr.graphics.translate(0, 0, .5)
						lovr.graphics.rotate(-fan, 0, 1, 0)
						lovr.graphics.translate(0, 0, -.65)
						lovr.graphics.rotate(-math.pi / 2, 1, 0, 0)
						lovr.graphics.rotate(.1, 0, 1, 0)
						if card.type == 1 then
							self.models.rock:draw(0, 0, 0, .5)
						elseif card.type == 2 then
							self.models.paper:draw(0, 0, 0, .5)
						elseif card.type == 3 then
							self.models.scissors:draw(0, 0, 0, .5)
						end
						lovr.graphics.pop()
						lovr.graphics.pop()
						fan = fan + spread
					end
				end
			end
		end
	end

	if self.controllerModel then
		for i, controller in ipairs(self.controllers) do
			local x, y, z = controller:getPosition()
			self.controllerModel:draw(x, y, z, 1, controller:getOrientation())
		end
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
		end
	end
end

function client.messages.server.gamestate(self, data)
	self.gameState = data.state
	self.timer = data.timer
end

return client
