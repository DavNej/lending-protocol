// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;
import {DeployLending} from "script/DeployLending.s.sol";
import {Lending} from "src/contracts/Lending.sol";
import {ILPTokenFactory} from "src/interfaces/ILPTokenFactory.sol";
import {HelperLending} from "./HelperLending.t.sol";

contract LendingTest is HelperLending {
    function setUp() public {
        DeployLending deployLending = new DeployLending();
        s_lending = deployLending.run();
        s_usdc = deployLending.usdc();
        s_weth = deployLending.weth();
        s_wdoge = deployLending.wdoge();
        s_deployer = msg.sender;
    }

    function testSetScaledCollateralRatio() public {
        uint256 scaledRatio = 180 * s_lending.SCALING_FACTOR() / 100;

        vm.startPrank(s_deployer);
        s_lending.setScaledCollateralRatio(s_usdc, scaledRatio);
        vm.stopPrank();
        assertEq(s_lending.getScaledCollateralRatio(s_usdc), scaledRatio, "Failed to set collateral ratio");
    }

    function testCreatePool__ZeroAddress() public {
        vm.expectRevert(Lending.Lending__ZeroAddress.selector);
        s_lending.createPool(address(0));
    }

    function testCreatePool__AlreadyExists() public {
        s_lending.createPool(s_weth);

        vm.expectRevert(Lending.Lending__PoolAlreadyExists.selector);
        s_lending.createPool(s_weth);
    }

    function testCreatePool__Success() public {
        address asset = s_usdc;

        vm.expectEmit(true, true, true, false);
        emit Lending.PoolCreated(asset, address(0));
        emit ILPTokenFactory.CreateLPToken(address(0));
        address lpTokenAddress = s_lending.createPool(asset);

        assertFalse(lpTokenAddress == address(0), "LPToken creation failed");

        assertEq(s_lending.getPool(asset).lpTokenAddress, lpTokenAddress, "LPToken address not set");
        assertEq(s_lending.getPool(asset).lastInterestUpdateTime, block.timestamp, "Last interest update time not set");
        assertEq(s_lending.getPool(asset).totalBorrowed, 0, "Total borrowed not set");
        assertEq(
            s_lending.getPool(asset).scaledInterestRate,
            s_lending.DEFAULT_SCALED_INTEREST_RATE(),
            "Interest rate not set"
        );
    }
}
