// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {Lending} from "src/contracts/Lending.sol";

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
}
