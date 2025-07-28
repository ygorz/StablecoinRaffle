// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DeployStablecoinRaffle} from "script/DeployStablecoinRaffle.s.sol";
import {StaluxCoin} from "src/StaluxCoin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StablecoinRaffle} from "src/StablecoinRaffle.sol";
import {CodeConstants, HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {DummyPlayer} from "test/mocks/DummyPlayer.sol";

contract RaffleTest is Test, CodeConstants {
    StaluxCoin public staluxCoin;
    StablecoinRaffle public stablecoinRaffle;
    HelperConfig public helperConfig;

    uint256 public entranceFee;
    uint256 public gameInterval;
    address public priceFeedAddress;
    address public vrfCoordinator;
    uint256 public expectedEthPrice;
    address public PLAYER1 = makeAddr("PLAYER1");
    address public PLAYER2 = makeAddr("PLAYER2");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    event RaffleEntered(address indexed player);

    function setUp() external {
        DeployStablecoinRaffle deployRaffle = new DeployStablecoinRaffle();
        (staluxCoin, stablecoinRaffle, helperConfig) = deployRaffle.run();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        gameInterval = config.gameDuration;
        priceFeedAddress = config.priceFeedAddress;
        vrfCoordinator = config.vrfCoordinatorAddress;
        vm.deal(PLAYER1, STARTING_PLAYER_BALANCE);
        vm.deal(PLAYER2, STARTING_PLAYER_BALANCE);
    }

    modifier raffleEntered(uint256 amount) {
        amount = bound(amount, entranceFee, type(uint96).max);
        vm.deal(PLAYER1, amount);
        vm.prank(PLAYER1);
        stablecoinRaffle.enterRaffle{value: amount}();
        _;
    }

    modifier timeForward() {
        vm.warp(block.timestamp + gameInterval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier getEthPrice() {
        (, int256 price,,,) = MockV3Aggregator(priceFeedAddress).latestRoundData();
        expectedEthPrice = uint256(price) * 1e10; // Convert to 18 decimals
        _;
    }

    modifier skipFork() {
        if (block.chainid != ANVIL_CHAIN_ID) {
            return;
        }
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
    function testReceiveFunctionEntersRaffle(uint256 amount) public {
        vm.prank(PLAYER1);
        amount = bound(amount, entranceFee, type(uint96).max);
        (bool success,) = address(stablecoinRaffle).call{value: entranceFee}("");

        assertTrue(success);
        assertEq(stablecoinRaffle.getPlayerInGame(0), PLAYER1);
        assertEq(stablecoinRaffle.getAmountOfPlayersEntered(), 1);
    }

    function testFallbackFunctionEntersRaffle(uint256 amount) public {
        bytes4 functionSelector = bytes4(keccak256("transfer(address,uint256)"));
        bytes memory data = abi.encodeWithSelector(functionSelector);
        amount = bound(amount, entranceFee, type(uint96).max);

        vm.deal(PLAYER1, amount);
        vm.prank(PLAYER1);
        (bool success,) = address(stablecoinRaffle).call{value: amount}(data);

        assertTrue(success);
        assertEq(stablecoinRaffle.getPlayerInGame(0), PLAYER1);
        assertEq(stablecoinRaffle.getAmountOfPlayersEntered(), 1);
    }

    /*------------------------- Constructor Tests --------------------------*/

    /*------------------------- Enter Raffle Tests -------------------------*/
    function testPlayerCanEnterRaffle(uint256 amount) public raffleEntered(amount) {
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

    function testCantEnterIfRaffleCalculating(uint256 amount) public raffleEntered(amount) {
        vm.warp(block.timestamp + gameInterval + 1);
        vm.roll(block.number + 1);
        stablecoinRaffle.performUpkeep("");

        amount = bound(amount, entranceFee, type(uint96).max);
        vm.deal(PLAYER2, amount);
        vm.prank(PLAYER2);
        vm.expectRevert(StablecoinRaffle.StablecoinRaffle__RaffleNotOpen.selector);
        stablecoinRaffle.enterRaffle{value: amount}();
    }

    function testEnteringRaffleEmitsEvent() public {
        vm.prank(PLAYER1);
        vm.expectEmit(true, false, false, false, address(stablecoinRaffle));
        emit StablecoinRaffle.RaffleEntered(PLAYER1);
        stablecoinRaffle.enterRaffle{value: entranceFee}();
    }

    function testGameAroundBalanceUpdatesAfterPlayersEnter(uint256 amount) public {
        amount = bound(amount, entranceFee, type(uint96).max);
        vm.deal(PLAYER1, amount);
        vm.prank(PLAYER1);
        stablecoinRaffle.enterRaffle{value: amount}();
        assertEq(stablecoinRaffle.getGameRoundBalance(), amount);
    }

    /*------------------------- Check Upkeep Tests -------------------------*/
    function testCheckUpkeepReturnsTrueIfAllConditionsMet(uint256 amount) public raffleEntered(amount) timeForward {
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

    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen(uint256 amount) public raffleEntered(amount) timeForward {
        stablecoinRaffle.performUpkeep("");

        (bool upkeepNeeded,) = stablecoinRaffle.checkUpkeep("");
        assert(upkeepNeeded == false);
    }

    /*------------------------- Perform Upkeep Tests -----------------------*/
    function testPerformUpkeepRevertsIfUpkeepNotNeeded(uint256 amount) public raffleEntered(amount) {
        vm.expectRevert(StablecoinRaffle.StablecoinRaffle__UpkeepNotNeeded.selector);
        stablecoinRaffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfRaffleIsCalculating(uint256 amount) public raffleEntered(amount) timeForward {
        stablecoinRaffle.performUpkeep("");

        vm.expectRevert(StablecoinRaffle.StablecoinRaffle__UpkeepNotNeeded.selector);
        stablecoinRaffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId(uint256 amount)
        public
        raffleEntered(amount)
        timeForward
    {
        vm.recordLogs();
        stablecoinRaffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        StablecoinRaffle.RaffleGameState raffleState = stablecoinRaffle.getRaffleGameState();

        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    /*------------------------- Fulfill Random Words Tests -----------------*/

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId, uint256 amount)
        public
        raffleEntered(amount)
        timeForward
        skipFork
    {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(stablecoinRaffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney(uint256 amount) public skipFork {
        // Arrange
        uint256 entrants = 20; // 20 people total will enter
        uint256 startingIndex = 1;
        amount = bound(amount, entranceFee, type(uint96).max);

        for (uint256 i = startingIndex; i <= entrants; i++) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, amount);
            stablecoinRaffle.enterRaffle{value: amount}();
        }

        vm.warp(block.timestamp + gameInterval + 1);
        vm.roll(block.number + 1);

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

    function testRedeemStablecoinRevertsIfRedeemingBreaksProtocolHealth(uint256 amount)
        public
        raffleEntered(amount)
        timeForward
        skipFork
    {
        vm.recordLogs();
        stablecoinRaffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(stablecoinRaffle));

        // Artificially inflate the supply thus decreasing health factor as contract
        // has the same amount of ETH still
        uint256 stablecoinToRedeem = staluxCoin.balanceOf(PLAYER1);
        uint256 stablecoinToMint = staluxCoin.balanceOf(PLAYER1) * 2;

        vm.prank(address(stablecoinRaffle));
        staluxCoin.mint(PLAYER1, stablecoinToMint);

        vm.prank(PLAYER1);
        vm.expectPartialRevert(StablecoinRaffle.StablecoinRaffle__RedeemingBreaksProtocolHealth.selector);
        stablecoinRaffle.redeemStablecoinForEth(stablecoinToRedeem);
    }

    function testTransferFailsInRedeemStablecoin() public skipFork {
        DummyPlayer dummyPlayer = new DummyPlayer();
        vm.deal(address(dummyPlayer), 100 ether);
        vm.prank(address(dummyPlayer));
        stablecoinRaffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + gameInterval + 1);
        vm.roll(block.number + 1);
        vm.recordLogs();
        stablecoinRaffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(stablecoinRaffle));

        vm.startPrank(address(dummyPlayer));
        vm.expectRevert(StablecoinRaffle.StablecoinRaffle__TransferFailed.selector);
        stablecoinRaffle.redeemStablecoinForEth(1 ether);
        vm.stopPrank();
    }

    /*------------------------- Price Feed Tests ---------------------------*/
    function testPriceOfEthReturnsCorrectValue() public getEthPrice {
        uint256 priceOfEth = stablecoinRaffle.priceOfEth();
        assertEq(priceOfEth, expectedEthPrice);
    }

    function testUsdValueOfEthReturnsCorrectValue() public view {
        uint256 ethAmount = 1 ether;
        uint256 priceOfEth = stablecoinRaffle.priceOfEth();
        uint256 expectedUsdValue = (ethAmount * priceOfEth) / 1e18;
        assertEq(stablecoinRaffle.usdValueOfEth(ethAmount), expectedUsdValue);
    }

    /*------------------------- Protocol Health Tests ----------------------*/
    function testGetProtocolHealthReturnsCorrectValue(uint256 amount)
        public
        raffleEntered(amount)
        timeForward
        skipFork
    {
        vm.recordLogs();
        stablecoinRaffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(stablecoinRaffle));

        uint256 stablecoinSupply = staluxCoin.totalSupply();
        uint256 raffleContractBalanceEthUsdValue = (address(stablecoinRaffle).balance * 2000e18) / 1e18;
        uint256 expectedProtocolHealth = (raffleContractBalanceEthUsdValue * 1e18) / stablecoinSupply;
        uint256 protocolHealth = stablecoinRaffle.getProtocolHealth();
        assertEq(expectedProtocolHealth, protocolHealth);
    }

    function testGetProtocolHealthReturnsMaxValueIfNoStablecoinMinted(uint256 amount) public raffleEntered(amount) {
        uint256 protocolHealth = stablecoinRaffle.getProtocolHealth();
        assertEq(protocolHealth, type(uint256).max);
    }

    /*------------------------- Calculation Tests --------------------------*/
    function testGetEthToStablecoinWinningAmountReturnsCorrectValue() public getEthPrice {
        uint256 ethAmount = 2 ether;
        uint256 expectedStablecoinAmount = ((ethAmount * expectedEthPrice) / 1e18) / 2;
        assertEq(stablecoinRaffle.ethToStablecoinWinningAmount(ethAmount), expectedStablecoinAmount);
    }

    function testGetStablecoinToEthRedeemAmountReturnsCorrectValue() public getEthPrice {
        uint256 stablecoinAmount = 2 ether;
        uint256 expectedEthAmount = (stablecoinAmount * 1e18) / expectedEthPrice;
        assertEq(stablecoinRaffle.stablecoinToEthRedeemAmount(stablecoinAmount), (expectedEthAmount / 8));
    }

    /*------------------------- Getter Function Tests ----------------------*/
    function testGetEntranceFeeReturnsCorrectValue() public view {
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
}
