local enet = require 'enet'
local trickle = require 'trickle'
local config = require 'config'
local signatures = require 'signatures'
local words = require 'words'

local function log(peer, ...)
  local tag = peer == 'all' and peer or peer:index()
  --print('[' .. tag .. ']', ...)
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

	self.gameState = 'waiting'
	self.timer = 0
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

	if self.timer > 0 then
		self.timer = self.timer - dt
		if self.timer <= 0 and self.gameState == 'playing' then
			print('times up!')
		end
	end

	for i = 1, config.maxPlayers do
		if self.players[i] then
			if self.players[i].dueling == 0 and self.players[i].proposition > 0 then
				for j = 1, config.maxPlayers do
					if i ~= j and self.players[j] and self.players[j].dueling == 0 then
						local p1, p2 = self.players[i], self.players[j]
						local thresh = (.08 / (config.bounds * 2)) * (2 ^ 16)
						if p1.proposition == p2.proposition and math.sqrt((p1.rx - p2.rx) ^ 2 + (p1.ry - p2.ry) ^ 2 + (p1.rz - p2.rz) ^ 2) < thresh then
							p1.dueling = j
							p2.dueling = i
							p1.duelTimer = 30
							p2.duelTimer = 30
							p1.duelOutcomeTimer = 1
							p2.duelOutcomeTimer = 1
							p1.proposition = 0
							p2.proposition = 0
							p1.duelChoice = 0
							p2.duelChoice = 0
							self:broadcast('duel', { first = i, second = j })
						end
					end
				end
			end

			if self.players[i].dueling > 0 then
				local p1 = self.players[i]
				local p2 = self.players[p1.dueling]

				if p1.duelChoice > 0 and p2.duelChoice > 0 then
					p1.duelTimer = 0
					p2.duelTimer = 0
					p1.duelOutcomeTimer = math.max(p1.duelOutcomeTimer - dt, 0)

					if p1.duelOutcomeTimer == 0 then
						p1.dueling = 0
						p2.dueling = 0
						p1.cards[p1.duelChoice].position = 0
						p2.cards[p2.duelChoice].position = 0

						-- Figure out if someone won
						local p1Type = p1.cards[p1.duelChoice].type
						local p2Type = p2.cards[p2.duelChoice].type
						if (p1Type == 2 and p2Type == 1) or (p1Type == 1 and p2Type == 3) or (p1Type == 3 and p2Type == 2) then
							p1.stars = p1.stars + 1
							p2.stars = p2.stars - 1
						elseif (p2Type == 2 and p1Type == 1) or (p2Type == 1 and p1Type == 3) or (p2Type == 3 and p1Type == 2) then
							p1.stars = p1.stars - 1
							p2.stars = p2.stars + 1
						end

						-- Tell everyone about the changes
						self:broadcast('outcome', { first = i, second = p1.dueling, firstCards = p1.cards, secondCards = p2.cards, firstStars = p1.stars, secondStars = p2.stars })
					end
				end

				if p1.duelTimer > 0 then
					p1.duelTimer = math.max(p1.duelTimer - dt, 0)
					if p1.duelTimer == 0 then
						p1.dueling = 0
						p2.dueling = 0

						if p1.duelChoice > 0 and p2.duelChoice == 0 then
							p1.cards[p1.duelChoice].position = 0
							p1.stars = p1.stars + 1
							p2.stars = p2.stars - 1
						elseif p2.duelChoice > 0 and p1.duelChoice == 0 then
							p2.cards[p2.duelChoice].position = 0
							p2.stars = p2.stars + 1
							p1.stars = p1.stars - 1
						end

						self:broadcast('outcome', { first = i, second = p1.dueling, firstCards = p1.cards, secondCards = p2.cards, firstStars = p1.stars, secondStars = p2.stars })
					end
				end
			end
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

		self:broadcast('sync', payload, 'unreliable')
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

function server:broadcast(message, data, method)
  log('all', 'broadcast', message)
  self.upload:clear()
  self.upload:write(signatures.server[message].id, '4bits')
  self.upload:pack(data, signatures.server[message])
  self.host:broadcast(tostring(self.upload), 0, method or 'reliable')
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
		angle = 0,
		ax = 0,
		ay = 0,
		az = 0,
		lx = 0,
		ly = 0,
		lz = 0,
		langle = 0,
		lax = 0,
		lay = 0,
		laz = 0,
		rx = 0,
		ry = 0,
		rz = 0,
		rangle = 0,
		rax = 0,
		ray = 0,
		raz = 0,
    stars = 3,
    money = 10,
    cards = {
      { type = 1, position = 1 },
      { type = 2, position = 2 },
      { type = 3, position = 3 },
      { type = 1, position = 1 },
      { type = 2, position = 2 },
      { type = 3, position = 3 },
      { type = 1, position = 1 },
      { type = 2, position = 2 },
      { type = 3, position = 3 },
      { type = 1, position = 1 },
      { type = 2, position = 2 },
      { type = 3, position = 3 }
    },
		emoji = 0,
		grabbedCard = 0,
		proposition = 0,
		dueling = 0,
		duelTimer = 0,
		duelOutcomeTimer = 0,
		duelChoice = 0
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
  self:send(peer, 'join', { id = player.id, state = self.gameState, timer = self.timer })
  self:broadcast('player', player)
	local count = 0
	for i = 1, config.maxPlayers do
		if self.players[i] then
			count = count + 1
			if i ~= player.id then
				self:send(peer, 'player', self.players[i])
			end
		end
	end

	if self.gameState == 'waiting' and count >= config.groupSize then
		self.gameState = 'playing'
		self.timer = 10 * 60
		self:broadcast('gamestate', { state = self.gameState, timer = self.timer })
	end
end

function server.messages.input(self, peer, data)
  if not self.players[peer] then return end
  local player = self.players[self.players[peer]]
  player.x, player.y, player.z = data.x, data.y, data.z
  player.angle, player.ax, player.ay, player.az = data.angle, data.ax, data.ay, data.az
  player.lx, player.ly, player.lz = data.lx, data.ly, data.lz
  player.langle, player.lax, player.lay, player.laz = data.langle, data.lax, data.lay, data.laz
  player.rx, player.ry, player.rz = data.rx, data.ry, data.rz
  player.rangle, player.rax, player.ray, player.raz = data.rangle, data.rax, data.ray, data.raz
	player.emoji = data.emoji
	player.grabbedCard = data.grabbedCard
	player.proposition = data.proposition
	player.duelChoice = data.duelChoice
end

return server
