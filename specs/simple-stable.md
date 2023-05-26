# Simple Stable

The following spec defines the workings of a minimised collateralized debt position based stablecoin.

## Acceptance Criteria

As a user who
1. has ethereum
2. believes ETH will rise in price over some duration of time
3. is willing to hold onto it for that duration
I want USD spending power, so that I can draw some kind of liquid value from ETH while still owning it long term.

As an arbitrager, I would like to run a scheduled script that makes me money.

## Contracts

### Position

Manages the debt position of an account.

#### Properties

- minimum collatorization ratio
- total debt

#### Actions

- deposit ETH
- withdraw ETH
- withdraw coin
- deposit coin
- liquidate
 
### Notary

Responsible for initializing and authenticating vaults.

#### Actions

- open position


### Coin

Responsible for burning and minting coin. Implements ERC20.

#### Actions

- Mint coin controlled by vault logic.
- All other actions are standard ERC20.

### Price Feed

Responsible for providing price data to calculate collatoraliation ratio

#### Actions

- Call a price provider service contract to update price data.
- Get price data.

## TBD

Strategy for locking down price oracle so that LINK balance is not spent through excess requests.







