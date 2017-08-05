local enet = require 'enet'
local trickle = require 'trickle'
local signatures = require 'signatures'

local client = {}

local function log(...)
  print(client.state, ...)
end

function client:init()
  self:reset()
end

function client:update(dt)
  local event = self.host:service(0)
  if event and self.events[self.state][event.type] then
    self.events[self.state][event.type](self, event)
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
    self.peer:disconnect()
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
  self:connect(arg[3] or 'localhost:12512')
end

function client:send(message, data)
  log('send', message)
  self.upload:clear()
  self.upload:write(signatures.client[message].id, '4bits')
  self.upload:pack(data, signatures.client[message])
  self.peer:send(tostring(self.upload))
end

client.events = {lobby = {}, server = {}}
function client.events.lobby.connect(self, event)
  log('event', 'connect')
  self.peer = event.peer
  self:send('join')
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

function client.events.server.connect(self, event)
  log('event', 'connect')
  self.peer = event.peer
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

client.messages = {lobby = {}, server = {}}

function client.messages.lobby.start(self, data)
  self.state = 'server'
  self:connect(data.server)
end

return client
