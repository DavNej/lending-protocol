// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {MockERC20} from "test/MockERC20.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address usdc;
        address weth;
        address wdoge;
    }

    NetworkConfig public activeNetworkConfig;

    uint256 public SEPOLIA_CHAIN_ID = 11155111;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getEthereumSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilLocalConfig();
        }
    }

    function getEthereumSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            usdc: 0x2181c6817Cc2429bbf5C50D532D18c7008E6863A,
            weth: 0x5f207d42F869fd1c71d7f0f81a2A67Fc20FF7323,
            wdoge: 0xd929eE587b6d8B6d41C9D5917de12e4ff14BdD7d // does not exist on Sepolia
        });
    }

    function getOrCreateAnvilLocalConfig() public returns (NetworkConfig memory) {
        if (
            activeNetworkConfig.usdc != address(0) || activeNetworkConfig.weth != address(0)
                || activeNetworkConfig.wdoge != address(0)
        ) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockERC20 usdc = new MockERC20("usdc", "usdc");
        MockERC20 weth = new MockERC20("weth", "weth");
        MockERC20 wdoge = new MockERC20("wdoge", "wdoge");
        vm.stopBroadcast();

        return NetworkConfig({usdc: address(usdc), weth: address(weth), wdoge: address(wdoge)});
    }
}
