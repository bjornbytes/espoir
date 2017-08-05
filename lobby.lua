local enet = require 'enet'
local trickle = require 'trickle'
local config = require 'config'
local signatures = require 'signatures'

local function log(peer, ...)
  print('[' .. peer:index() .. ']', ...)
end

local lobby = {}

function lobby:init()
  self.host = enet.host_create('*:12512')

  if not self.host then
    error('Could not start lobby')
  end

  self.peers = {}
  self.queue = {}
  self.upload = trickle.create()
  self.download = trickle.create()

  print('Lobby ready on ' .. self.host:get_socket_address())
end

function lobby:update(dt)
  local event = self.host:service(100)
  if event and self.events[event.type] then
    self.events[event.type](self, event)
  end
end

function lobby:quit()
  if not self.host then return end

  for i = 1, self.host:peer_count() do
    local peer = self.host:get_peer(i)
    if peer then
      peer:disconnect_now()
    end
  end

  self.host:flush()
end

function lobby:enqueue(peer)
  for i = 1, #self.queue do
    if self.queue[i] == peer then
      return
    end
  end

  table.insert(self.queue, peer)

  if #self.queue == config.groupSize then
    self:start()
  end
end

function lobby:dequeue(peer)
  for i = 1, #self.queue do
    if self.queue[i] == peer then
      table.remove(self.queue, i)
      return
    end
  end
end

function lobby:start()
  if #self.queue < config.groupSize then
    return
  end

  while #self.queue > 0 do
    self:send(self.queue[#self.queue], 'start', { port = 12513 })
    self.queue[#self.queue]:send(tostring(self.upload))
    self.queue[#self.queue]:disconnect_later()
    table.remove(self.queue)
  end
end

function lobby:send(peer, message, data)
  log(peer, 'send', message)
  self.upload:clear()
  self.upload:write(signatures.lobby[message].id, '4bits')
  self.upload:pack(data, signatures.lobby[message])
  peer:send(tostring(self.upload))
end

lobby.events = {}
function lobby.events.connect(self, event)
  log(event.peer, 'event', 'connect')
  self.peers[event.peer] = event.peer
end

function lobby.events.disconnect(self, event)
  log(event.peer, 'event', 'disconnect')
  self:dequeue(event.peer)
  self.peers[event.peer] = nil
end

function lobby.events.receive(self, event)
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

lobby.messages = {}
function lobby.messages.queue(self, peer, data)
  self:enqueue(peer)
end

return lobby
