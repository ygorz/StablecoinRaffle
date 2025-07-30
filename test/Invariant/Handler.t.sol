// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {StaluxCoin} from "src/StaluxCoin.sol";
import {StablecoinRaffle} from "src/StablecoinRaffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract Handler is Test {
    StaluxCoin public coin;
    StablecoinRaffle public raffle;
    HelperConfig public config;
    HelperConfig.NetworkConfig public networkConfig;

    uint256 constant MAX_DEPOSIT_AMOUNT = type(uint96).max;

    constructor(StaluxCoin _coin, StablecoinRaffle _raffle, HelperConfig.NetworkConfig memory _networkConfig) {
        coin = _coin;
        raffle = _raffle;
        networkConfig = _networkConfig;
    }

    function enterRaffle(uint256 amount) public {
        if (raffle.getRaffleGameState() != StablecoinRaffle.RaffleGameState.OPEN) {
            return;
        }
        if (msg.sender == address(raffle)) {
            return;
        }

        uint256 minEntranceFeeInUsd = raffle.getEntranceFee();
        uint256 priceOfEth = raffle.priceOfEth();
        uint256 minEthToEnterRaffle = (minEntranceFeeInUsd * 1e18) / priceOfEth;

        amount = bound(amount, minEthToEnterRaffle, MAX_DEPOSIT_AMOUNT);
        vm.deal(msg.sender, MAX_DEPOSIT_AMOUNT);
        vm.prank(msg.sender);
        raffle.enterRaffle{value: amount}();
    }

    function chooseWinner() public {
        if (raffle.getAmountOfPlayersEntered() == 0) {
            return;
        }
        vm.warp(block.timestamp + raffle.getGameDuration() + 1);
        vm.roll(block.number + 1);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(networkConfig.vrfCoordinatorAddress).fulfillRandomWords(
            uint256(requestId), address(raffle)
        );
    }
}
