local box = require('box')
local log = require('log')

-- Function to calculate market price (average of best bid and ask)
function GetMarketPrice(market)
  local highest_bid = box.space.orders.index.market:select(
    { market, 'buy', 'pending' },
    { limit = 1, iterator = 'REQ' }
  )[1]

  local lowest_ask = box.space.orders.index.market:select(
    { market, 'sell', 'pending' },
    { limit = 1, iterator = 'EQ' }
  )[1]

  if highest_bid and lowest_ask then
    return (highest_bid.price + lowest_ask.price) / 2
  elseif highest_bid then
    return highest_bid.price
  elseif lowest_ask then
    return lowest_ask.price
  else
    log.warn("No open orders found for market: " .. market)
    return 0 -- Or some default value
  end
end

-- Function to calculate margin ratio
function CalculateMarginRatio(user_id)
  local user = box.space.users:get { user_id }
  local balance = user.balance
  local positions = box.space.positions:select { user_id }
  local total_exposure = 0
  local total_pnl = 0

  for _, position in ipairs(positions) do
    local market_price = GetMarketPrice(position.market)
    local pnl = (market_price - position.entry_price) * position.amount
    local exposure = math.abs(position.amount * market_price * position.leverage)
    total_pnl = total_pnl + pnl
    total_exposure = total_exposure + exposure
  end

  local equity = balance + total_pnl
  return equity / total_exposure
end

-- Function to print user information
function PrintUserInfo(user_id)
  local user = box.space.users:get { user_id }
  if not user then
    log.error("User not found: " .. user_id)
    return
  end

  local balance = user.balance
  log.info("User: " .. user_id)
  log.info("Balance: " .. balance)

  -- Get open positions
  local positions = box.space.positions:select { user_id }
  log.info("Open Positions:")
  local total_exposure = 0
  local total_pnl = 0

  for _, position in ipairs(positions) do
    local market = position.market
    local amount = position.amount
    local entry_price = position.entry_price
    local leverage = position.leverage
    local market_price = GetMarketPrice(market)
    local pnl = (market_price - entry_price) * amount
    local exposure = math.abs(amount * market_price * leverage)

    log.info(string.format("  Market: %s, Amount: %f, Entry Price: %f, Current Price: %f, PnL: %f, Exposure: %f",
      market, amount, entry_price, market_price, pnl, exposure))

    total_pnl = total_pnl + pnl
    total_exposure = total_exposure + exposure
  end

  log.info("Total PnL: " .. total_pnl)
  log.info("Total Exposure: " .. total_exposure)

  -- Calculate and print margin ratio
  local equity = balance + total_pnl
  local margin_ratio = total_exposure > 0 and (equity / total_exposure) or 0
  log.info("Margin Ratio: " .. margin_ratio)

  -- Get open orders
  local all_orders = box.space.orders.index.user:select { user_id }
  log.info("All orders:")

  local open_orders = box.space.orders.index.user:select { user_id }
  log.info("Open Orders:")
  for _, order in ipairs(open_orders) do
    if order.status == 'pending' then
      log.info(string.format("  Order ID: %s, Market: %s, Side: %s, Price: %f, Amount: %f, Status: %s",
        order.order_id, order.market, order.side, order.price, order.amount, order.status))
    end
  end
end

-- Function to print orderbook
function PrintOrderbook(market)
  local bids = box.space.orders.index.market:select({ market, 'buy', 'pending' }, { iterator = 'REQ' })
  local asks = box.space.orders.index.market:select({ market, 'sell', 'pending' }, { iterator = 'EQ' })

  log.info("Bids:")
  local bid_count = #bids
  for i = math.max(1, bid_count - 9), bid_count do
    local bid = bids[i]
    log.info(string.format("  Price: %s, Amount: %s", bid.price, bid.amount))
  end

  log.info("Asks:")
  for i, ask in ipairs(asks) do
    if i > 10 then break end
    log.info(string.format("  Price: %s, Amount: %s", ask.price, ask.amount))
  end
end
