// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol"; // Assuming you have a LinkToken mock in your test directory

abstract contract CodeConstants {
    // Chain IDs
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;

    // Pricefeed Mock Values
    uint8 public constant MOCK_PRICEFEED_DECIMALS = 8; // 8 decimals for price feed
    int256 public constant MOCK_PRICEFEED_INITIAL_ANSWER = 2000e8; // 2000 dollars

    // VRF Mock Values
    uint96 public constant MOCK_BASE_FEE = 0.25 ether;
    uint96 public constant MOCK_GAS_PRICE_LINK = 1e9;
    int256 public constant MOCK_WEI_PER_UNIT_LINK = 4e15;
}

contract HelperConfig is Script, CodeConstants {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 gameDuration;
        address priceFeed;
        address vrfCoordinator;
        bytes32 keyHash;
        uint256 subscriptionId;
        uint32 callbackGasLimit;
        address linkToken;
        address account;
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].vrfCoordinator != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            entranceFee: 2e18, // 2 dollars = 2e18
            gameDuration: 30, // every 30 seconds
            priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            subscriptionId: 9642763729064717391464225939360127295978090115406467302701334453968728686934,
            callbackGasLimit: 500000,
            linkToken: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            account: 0x6D77695FEBa33E2e2FdD435997dC4f9Ba8bFD532
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.vrfCoordinator != address(0)) {
            return localNetworkConfig;
        }

        // Deploy mocks
        vm.startBroadcast();
        MockV3Aggregator priceFeedMock = new MockV3Aggregator(MOCK_PRICEFEED_DECIMALS, MOCK_PRICEFEED_INITIAL_ANSWER);
        VRFCoordinatorV2_5Mock vrfCoordinatorMock =
            new VRFCoordinatorV2_5Mock(MOCK_BASE_FEE, MOCK_GAS_PRICE_LINK, MOCK_WEI_PER_UNIT_LINK);
        LinkToken linkTokenMock = new LinkToken();
        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            entranceFee: 2e18, // 2 dollars = 2e18
            gameDuration: 30, // every 30 seconds
            priceFeed: address(priceFeedMock),
            vrfCoordinator: address(vrfCoordinatorMock),
            // keyhash doesnt matter for local mock testing
            keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            subscriptionId: 0,
            // gas limit also doesnt matter for local mock testing
            callbackGasLimit: 500000,
            linkToken: address(linkTokenMock),
            account: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38 // Default sender address
        });

        return localNetworkConfig;
    }
}
