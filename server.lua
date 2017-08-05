local enet = require 'enet'
local trickle = require 'trickle'
local config = require 'config'
local signatures = require 'signatures'

local function log(peer, ...)
  print('[' .. peer:index() .. ']', ...)
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

  print('Server ready on ' .. self.host:get_socket_address())
end

function server:update(dt)
  local event = self.host:service(0)
  if event and self.events[event.type] then
    self.events[event.type](self, event)
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

server.events = {}
function server.events.connect(self, event)
  log(event.peer, 'event', 'connect')
  self.peers[event.peer] = event.peer
end

function server.events.disconnect(self, event)
  log(event.peer, 'event', 'disconnect')
  self.peers[event.peer] = nil
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

return server
