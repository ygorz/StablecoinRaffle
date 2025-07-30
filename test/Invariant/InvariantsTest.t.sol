// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployStablecoinRaffle} from "script/DeployStablecoinRaffle.s.sol";
import {StaluxCoin} from "src/StaluxCoin.sol";
import {StablecoinRaffle} from "src/StablecoinRaffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Handler} from "test/Invariant/Handler.t.sol";

// What are our invariants?
// 1. Collateral value in raffle contract must always be
// greater than or equal to the total stablecoin supply.
// 2. Getter functions should never revert.

contract InvariantsTest is StdInvariant, Test {
    DeployStablecoinRaffle deployer;
    StaluxCoin coin;
    StablecoinRaffle raffle;
    HelperConfig config;
    HelperConfig.NetworkConfig networkConfig;
    Handler handler;

    function setUp() external {
        deployer = new DeployStablecoinRaffle();
        (coin, raffle,, networkConfig) = deployer.run();
        handler = new Handler(coin, raffle, networkConfig);
        targetContract(address(handler));
    }

    function invariant_raffleMustHaveMoreCollateralThanStablecoin() external view {
        uint256 totalStablecoinSupply = coin.totalSupply();
        uint256 totalEthInRaffle = address(raffle).balance;
        uint256 totalCollateralValue = raffle.usdValueOfEth(totalEthInRaffle);

        console2.log("Total Stablecoin Supply:", totalStablecoinSupply);
        console2.log("Total ETH in Raffle:", totalEthInRaffle);
        console2.log("Total Collateral Value (USD):", totalCollateralValue);

        assert(totalCollateralValue >= totalStablecoinSupply);
    }

    function invariant_getterFunctionsShouldNotRevert() external view {
        raffle.getEntranceFee();
        raffle.getGameDuration();
        raffle.getRaffleGameState();
        raffle.getMostRecentWinner();
        raffle.getAmountOfPlayersEntered();
        raffle.getGameRoundBalance();
        raffle.getLastTimeStamp();
    }
}
