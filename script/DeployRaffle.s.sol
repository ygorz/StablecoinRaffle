// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {StaluxCoin} from "src/StaluxCoin.sol";
import {StablecoinRaffle} from "src/StablecoinRaffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";

contract DeployRaffle is Script {
    function run() external {
        deployStablecoinRaffle();
    }

    function deployStablecoinRaffle() public returns (StaluxCoin, StablecoinRaffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        if (config.subscriptionId == 0) {
            // Create a subscription
            CreateSubscription createSubscription = new CreateSubscription();
            //vm.roll(block.number + 1);
            (config.subscriptionId, config.vrfCoordinator) =
                createSubscription.createSubscription(config.vrfCoordinator, config.account);

            // Fund the subscription
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                config.vrfCoordinator, config.subscriptionId, config.linkToken, config.account
            );
        }

        vm.startBroadcast(config.account);
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

        // Add a consumer, we don't use a broadcast because it's in the addconsumer script
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(address(stablecoinRaffle), config.vrfCoordinator, config.subscriptionId, config.account);

        return (staluxCoin, stablecoinRaffle, helperConfig);
    }
}
