// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @dev Interface of LPToken
 * Defines an interface for "ERC20-like" tokens
 */
interface ILPToken is IERC20 {
    function mint(address to, uint256 amount) external;

    function burn(address account, uint256 amount) external;
}
