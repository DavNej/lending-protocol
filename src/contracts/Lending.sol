// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {LPTokenFactory} from "src/contracts/LPTokenFactory.sol";

/**
 * @title Lending
 * @author DavNej
 * @dev A lending protocol that allows users to deposit assets and borrow other assets using collateral
 *
 */
contract Lending is Ownable, ReentrancyGuard {
    uint256 public constant SCALING_FACTOR = 1e18;
    ///@dev default interest rate 2%
    uint256 public constant DEFAULT_SCALED_INTEREST_RATE = 2 * SCALING_FACTOR / 100;

    LPTokenFactory lpTokenfactory;

    mapping(address asset => uint256 ratio) private scaledCollateralRatios;
    mapping(address asset => Pool pool) private pools;
    event PoolCreated(address asset, address lpToken);
    error Lending__PoolAlreadyExists();
    error Lending__PoolNotFound();
    error Lending__ZeroAddress();

    struct Pool {
        address lpTokenAddress;
        uint256 lastInterestUpdateTime;
        uint256 scaledInterestRate;
        uint256 totalBorrowed;
    }

    /**
     * @notice Modifier to check if a pool exists for a given asset
     * @param asset The address of the asset to check
     */
    modifier poolExists(address asset) {
        if (pools[asset].lpTokenAddress == address(0)) {
            revert Lending__PoolNotFound();
        }
        _;
    }

    /**
     * @notice Modifier to check if an address is non-zero
     * @param _address The address to check
     */
    modifier nonZeroAddress(address _address) {
        if (_address == address(0)) {
            revert Lending__ZeroAddress();
        }
        _;
    }

    constructor() Ownable(msg.sender) {
        lpTokenfactory = new LPTokenFactory();
    }

    /**
     * @notice Create a new pool for a given asset
     * @param asset The address of the token to create a pool for
     */
    function createPool(address asset) external nonZeroAddress(asset) returns (address) {
        if (pools[asset].lpTokenAddress != address(0)) {
            revert Lending__PoolAlreadyExists();
        }

        string memory name = string.concat("lp", ERC20(asset).name());
        string memory symbol = string.concat("lp", ERC20(asset).symbol());
        address lpTokenAddress = lpTokenfactory.createLPToken(name, symbol);

        pools[asset] = Pool({
            lpTokenAddress: lpTokenAddress,
            lastInterestUpdateTime: block.timestamp,
            scaledInterestRate: DEFAULT_SCALED_INTEREST_RATE,
            totalBorrowed: 0
        });

        emit PoolCreated(asset, lpTokenAddress);
        return lpTokenAddress;
    }

    /**
     * @notice Set the collateral ratio for a given asset
     * @param asset address of the token to set the ratio for
     * @param ratio the ratio value in percent (multiplied by the SCALING_FACTOR)
     */
    function setScaledCollateralRatio(address asset, uint256 ratio) external onlyOwner nonZeroAddress(asset) {
        scaledCollateralRatios[asset] = ratio;
    }

}
