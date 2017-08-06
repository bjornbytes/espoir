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
    { 'z', '16bits' },
    { 'angle', '16bits' },
    { 'ax', '16bits' },
    { 'ay', '16bits' },
    { 'az', '16bits' },
    { 'lx', '16bits' },
    { 'ly', '16bits' },
    { 'lz', '16bits' },
    { 'langle', '16bits' },
    { 'lax', '16bits' },
    { 'lay', '16bits' },
    { 'laz', '16bits' },
    { 'rx', '16bits' },
    { 'ry', '16bits' },
    { 'rz', '16bits' },
    { 'rangle', '16bits' },
    { 'rax', '16bits' },
    { 'ray', '16bits' },
    { 'raz', '16bits' },
		{ 'emoji', '8bits' },
		{ 'grabbedCard', '8bits' },
		{ 'proposition', '2bits' }
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
		{ 'state', 'string' },
		{ 'timer', 'float' }
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
    { 'lx', '16bits' },
    { 'ly', '16bits' },
    { 'lz', '16bits' },
		{ 'langle', '16bits' },
    { 'lax', '16bits' },
    { 'lay', '16bits' },
    { 'laz', '16bits' },
    { 'rx', '16bits' },
    { 'ry', '16bits' },
    { 'rz', '16bits' },
		{ 'rangle', '16bits' },
    { 'rax', '16bits' },
    { 'ray', '16bits' },
    { 'raz', '16bits' },
    { 'stars', '4bits' },
    { 'money', '8bits' },
    { 'cards', { { 'type', '2bits' }, { 'position', '4bits' } } },
		{ 'emoji', '8bits' },
		{ 'grabbedCard', '8bits' },
		{ 'proposition', '2bits' }
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
        { 'lx', '16bits' },
        { 'ly', '16bits' },
        { 'lz', '16bits' },
				{ 'langle', '16bits' },
				{ 'lax', '16bits' },
				{ 'lay', '16bits' },
				{ 'laz', '16bits' },
        { 'rx', '16bits' },
        { 'ry', '16bits' },
        { 'rz', '16bits' },
				{ 'rangle', '16bits' },
				{ 'rax', '16bits' },
				{ 'ray', '16bits' },
				{ 'raz', '16bits' },
				{ 'emoji', '8bits' },
				{ 'grabbedCard', '8bits' },
				{ 'proposition', '2bits' }
      }
    }
  },

	'gamestate',
	gamestate = {
		id = 4,
		{ 'state', 'string' },
		{ 'timer', 'float' }
	}
}

return signatures
