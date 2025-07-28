// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

abstract contract CodeConstants {
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ANVIL_CHAIN_ID = 31337;

    uint256 public constant ENTRANCE_FEE = 2e18; // $2 dollars
    uint256 public constant GAME_DURATION = 30; // 30 seconds

    uint8 public constant MOCK_PRICEFEED_DECIMALS = 8; // to match what chainlink does
    int256 public constant MOCK_PRICEFEED_INITIAL_PRICE = 2000e8; // 2000 dollars

    uint96 public constant MOCK_VRF_BASE_FEE = 0.25 ether;
    uint96 public constant MOCK_VRF_GAS_PRICE = 1e9;
    int256 public constant MOCK_VRF_WEI_PER_UNIT_LINK = 4e15; // 4e15 wei per LINK

    uint32 public constant VRF_MAX_GAS_LIMIT = 25e5;
}

contract HelperConfig is Script, CodeConstants {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 gameDuration;
        address priceFeedAddress;
        address vrfCoordinatorAddress;
        bytes32 vrfKeyHash;
        uint256 vrfSubscriptionId;
        uint32 vrfCallbackGasLimit;
        address linkToken;
        address deployerAccount;
    }

    NetworkConfig public localConfig;

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (chainId == ETH_SEPOLIA_CHAIN_ID) {
            return getSepoliaEthConfiguration();
        } else if (chainId == ANVIL_CHAIN_ID) {
            return getOrCreateAnvilConfiguration();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getSepoliaEthConfiguration() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            entranceFee: ENTRANCE_FEE,
            gameDuration: GAME_DURATION,
            // Price feed from: https://docs.chain.link/data-feeds/price-feeds/addresses
            priceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            // Vrf info from: https://docs.chain.link/vrf/v2-5/supported-networks
            vrfCoordinatorAddress: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            vrfKeyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            vrfSubscriptionId: 9642763729064717391464225939360127295978090115406467302701334453968728686934,
            vrfCallbackGasLimit: VRF_MAX_GAS_LIMIT,
            linkToken: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            deployerAccount: 0x6D77695FEBa33E2e2FdD435997dC4f9Ba8bFD532 // burner metamask
        });
    }

    function getOrCreateAnvilConfiguration() public returns (NetworkConfig memory) {
        if (localConfig.vrfCoordinatorAddress != address(0)) {
            return localConfig;
        } else {
            vm.startBroadcast();
            MockV3Aggregator mockPriceFeed = new MockV3Aggregator(MOCK_PRICEFEED_DECIMALS, MOCK_PRICEFEED_INITIAL_PRICE);

            VRFCoordinatorV2_5Mock mockVrfCoordinator =
                new VRFCoordinatorV2_5Mock(MOCK_VRF_BASE_FEE, MOCK_VRF_GAS_PRICE, MOCK_VRF_WEI_PER_UNIT_LINK);

            LinkToken mockLinkToken = new LinkToken();
            vm.stopBroadcast();

            localConfig = NetworkConfig({
                entranceFee: ENTRANCE_FEE,
                gameDuration: GAME_DURATION,
                priceFeedAddress: address(mockPriceFeed),
                vrfCoordinatorAddress: address(mockVrfCoordinator),
                vrfKeyHash: 0, // doesn't matter for mock
                vrfSubscriptionId: 0, // will be updated during mock subscription creation
                vrfCallbackGasLimit: VRF_MAX_GAS_LIMIT,
                linkToken: address(mockLinkToken),
                deployerAccount: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38 //default foundry sender
            });

            return localConfig;
        }
    }
}
