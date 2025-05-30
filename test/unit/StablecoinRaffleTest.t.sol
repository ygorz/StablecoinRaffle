// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {StaluxCoin} from "src/StaluxCoin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StablecoinRaffle} from "src/StablecoinRaffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract RaffleTest is Test {
    StaluxCoin public staluxCoin;
    StablecoinRaffle public stablecoinRaffle;
    HelperConfig public helperConfig;

    uint256 public entranceFee;
    uint256 public gameInterval;
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
        vm.deal(PLAYER1, STARTING_PLAYER_BALANCE);
        vm.deal(PLAYER2, STARTING_PLAYER_BALANCE);
    }

    /*------------------------- Stablecoin Tests ---------------------------*/
    function testNotOwnerCannotMint() public {
        vm.startPrank(PLAYER1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, PLAYER1));
        staluxCoin.mint(PLAYER1, 1000);
        vm.stopPrank();
    }

    function testNotOwnerCannotBurn() public {
        vm.startPrank(PLAYER1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, PLAYER1));
        staluxCoin.burn(PLAYER1, 1000);
        vm.stopPrank();
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
        vm.startPrank(PLAYER1);

        (bool success,) = address(stablecoinRaffle).call{value: entranceFee}("");
        assertTrue(success);
        vm.stopPrank();

        assertEq(stablecoinRaffle.getPlayerInGame(0), PLAYER1);
        assertEq(stablecoinRaffle.getAmountOfPlayersEntered(), 1);
    }

    function testFallbackFunctionEntersRaffle() public {
        bytes4 functionSelector = bytes4(keccak256("transfer(address,uint256)"));

        bytes memory data = abi.encodeWithSelector(functionSelector);

        vm.startPrank(PLAYER1);

        (bool success,) = address(stablecoinRaffle).call{value: entranceFee}(data);
        assertTrue(success);
        vm.stopPrank();

        assertEq(stablecoinRaffle.getPlayerInGame(0), PLAYER1);
        assertEq(stablecoinRaffle.getAmountOfPlayersEntered(), 1);
    }

    /*------------------------- Enter Raffle Tests -------------------------*/
    function testPlayerCanEnterRaffle() public {
        vm.startPrank(PLAYER1);
        stablecoinRaffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();

        assertEq(stablecoinRaffle.getPlayerInGame(0), PLAYER1);
        assertEq(stablecoinRaffle.getAmountOfPlayersEntered(), 1);
    }

    function testEnterRaffleWithZeroEthReverts() public {
        vm.startPrank(PLAYER1);
        vm.expectRevert(StablecoinRaffle.StablecoinRaffle__NeedsMoreThanZero.selector);
        stablecoinRaffle.enterRaffle{value: 0}();
        vm.stopPrank();
    }

    function testEnterRaffleRevertsIfNotEnoughEth() public {
        vm.startPrank(PLAYER1);
        vm.expectRevert(StablecoinRaffle.StablecoinRaffle__SendMoreEthToEnterRaffle.selector);
        stablecoinRaffle.enterRaffle{value: 1 wei}();
        vm.stopPrank();
    }

    // function testCantEnterIfRaffleCalculating() public {
    //     vm.startPrank(PLAYER1);
    //     stablecoinRaffle.enterRaffle{value: entranceFee}();
    //     vm.stopPrank();

    //     vm.warp(block.timestamp + gameInterval + 1);
    //     vm.roll(block.number + 1);
    //     stablecoinRaffle.performUpkeep("");

    //     vm.startPrank(PLAYER1);

    //     vm.expectRevert(StablecoinRaffle.StablecoinRaffle__RaffleNotOpen.selector);
    //     stablecoinRaffle.enterRaffle{value: entranceFee}();
    //     vm.stopPrank();
    // }

    function testEnteringRaffleEmitsEvent() public {
        vm.startPrank(PLAYER1);
        vm.expectEmit(true, false, false, false, address(stablecoinRaffle));
        emit StablecoinRaffle.RaffleEntered(PLAYER1);
        stablecoinRaffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();
    }

    function testGameAroundBalanceUpdatesAfterPlayersEnter() public {
        vm.startPrank(PLAYER1);
        stablecoinRaffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();

        vm.startPrank(PLAYER2);
        stablecoinRaffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();

        assertEq(stablecoinRaffle.getGameRoundBalance(), entranceFee * 2);
    }
}
