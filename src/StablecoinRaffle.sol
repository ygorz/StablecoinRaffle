// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/*
   _____  _          _      _                    _          _____          __   __  _       
  / ____|| |        | |    | |                  (_)        |  __ \        / _| / _|| |      
 | (___  | |_  __ _ | |__  | |  ___   ___  ___   _  _ __   | |__) | __ _ | |_ | |_ | |  ___ 
  \___ \ | __|/ _` || '_ \ | | / _ \ / __|/ _ \ | || '_ \  |  _  / / _` ||  _||  _|| | / _ \
  ____) || |_| (_| || |_) || ||  __/| (__| (_) || || | | | | | \ \| (_| || |  | |  | ||  __/
 |_____/  \__|\__,_||_.__/ |_| \___| \___|\___/ |_||_| |_| |_|  \_\\__,_||_|  |_|  |_| \___|
                                                                                            
                   ______________
    __,.,---'''''              '''''---..._
 ,-'             .....:::''::.:            '`-.
'           ...:::.....       '
            ''':::'''''       .               ,
|'-.._           ''''':::..::':          __,,-
 '-.._''`---.....______________.....---''__,,-
      ''`---.....______________.....---''
*/

/**
 * @title StablecoinRaffle
 * @author George Gorzhiyev
 * @notice A stablecoin raffle game where players can enter by sending a certain amount of ETH.
 * The winner is randomly selected from the players whoe ntered the raffle and the winner receives half of the balance of the current game minted as a stablecoin.
 * @dev This implements Chainlink VRF and Automation
 */
contract StablecoinRaffle {
    /*-------------------- ERRORS --------------------*/
    error StablecoinRaffle__SendMoreEthToEnterRaffle();
    error StablecoinRaffle__RaffleNotOpen();
    error StablecoinRaffle__TransferToRaffleGameFailed();

    /*-------------------- STATE VARIABLES -----------*/
    address[] private s_enteredPlayers;
    uint256 private s_gameBalance;
    uint256 private immutable i_ticketPrice;
    uint256 private immutable i_gameDuration;

    enum RaffleState {
        OPEN,
        CALCULATING_WINNER
    }

    /*-------------------- EVENTS --------------------*/

    /*-------------------- MODIFIERS -----------------*/

    /*\/\/\/\/\/\/\/\/\/\/ FUNCTIONS \/\/\/\/\/\/\/\/\*/

    /*-------------------- CONSTRUCTOR ---------------*/
    constructor(uint256 _ticketPrice, uint256 _gameDuration) {
        i_ticketPrice = _ticketPrice; // Set the ticket price
        i_gameDuration = _gameDuration; // Set the game duration
    }

    /*-------------------- EXTERNAL FUNCTIONS --------*/
    function enterRaffle() external payable {
        // Check if the player has sent the correct amount of ETH
        if (msg.value < i_ticketPrice) {
            revert StablecoinRaffle__SendMoreEthToEnterRaffle();
        }

        // Check if the raffle is open
        if (RaffleState != RaffleState.OPEN) {
            revert StablecoinRaffle__RaffleNotOpen();
        }

        // Add player to the players list
        s_enteredPlayers.push(msg.sender);

        // Update the game balance
        s_gameBalance += msg.value;

        // Transfer the ticket price to the contract
        (bool success,) = address(this).call{value: msg.value}("");
        if (!success) {
            revert StablecoinRaffle__TransferToRaffleGameFailed();
        }
    }

    function pickWinner() external {
        // Check if there are any players
        require(s_enteredPlayers.length > 0, "No players entered the raffle");

        // Generate a random index
        uint256 randomIndex =
            uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))) % s_enteredPlayers.length;

        // Get the winner's address
        address winner = s_enteredPlayers[randomIndex];

        // Calculate the amount to send to the winner
        uint256 amountToSend = s_gameBalance / 2;

        // Transfer the total balance to the winner
        (bool success,) = winner.call{value: amountToSend}("");

        // Reset the players list for the next raffle
        delete s_enteredPlayers;
        // Reset the game balance
        s_gameBalance = 0;
    }

    /*-------------------- GETTER FUNCTIONS ----------*/
    function getTicketPrice() external view returns (uint256) {
        return i_ticketPrice;
    }

    function getGameDuration() external view returns (uint256) {
        return i_gameDuration;
    }
}
