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

local function normalize(x)
	return math.floor(((x + config.bounds) / (2 * config.bounds)) * (2 ^ 16))
end

local function denormalize(x)
  return ((x / (2 ^ 16)) - .5) * 2 * config.bounds
end

function client:init()
  self:reset()
	self:refreshControllers()
	self.lastInput = lovr.timer.getTime()
	self.models = {
		rock = lovr.graphics.newModel('media/rock-card.obj', 'media/rock-side.png'),
		paper = lovr.graphics.newModel('media/paper-card.obj', 'media/paper-side.png'),
		scissors = lovr.graphics.newModel('media/scissor-card.obj', 'media/scissor-side.png')
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
    self:send('input', {
			x = normalize(x),
			y = normalize(y),
			z = normalize(z),
			angle = math.floor((angle / (2 * math.pi)) * (2 ^ 16)),
			ax = math.floor(ax * (2 ^ 16)),
			ay = math.floor(ay * (2 ^ 16)),
			az = math.floor(az * (2 ^ 16))
		})
		self.lastInput = t
  end
end

function client:draw()
	if self.state == 'server' then
		lovr.graphics.setColor(255, 255, 255)
		lovr.graphics.plane('fill', 0, 0, 0, 10, math.pi / 2, 1, 0, 0)

		if self.gameState == 'waiting' then
			lovr.graphics.print('Waiting for contestants...', 0, 3, -5, .5)
		end

		for i, player in ipairs(self.players) do
			if player.id ~= self.id then
				local x, y, z = denormalize(player.x), denormalize(player.y), denormalize(player.z)
				local angle, ax, ay, az = (player.angle / (2 ^ 16)) * (2 * math.pi), player.ax / (2 ^ 16), player.ay / (2 ^ 16), player.az / (2 ^ 16)
				lovr.graphics.cube('fill', x, y, z, .3, angle, ax, ay, az)
			else
				if self.controllers[1] then
					local cardCount = 0
					for i, card in ipairs(player.cards) do
						if card.position > 0 then
							cardCount = cardCount + 1
						end
					end

					local spread = .1
					local fan = -(cardCount - 1) / 2 * spread
					for i, card in ipairs(player.cards) do
						local x, y, z = self.controllers[1]:getPosition()
						local angle, ax, ay, az = self.controllers[1]:getOrientation()
						lovr.graphics.push()
						lovr.graphics.translate(x, y, z)
						lovr.graphics.rotate(angle, ax, ay, az)
						lovr.graphics.push()
						lovr.graphics.rotate(fan, 0, 1, 0)
						lovr.graphics.translate(0, 0, -.2)
						self.models.rock:draw(0, 0, 0, 1, math.pi / 2, 1, 1, 0)
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
		end
	end
end

function client.messages.server.gamestate(self, data)
	self.gameState = data.state
end

return client
