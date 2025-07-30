// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {StaluxCoin} from "src/StaluxCoin.sol";
import {StablecoinRaffle} from "src/StablecoinRaffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {VrfSubscriptionInteractions} from "script/VrfSubscriptionInteractions.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

contract DeployStablecoinRaffle is Script {
    StaluxCoin public staluxCoin;
    StablecoinRaffle public stablecoinRaffle;
    HelperConfig public helperConfig;

    function run() external returns (StaluxCoin, StablecoinRaffle, HelperConfig, HelperConfig.NetworkConfig memory) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        VrfSubscriptionInteractions vrfInteractions = new VrfSubscriptionInteractions();

        // Create and fund Mock VRF subscription if it doesn't exist
        if (config.vrfSubscriptionId == 0) {
            uint256 fundAmount = type(uint128).max; // 1000 mock LINK tokens
            vrfInteractions.createVrfSubscription(config.vrfCoordinatorAddress, config.deployerAccount);

            config.vrfSubscriptionId =
                vrfInteractions.createVrfSubscription(config.vrfCoordinatorAddress, config.deployerAccount);

            vrfInteractions.fundVrfSubscription(
                config.vrfCoordinatorAddress, config.vrfSubscriptionId, fundAmount, config.deployerAccount
            );
        }

        // Deploy stablecoin and raffle contracts with all parameters
        vm.startBroadcast(config.deployerAccount);
        staluxCoin = new StaluxCoin();
        stablecoinRaffle = new StablecoinRaffle(
            address(staluxCoin),
            config.entranceFee,
            config.gameDuration,
            config.priceFeedAddress,
            config.vrfCoordinatorAddress,
            config.vrfKeyHash,
            config.vrfSubscriptionId,
            config.vrfCallbackGasLimit
        );
        staluxCoin.transferOwnership(address(stablecoinRaffle));
        vm.stopBroadcast();

        // Add the raffle as consumer to the mock VRF subscription
        vrfInteractions.addVrfConsumer(
            config.vrfCoordinatorAddress, config.vrfSubscriptionId, config.deployerAccount, address(stablecoinRaffle)
        );

        return (staluxCoin, stablecoinRaffle, helperConfig, config);
    }
}
