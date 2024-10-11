local box = require('box')

-- Initialize Tarantool space for users, orders, and positions
box.once('init', function()
  box.schema.space.create('users')
  box.space.users:format({
    { name = 'user_id', type = 'string' },
    { name = 'balance', type = 'number' }
  })
  box.space.users:create_index('primary', { parts = { 'user_id' } })

  box.schema.space.create('orders')
  box.space.orders:format({
    { name = 'order_id', type = 'string' },
    { name = 'user_id',  type = 'string' },
    { name = 'market',   type = 'string' },
    { name = 'side',     type = 'string' },
    { name = 'price',    type = 'number' },
    { name = 'amount',   type = 'number' },
    { name = 'leverage', type = 'number' },
    { name = 'status',   type = 'string' },
  })
  box.space.orders:create_index('primary', { parts = { 'order_id' } })
  box.space.orders:create_index('market', { parts = { 'market', 'side', 'status', 'price' }, unique = false })
  box.space.orders:create_index('user', { parts = { 'user_id', 'status' }, unique = false })

  box.schema.space.create('positions')
  box.space.positions:format({
    { name = 'user_id',     type = 'string' },
    { name = 'market',      type = 'string' },
    { name = 'amount',      type = 'number' },
    { name = 'entry_price', type = 'number' },
    { name = 'leverage',    type = 'number' }
  })
  box.space.positions:create_index('primary', { parts = { 'user_id', 'market' } })
end)

-- Order
Order = {
  order_id = '',
  user_id = '',
  market = '',
  side = '',
  price = 0,
  amount = 0,
  leverage = 1,
  status = 'pending'
}

function Order:new(o)
  if type(o) ~= "table" then
    -- Convert Tarantool tuple to Lua table
    o = {
      order_id = o[1],
      user_id = o[2],
      market = o[3],
      side = o[4],
      price = tonumber(o[5]),
      amount = tonumber(o[6]),
      leverage = tonumber(o[7]),
      status = o[8] or 'pending'
    }
  end
  setmetatable(o, self)
  self.__index = self
  return o
end
