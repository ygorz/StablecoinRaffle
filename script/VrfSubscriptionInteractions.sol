// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {console2} from "forge-std/console2.sol";

contract VrfSubscriptionInteractions is Script {
    VRFCoordinatorV2_5Mock public vrfCoordinator;

    function run() public {}

    function createVrfSubscription(address vrf, address account) public returns (uint256 subId) {
        // Ensure the block number is not zero to avoid issues with the mock
        if (block.number == 0) {
            vm.roll(block.number + 1);
        }
        vm.startBroadcast(account);
        subId = VRFCoordinatorV2_5Mock(vrf).createSubscription();
        vm.stopBroadcast();
        return subId;
    }

    function addVrfConsumer(address vrf, uint256 subId, address account, address consumer) public {
        vm.startBroadcast(account);
        VRFCoordinatorV2_5Mock(vrf).addConsumer(subId, consumer);
        vm.stopBroadcast();
    }

    function fundVrfSubscription(address vrf, uint256 subId, uint256 amount, address account) public {
        vm.startBroadcast(account);
        VRFCoordinatorV2_5Mock(vrf).fundSubscription(subId, amount);
        vm.stopBroadcast();
    }
}
