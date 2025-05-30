// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {StaluxCoin} from "src/StaluxCoin.sol";
import {StablecoinRaffle} from "src/StablecoinRaffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployRaffle is Script {
    function run() external {}

    function deployStablecoinRaffle() public returns (StaluxCoin, StablecoinRaffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast();
        StaluxCoin staluxCoin = new StaluxCoin();
        StablecoinRaffle stablecoinRaffle = new StablecoinRaffle(
            address(staluxCoin),
            config.entranceFee,
            config.gameDuration,
            config.priceFeed,
            config.vrfCoordinator,
            config.keyHash,
            config.subscriptionId,
            config.callbackGasLimit
        );
        staluxCoin.transferOwnership(address(stablecoinRaffle));
        vm.stopBroadcast();

        return (staluxCoin, stablecoinRaffle, helperConfig);
    }
}
