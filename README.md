# StablecoinRaffle

// What do we need?  
// Game contract  
// Vault to send money to - game vault?  
// ERC20 token contract  
// CCIP stuff  

A Solidity project by George Gorzhiyev to practice the following:

1 - Users enter a raffle by paying in ETH  
    a - Chainlink pricefeeds will check value - 2 dollars to enter  
    b - Chainlink VRF will choose a winner  
    c - Chainlink Keepers will run the game by calling the function to pick a winner  

2 - Winner of raffle will be minted RaffleCoin, a faux "stablecoin" where the value is collateralized by all of the entries into the raffle, going into a "vault"  
    a - Each raffle game will last a week and the winner will get half of the games entries in the minted rafflecoin  
    b - Assumption is 1 rafflecoin - 1 dollar  
    c - There will naturally be a build up of collateral in the vault as a reserve  
    d - User can use the rafflecoin as money or go to vault and redeem it for eth but will only get 1/8th the value  
        i - This is done to keep the user wanting to use the coin and not go to vault to redeem 
        it as there is now less value doing it that way from the vault  
        ii - For example, in a round of a game:  
            - $1000 dollars worth of tickets are purchased  
            - Winner is chose and given half of that (in minted rafflecoin) so they get 500 RFC (rafflecoin) (1 dollar = 1 RFC)  
            - The purchased amount of ETH tickets goes into vault  
            - User can treat the RFC like currency or redeem for ETH in vault  
            - Redeeming from vault will give 1/8th the value in order to not drain vault  
            - So user will get 1/8th of 500 in ETH = 62.5  
            - If they redeem the ETH, the vault will still be overcollateralized and have 1000 - 62.5 = 937.5  
  
3 - Minted Rafflecoin can be sent cross chain and will incorporate CCIP Cross Chain Token