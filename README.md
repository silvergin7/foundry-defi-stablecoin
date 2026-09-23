# Decentralized Stablecoin

DSC is an overcollateralized stablecoin pegged to the US dollar. It is backed by WETH and WBTC. Chainlink price feeds set the USD value of that collateral. You can mint DSC only when your collateral covers the debt, and you can be liquidated if your position falls too low.

## Contracts

- `DecentralizedStableCoin` is the DSC token.
- `DSCEngine` handles deposits, minting, burning, redemption, and liquidation.
- `OracleLib` rejects stale Chainlink prices.

## Run the tests

```bash
forge test
forge coverage
```
