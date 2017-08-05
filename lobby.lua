local enet = require 'enet'
local trickle = require 'trickle'
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
  local event = self.host:service(30)
  if event and self.events[event.type] then
    self.events[event.type](self, event)
  end
end

lobby.events = {}
function lobby.events.connect(self, event)
  log(event.peer, 'event', 'connect')
  self.peers[event.peer] = event.peer
end

function lobby.events.disconnect(self, event)
  log(event.peer, 'event', 'disconnect')
  self.peers[event.peer] = nil
end

function lobby.events.receive(self, event)
  log(event.peer, 'event', 'receive')
  self.download:load(event.data)

  while true do
    local message = self.download:read('4bits')
    local signature = message and signatures.client[message]
    if not message or not signature or not self.messages[message] then break end
    self.messages[message](self, peer, self.download:unpack(signature))
  end
end

lobby.messages = {}
function lobby.messages.authenticate(self, peer, data)
  log(event.peer, 'message', 'authenticate')
  print('Someone authenticated as ' .. data.username)
end

return lobby
