// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {StaluxCoin} from "src/StaluxCoin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StablecoinRaffle} from "src/StablecoinRaffle.sol";
import {CodeConstants, HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test, CodeConstants {
    StaluxCoin public staluxCoin;
    StablecoinRaffle public stablecoinRaffle;
    HelperConfig public helperConfig;

    uint256 public entranceFee;
    uint256 public gameInterval;
    address vrfCoordinator;
    address public PLAYER1 = makeAddr("PLAYER1");
    address public PLAYER2 = makeAddr("PLAYER2");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    event RaffleEntered(address indexed player);

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (staluxCoin, stablecoinRaffle, helperConfig) = deployRaffle.deployStablecoinRaffle();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        gameInterval = config.gameDuration;
        vrfCoordinator = config.vrfCoordinator;
        vm.deal(PLAYER1, STARTING_PLAYER_BALANCE);
        vm.deal(PLAYER2, STARTING_PLAYER_BALANCE);
    }

    modifier raffleEntered() {
        vm.prank(PLAYER1);
        stablecoinRaffle.enterRaffle{value: entranceFee}();
        _;
    }

    modifier timeForward() {
        vm.warp(block.timestamp + gameInterval + 1);
        vm.roll(block.number + 1);
        _;
    }

    /*------------------------- Stablecoin Tests ---------------------------*/
    function testNotOwnerCannotMint() public {
        vm.prank(PLAYER1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, PLAYER1));
        staluxCoin.mint(PLAYER1, 1000);
    }

    function testNotOwnerCannotBurn() public {
        vm.prank(PLAYER1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, PLAYER1));
        staluxCoin.burn(PLAYER1, 1000);
    }

    /*------------------------- Game Contract Tests ------------------------*/
    function testStaluxCoinOwnershipTransferedToRaffle() public view {
        assertEq(staluxCoin.owner(), address(stablecoinRaffle));
    }

    function testRaffleInitializesInOpenState() public view {
        assert(stablecoinRaffle.getRaffleGameState() == StablecoinRaffle.RaffleGameState.OPEN);
    }

    /*------------------------- Receive/Fallback Function Tests ------------*/
    function testReceiveFunctionEntersRaffle() public {
        vm.prank(PLAYER1);
        (bool success,) = address(stablecoinRaffle).call{value: entranceFee}("");

        assertTrue(success);
        assertEq(stablecoinRaffle.getPlayerInGame(0), PLAYER1);
        assertEq(stablecoinRaffle.getAmountOfPlayersEntered(), 1);
    }

    function testFallbackFunctionEntersRaffle() public {
        bytes4 functionSelector = bytes4(keccak256("transfer(address,uint256)"));
        bytes memory data = abi.encodeWithSelector(functionSelector);

        vm.prank(PLAYER1);
        (bool success,) = address(stablecoinRaffle).call{value: entranceFee}(data);

        assertTrue(success);
        assertEq(stablecoinRaffle.getPlayerInGame(0), PLAYER1);
        assertEq(stablecoinRaffle.getAmountOfPlayersEntered(), 1);
    }

    /*------------------------- Constructor Tests --------------------------*/

    /*------------------------- Enter Raffle Tests -------------------------*/
    function testPlayerCanEnterRaffle() public raffleEntered {
        assertEq(stablecoinRaffle.getPlayerInGame(0), PLAYER1);
        assertEq(stablecoinRaffle.getAmountOfPlayersEntered(), 1);
    }

    function testEnterRaffleWithZeroEthReverts() public {
        vm.prank(PLAYER1);
        vm.expectRevert(StablecoinRaffle.StablecoinRaffle__NeedsMoreThanZero.selector);
        stablecoinRaffle.enterRaffle{value: 0}();
    }

    function testEnterRaffleRevertsIfNotEnoughEth() public {
        vm.prank(PLAYER1);
        vm.expectRevert(StablecoinRaffle.StablecoinRaffle__SendMoreEthToEnterRaffle.selector);
        stablecoinRaffle.enterRaffle{value: 1 wei}();
    }

    function testCantEnterIfRaffleCalculating() public raffleEntered {
        vm.warp(block.timestamp + gameInterval + 1);
        vm.roll(block.number + 1);
        stablecoinRaffle.performUpkeep("");

        vm.prank(PLAYER1);
        vm.expectRevert(StablecoinRaffle.StablecoinRaffle__RaffleNotOpen.selector);
        stablecoinRaffle.enterRaffle{value: entranceFee}();
    }

    function testEnteringRaffleEmitsEvent() public {
        vm.prank(PLAYER1);
        vm.expectEmit(true, false, false, false, address(stablecoinRaffle));
        emit StablecoinRaffle.RaffleEntered(PLAYER1);
        stablecoinRaffle.enterRaffle{value: entranceFee}();
    }

    function testGameAroundBalanceUpdatesAfterPlayersEnter() public raffleEntered {
        assertEq(stablecoinRaffle.getGameRoundBalance(), entranceFee);
    }

    /*------------------------- Check Upkeep Tests -------------------------*/
    function testCheckUpkeepReturnsTrueIfAllConditionsMet() public raffleEntered timeForward {
        (bool upkeepNeeded,) = stablecoinRaffle.checkUpkeep("");
        assert(upkeepNeeded == true);
    }

    function testCheckUpkeepReturnsFalseIfNoPlayersAndNotEnoughTimePassed() public view {
        (bool upkeepNeeded,) = stablecoinRaffle.checkUpkeep("");
        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsFalseIfTimePassedButNoPlayers() public timeForward {
        (bool upkeepNeeded,) = stablecoinRaffle.checkUpkeep("");
        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public raffleEntered timeForward {
        stablecoinRaffle.performUpkeep("");

        (bool upkeepNeeded,) = stablecoinRaffle.checkUpkeep("");
        assert(upkeepNeeded == false);
    }

    /*------------------------- Perform Upkeep Tests -----------------------*/
    function testPerformUpkeepRevertsIfUpkeepNotNeeded() public raffleEntered {
        vm.expectRevert(StablecoinRaffle.StablecoinRaffle__UpkeepNotNeeded.selector);
        stablecoinRaffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfRaffleIsCalculating() public raffleEntered timeForward {
        stablecoinRaffle.performUpkeep("");

        vm.expectRevert(StablecoinRaffle.StablecoinRaffle__UpkeepNotNeeded.selector);
        stablecoinRaffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered timeForward {
        vm.recordLogs();
        stablecoinRaffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        StablecoinRaffle.RaffleGameState raffleState = stablecoinRaffle.getRaffleGameState();

        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    /*------------------------- Fulfill Random Words Tests -----------------*/
    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        raffleEntered
        timeForward
        skipFork
    {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(stablecoinRaffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered timeForward skipFork {
        // Arrange
        uint256 additionalEntrants = 10; // 11 people total will enter
        uint256 startingIndex = 1; // PLAYER1 is already entered, so we start from PLAYER2

        for (uint256 i = startingIndex; i < (startingIndex + additionalEntrants); i++) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, STARTING_PLAYER_BALANCE);
            stablecoinRaffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = stablecoinRaffle.getLastTimeStamp();
        uint256 gameRoundBalance = stablecoinRaffle.getGameRoundBalance();

        // Act
        vm.recordLogs();
        stablecoinRaffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(stablecoinRaffle));

        // Assert
        address recentWinner = stablecoinRaffle.getMostRecentWinner();
        StablecoinRaffle.RaffleGameState raffleState = stablecoinRaffle.getRaffleGameState();
        uint256 winnerBalance = staluxCoin.balanceOf(recentWinner);
        uint256 endingTimeStamp = stablecoinRaffle.getLastTimeStamp();
        uint256 stablecoinPrizeForWinner = stablecoinRaffle.ethToStablecoinWinningAmount(gameRoundBalance);

        assert(winnerBalance == stablecoinPrizeForWinner);
        assert(uint256(raffleState) == 0);
        assert(endingTimeStamp > startingTimeStamp);
    }

    /*------------------------- Redeem Stablecoin Tests --------------------*/
    function testRedeemStablecoinRevertsIfRedeemingZero() public {
        vm.startPrank(PLAYER1);
        vm.expectRevert(StablecoinRaffle.StablecoinRaffle__NeedsMoreThanZero.selector);
        stablecoinRaffle.redeemStablecoinForEth(0);
        vm.stopPrank();
    }

    // Testing the redeem function with some arbitrary setup, to ensure it works as expected
    function testRedeemStablecoinFunctionRedeemsSuccessfully() public {
        // Make sure the raffle contract has a lot of balance
        vm.deal(address(stablecoinRaffle), 100 ether);

        // Mint some stablecoins to PLAYER1, as if they had won the raffle
        vm.startPrank(address(stablecoinRaffle));
        staluxCoin.mint(PLAYER1, 1 ether);
        vm.stopPrank();

        // PLAYER1 redeems their stablecoin for ETH
        vm.startPrank(PLAYER1);
        uint256 stablecoinAmount = 1 ether;
        uint256 initialPlayerBalance = PLAYER1.balance;
        stablecoinRaffle.redeemStablecoinForEth(stablecoinAmount);
        uint256 finalPlayerBalance = PLAYER1.balance - initialPlayerBalance;
        vm.stopPrank();

        // Calculate the expected ETH amount based on the stablecoin to ETH conversion rate
        uint256 expectedFinalPlayerBalance = stablecoinRaffle.stablecoinToEthRedeemAmount(stablecoinAmount);

        // Check that the player's balance increased by the correct amount
        assertEq(finalPlayerBalance, expectedFinalPlayerBalance);
        assertEq(staluxCoin.balanceOf(PLAYER1), 0);
    }

    function testRedeemStablecoinRevertsIfRedeemingMoreThanBalance() public {
        // Mint some stablecoins to PLAYER1, as if they had won the raffle
        vm.startPrank(address(stablecoinRaffle));
        staluxCoin.mint(PLAYER1, 1 ether);
        vm.stopPrank();

        vm.startPrank(PLAYER1);
        uint256 stablecoinAmount = 2 ether; // More than the balance
        vm.expectRevert(StablecoinRaffle.StablecoinRaffle__NotEnoughStablecoinToRedeem.selector);
        stablecoinRaffle.redeemStablecoinForEth(stablecoinAmount);
        vm.stopPrank();
    }

    function testRedeemStablecoinRevertsIfGameContractDoesntHaveEnoughEth() public {
        // Mint some stablecoins to PLAYER1, as if they had won the raffle
        vm.startPrank(address(stablecoinRaffle));
        staluxCoin.mint(PLAYER1, 1 ether);
        vm.stopPrank();

        // Set the game contract's balance to 0
        vm.deal(address(stablecoinRaffle), 0);

        vm.startPrank(PLAYER1);
        uint256 stablecoinAmount = 1 ether;
        vm.expectRevert(StablecoinRaffle.StablecoinRaffle__NotEnoughEthInVaultToRedeem.selector);
        stablecoinRaffle.redeemStablecoinForEth(stablecoinAmount);
        vm.stopPrank();
    }

    // function testRedeemStablecoinRevertsIfRevertingBreaksProtocolHealth() public {
    //     // Mint some stablecoins to PLAYER1, as if they had won the raffle
    //     vm.startPrank(address(stablecoinRaffle));
    //     staluxCoin.mint(PLAYER1, 1000 ether);
    //     vm.stopPrank();

    //     // Set the game contract's balance to low eth amount
    //     vm.deal(address(stablecoinRaffle), 2e18);

    //     // 4000e18 price of 2 eth

    //     vm.startPrank(PLAYER1);
    //     uint256 stablecoinAmount = 1000 ether;
    //     vm.expectRevert(StablecoinRaffle.StablecoinRaffle__RedeemingBreaksProtocolHealthFactor.selector);
    //     stablecoinRaffle.redeemStablecoinForEth(stablecoinAmount);
    //     vm.stopPrank();
    // }

    /*------------------------- Getter Function Tests ----------------------*/
    function testGetEntraceFeeReturnsCorrectValue() public view {
        assertEq(stablecoinRaffle.getEntranceFee(), entranceFee);
    }

    function testGetGameDurationReturnsCorrectValue() public view {
        assertEq(stablecoinRaffle.getGameDuration(), gameInterval);
    }

    function testGetRaffleGameStateReturnsCorrectValue() public view {
        assertEq(uint256(stablecoinRaffle.getRaffleGameState()), uint256(StablecoinRaffle.RaffleGameState.OPEN));
    }

    function testGetAmountOfPlayersEnteredReturnsCorrectValue() public {
        vm.startPrank(PLAYER1);
        stablecoinRaffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();

        vm.startPrank(PLAYER2);
        stablecoinRaffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();

        assertEq(stablecoinRaffle.getAmountOfPlayersEntered(), 2);
    }

    function testGetPlayerInGameReturnsCorrectValue() public {
        vm.startPrank(PLAYER1);
        stablecoinRaffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();

        assertEq(stablecoinRaffle.getPlayerInGame(0), PLAYER1);
    }

    function testGetGameRoundBalanceReturnsCorrectValue() public {
        vm.startPrank(PLAYER1);
        stablecoinRaffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();

        vm.startPrank(PLAYER2);
        stablecoinRaffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();

        assertEq(stablecoinRaffle.getGameRoundBalance(), entranceFee * 2);
    }

    function testGetProtocolHealthReturnsCorrectValue() public raffleEntered timeForward skipFork {
        vm.recordLogs();
        stablecoinRaffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(stablecoinRaffle));

        uint256 stablecoinSupply = staluxCoin.totalSupply();
        uint256 raffleContractBalanceEthUsdValue = (address(stablecoinRaffle).balance * 2000e18) / 1e18;
        uint256 expectedProtocolHealth = raffleContractBalanceEthUsdValue / stablecoinSupply;
        uint256 protocolHealth = stablecoinRaffle.getProtocolHealth();
        assertEq(expectedProtocolHealth, protocolHealth);
    }

    function testGetProtocolHealthReturnsMaxValueIfNoStablecoinMinted() public raffleEntered {
        uint256 protocolHealth = stablecoinRaffle.getProtocolHealth();
        assertEq(protocolHealth, type(uint256).max);
    }

    function testGetEthToStablecoinWinningAmountReturnsCorrectValue() public view {
        uint256 ethAmount = 2 ether;
        uint256 ethPrice = 2000e18;
        uint256 expectedStablecoinAmount = ((ethAmount * ethPrice) / 1e18) / 2;
        assertEq(stablecoinRaffle.ethToStablecoinWinningAmount(ethAmount), expectedStablecoinAmount);
    }

    function testGetStablecoinToEthRedeemAmountReturnsCorrectValue() public view {
        uint256 stablecoinAmount = 2 ether;
        uint256 ethPrice = 2000e18;

        uint256 expectedEthAmount = (stablecoinAmount * 1e18) / ethPrice;
        assertEq(stablecoinRaffle.stablecoinToEthRedeemAmount(stablecoinAmount), (expectedEthAmount / 8));
    }
}
