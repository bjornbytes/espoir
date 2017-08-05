local config = require 'config'

function lovr.conf(t)
  if config.role ~= 'client' then
    t.modules.headset = false
    t.modules.graphics = false
    t.modules.audio = false
  end
end
