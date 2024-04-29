// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";

import {MockERC20} from "test/MockERC20.sol";
import {Lending} from "src/contracts/Lending.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployLending is Script {
    address public usdc;
    address public weth;
    address public wdoge;

    function run() external returns (Lending) {
        HelperConfig helperConfig = new HelperConfig();
        (usdc, weth, wdoge) = helperConfig.activeNetworkConfig();

        vm.startBroadcast();
        Lending lending = new Lending();
        lending.setScaledCollateralRatio(usdc, 150 * lending.SCALING_FACTOR() / 100);
        lending.setScaledCollateralRatio(weth, 180 * lending.SCALING_FACTOR() / 100);
        lending.setScaledCollateralRatio(wdoge, 1000 * lending.SCALING_FACTOR() / 100);
        vm.stopBroadcast();

        return lending;
    }
}
