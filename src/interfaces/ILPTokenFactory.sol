// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @dev Interface of LPTokenFactory
 */
interface ILPTokenFactory {
    event CreateLPToken(address lpTokenAddress);

    function createLPToken(string calldata _name, string calldata _symbol) external returns (address);
}
