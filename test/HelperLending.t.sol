// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Lending} from "src/contracts/Lending.sol";
import {ILPToken} from "src/interfaces/ILPToken.sol";

abstract contract HelperLending is Test {
    address s_usdc;
    address s_weth;
    address s_wdoge;
    Lending s_lending;

    address s_deployer;
    address ALICE = makeAddr("alice");
    address BOB = makeAddr("bob");
    address CHARLES = makeAddr("charles");

    uint256 constant INITIAL_ALICE_BALANCE = 1000 ether;
    uint256 constant INITIAL_BOB_BALANCE = 1000 ether;
    uint256 constant INITIAL_CHARLES_BALANCE = 1000 ether;

    function fundUserWithToken(address user, address token, uint256 amount) internal {
        vm.startPrank(s_deployer);
        IERC20(token).transfer(user, amount);
        vm.stopPrank();

        assertEq(IERC20(token).balanceOf(user), amount, "fundUserWithToken helper: User balance");
    }

    function depositFor(address user, address asset, uint256 amount) internal {
        vm.startPrank(user);

        address lpTokenAddress = s_lending.getPool(asset).lpTokenAddress;

        if (lpTokenAddress == address(0)) {
            lpTokenAddress = s_lending.createPool(asset);
        }

        IERC20(asset).approve(address(s_lending), amount);

        uint256 minted = s_lending.deposit(asset, amount);
        vm.stopPrank();

        assertEq(ILPToken(lpTokenAddress).balanceOf(user), minted, "depositFor helper: LPToken balance");
    }

    function withdrawFor(address user, address asset, uint256 amount) public {
        vm.startPrank(user);

        uint256 userBalance = IERC20(asset).balanceOf(user);

        ILPToken lpToken = ILPToken(s_lending.getPool(asset).lpTokenAddress);
        lpToken.approve(address(s_lending), amount);

        s_lending.withdraw(asset, amount);
        vm.stopPrank();

        assertEq(IERC20(asset).balanceOf(user), userBalance + amount, "withdrawFor helper: Asset balance");
    }
}
