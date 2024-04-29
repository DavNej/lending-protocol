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

    /**
     * ==================== Type declarations ====================
     */
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
     * ==================== State variables ====================
     */
    uint256 public constant SCALING_FACTOR = 1e18;
    ///@dev default interest rate 2%
    uint256 public constant DEFAULT_SCALED_INTEREST_RATE = 2 * SCALING_FACTOR / 100;

    LPTokenFactory lpTokenfactory;

    mapping(address asset => uint256 ratio) private scaledCollateralRatios;
    mapping(address asset => Pool pool) private pools;
    mapping(uint256 => Loan) loans;
    uint256 currLoanId = 1;

    /**
     * ==================== Events ====================
     */
    event Borrow(address indexed account, uint256 loanId);
    event CollateralAdded(uint256 loanId, uint256 amount);
    event CollateralRemoved(uint256 loanId, uint256 amount);
    event Deposit(address indexed account, address asset, uint256 amount);
    event Liquidated(address indexed liquidater, uint256 loanId);
    event LoanClosed(uint256 loanId);
    event PoolCreated(address asset, address lpToken);
    event Repay(uint256 loanId, uint256 amount);
    event Withdraw(address indexed account, address asset, uint256 amount);

    /**
     * ==================== Errors ====================
     */
    error Lending__CollateralNotAccepted();
    error Lending__InsufficientCollateral();
    error Lending__InsufficientLPTokens();
    error Lending__LiquidationForbidden();
    error Lending__LoanNotFound();
    error Lending__NotEnoughLiquidity();
    error Lending__PoolAlreadyExists();
    error Lending__PoolNotFound();
    error Lending__ZeroAddress();
    error Lending__ZeroAmount();

    /**
     * ==================== Modifiers ====================
     */

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

    /**
     * ==================== Constructor ====================
     */
    constructor() Ownable(msg.sender) {
        lpTokenfactory = new LPTokenFactory();
    }

    /**
     * ==================== External Functions ====================
     */

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

        updatePoolInterestRate(asset);

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

        updatePoolInterestRate(asset);

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
     * @notice Decrease the collateral amount of a loan
     * @param loanId The ID of the loan to remove collateral from
     * @param collateralAmountToRemove The amount of collateral to remove
     */
    function removeCollateral(uint256 loanId, uint256 collateralAmountToRemove)
        external
        nonReentrant
        nonZeroAmount(collateralAmountToRemove)
        loanExists(loanId)
    {
        Loan memory loan = loans[loanId];

        updateLoanInterest(loanId);

        ///@todo collateral exchange rate to be determined. For now it is set to 1:1
        uint256 scaledCollateralExchangeRate = 100 * SCALING_FACTOR / 100;

        if (
            (loan.collateralAmount - collateralAmountToRemove) * scaledCollateralExchangeRate
                < (loan.amount + loan.interestDue) * scaledCollateralRatios[loan.collateral]
        ) {
            revert Lending__InsufficientCollateral();
        }

        IERC20(loan.collateral).safeTransfer(msg.sender, collateralAmountToRemove);

        loan.collateralAmount -= collateralAmountToRemove;
        loans[loanId] = loan;

        emit CollateralRemoved(loanId, collateralAmountToRemove);
    }

    function repay(uint256 loanId, uint256 amount) external nonReentrant nonZeroAmount(amount) loanExists(loanId) {
        Loan memory loan = loans[loanId];

        ///@todo user should call updateLoanInterest in order to know the total amount to fully repay the loan. UX should be improved !
        updateLoanInterest(loanId);

        if (amount >= loan.amount + loan.interestDue) {
            IERC20(loan.asset).safeTransferFrom(msg.sender, address(this), loan.amount + loan.interestDue);

            uint256 collateralAmountToTransfer = loan.collateralAmount;

            pools[loan.asset].totalBorrowed -= loan.amount;

            loan.interestDue = 0;
            loan.amount = 0;
            loan.collateralAmount = 0;

            loans[loanId] = loan;

            IERC20(loan.collateral).safeTransfer(msg.sender, collateralAmountToTransfer);

            emit Repay(loanId, amount);
            emit LoanClosed(loanId);
        } else if (amount > loan.interestDue) {
            IERC20(loan.asset).safeTransferFrom(msg.sender, address(this), amount);

            pools[loan.asset].totalBorrowed -= amount - loan.interestDue;

            loan.amount -= amount - loan.interestDue;
            loan.interestDue = 0;
            loans[loanId] = loan;

            emit Repay(loanId, amount);
        } else {
            IERC20(loan.asset).safeTransferFrom(msg.sender, address(this), amount);

            loan.interestDue -= amount;
            loans[loanId] = loan;

            emit Repay(loanId, amount);
        }
    }

    /**
     * @notice Liquidate a loan
     * @param loanId The ID of the loan to liquidate
     */
    function liquidate(uint256 loanId) external nonReentrant loanExists(loanId) {
        Loan memory loan = loans[loanId];

        updateLoanInterest(loanId);

        ///@todo collateral exchange rate to be determined. For now it is set to 1:1
        uint256 scaledCollateralExchangeRate = 100 * SCALING_FACTOR / 100;

        if (
            loan.collateralAmount * scaledCollateralExchangeRate
                > (loan.amount + loan.interestDue) * scaledCollateralRatios[loan.collateral]
        ) {
            revert Lending__LiquidationForbidden();
        }

        IERC20(loan.asset).safeTransferFrom(msg.sender, address(this), loan.amount + loan.interestDue);

        uint256 collateralAmountToTransfer = loan.collateralAmount;

        pools[loan.asset].totalBorrowed -= loan.amount;

        loan.interestDue = 0;
        loan.amount = 0;
        loan.collateralAmount = 0;

        loans[loanId] = loan;

        IERC20(loan.collateral).safeTransfer(msg.sender, collateralAmountToTransfer);

        emit Liquidated(msg.sender, loanId);
    }

    /**
     * ==================== Public Functions ====================
     */

    /**
     * Calculate interest owed on a loan since its last update and update the values. Interest calculation is linear with a day basis
     * @param loanId The ID of the loan to calculate interest for
     * @return The amount of interest due
     */
    function updateLoanInterest(uint256 loanId) public loanExists(loanId) returns (uint256) {
        Loan memory loan = loans[loanId];

        uint256 timeElapsedInDays = (block.timestamp - loan.lastUpdateTimestamp) / 1 days;

        if (timeElapsedInDays == 0) {
            return 0;
        }

        loan.interestDue = loan.amount * loan.scaledBorrowRate * timeElapsedInDays / (SCALING_FACTOR * 365);
        loan.lastUpdateTimestamp = block.timestamp;

        loans[loanId] = loan;

        return loan.interestDue;
    }

    /**
     * @notice Update the interest rate for a given asset pool based on the pool's utilization rate.
     * @param asset The address of the asset pool
     */
    function updatePoolInterestRate(address asset) public poolExists(asset) returns (uint256) {
        if (pools[asset].lastInterestUpdateTime == block.timestamp) {
            return pools[asset].scaledInterestRate;
        }

        uint256 totalBorrowed = pools[asset].totalBorrowed;
        uint256 totalDeposits = IERC20(asset).balanceOf(address(this)) + totalBorrowed;

        if (totalDeposits == 0) {
            pools[asset].scaledInterestRate = DEFAULT_SCALED_INTEREST_RATE;
            return pools[asset].scaledInterestRate;
        }

        uint256 scaledUtilizationRate = (totalBorrowed * SCALING_FACTOR) / totalDeposits;

        uint256 lowerThreshold = 30 * SCALING_FACTOR / 100;
        uint256 higherThreshold = 80 * SCALING_FACTOR / 100;

        uint256 lowAdjustmentRate = 10 * SCALING_FACTOR / 100;
        uint256 highAdjustmentRate = 20 * SCALING_FACTOR / 100;

        if (scaledUtilizationRate < lowerThreshold) {
            pools[asset].scaledInterestRate =
                (pools[asset].scaledInterestRate * (SCALING_FACTOR - highAdjustmentRate)) / SCALING_FACTOR;
        } else if (scaledUtilizationRate > higherThreshold) {
            pools[asset].scaledInterestRate =
                (pools[asset].scaledInterestRate * (SCALING_FACTOR + highAdjustmentRate)) / SCALING_FACTOR;
        } else {
            pools[asset].scaledInterestRate =
                (pools[asset].scaledInterestRate * (SCALING_FACTOR + lowAdjustmentRate)) / SCALING_FACTOR;
        }

        pools[asset].lastInterestUpdateTime = block.timestamp;

        return pools[asset].scaledInterestRate;
    }

    /**
     * ==================== View Functions ====================
     */

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
}
