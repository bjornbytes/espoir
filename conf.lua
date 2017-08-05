MODE = arg[2] or 'client'

function lovr.conf(t)
  if MODE ~= 'client' then
    t.modules.headset = false
    t.modules.graphics = false
    t.modules.audio = false
  end
end
