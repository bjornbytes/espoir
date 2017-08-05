local signatures = {}

signatures.client = {
  'queue',
  queue = {
    id = 1
  },

	'join',
	join = {
		id = 2
	}
}

signatures.lobby = {
  'start',
  start = {
    id = 1,
    { 'server', 'string' }
  }
}

signatures.server = {
	'join',
	join = {
		id = 1,
		{ 'id', '8bits' }
	},

	'player',
	player = {
		id = 2,
		{ 'id', '8bits' },
		{ 'username', 'string' },
		{ 'stars', '4bits' },
		{ 'money', '8bits' },
		{ 'cards', { { 'type', '2bits' }, { 'position', '4bits' } } }
	}
}

return signatures
