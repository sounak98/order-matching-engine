local box = require('box')
local log = require('log')

require('utils')

Orderbook = {
  market = ''
}

function Orderbook:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function Orderbook:add_order(order)
  -- Check if user has sufficient balance
  if not self:check_sufficient_balance(order) then
    log.error(string.format("Order rejected: Insufficient balance for user %s", order.user_id))
    return false
  end

  -- Check if the order already exists
  local existing_order = box.space.orders:get(order.order_id)
  if not existing_order then
    -- Persist the order only if it doesn't exist
    box.space.orders:insert({
      order.order_id,
      order.user_id,
      order.market,
      order.side,
      order.price,
      order.amount,
      order.leverage,
      'pending'
    })
    log.info(string.format("Order persisted: %s %s %f @ %f", order.user_id, order.side, order.amount, order.price))
  else
    log.info(string.format("Order already exists: %s", order.order_id))
  end
  return true
end

function Orderbook:check_sufficient_balance(order)
  local user = box.space.users:get { order.user_id }
  if not user then
    return false
  end

  local balance = user.balance
  local required_margin = 0
  local existing_position = box.space.positions:get { order.user_id, order.market }

  -- Check if the order reduces an existing position
  if existing_position then
    local position_size = existing_position.amount
    local position_side = position_size > 0 and 'long' or 'short'
    local order_side = order.side == 'buy' and 'long' or 'short'

    if position_side ~= order_side then
      -- Order reduces or closes the position
      local reduction_amount = math.min(math.abs(position_size), order.amount)
      order.amount = order.amount - reduction_amount
      if order.amount <= 0 then
        return true -- No additional margin required
      end
    end
  end

  -- Calculate required margin for the remaining order amount
  required_margin = order.price * order.amount / order.leverage

  -- Check existing positions and open orders
  local positions = box.space.positions:select { order.user_id }
  local open_orders = box.space.orders.index.user:select { order.user_id, 'pending' }

  for _, position in ipairs(positions) do
    if position.market ~= order.market then
      local market_price = GetMarketPrice(position.market)
      local position_value = math.abs(position.amount * market_price)
      required_margin = required_margin + position_value / position.leverage
    end
  end

  for _, open_order in ipairs(open_orders) do
    if open_order.market ~= order.market or open_order.side == order.side then
      required_margin = required_margin + open_order.price * open_order.amount / open_order.leverage
    end
  end

  return balance >= required_margin
end

function Orderbook:get_top_orders()
  local top_buy = box.space.orders.index.market:select(
    { self.market, 'buy', 'pending' }, { limit = 1, iterator = 'EQ' }
  )[1]
  local top_sell = box.space.orders.index.market:select(
    { self.market, 'sell', 'pending' }, { limit = 1, iterator = 'EQ' }
  )[1]
  return top_buy, top_sell
end

function Orderbook:update_order(order, new_amount)
  if new_amount == 0 then
    box.space.orders:update(order.order_id, { { '=', 6, new_amount }, { '=', 8, 'filled' } })
  else
    box.space.orders:update(order.order_id, { { '=', 6, new_amount } })
  end
end

function Orderbook:match_orders()
  while true do
    local top_buy, top_sell = self:get_top_orders()

    if not top_buy or not top_sell or top_buy.price < top_sell.price then
      break
    end

    local match_price = (top_buy.price + top_sell.price) / 2
    local match_amount = math.min(top_buy.amount, top_sell.amount)

    -- Execute the trade
    self:execute_trade(top_buy, top_sell, match_price, match_amount)

    -- Update orders
    self:update_order(top_buy, top_buy.amount - match_amount)
    self:update_order(top_sell, top_sell.amount - match_amount)
  end
end

function Orderbook:execute_trade(buy_order, sell_order, price, amount)
  -- Update buyer's position
  self:update_position(buy_order.user_id, amount, price, buy_order.leverage)

  -- Update seller's position
  self:update_position(sell_order.user_id, -amount, price, sell_order.leverage)

  -- Update buy order
  local buy_remaining = buy_order.amount - amount
  local buy_status = buy_remaining == 0 and 'filled' or 'pending'
  box.space.orders:update(buy_order.order_id, {
    { '=', 6, buy_remaining },
    { '=', 8, buy_status }
  })

  -- Update sell order
  local sell_remaining = sell_order.amount - amount
  local sell_status = sell_remaining == 0 and 'filled' or 'pending'
  box.space.orders:update(sell_order.order_id, {
    { '=', 6, sell_remaining },
    { '=', 8, sell_status }
  })

  log.info(string.format("Trade executed: %s buys %f from %s at %f",
    buy_order.user_id, amount, sell_order.user_id, price))
end

function Orderbook:update_position(user_id, amount, price, leverage)
  local position = box.space.positions:get { user_id, self.market }
  if position then
    local new_amount = position.amount + amount
    if math.abs(new_amount) < 1e-8 then -- Close position if amount is very close to zero
      box.space.positions:delete({ user_id, self.market })
      log.info(string.format("Position closed: user=%s, market=%s", user_id, self.market))
    else
      local new_entry_price = (position.entry_price * position.amount + price * amount) / new_amount
      local new_leverage = (position.leverage * position.amount + leverage * amount) / new_amount

      box.space.positions:update({ user_id, self.market }, {
        { '=', 3, new_amount },
        { '=', 4, new_entry_price },
        { '=', 5, new_leverage }
      })

      log.info(string.format(
        "Position updated: user=%s, market=%s, new_amount=%f, new_entry_price=%f, new_leverage=%f",
        user_id, self.market, new_amount, new_entry_price, new_leverage))
    end
  else
    box.space.positions:insert { user_id, self.market, amount, price, leverage }

    log.info(string.format("New position created: user=%s, market=%s, amount=%f, entry_price=%f, leverage=%f",
      user_id, self.market, amount, price, leverage))
  end
end
