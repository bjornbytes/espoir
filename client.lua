local enet = require 'enet'

local client = {}

local function log(peer, ...)
  print('[' .. peer:index() .. ']', ...)
end

function client:init()
  self:reset()
end

function client:connect(address)
  if self.host then
    self.host:disconnect()
    self.host:flush()
    self.host = nil
  end

  self.host = enet.host_create()
  self.host:connect(address)
end

function client:reset()
  self:connect(arg[3] or 'localhost:12512')
end

function client:update(dt)
  local event = self.host:service(0)
  if event and self.events[event.type] then
    self.events[event.type](self, event)
  end
end

client.events = {}
function client.events.connect(self, event)
  log(event.peer, 'event', 'connect')
  self.peer = event.peer
end

function client.events.disconnect(self, event)
  log(event.peer, 'event', 'disconnect')
  self.peer = nil
end

function client.events.receive(self, event)
  log(event.peer, 'event', 'receive')
end

client.messages = {}

return client
