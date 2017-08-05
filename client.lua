local enet = require 'enet'
local trickle = require 'trickle'
local config = require 'config'
local signatures = require 'signatures'

local client = {}

local function log(...)
  print(client.state, ...)
end

local function normalize(x)
	return math.floor(((x + config.bounds) / (2 * config.bounds)) * (2 ^ 16))
end

local function denormalize(x)
  return ((x / (2 ^ 16)) - .5) * config.bounds
end

function client:init()
  self:reset()
	self.lastInput = lovr.timer.getTime()
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
    self:send('input', { x = normalize(x), y = normalize(y), z = normalize(z) })
		self.lastInput = t
  end
end

function client:draw()
	print('draw', #self.players)
  for i, player in ipairs(self.players) do
		print(player.id, self.id)
    if player.id ~= self.id then
      local x, y, z = denormalize(player.x), denormalize(player.y), denormalize(player.z)
			print(x, y, z)
      lovr.graphics.cube('fill', x, y, z, .3)
    end
  end
end

function client:quit()
  if self.host and self.peer then
    self.peer:disconnect_now()
    self.host:flush()
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
	print('sync', #data.players, #self.players)
	for i, player in ipairs(data.players) do
		print(player.id .. ' is at ' .. player.x .. ', ' .. player.y .. ', ' .. player.z)
		if player.id ~= self.id and self.players[player.id] then
			local p = self.players[player.id]
			p.x, p.y, p.z = player.x, player.y, player.z
		end
	end
end

return client
