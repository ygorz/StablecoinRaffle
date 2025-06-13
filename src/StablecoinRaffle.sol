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

pragma solidity ^0.8.19;

// Stablecoin for raffle winner
import {StaluxCoin} from "src/StaluxCoin.sol";
// OpenZeppelin imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// Chainlink imports
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

/*
   _____ _        _     _                _       _____        __  __ _      
  / ____| |      | |   | |              (_)     |  __ \      / _|/ _| |     
 | (___ | |_ __ _| |__ | | ___  ___ ___  _ _ __ | |__) |__ _| |_| |_| | ___ 
  \___ \| __/ _` | '_ \| |/ _ \/ __/ _ \| | '_ \|  _  // _` |  _|  _| |/ _ \
  ____) | || (_| | |_) | |  __/ (_| (_) | | | | | | \ \ (_| | | | | | |  __/
 |_____/ \__\__,_|_.__/|_|\___|\___\___/|_|_| |_|_|  \_\__,_|_| |_| |_|\___|
                                               
*/

/**
 * @title StablecoinRaffle
 * @author George Gorzhiyev
 * @notice A raffle game where winners will be minted a stablecoin, backed by
 * ETH in the contract. Influenced by and remixed from Cyfrin Updraft courses.
 *
 * The winner is randomly selected from the players who entered the raffle and
 * receives half of the balance (in USD) of the current game minted as a stablecoin.
 * The stablecoin is the equivalent of 1 coin = 1 USD. StaluxCoin is the name.
 * The winner can redeem the stablecoin for ETH at a later time but for only 1/8th
 * the value, as we want to encourage them to keep the stablecoin and use it.
 * The game is open for a certain duration and players can enter multiple times.
 * @dev This implements Chainlink pricefeeds, VRF and Automation.
 * @dev CHAINLINK PRICEFEEDS - Will check the Usd value of the ETH sent to enter the
 * raffle and make sure it meets the minimum entrance fee.
 * @dev CHAINLINK VRF - Will be used to get a random number to pick the winner.
 * @dev CHAINLINK AUTOMATION - Will be used to automation the game by checking certain
 * parameters and then when met, pick a winner and mint them the stablecoin.
 */
contract StablecoinRaffle is VRFConsumerBaseV2Plus, AutomationCompatibleInterface, ReentrancyGuard {
    /*--------------- ERRORS -----------------------------------------------------*/
    error StablecoinRaffle__NeedsMoreThanZero();
    error StablecoinRaffle__SendMoreEthToEnterRaffle();
    error StablecoinRaffle__RaffleNotOpen();
    error StablecoinRaffle__UpkeepNotNeeded();
    error StablecoinRaffle__NotEnoughStablecoinToRedeem();
    error StablecoinRaffle__TransferFailed();
    error StablecoinRaffle__NotEnoughEthInVaultToRedeem();
    error StablecoinRaffle__RedeemingBreaksProtocolHealth();

    /*--------------- TYPE DECLARATIONS ------------------------------------------*/
    enum RaffleGameState {
        OPEN, // 0
        CALCULATING // 1

    }

    /*--------------- STATE VARIABLES --------------------------------------------*/
    StaluxCoin private immutable i_stablecoin;
    AggregatorV3Interface private immutable i_priceFeed;

    // Raffle game variables
    uint256 private immutable i_entranceUsdFee;
    uint256 private immutable i_gameDuration;

    RaffleGameState private s_gameState;
    address[] private s_enteredPlayers;
    uint256 private s_gameRoundBalance;
    uint256 private s_lastTimeStamp;
    address private s_mostRecentWinner;

    uint256 private constant HALF = 2;
    uint256 private constant EIGHTH = 8;
    uint256 private constant MINIMUM_PROTOCOL_HEALTH = 2;

    // Chainlink price feed precision variables
    uint256 private constant USD_TO_ETH_PRECISION = 1e10;
    uint256 private constant ETH_PRECISION = 1e18;

    // Chainlink VRF variables
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    /*--------------- EVENTS -----------------------------------------------------*/
    event RaffleEntered(address indexed player);
    event RaffleWinnerPicked(address indexed winner);
    event StablecoinRedeemed(
        address indexed redeemer, uint256 indexed amountOfStablecoin, uint256 indexed adjustedAmountInEth
    );
    event RequestedRaffleWinner(uint256 indexed requestId);

    /*--------------- MODIFIERS --------------------------------------------------*/
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert StablecoinRaffle__NeedsMoreThanZero();
        }
        _;
    }

    /*\/-\/-\/-\/-\/-\/-\/-\/-- FUNCTIONS --\/-\/-\/-\/-\/-\/-\/*/
    /*--------------- CONSTRUCTOR ------------------------------------------------*/
    constructor(
        address stablecoin,
        uint256 entranceFee,
        uint256 gameDuration,
        address priceFeed,
        address vrfCoordinator,
        bytes32 keyHash,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_stablecoin = StaluxCoin(stablecoin); // Set the stablecoin contract address
        i_entranceUsdFee = entranceFee; // Set the ticket price in USD, must be in e18 format
        i_gameDuration = gameDuration; // Set the game duration
        i_priceFeed = AggregatorV3Interface(priceFeed); // Set the price feed address
        i_keyHash = keyHash; // Set the key hash for VRF
        i_subscriptionId = subscriptionId; // Set the subscription ID for VRF
        i_callbackGasLimit = callbackGasLimit; // Set the gas limit for the callback function

        s_lastTimeStamp = block.timestamp; // Set the start time of the game
        s_gameState = RaffleGameState.OPEN; // Set the initial game state to OPEN
    }

    /*--------------- RECEIVE/FALLBACK FUNCTIONS ---------------------------------*/
    receive() external payable {
        enterRaffle();
    }

    fallback() external payable {
        enterRaffle();
    }

    /*--------------- PUBLIC FUNCTIONS -------------------------------------------*/
    /**
     * @notice Allows players to enter the raffle by sending ETH.
     * The amount must be greater than 0 and must meet the entrance fee in USD.
     * @dev Chainlink price feed is used to check the USD value of the ETH sent.
     */
    function enterRaffle() public payable moreThanZero(msg.value) {
        // Check if the player has sent the correct amount of ETH in Usd value
        if (usdValueOfEth(msg.value) < i_entranceUsdFee) {
            revert StablecoinRaffle__SendMoreEthToEnterRaffle();
        }

        // Check if the game is open
        if (s_gameState != RaffleGameState.OPEN) {
            revert StablecoinRaffle__RaffleNotOpen();
        }

        // Add player to the players list and emit event
        s_enteredPlayers.push(msg.sender);
        emit RaffleEntered(msg.sender);

        // Update the game balance in the round
        s_gameRoundBalance += msg.value;
    }

    /*--------------- EXTERNAL FUNCTIONS -----------------------------------------*/
    /**
     * @notice This function, when conditions are met, will go through
     * the process of picking a winner and minting the stablecoin to them.
     * @dev This function is called by Chainlink Automation when upkeep is needed.
     * @dev Since it is external and can be called by anyone, we will do a check
     * of conditions before proceeding with the upkeep.
     * @param - NOT USED
     */
    function performUpkeep(bytes calldata /* performData */ ) external {
        // Check upKeep conditions - revert if not met
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert StablecoinRaffle__UpkeepNotNeeded();
        }

        // Set the game state to CALCULATING
        s_gameState = RaffleGameState.CALCULATING;

        // Create VRF request for a random number
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });

        // Send VRF request to VRFCoordinator
        // "Words" = Random number
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffleWinner(requestId); // redundant as vrfcoordinator emits too
    }

    /**
     * @notice Allows a holder of the stablecoin to redeem it for ETH.
     * @notice The protocol is designed such that amount of ETH received
     * will be 1/8th of the stablecoin amount. 1 stablecoin = 1 USD.
     * @notice It will check the protocol health factor before allowing the redemption.
     * @param amount The amount of stablecoin to redeem
     */
    function redeemStablecoinForEth(uint256 amount) external moreThanZero(amount) nonReentrant {
        uint256 adjustedEthAmount = stablecoinToEthRedeemAmount(amount);

        // Check if the player has enough stablecoin to redeem
        if (i_stablecoin.balanceOf(msg.sender) < amount) {
            revert StablecoinRaffle__NotEnoughStablecoinToRedeem();
        }

        // Check if vault has enough balance to redeem adjusted amount
        if (address(this).balance < adjustedEthAmount) {
            revert StablecoinRaffle__NotEnoughEthInVaultToRedeem();
        }

        // Check if redeeming breaks the protocol health factor
        uint256 adjustedStablecoinAmountAfterRedeem = (i_stablecoin.totalSupply() - amount);
        _revertIfProtocolHealthIsBrokenFromRedeeming(adjustedEthAmount, adjustedStablecoinAmountAfterRedeem);

        // Burn the stablecoin from the player's balance
        i_stablecoin.burn(msg.sender, amount);

        // Transfer the adjusted amount to the player
        (bool success,) = msg.sender.call{value: adjustedEthAmount}("");
        if (!success) {
            revert StablecoinRaffle__TransferFailed();
        }

        emit StablecoinRedeemed(msg.sender, amount, adjustedEthAmount);
    }

    /*--------------- INTERNAL FUNCTIONS -----------------------------------------*/
    /**
     * @notice This function is called by Chainlink VRF to fulfill the random number request.
     * @notice It picks a random winner from the players who entered the raffle.
     * @param - NOT USED
     * @param randomWords - The random number generated by Chainlink VRF
     */
    function fulfillRandomWords(uint256, /*requestId*/ uint256[] calldata randomWords) internal override {
        // Use the random number to pick a winner from the current game
        uint256 indexOfWinner = randomWords[0] % s_enteredPlayers.length;

        // Get the winner address and set it as the most recent winner
        address recentWinner = s_enteredPlayers[indexOfWinner];
        s_mostRecentWinner = recentWinner;
        emit RaffleWinnerPicked(s_mostRecentWinner);

        // Calculate the adjusted amount of stablecoin to mint for the winner
        // 1 stablecoin = 1 USD, they will get 1/2 of the game balance
        uint256 winnerAdjustedAmount = ethToStablecoinWinningAmount(s_gameRoundBalance);

        // Set game to be open and reset players list, balance and time
        s_gameState = RaffleGameState.OPEN;
        s_enteredPlayers = new address[](0);
        s_gameRoundBalance = 0;
        s_lastTimeStamp = block.timestamp;

        // Mint stablecoin to the winner, in the adjusted amount
        _mintStablecoinToWinner(recentWinner, winnerAdjustedAmount);
    }

    /*--------------- PRIVATE FUNCTIONS ------------------------------------------*/
    /**
     * @notice This function mints the stablecoin to the winner
     * @param _winner - The address of the raffle winner
     * @param _amount - The amount of stablecoin to mint
     */
    function _mintStablecoinToWinner(address _winner, uint256 _amount) private {
        i_stablecoin.mint(_winner, _amount);
    }

    /*--------------- EXTERNAL/PUBLIC (VIEW & PURE) FUNCTIONS --------------------*/
    /**
     * @notice This function is checking if game conditions are met,
     * before going through the process of picking a winner.
     * @dev This is the function that Chainlink Automation will call to see if
     * the lottery is ready to have a winner picked. The following need to be true
     * in order for the upkeep to be performed:
     * 1. The time has passed for the game duration
     * 2. The raffle is open
     * 3. The contract has ETH (or players so to speak)
     * 4. The players list is not empty
     * 5. Implicitly, your subscription is funded with $LINK
     * @param - Ignored, we don't need to pass any data
     * @return upkeepNeeded A boolean that indicates if upkeep is needed
     * @return - Ignored, we don't use performData
     */
    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        // Check condition of time, game state, balance and players
        bool enoughTimeHasPassed = ((block.timestamp - s_lastTimeStamp) > i_gameDuration);
        bool isGameOpen = (s_gameState == RaffleGameState.OPEN);
        // possibly redundant, as players must send ETH to enter
        bool gameHasBalance = (s_gameRoundBalance > 0);
        bool gameHasPlayers = (s_enteredPlayers.length > 0);

        // Check if all conditions are met - if any isn't, this will be false
        upkeepNeeded = (enoughTimeHasPassed && isGameOpen && gameHasBalance && gameHasPlayers);
        return (upkeepNeeded, "");
    }

    /**
     * @notice This function returns the current price of ETH in USD
     * @notice It uses Chainlink price feed to get the latest price
     * @dev The price is returned in 18 decimals format
     * @return The price of ETH in USD
     */
    function priceOfEth() public view returns (uint256) {
        (, int256 price,,,) = i_priceFeed.latestRoundData();
        // Adjusting the price to match the decimals of ETH = 18
        return uint256(price) * USD_TO_ETH_PRECISION;
    }

    /**
     * @notice Get the USD value of ETH amount
     * @param _amount The amount of ETH to convert
     * @return The conversion rate of ETH to USD
     */
    function usdValueOfEth(uint256 _amount) public view returns (uint256) {
        uint256 ethPrice = priceOfEth();
        uint256 usdValueOfEthAmount = (ethPrice * _amount) / ETH_PRECISION;
        return usdValueOfEthAmount;
    }

    /**
     * @notice Returns the amount of ETH that would be minted as stablecoin
     * for the given amount of ETH sent to enter the raffle.
     * @param ethAmount The amount of ETH to convert to stablecoin
     * @return The adjusted amount of stablecoin to mint for the given ETH amount
     */
    function ethToStablecoinWinningAmount(uint256 ethAmount) public view returns (uint256) {
        return (usdValueOfEth(ethAmount)) / HALF;
    }

    /**
     * @notice Returns the amount of ETH that would be redeemed for the given
     * amount of stablecoin. The amount is adjusted to be 1/8th of the stablecoin
     * value, as per protocol design.
     * @param stablecoinAmount The amount of stablecoin to convert to ETH
     * @return The adjusted amount of ETH to redeem for the given stablecoin amount
     */
    function stablecoinToEthRedeemAmount(uint256 stablecoinAmount) public view returns (uint256) {
        uint256 ethPrice = priceOfEth();
        uint256 stablecoinToEthAmount = (stablecoinAmount * ETH_PRECISION) / ethPrice;
        return stablecoinToEthAmount / EIGHTH;
    }

    /**
     * @notice Returns the current protocol health factor.
     * @notice The protocol health factor is the ratio of the ETH value in the contract
     * to the total supply of stablecoin. It should be at least 2 to ensure overcollateralization.
     * @return The protocol health factor as a uint256
     */
    function getProtocolHealth() public view returns (uint256) {
        uint256 stablecoinSupply = i_stablecoin.totalSupply();
        if (stablecoinSupply == 0) {
            return type(uint256).max; // If no stablecoins, protocol health is max
        }
        uint256 protocolEthValue = usdValueOfEth(address(this).balance);
        return protocolEthValue / stablecoinSupply;
    }

    /*--------------- INTERNAL/PRIVATE (VIEW & PURE) FUNCTIONS -------------------*/
    function _revertIfProtocolHealthIsBrokenFromRedeeming(uint256 _protocolEthValue, uint256 _stablecoinAmount)
        private
        pure
    {
        if (_stablecoinAmount == 0) {
            return; // If no stablecoins, protocol health is not broken
        }

        uint256 protocolHealth = _protocolEthValue / _stablecoinAmount;

        if (protocolHealth < MINIMUM_PROTOCOL_HEALTH) {
            revert StablecoinRaffle__RedeemingBreaksProtocolHealth();
        }
    }

    /*--------------- GETTER FUNCTIONS -------------------------------------------*/
    /*
     * @notice This function returns the address of the most recent winner.
     * @return The address of the most recent winner
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceUsdFee;
    }

    /**
     * @notice This function returns the duration of the game.
     * @return The duration of the game in seconds
     */
    function getGameDuration() external view returns (uint256) {
        return i_gameDuration;
    }

    /**
     * @notice This function returns the game state of the raffle. OPEN or CALCULATING.
     * @return The game state of the raffle
     */
    function getRaffleGameState() external view returns (RaffleGameState) {
        return s_gameState;
    }

    /**
     * @notice This function returns the address of the most recent winner.
     * @return The address of the most recent winner
     */
    function getMostRecentWinner() external view returns (address) {
        return s_mostRecentWinner;
    }

    /**
     * @notice This function returns the amount of players currently entered in raffle.
     * @return The number of players currently entered in the raffle
     */
    function getAmountOfPlayersEntered() external view returns (uint256) {
        return s_enteredPlayers.length;
    }

    /**
     * @notice This function returns the address of the player at the given index.
     * @param _index The index of the player in the entered players list
     * @return The address of the player at the given index
     */
    function getPlayerInGame(uint256 _index) external view returns (address) {
        return s_enteredPlayers[_index];
    }

    /**
     * @notice Returns the balance of the current game round.
     * @return The balance of the current game round
     */
    function getGameRoundBalance() external view returns (uint256) {
        return s_gameRoundBalance;
    }

    /**
     * @notice Returns the last time stamp of the game.
     * @return The last time stamp of the game
     */
    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
