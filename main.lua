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

function lovr.controlleradded(...)
	if controller.controlleradded then controller:controlleradded(...) end
end

function lovr.controllerremoved(...)
	if controller.controllerremoved then controller:controllerremoved(...) end
end

function lovr.controllerpressed(...)
	if controller.controllerpressed then controller:controllerpressed(...) end
end

function lovr.controllerreleased(...)
	if controller.controllerreleased then controller:controllerreleased(...) end
end
