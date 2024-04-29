// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ILPToken} from "src/interfaces/ILPToken.sol";

/**
 * @title LPToken
 * @author DavNej
 * @notice Implementation of the interest bearing token for the Lending protocol
 */
contract LPToken is ILPToken, ERC20, Ownable {
    constructor(address _owner, string memory _name, string memory _symbol) ERC20(_name, _symbol) Ownable(_owner) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }
}
