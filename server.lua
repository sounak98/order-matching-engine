#!/usr/bin/env tarantool

local box = require('box')
local log = require('log')
local fiber = require('fiber')

box.cfg {
  listen = 3301,
  log = 'server.log'
}

require('init')
require('orderbook')
require('utils')

-- Main application logic
local function process_order(order)
  local orderbook = Orderbook:new { market = order.market }

  -- -- Load existing orders for the market
  -- local existing_orders = box.space.orders.index.market:select { order.market }
  -- for _, existing_order in ipairs(existing_orders) do
  --   log.info(string.format("existing_order: %s", existing_order))
  --   orderbook:add_order(Order:new(existing_order))
  -- end

  -- Add the new order
  if not orderbook:add_order(order) then
    log.error(string.format("Order rejected: Insufficient balance for user %s", order.user_id))
    return -- Order rejected due to insufficient balance
  end

  -- Match orders
  orderbook:match_orders()

  -- Calculate margin after execution
  local margin = CalculateMarginRatio(order.user_id)

  -- Check if margin is sufficient (10% in this example)
  if margin < 0.1 then
    -- Revert the transaction
    box.rollback()
    log.error(string.format("Order rejected: Insufficient margin for user %s", order.user_id))
  else
    -- Commit the transaction
    box.commit()
    log.info(string.format("Order processed successfully for user %s", order.user_id))
  end
end

-- Async order receiver
local function order_receiver()
  -- local ch = fiber.channel(100)

  -- fiber.create(function()
  --   while true do
  --     local order = ch:get()
  --     if order then
  --       box.atomic(function()
  --         process_order(order)
  --       end)
  --     end
  --   end
  -- end)

  -- return function(order)
  --   ch:put(order)
  -- end

  return function(order)
    process_order(order)
  end
end

-- Initialize the order receiver
local submit_order = order_receiver()

-- Reset the database (for testing purposes)
local function reset_database()
  box.space.users:truncate()
  box.space.orders:truncate()
  box.space.positions:truncate()
  log.info("Database reset completed")
end

-- Example usage
local function run_tests()
  reset_database()

  -- Initialize user balances
  box.space.users:insert { 'user1', 1000000 } -- 1 million initial balance
  box.space.users:insert { 'user2', 1000000 } -- 1 million initial balance

  log.info("Initial state:")
  PrintUserInfo('user1')
  PrintUserInfo('user2')

  -- Submit orders with leverage
  log.info("Submitting orders:")

  -- ETH Market
  -- Buy orders for user1
  for i = 1, 15 do
    local price = 1900 + i * 10 -- Prices from 1910 to 2050
    submit_order(Order:new { order_id = 'ETH_B' .. i, user_id = 'user1', market = 'ETH', side = 'buy', price = price, amount = 1, leverage = 2 })
  end

  -- Sell orders for user2
  for i = 1, 15 do
    local price = 2100 - i * 10 -- Prices from 2090 to 1950
    submit_order(Order:new { order_id = 'ETH_S' .. i, user_id = 'user2', market = 'ETH', side = 'sell', price = price, amount = 1, leverage = 2 })
  end

  -- BTC Market
  -- Buy orders for user1
  for i = 1, 15 do
    local price = 29000 + i * 100 -- Prices from 29100 to 30400
    submit_order(Order:new { order_id = 'BTC_B' .. i, user_id = 'user1', market = 'BTC', side = 'buy', price = price, amount = 0.1, leverage = 5 })
  end

  -- Sell orders for user2
  for i = 1, 15 do
    local price = 31000 - i * 100 -- Prices from 30900 to 29600
    submit_order(Order:new { order_id = 'BTC_S' .. i, user_id = 'user2', market = 'BTC', side = 'sell', price = price, amount = 0.1, leverage = 5 })
  end

  -- Wait for order processing
  fiber.sleep(1)

  log.info("State after initial order submission:")
  PrintUserInfo('user1')
  PrintUserInfo('user2')

  -- Execute some trades
  -- ETH Market
  submit_order(Order:new { order_id = 'ETH_EXEC1', user_id = 'user1', market = 'ETH', side = 'buy', price = 2100, amount = 5, leverage = 2 })
  submit_order(Order:new { order_id = 'ETH_EXEC2', user_id = 'user2', market = 'ETH', side = 'sell', price = 1900, amount = 3, leverage = 2 })

  -- BTC Market
  submit_order(Order:new { order_id = 'BTC_EXEC1', user_id = 'user1', market = 'BTC', side = 'buy', price = 31000, amount = 0.5, leverage = 5 })
  submit_order(Order:new { order_id = 'BTC_EXEC2', user_id = 'user2', market = 'BTC', side = 'sell', price = 29000, amount = 0.3, leverage = 5 })

  -- Wait for order processing
  fiber.sleep(1)

  log.info("Final state:")
  PrintUserInfo('user1')
  PrintUserInfo('user2')

  -- Print orderbook status
  log.info("ETH Orderbook:")
  PrintOrderbook('ETH')
  log.info("BTC Orderbook:")
  PrintOrderbook('BTC')
end

-- Run the tests
run_tests()
