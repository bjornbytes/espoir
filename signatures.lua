local signatures = {}

signatures.client = {
  'queue',
  queue = {
    id = 1
  },

  'join',
  join = {
    id = 2
  },

  'input',
  input = {
    id = 3,
    { 'x', '16bits' },
    { 'y', '16bits' },
    { 'z', '16bits' }
  }
}

signatures.lobby = {
  'start',
  start = {
    id = 1,
    { 'port', '16bits' }
  }
}

signatures.server = {
  'join',
  join = {
    id = 1,
    { 'id', '8bits' },
		{ 'state', 'string' }
  },

  'player',
  player = {
    id = 2,
    { 'id', '8bits' },
    { 'username', 'string' },
    { 'x', '16bits' },
    { 'y', '16bits' },
    { 'z', '16bits' },
		{ 'angle', '16bits' },
    { 'ax', '16bits' },
    { 'ay', '16bits' },
    { 'az', '16bits' },
    { 'stars', '4bits' },
    { 'money', '8bits' },
    { 'cards', { { 'type', '2bits' }, { 'position', '4bits' } } }
  },

  'sync',
  sync = {
    id = 3,
    {
      'players', {
        { 'id', '8bits' },
        { 'x', '16bits' },
        { 'y', '16bits' },
        { 'z', '16bits' },
				{ 'angle', '16bits' },
				{ 'ax', '16bits' },
				{ 'ay', '16bits' },
				{ 'az', '16bits' },
      }
    }
  },

	'gamestate',
	gamestate = {
		id = 4,
		{ 'state', 'string' }
	}
}

return signatures
