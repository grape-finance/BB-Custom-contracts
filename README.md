# BetterBank Custom Contracts & Tests (Mocha, Ethers, Hardhat 3)

[BetterBank Website](https://betterbank.io)

[BetterBank Docs](https://betterbanks-organization.gitbook.io/better-bank)

[BetterBank WhitePaper](https://betterbank.io/whitepaper)

## Contract Descriptions

### Esteem.sol
The Esteem token serves as the primary utility and reward mechanism within the ecosystem. The token inherits from ERC20Burnable and Ownable, providing both burning capabilities for redemptions and administrative control over the minting process. The contract maintains a mapping of authorized minters and enforces access control through the onlyMinter modifier, allowing the owner to add or remove minting permissions as needed. There is no official LP pool for Esteem tokens or an intended max supply, they are intended to be minted/burned in the PulseMinter.sol contract for fixed values. Esteem token is to be staked in the Groves (Staking.sol) which earns newly minted Favor tokens each epoch.


### Favor.sol
The Favor tokens represent the base trading assets paired with different underlying tokens (PLS, PLSX, DAI). These tokens implement a taxation and bonus system designed to incentivize holding while generating protocol revenue. The contract features a maximum 50% sell tax, with transfers to non tax exempt contracts automatically treated as sells. Additionally, the system provides a 44% buy bonus in Esteem tokens to encourage purchasing when the TWAP of the Favor token is below 3.00, along with a 25% treasury bonus that's minted to the protocol treasury on top of the 44% user bonus. The taxation logic is implemented through an overridden _update function that detects contract transfers and applies the appropriate tax, sending the collected amount directly to the treasury address. The intention is to have our Zapper.sol contract be taxExempt and therefore control user buys/sells/liquidity adds where we add additional logic. All other non official contract transfers are treated as an automatic sell and taxed as such.


### PulseMinter.sol
The PulseMinter contract handles the minting of Esteem tokens and their redemption back into Favor tokens. Users can mint Esteem using either native PLS or approved ERC20 tokens like PLSX and DAI, with the system starting at a base price of $21 per Esteem token. The contract implements a dynamic pricing mechanism that increases the Esteem mint rate by $0.25 daily. 

The redemption system allows users to convert their Esteem back into Favor tokens at a 70% rate, with calculations based on current oracle prices. No tokens are stored in this contract, all interactions either mint or burn Esteem or Favor and send relevant tokens to the treasury and user addresses.

Proceeds from Esteem minting are directed to the treasury, 80% of these funds are automatically deposited into BetterBank lending pools (Aave V3 codebase) on behalf of the holding treasury wallet, while the remaining 20% is allocated to the team treasury wallet in the base token that was used to mint Esteem. This contract also includes price oracle integration, with each supported token having its own dedicated oracle for accurate USD valuations either being from the Fetch Oracle network on Pulsechain if a feed exists or from our own uni v2 TWAP oracles deployed on specific pairs with sufficient liquidity.


### FavorTreasury.sol
The FavorTreasury contract implements an automated seigniorage system that manages token supply expansion based on TWAP price. The system operates on 1-hour epochs, with supply expansion ranging from 0.001% to 3% depending on the current token price. The intention is for supply to expand at roughly the % per day based on its current TWAP of the paired token, ie. If FavorPLS is 2x PLS price at the current epoch it will mint 2% new FavorPLS supply / 24 for that current epoch, and the following epoch it will perform the same calculation using the next hourly TWAP value. The treasury handles the minting and the calculations of minting and then sends this newly minted Favor to the respective Grove (Staking.sol) contract for distribution to stakers.


### Staking.sol
The Staking contract, also known as the Grove, provides a staking system where users stake Esteem tokens to earn newly minted Favor rewards. The system implements a snapshot-based reward distribution mechanism that ensures fair and accurate reward calculations based on the amount staked and the users share of total stake. Users can stake/unstake their Esteem tokens at any time without penalty, and the system automatically tracks their position and calculates earned rewards. Users are free to stake and unstake on the epochs if they desire however there is no benefit to doing so for them as there is no other utility for Esteem in the protocol other than Grove staking. The gamification here allows users to move freely between each Grove as they see fit based on the demand and yield in each Grove.

The reward distribution system uses a snapshot mechanism that maintains a history of reward distributions, with a maximum of 50,000 historical snapshots to manage gas costs. When rewards are allocated to the Grove, they are distributed proportionally among all stakers based on their stake size. Users can claim their rewards at any time without withdrawing their staked tokens, and the system automatically handles reward calculations when users exit their positions.


### Zapper.sol
The Zapper contract provides gated trading and liquidity management functionality, integrating with both PulseX router functions (Uniswap V2 fork) and BetterBank lending pools (Aave V3 codebase). The Zapper contract is listed as TaxExempt on the Favor token contract and also as an approved BuyWrapper. This allows users to interact with it without automatically being taxed such as for Buys/Liquidity adds. 

The contract implements flash loan functionality using BetterBank lending pools, allowing users to create liquidity positions without requiring the full capital upfront. In this flash loan functionality users supply some amount of Favor tokens, this is then paired with a flash loaned amount of base token to create LP which is then deposited into the lending pool as collateral and used to borrow the initial flash loaned token amount to repay. 

The zapper system includes both buy and sell functionality, with automatic Esteem bonus logging for purchases and tax collection in paired base token for sales. When users buy Favor tokens through this approved buy wrapper, the system automatically logs the purchase and calculates Esteem bonuses. For sales, the system collects the appropriate tax in base tokens and distributes it according to the 80/20 split between holding and team wallets with 80% being automatically deposited for the holding treasury wallet into the lending pool the same as in the PulseMinter contract. The contract also provides zap buy in functionality, allowing users to convert single base tokens into liquidity pool positions automatically. 


### Oracles
The oracle system integrates multiple price feed sources to ensure accurate and reliable token valuations. The **MinterOracle.sol** contract serves as the primary price provider as a view contract, integrating with the Fetch Protocol to obtain external price feeds for base tokens like PLS and PLSX as well as our TWAP oracles **UniTWAPOracle.sol** and **LPTWAPOracle.sol** to provide feeds for other tokens including Favor and LP tokens without a Fetch feed. 

**UniTWAPOracle.sol** is used for Favor token price validation, providing time-weighted average prices that help prevent manipulation and ensure price stability for individual tokens inside liquidity pairs. For liquidity pool tokens, specialized LP oracles **LPTWAPOracle.sol** calculate USD-denominated values using geometric mean pricing formulas with reserves also averaged to accurately calculate LP token prices in USD. All oracles implement price cap mechanisms and data freshness requirements.

**Epoch.sol** is used as a helper within our TWAP oracle contracts to provide a standardized method of enforcing the time period upon which the TWAP values are calculated inside these oracle contracts.



## Project Overview

This project showcases a Hardhat 3 Beta project using `mocha` for tests and the `ethers` library for Ethereum interactions.

To learn more about the Hardhat 3 Beta, please visit the [Getting Started guide](https://hardhat.org/docs/getting-started#getting-started-with-hardhat-3). To share your feedback, join our [Hardhat 3 Beta](https://hardhat.org/hardhat3-beta-telegram-group) Telegram group or [open an issue](https://github.com/NomicFoundation/hardhat/issues/new) in our GitHub issue tracker.

This example project includes:

- A simple Hardhat configuration file.
- Foundry-compatible Solidity unit tests.
- TypeScript integration tests using `mocha` and ethers.js
- Examples demonstrating how to connect to different types of networks, including locally simulating OP mainnet.

## Usage

### Running Tests

To run all the tests in the project, execute the following command:

```shell
npx hardhat test
```

You can also selectively run the Solidity or `mocha` tests:

```shell
npx hardhat test solidity
npx hardhat test mocha
```

### Make a deployment to Sepolia

This project includes an example Ignition module to deploy the contract. You can deploy this module to a locally simulated chain or to Sepolia.

To run the deployment to a local chain:

```shell
npx hardhat ignition deploy ignition/modules/Counter.ts
```

To run the deployment to Sepolia, you need an account with funds to send the transaction. The provided Hardhat configuration includes a Configuration Variable called `SEPOLIA_PRIVATE_KEY`, which you can use to set the private key of the account you want to use.

You can set the `SEPOLIA_PRIVATE_KEY` variable using the `hardhat-keystore` plugin or by setting it as an environment variable.

To set the `SEPOLIA_PRIVATE_KEY` config variable using `hardhat-keystore`:

```shell
npx hardhat keystore set SEPOLIA_PRIVATE_KEY
```

After setting the variable, you can run the deployment with the Sepolia network:

```shell
npx hardhat ignition deploy --network sepolia ignition/modules/Counter.ts
```
