// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {LPToken} from "src/contracts/LPToken.sol";
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
    mapping(uint256 => Loan) loans;
    uint256 currLoanId = 1;

    event Borrow(address indexed account, uint256 loanId);
    event CollateralAdded(uint256 loanId, uint256 amount);
    event Deposit(address indexed account, address asset, uint256 amount);
    event PoolCreated(address asset, address lpToken);
    event Withdraw(address indexed account, address asset, uint256 amount);

    error Lending__CollateralNotAccepted();
    error Lending__InsufficientCollateral();
    error Lending__InsufficientLPTokens();
    error Lending__LoanNotFound();
    error Lending__NotEnoughLiquidity();
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

    struct Loan {
        address borrower;
        // uint256 createdAt;
        uint256 lastUpdateTimestamp;
        address asset;
        uint256 amount;
        address collateral;
        uint256 collateralAmount;
        uint256 scaledBorrowRate;
        uint256 interestDue;
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
     * @notice Modifier to check if a loan exists
     * @param loanId The ID of the loan to check
     */
    modifier loanExists(uint256 loanId) {
        if (loans[loanId].asset == address(0)) {
            revert Lending__LoanNotFound();
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

    /**
     * @notice Withdraw asset from the lending protocol
     * @param asset The address of the token to withdraw
     * @param amount The amount of token to withdraw
     */
    function withdraw(address asset, uint256 amount) external nonReentrant nonZeroAmount(amount) poolExists(asset) {
        address lpTokenAddress = pools[asset].lpTokenAddress;

        uint256 totalAssetBalance = IERC20(asset).balanceOf(address(this));

        if (amount > totalAssetBalance) {
            revert Lending__NotEnoughLiquidity();
        }

        uint256 totalLPTokens = LPToken(lpTokenAddress).totalSupply();
        uint256 lpTokensToBurn = (amount * totalLPTokens) / totalAssetBalance;

        if (LPToken(lpTokenAddress).balanceOf(msg.sender) < lpTokensToBurn) {
            revert Lending__InsufficientLPTokens();
        }

        LPToken(lpTokenAddress).burn(msg.sender, lpTokensToBurn);
        IERC20(asset).safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, asset, amount);
    }

    /**
     * Borrow an asset from the lending protocol
     * @param asset address of the token to borrow
     * @param amount amount of token to borrow
     * @param collateral address of the token to use as collateral
     * @param collateralAmount amount of collateral to use
     */
    function borrow(address asset, uint256 amount, address collateral, uint256 collateralAmount)
        external
        nonReentrant
        nonZeroAddress(asset)
        nonZeroAddress(collateral)
        nonZeroAmount(amount)
        nonZeroAmount(collateralAmount)
        poolExists(asset)
        returns (uint256 loanId)
    {
        if (scaledCollateralRatios[collateral] == 0) {
            revert Lending__CollateralNotAccepted();
        }

        if (IERC20(asset).balanceOf(address(this)) < amount) {
            revert Lending__NotEnoughLiquidity();
        }

        ///@todo collateral exchange rate to be determined. For now it is set to 1:1
        uint256 scaledCollateralExchangeRate = 100 * SCALING_FACTOR / 100;

        if (collateralAmount * scaledCollateralExchangeRate < amount * scaledCollateralRatios[collateral]) {
            revert Lending__InsufficientCollateral();
        }

        Loan memory loan = Loan({
            borrower: msg.sender,
            lastUpdateTimestamp: block.timestamp,
            asset: asset,
            amount: amount,
            collateral: collateral,
            collateralAmount: collateralAmount,
            ///@dev Fixed borrow rate. Set when loan is taken
            scaledBorrowRate: pools[asset].scaledInterestRate,
            interestDue: 0
        });

        loans[currLoanId] = loan;
        loanId = currLoanId;
        currLoanId++;

        pools[asset].totalBorrowed += amount;

        IERC20(collateral).safeTransferFrom(msg.sender, address(this), collateralAmount);
        IERC20(asset).safeTransfer(msg.sender, amount);

        emit Borrow(msg.sender, loanId);
    }

    /**
     * @notice Increase the collateral amount of a loan
     * @param loanId The ID of the loan to add collateral to
     * @param collateralAmountToAdd The amount of collateral to add
     */
    function addCollateral(uint256 loanId, uint256 collateralAmountToAdd)
        external
        nonReentrant
        nonZeroAmount(collateralAmountToAdd)
        loanExists(loanId)
    {
        Loan memory loan = loans[loanId];

        updateLoanInterest(loanId);

        IERC20(loan.collateral).safeTransferFrom(msg.sender, address(this), collateralAmountToAdd);

        loan.collateralAmount += collateralAmountToAdd;
        loans[loanId] = loan;

        emit CollateralAdded(loanId, collateralAmountToAdd);
    }

    /**
     * @notice Get the scaled collateral ratio for a given asset
     * @param asset address of the token to get the collateral ratio for
     */
    function getScaledCollateralRatio(address asset) external view returns (uint256) {
        return scaledCollateralRatios[asset];
    }

    /**
     * @notice Get the pool for a given asset
     * @param asset address of the token to get the pool for
     */
    function getPool(address asset) external view returns (Pool memory) {
        return pools[asset];
    }

    /**
     * @notice retrieve a loan from its ID
     * @param loanId The ID of the loan to retrieve
     */
    function getLoan(uint256 loanId) external view returns (Loan memory) {
        return loans[loanId];
    }
