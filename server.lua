local enet = require 'enet'
local trickle = require 'trickle'
local config = require 'config'
local signatures = require 'signatures'
local words = require 'words'

local function log(peer, ...)
  local tag = peer == 'all' and peer or peer:index()
  print('[' .. tag .. ']', ...)
end

local server = {}

function server:init()
  self.host = enet.host_create('*:12513')

  if not self.host then
    error('Could not start server')
  end

  self.peers = {}
  self.upload = trickle.create()
  self.download = trickle.create()

  self.players = {}
	self.lastSync = lovr.timer.getTime()

  print('Server ready on ' .. self.host:get_socket_address())
end

function server:update(dt)
	while true do
		local event = self.host:service(0)
		if not event then break end
		if self.events[event.type] then
			self.events[event.type](self, event)
		end
	end

	local t = lovr.timer.getTime()
	if #self.players > 1 and (t - self.lastSync) >= config.syncRate then
		local payload = { players = {} }
		for i = 1, config.maxPlayers do
			if self.players[i] then
				table.insert(payload.players, self.players[i])
			end
		end

		self:broadcast('sync', payload)
		self.lastSync = t
	end
end

function server:quit()
  if not self.host then return end

  for i = 1, self.host:peer_count() do
    local peer = self.host:get_peer(i)
    if peer then
      peer:disconnect_now()
    end
  end

  self.host:flush()
end

function server:send(peer, message, data)
  log(peer, 'send', message)
  self.upload:clear()
  self.upload:write(signatures.server[message].id, '4bits')
  self.upload:pack(data, signatures.server[message])
  peer:send(tostring(self.upload))
end

function server:broadcast(message, data)
  log('all', 'broadcast', message)
  self.upload:clear()
  self.upload:write(signatures.server[message].id, '4bits')
  self.upload:pack(data, signatures.server[message])
  self.host:broadcast(tostring(self.upload))
end

function server:generateUsername()
  local function isTaken(username)
    for i = 1, config.maxPlayers do
      local player = self.players[i]
      if player and player.username == username then
        return true
      end
    end

    return false
  end

  local username = ''

  repeat
    local adjective = words.adjectives[lovr.math.random(#words.adjectives)]
    local noun = words.nouns[lovr.math.random(#words.nouns)]
    username = adjective .. ' ' .. noun
  until not isTaken(username)

  return username
end

function server:createPlayer(peer)
  local id = #self.players + 1
  self.players[peer] = id
  self.players[id] = {
    id = id,
    username = self:generateUsername(),
    x = 2 ^ 15,
    y = 43000, -- 1.6m
    z = 2 ^ 15,
    stars = 3,
    money = 10,
    cards = {
      { type = 1, position = 1 },
      { type = 2, position = 2 },
      { type = 3, position = 3 }
    }
  }

  return self.players[id]
end

server.events = {}
function server.events.connect(self, event)
  log(event.peer, 'event', 'connect')
  self.peers[event.peer] = event.peer
end

function server.events.disconnect(self, event)
  log(event.peer, 'event', 'disconnect')
  self.peers[event.peer] = nil
  local id = self.players[event.peer]
  self.players[id] = nil
  self.players[event.peer] = nil
end

function server.events.receive(self, event)
  self.download:load(event.data)

  while true do
    local messageId = self.download:read('4bits')
    local message = messageId and signatures.client[messageId]
    local signature = message and signatures.client[message]

    if not signature or not self.messages[message] then break end

    log(event.peer, 'event', 'receive', message)
    self.messages[message](self, event.peer, self.download:unpack(signature))
  end
end

server.messages = {}
function server.messages.join(self, peer, data)
  local player = self:createPlayer(peer)
  self:send(peer, 'join', { id = player.id })
  self:broadcast('player', player)
	for i = 1, config.maxPlayers do
		if self.players[i] then
			self:send(peer, 'player', self.players[i])
		end
	end
end

function server.messages.input(self, peer, data)
  if not self.players[peer] then return end
  local player = self.players[self.players[peer]]
  player.x, player.y, player.z = data.x, data.y, data.z
end

return server
