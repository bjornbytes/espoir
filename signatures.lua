local signatures = {}

signatures.client = {
  'join',
  join = {
    id = 1
  }
}

signatures.lobby = {
  'start',
  start = {
    id = 1,
    { 'server', 'string' }
  }
}

signatures.server = {}

return signatures
