# Order Matching Engine

This project implements a order matching engine for a futures exchange using Lua and Tarantool.

## Setup and Usage

To run the tests and start the server:

```
$ tarantool server.lua
```

## Structure

- `init.lua`: Initializes the Tarantool spaces and indexes.
- `orderbook.lua`: Implements the order matching engine and position management.
- `utils.lua`: Contains utility functions for market price calculation and margin ratio calculation.
- `server.lua`: Main server script that ties everything together and runs the tests.

## Key Design Decisions

### 1. Order Matching Engine

- **Continuous Matching**: We implement a continuous matching system where orders are matched as soon as they are placed, rather than using periodic batch auctions.
- **Efficient Order Retrieval**: We use Tarantool's secondary indexes to quickly retrieve the best bid and ask orders for each market.

### 2. Position Management

- **Continuous Position Updating**: Positions are updated in real-time as trades are executed, providing up-to-date information on user exposures.
- **Leverage Handling**: The system supports leveraged trading, with position sizes and margin requirements adjusted accordingly.

### 3. Balance and Margin Checks

- **Pre-Trade Checks**: Before an order is added to the orderbook, we perform checks to ensure the user has sufficient balance and margin.
- **Cross-Market Margin**: The margin check considers the user's positions and open orders across all markets, not just the current market.
- **Post-Execution Margin Check**: The engine executes orders only if the account margin remains above 10% after the order is executed. If the margin falls below this threshold, the transaction is reverted.
- **Transaction Safety**: Atomicity is ensured by using Tarantool's transaction mechanism, which guarantees that either all changes are applied or none are, maintaining data consistency.

### 4. Market Price Calculation

- **Efficient Querying**: We use Tarantool's indexes to quickly retrieve the best bid and ask prices for market price calculation.
- **Fallback Logic**: If there are no orders on one side of the book, we use the available side. If the book is empty, we return a default value.

## Scope for Future Development

1. **ID Sequencing**: Implement a sequencing mechanism for generating unique, monotonically increasing IDs for users, orders and positions.
2. **Trade History**: Create a new 'trade' space to store executed trades for analytics.
3. **Liquidation**: Implement a liquidation mechanism to close out positions that fall below the maintenance margin.
4. **Fee Structure**: Implement funding fees for perpetual futures and trading fees to monetize the exchange and incentivize market stability.
5. **Scalability**: As the system grows, consider sharding strategies for handling increased load across multiple Tarantool instances.
6. **API Layer**: Develop a WebSocket API for client interactions.
