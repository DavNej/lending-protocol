// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ILPTokenFactory} from "src/interfaces/ILPTokenFactory.sol";
import {LPToken} from "./LPToken.sol";

/**
 * @title LPTokenFactory
 * @author DavNej
 * @notice Implementation of the LP token factory responsible for creating LP tokens
 */
contract LPTokenFactory is ILPTokenFactory, Ownable {
    address[] public lpTokens;

    constructor() Ownable(msg.sender) {}

    function createLPToken(string calldata _name, string calldata _symbol) external onlyOwner returns (address) {
        LPToken token = new LPToken(owner(), _name, _symbol);
        lpTokens.push(address(token));

        emit CreateLPToken(address(token));

        return address(token);
    }
}
