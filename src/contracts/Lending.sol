// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {LPTokenFactory} from "src/contracts/LPTokenFactory.sol";
import {ILPToken} from "src/interfaces/ILPToken.sol";

/**
 * @title Lending
 * @author DavNej
 * @dev A lending protocol that allows users to deposit assets and borrow other assets using collateral
 *
 */
contract Lending is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant SCALING_FACTOR = 1e18;
    ///@dev default interest rate 2%
    uint256 public constant DEFAULT_SCALED_INTEREST_RATE = 2 * SCALING_FACTOR / 100;

    LPTokenFactory lpTokenfactory;

    mapping(address asset => uint256 ratio) private scaledCollateralRatios;
    mapping(address asset => Pool pool) private pools;
    event Deposit(address indexed account, address asset, uint256 amount);
    event PoolCreated(address asset, address lpToken);
    error Lending__PoolAlreadyExists();
    error Lending__PoolNotFound();
    error Lending__ZeroAddress();
    error Lending__ZeroAmount();

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

    /**
     * @notice Modifier to check if an amount is non-zero
     * @param amount The amount to check
     */
    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) {
            revert Lending__ZeroAmount();
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

    /**
     * @notice Supply token to the lending protocol
     * @param asset The address of the asset to deposit
     * @param amount The amount of token to deposit
     * @return The amount of LP Tokens minted
     */
    function deposit(address asset, uint256 amount)
        external
        nonReentrant
        nonZeroAddress(asset)
        nonZeroAmount(amount)
        poolExists(asset)
        returns (uint256)
    {
        address lpTokenAddress = pools[asset].lpTokenAddress;

        updatePoolInterestRate(asset);

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        uint256 scaledExchangeRate = 100 * SCALING_FACTOR / 100;

        /**
         * @todo CARE MUST BE TAKEN HERE => number of decimals of different tokens
         */
        if (ILPToken(lpTokenAddress).totalSupply() > 0) {
            scaledExchangeRate =
                IERC20(asset).balanceOf(address(this)) * SCALING_FACTOR / ILPToken(lpTokenAddress).totalSupply();
        }

        uint256 lpTokensToMint = amount * SCALING_FACTOR / scaledExchangeRate;

        ILPToken(lpTokenAddress).mint(msg.sender, lpTokensToMint);

        emit Deposit(msg.sender, asset, amount);

        return lpTokensToMint;
    }
