local controllers = {
  client = require 'client',
  --server = require 'server',
  lobby = require 'lobby'
}

local controller = controllers[MODE]

function lovr.load()
  controller:init()
end

function lovr.update(dt)
  controller:update(dt)
end
