# StablecoinRaffle - A decentralized raffle that awards a stablecoin

![License](https://img.shields.io/badge/license-MIT-darkred.svg) ![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.19-blue.svg) ![Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange.svg)

StablecoinRaffle is decentralized raffle that mints a stablecoin to winners and enables redeeming of it for Ethereum.

## Features
- 🔗 **Chainlink Price Feeds**: For accurate tamper-proof price data to calculate raffle minting and redeeming
- 🔗 **Chainlink Verifiable Random Number**: For generating a verifiably random number to choose the winner of the contract
- 🔗 **Chainlink Automation Compatability**: For making the raffle completely decentralized and automatically run/executed

## Stablecoin & Protocol Information
- 🪙 **Protocol**: An overcollaterlized debt position. 1 stablecoin = 1 dollar. Protocol should have minimum double the amount of collateral as there is stablecoin. Minting and burning is handled purely by the raffle game contract.
- 🪙 **Stablecoin (Stalux)**: The stablecoin (named Stalux - Stability + Luxury) is backed by the collateral in the raffle game contract (the ETH being sent by players to enter the raffle)
- 🪙 **Stablecoin Minting**: When a winner is chosen by Chainlink VRF, the USD value of the Ethereum in the game round is calculated with Chainlink Price Feeds and half of it is minted as the stablecoin to the winner. This way, the coin is always overcollateralized and the backing Ethereum collateral is kept in the raffle.
- 🪙 **Stablecoin Redeeming**: If a holder of the stablecoin wants to redeem it for Ethereum in the raffle contract, they will receive 1/8th of the value in ETH. This is designed to encourage holders to treat and use it like currency, rather than redeem, where 1 stablecoin = 1 dollar and should they choose to redeem it for ETH. The protocol will not allow a user to redeem their stablecoin if redeeming will reduce collateral value below 200% of the total supply of stablecoin. We want to maintain, roughly, a double overcollaterlized position so there should always be at least double the collateral as compared to stablecoin.
  
###### Possible Future Additions
<small>- Making the stablecoin cross chain by using Chainlink Cross Chain Token standard.</small>
<small>- Using native ETH, inside the contract, as payments for Chainlink services, making it fully self running.</small>
<small>- Adding a front end and making it into a decentralized application (dApp).</small>


## Project Structure
```
[script]
    ├── DeployStablecoinRaffle.s.sol    # Deployer script
    ├── HelperConfig.s.sol              # Helper file 
    └── VrfSubscriptionInteractions.sol # Script for Mock VRF
[src]
    ├── StablecoinRaffle.sol            # Raffle game contract
    └── StaluxCoin.sol                  # The stablecoin
[test]
    ├── [Invariant]                     # Files for Invariant Test
        ├── Handler.t.sol
        └── InvariantsTest.t.sol
    ├── StablecoinRaffleTest.t.sol      # Unit and fuzz tests
    └── [mocks]                         # Mocks for testing
        ├── DummyPlayer.sol
        └── LinkToken.sol
```

## Getting Started
### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Git](https://git-scm.com/)

### Installation and Testing
1. **Clone the repo**
   ```
   git clone https://github.com/ygorz/StablecoinRaffle.git
   cd StablecoinRaffle
   ```

2. **Install dependencies**
   ```
   make install
   ```

3. **Build project**
   ```
   make build
   ```

4. **Run tests**
   ```
   make test
   ```

**Built to practice the lessons taught by [Cyfrin Updraft](https://updraft.cyfrin.io/) ❤️**