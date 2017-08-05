local config = require 'config'

local controllers = {
  client = require 'client',
  server = require 'server',
  lobby = require 'lobby'
}

local controller = controllers[config.role]

function lovr.load()
  controller:init()
end

function lovr.update(dt)
  controller:update(dt)
end

function lovr.draw()
  if controller.draw then controller:draw() end
end

function lovr.quit()
  controller:quit()
end
