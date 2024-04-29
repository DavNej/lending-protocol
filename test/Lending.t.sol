// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {DeployLending} from "script/DeployLending.s.sol";
import {Lending} from "src/contracts/Lending.sol";
import {ILPToken} from "src/interfaces/ILPToken.sol";
import {ILPTokenFactory} from "src/interfaces/ILPTokenFactory.sol";
import {HelperLending} from "./HelperLending.t.sol";

contract LendingTest is HelperLending {
    function setUp() public {
        DeployLending deployLending = new DeployLending();
        s_lending = deployLending.run();
        s_usdc = deployLending.usdc();
        s_weth = deployLending.weth();
        s_wdoge = deployLending.wdoge();
        s_deployer = msg.sender;
    }

    function testSetScaledCollateralRatio() public {
        uint256 scaledRatio = 180 * s_lending.SCALING_FACTOR() / 100;

        vm.startPrank(s_deployer);
        s_lending.setScaledCollateralRatio(s_usdc, scaledRatio);
        vm.stopPrank();
        assertEq(s_lending.getScaledCollateralRatio(s_usdc), scaledRatio, "Failed to set collateral ratio");
    }

    function testCreatePool__ZeroAddress() public {
        vm.expectRevert(Lending.Lending__ZeroAddress.selector);
        s_lending.createPool(address(0));
    }

    function testCreatePool__AlreadyExists() public {
        s_lending.createPool(s_weth);

        vm.expectRevert(Lending.Lending__PoolAlreadyExists.selector);
        s_lending.createPool(s_weth);
    }

    function testCreatePool__Success() public {
        address asset = s_usdc;

        vm.expectEmit(true, true, true, false);
        emit Lending.PoolCreated(asset, address(0));
        emit ILPTokenFactory.CreateLPToken(address(0));
        address lpTokenAddress = s_lending.createPool(asset);

        assertFalse(lpTokenAddress == address(0), "LPToken creation failed");

        assertEq(s_lending.getPool(asset).lpTokenAddress, lpTokenAddress, "LPToken address not set");
        assertEq(s_lending.getPool(asset).lastInterestUpdateTime, block.timestamp, "Last interest update time not set");
        assertEq(s_lending.getPool(asset).totalBorrowed, 0, "Total borrowed not set");
        assertEq(
            s_lending.getPool(asset).scaledInterestRate,
            s_lending.DEFAULT_SCALED_INTEREST_RATE(),
            "Interest rate not set"
        );
    }

    function testDeposit__ZeroAddress() public {
        vm.expectRevert(Lending.Lending__ZeroAddress.selector);
        s_lending.deposit(address(0), 100 ether);
    }

    function testDeposit__ZeroAmount() public {
        vm.expectRevert(Lending.Lending__ZeroAmount.selector);
        s_lending.deposit(s_weth, 0 ether);
    }

    function testDeposit__PoolNotFound() public {
        address assetToDeposit = s_usdc;
        uint256 amountToDeposit = 100 ether;

        fundUserWithToken(ALICE, assetToDeposit, INITIAL_ALICE_BALANCE);

        vm.startPrank(ALICE);
        IERC20(assetToDeposit).approve(address(s_lending), amountToDeposit);
        vm.expectRevert(Lending.Lending__PoolNotFound.selector);
        s_lending.deposit(assetToDeposit, amountToDeposit);
        vm.stopPrank();
    }

    function testDeposit__Success() public {
        address assetToDeposit = s_usdc;
        uint256 amountToDeposit = 100 ether;

        fundUserWithToken(ALICE, assetToDeposit, INITIAL_ALICE_BALANCE);
        address lpToken = s_lending.createPool(assetToDeposit);

        vm.startPrank(ALICE);
        IERC20(assetToDeposit).approve(address(s_lending), amountToDeposit);
        vm.expectEmit(true, true, true, true);
        emit Lending.Deposit(ALICE, assetToDeposit, amountToDeposit);
        uint256 minted = s_lending.deposit(assetToDeposit, amountToDeposit);
        vm.stopPrank();

        assertEq(
            IERC20(assetToDeposit).balanceOf(ALICE),
            INITIAL_ALICE_BALANCE - amountToDeposit,
            "Asset to deposit balance not updated"
        );
        assertEq(ILPToken(lpToken).balanceOf(ALICE), minted, "LPToken balance not updated");
        assertEq(ILPToken(lpToken).totalSupply(), minted, "LPToken total supply not updated");
    }

    function testWithdraw__PoolNotFound() public {
        vm.expectRevert(Lending.Lending__PoolNotFound.selector);
        s_lending.withdraw(s_usdc, 10 ether);
    }

    function testWithdraw__ZeroAmount() public {
        address asset = s_usdc;
        uint256 amountToDeposit = 10 ether;
        uint256 amountToWithdraw = 0 ether;

        fundUserWithToken(ALICE, asset, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, asset, amountToDeposit);

        vm.startPrank(ALICE);
        vm.expectRevert(Lending.Lending__ZeroAmount.selector);
        s_lending.withdraw(asset, amountToWithdraw);
        vm.stopPrank();
    }

    function testWithdraw__NotEnoughLiquidity() public {
        address asset = s_usdc;
        uint256 amountToDeposit = 10 ether;
        uint256 amountToWithdraw = 100 ether;

        fundUserWithToken(ALICE, asset, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, asset, amountToDeposit);

        vm.startPrank(ALICE);
        ILPToken lpToken = ILPToken(s_lending.getPool(asset).lpTokenAddress);
        lpToken.approve(address(s_lending), amountToWithdraw);

        vm.expectRevert(Lending.Lending__NotEnoughLiquidity.selector);
        s_lending.withdraw(asset, amountToWithdraw);
        vm.stopPrank();
    }

    function testWithdraw__InsufficientLPTokens() public {
        address asset = s_usdc;
        uint256 amountToDeposit = 100 ether;
        uint256 amountToWithdraw = 10 ether;

        fundUserWithToken(ALICE, asset, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, asset, amountToDeposit);

        vm.startPrank(BOB);
        ILPToken lpToken = ILPToken(s_lending.getPool(asset).lpTokenAddress);
        lpToken.approve(address(s_lending), amountToWithdraw);

        vm.expectRevert(Lending.Lending__InsufficientLPTokens.selector);
        s_lending.withdraw(asset, amountToWithdraw);
        vm.stopPrank();
    }

    function testWithdraw__Success() public {
        address asset = s_usdc;
        uint256 amountToDeposit = 100 ether;
        uint256 amountToWithdraw = 10 ether;

        fundUserWithToken(ALICE, asset, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, asset, amountToDeposit);

        uint256 aliceTokenBalance = INITIAL_ALICE_BALANCE - amountToDeposit;

        vm.startPrank(ALICE);
        ILPToken lpToken = ILPToken(s_lending.getPool(asset).lpTokenAddress);
        lpToken.approve(address(s_lending), amountToWithdraw);

        vm.expectEmit(true, true, true, true);
        emit Lending.Withdraw(ALICE, asset, amountToWithdraw);
        s_lending.withdraw(asset, amountToWithdraw);
        vm.stopPrank();

        aliceTokenBalance += amountToWithdraw;

        assertEq(IERC20(asset).balanceOf(ALICE), aliceTokenBalance, "Asset balance not updated");
        assertEq(lpToken.balanceOf(ALICE), amountToDeposit - amountToWithdraw, "LPToken balance not updated");
        assertEq(lpToken.totalSupply(), amountToDeposit - amountToWithdraw, "LPToken total supply not updated");
    }

    function testBorrow__ZeroAmount() public {
        address assetToBorrow = s_usdc;
        uint256 amountToDeposit = 10 ether;
        uint256 amountToBorrow = 0 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 10 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToDeposit);

        vm.startPrank(BOB);
        vm.expectRevert(Lending.Lending__ZeroAmount.selector);
        s_lending.borrow(assetToBorrow, amountToBorrow, collateral, collateralAmount);
        vm.stopPrank();
    }

    function testBorrow__PoolNotFound() public {
        address assetToBorrow = s_usdc;
        uint256 amountToDeposit = 10 ether;
        uint256 amountToBorrow = 10 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 10 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToDeposit);

        vm.startPrank(BOB);
        vm.expectRevert(Lending.Lending__PoolNotFound.selector);
        s_lending.borrow(s_wdoge, amountToBorrow, collateral, collateralAmount);
        vm.stopPrank();
    }

    function testBorrow__NotEnoughLiquidity() public {
        address assetToBorrow = s_usdc;
        uint256 amountToDeposit = 10 ether;
        uint256 amountToBorrow = 100 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 200 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToDeposit);

        vm.startPrank(BOB);
        ILPToken lpToken = ILPToken(s_lending.getPool(s_usdc).lpTokenAddress);
        lpToken.approve(address(s_lending), amountToBorrow);

        vm.expectRevert(Lending.Lending__NotEnoughLiquidity.selector);
        s_lending.borrow(assetToBorrow, amountToBorrow, collateral, collateralAmount);
        vm.stopPrank();
    }

    function testBorrow__Success() public {
        address assetToBorrow = s_usdc;
        uint256 amountToBorrow = 10 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 20 ether;
        uint256 assetAmountInContract = 100 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);
        depositFor(ALICE, assetToBorrow, assetAmountInContract);

        vm.startPrank(BOB);
        IERC20(collateral).approve(address(s_lending), collateralAmount);

        uint256 expectedLoanId = 1;
        vm.expectEmit(true, true, true, true);
        emit Lending.Borrow(BOB, expectedLoanId);
        uint256 loanId = s_lending.borrow(assetToBorrow, amountToBorrow, collateral, collateralAmount);
        vm.stopPrank();

        assertEq(expectedLoanId, loanId);

        assertEq(IERC20(assetToBorrow).balanceOf(BOB), amountToBorrow, "User assetToBorrow balance not updated");
        assertEq(
            IERC20(assetToBorrow).balanceOf(address(s_lending)),
            assetAmountInContract - amountToBorrow,
            "Contract assetToBorrow balance not updated"
        );
        assertEq(
            IERC20(collateral).balanceOf(BOB),
            INITIAL_BOB_BALANCE - collateralAmount,
            "User collateral balance not updated"
        );
        assertEq(
            IERC20(collateral).balanceOf(address(s_lending)),
            collateralAmount,
            "Contract collateral balance not updated"
        );

        assertEq(s_lending.getLoan(expectedLoanId).borrower, BOB);
        assertEq(s_lending.getLoan(expectedLoanId).lastUpdateTimestamp, block.timestamp);
        assertEq(s_lending.getLoan(expectedLoanId).asset, assetToBorrow);
        assertEq(s_lending.getLoan(expectedLoanId).amount, amountToBorrow);
        assertEq(s_lending.getLoan(expectedLoanId).collateral, collateral);
        assertEq(s_lending.getLoan(expectedLoanId).collateralAmount, collateralAmount);
        assertEq(
            s_lending.getLoan(expectedLoanId).scaledBorrowRate, s_lending.getPool(assetToBorrow).scaledInterestRate
        );
        assertEq(s_lending.getPool(assetToBorrow).totalBorrowed, amountToBorrow);
    }

    function testAddCollateral__ZeroAmount() public {
        address assetToBorrow = s_usdc;
        uint256 amountToDeposit = 100 ether;
        uint256 amountToBorrow = 50 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 100 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToDeposit);
        fundUserWithToken(BOB, collateral, INITIAL_ALICE_BALANCE);
        uint256 loanId = borrowFor(BOB, assetToBorrow, amountToBorrow, collateral, collateralAmount);

        vm.startPrank(BOB);
        vm.expectRevert(Lending.Lending__ZeroAmount.selector);
        s_lending.addCollateral(loanId, 0);
        vm.stopPrank();
    }

    function testAddCollateral__LoanNotFound() public {
        vm.startPrank(BOB);
        vm.expectRevert(Lending.Lending__LoanNotFound.selector);
        s_lending.addCollateral(7, 10 ether);
        vm.stopPrank();
    }

    function testAddCollateral__Success() public {
        address assetToBorrow = s_usdc;
        uint256 amountToDeposit = 100 ether;
        uint256 amountToBorrow = 50 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 100 ether;
        uint256 collateralAmountToAdd = 5 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToDeposit);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);

        uint256 loanId = borrowFor(BOB, assetToBorrow, amountToBorrow, collateral, collateralAmount);

        vm.startPrank(BOB);
        IERC20(collateral).approve(address(s_lending), collateralAmountToAdd);
        vm.expectEmit(true, true, true, true);
        emit Lending.CollateralAdded(loanId, collateralAmountToAdd);
        s_lending.addCollateral(loanId, collateralAmountToAdd);
        vm.stopPrank();

        assertEq(
            IERC20(collateral).balanceOf(address(s_lending)),
            collateralAmount + collateralAmountToAdd,
            "Contract collateral balance not updated"
        );
        assertEq(
            IERC20(collateral).balanceOf(BOB),
            INITIAL_BOB_BALANCE - collateralAmount - collateralAmountToAdd,
            "User collateral balance not updated"
        );
        assertEq(
            s_lending.getLoan(loanId).collateralAmount,
            collateralAmount + collateralAmountToAdd,
            "Loan collateral amount not updated"
        );
    }

    function testRemoveCollateral__ZeroAmount() public {
        address assetToBorrow = s_usdc;
        uint256 amountToDeposit = 100 ether;
        uint256 amountToBorrow = 50 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 100 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToDeposit);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);

        uint256 loanId = borrowFor(BOB, assetToBorrow, amountToBorrow, collateral, collateralAmount);

        vm.startPrank(BOB);
        vm.expectRevert(Lending.Lending__ZeroAmount.selector);
        s_lending.addCollateral(loanId, 0);
        vm.stopPrank();
    }

    function testRemoveCollateral__LoanNotFound() public {
        vm.startPrank(BOB);
        vm.expectRevert(Lending.Lending__LoanNotFound.selector);
        s_lending.addCollateral(7, 10 ether);
        vm.stopPrank();
    }

    function testRemoveCollateral__InsufficientCollateral() public {
        address assetToBorrow = s_usdc;
        uint256 amountToDeposit = 100 ether;
        uint256 amountToBorrow = 50 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 100 ether;
        uint256 collateralAmountToRemove = 90 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToDeposit);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);

        uint256 loanId = borrowFor(BOB, assetToBorrow, amountToBorrow, collateral, collateralAmount);

        vm.startPrank(BOB);
        vm.expectRevert(Lending.Lending__InsufficientCollateral.selector);
        s_lending.removeCollateral(loanId, collateralAmountToRemove);
        vm.stopPrank();
    }

    function testRemoveCollateral__Success() public {
        address assetToBorrow = s_usdc;
        uint256 amountToDeposit = 100 ether;
        uint256 amountToBorrow = 50 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 100 ether;
        uint256 collateralAmountToRemove = 5 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToDeposit);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);

        uint256 loanId = borrowFor(BOB, assetToBorrow, amountToBorrow, collateral, collateralAmount);

        vm.startPrank(BOB);
        vm.expectEmit(true, true, true, true);
        emit Lending.CollateralRemoved(loanId, collateralAmountToRemove);
        s_lending.removeCollateral(loanId, collateralAmountToRemove);
        vm.stopPrank();

        assertEq(
            IERC20(collateral).balanceOf(address(s_lending)),
            collateralAmount - collateralAmountToRemove,
            "Contract collateral balance not updated"
        );
        assertEq(
            IERC20(collateral).balanceOf(BOB),
            INITIAL_BOB_BALANCE - collateralAmount + collateralAmountToRemove,
            "User collateral balance not updated"
        );
        assertEq(
            s_lending.getLoan(loanId).collateralAmount,
            collateralAmount - collateralAmountToRemove,
            "Loan collateral amount not updated"
        );
    }

    function testRepay__ZeroAmount() public {
        address assetToBorrow = s_usdc;
        uint256 amountToDeposit = 100 ether;
        uint256 amountToBorrow = 50 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 100 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToDeposit);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);

        uint256 loanId = borrowFor(BOB, assetToBorrow, amountToBorrow, collateral, collateralAmount);

        vm.startPrank(BOB);
        vm.expectRevert(Lending.Lending__ZeroAmount.selector);
        s_lending.repay(loanId, 0);
        vm.stopPrank();
    }

    function testRepay__LoanNotFound() public {
        vm.startPrank(BOB);
        vm.expectRevert(Lending.Lending__LoanNotFound.selector);
        s_lending.repay(7, 10 ether);
        vm.stopPrank();
    }

    function testRepay__Success__FullRepay() public {
        address assetToBorrow = s_usdc;
        uint256 amountToBorrow = 100 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 200 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToBorrow);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);

        uint256 loanId = borrowFor(BOB, assetToBorrow, amountToBorrow, collateral, collateralAmount);

        vm.warp(block.timestamp + (2 * 365 days));
        s_lending.updateLoanInterest(loanId);

        uint256 interestDue = s_lending.getLoan(loanId).interestDue;
        uint256 amount = s_lending.getLoan(loanId).amount;
        uint256 repayAmount = amount + interestDue;

        vm.startPrank(s_deployer);
        IERC20(assetToBorrow).transfer(BOB, interestDue);
        vm.stopPrank();
        assertEq(IERC20(assetToBorrow).balanceOf(BOB), repayAmount);

        vm.startPrank(BOB);
        IERC20(assetToBorrow).approve(address(s_lending), repayAmount);
        vm.expectEmit(true, true, true, true);
        emit Lending.LoanClosed(loanId);
        emit Lending.Repay(loanId, repayAmount);
        s_lending.repay(loanId, repayAmount);
        vm.stopPrank();

        assertEq(IERC20(assetToBorrow).balanceOf(BOB), 0, "User assetToBorrow balance not updated");

        assertEq(
            IERC20(assetToBorrow).balanceOf(address(s_lending)),
            repayAmount,
            "Contract assetToBorrow balance not updated"
        );
        assertEq(IERC20(collateral).balanceOf(address(s_lending)), 0, "Contract collateral balance not updated");
        assertEq(IERC20(collateral).balanceOf(BOB), INITIAL_BOB_BALANCE, "User collateral balance not updated");

        assertEq(s_lending.getLoan(loanId).amount, 0, "Loan amount not updated");
        assertEq(s_lending.getLoan(loanId).collateralAmount, 0, "Loan collateral amount not updated");
        assertEq(s_lending.getPool(assetToBorrow).totalBorrowed, 0, "Pool total borrowed not updated");
    }

    function testFail__RepayPartial__LoanClosedNotEmitted() public {
        address assetToBorrow = s_usdc;
        uint256 amountToDeposit = 100 ether;
        uint256 amountToBorrow = 50 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 100 ether;
        uint256 repayAmount = 25 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToDeposit);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);

        uint256 loanId = borrowFor(BOB, assetToBorrow, amountToBorrow, collateral, collateralAmount);

        vm.startPrank(BOB);
        IERC20(assetToBorrow).approve(address(s_lending), repayAmount);
        vm.expectEmit(true, true, true, true);
        emit Lending.LoanClosed(loanId);
        vm.stopPrank();
    }

    function testRepay__Success__LessThanInterest() public {
        address assetToBorrow = s_usdc;
        uint256 amountToBorrow = 100 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 200 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToBorrow);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);

        uint256 loanId = borrowFor(BOB, assetToBorrow, amountToBorrow, collateral, collateralAmount);

        vm.warp(block.timestamp + (2 * 365 days));
        s_lending.updateLoanInterest(loanId);

        uint256 interestDue = s_lending.getLoan(loanId).interestDue;
        uint256 interestDifference = 10 gwei;
        assertGt(interestDue, interestDifference);
        uint256 repayAmount = interestDue - interestDifference;

        vm.startPrank(BOB);
        IERC20(assetToBorrow).approve(address(s_lending), repayAmount);
        vm.expectEmit(true, true, true, true);
        emit Lending.Repay(loanId, repayAmount);
        s_lending.repay(loanId, repayAmount);
        vm.stopPrank();

        assertEq(
            IERC20(assetToBorrow).balanceOf(BOB), amountToBorrow - repayAmount, "User assetToBorrow balance not updated"
        );

        assertEq(
            IERC20(assetToBorrow).balanceOf(address(s_lending)),
            repayAmount,
            "Contract assetToBorrow balance not updated"
        );
        assertEq(
            IERC20(collateral).balanceOf(BOB),
            INITIAL_BOB_BALANCE - collateralAmount,
            "User collateral balance should not be updated"
        );
        assertEq(
            IERC20(collateral).balanceOf(address(s_lending)),
            collateralAmount,
            "Contract collateral balance should not be updated"
        );

        assertEq(s_lending.getLoan(loanId).amount, amountToBorrow, "Loan amount should not be updated");
        assertEq(
            s_lending.getLoan(loanId).collateralAmount, collateralAmount, "Loan collateral amount should not be updated"
        );

        assertEq(s_lending.getLoan(loanId).interestDue, interestDifference, "Loan InterestDue not updated");

        assertEq(
            s_lending.getPool(assetToBorrow).totalBorrowed, amountToBorrow, "Pool total borrowed should not be updated"
        );
    }

    function testRepay__Success__MoreThanInterest() public {
        address assetToBorrow = s_usdc;
        uint256 amountToBorrow = 100 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 200 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToBorrow);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);

        uint256 loanId = borrowFor(BOB, assetToBorrow, amountToBorrow, collateral, collateralAmount);

        vm.warp(block.timestamp + (2 * 365 days));
        s_lending.updateLoanInterest(loanId);

        uint256 interestDue = s_lending.getLoan(loanId).interestDue;
        uint256 interestAddition = 10 gwei;
        uint256 repayAmount = interestDue + interestAddition;

        vm.startPrank(BOB);
        IERC20(assetToBorrow).approve(address(s_lending), repayAmount);
        vm.expectEmit(true, true, true, true);
        emit Lending.Repay(loanId, repayAmount);
        s_lending.repay(loanId, repayAmount);
        vm.stopPrank();

        assertEq(
            IERC20(assetToBorrow).balanceOf(BOB), amountToBorrow - repayAmount, "User assetToBorrow balance not updated"
        );

        assertEq(
            IERC20(assetToBorrow).balanceOf(address(s_lending)),
            repayAmount,
            "Contract assetToBorrow balance not updated"
        );
        assertEq(
            IERC20(collateral).balanceOf(BOB),
            INITIAL_BOB_BALANCE - collateralAmount,
            "User collateral balance should not be updated"
        );
        assertEq(
            IERC20(collateral).balanceOf(address(s_lending)),
            collateralAmount,
            "Contract collateral balance should not be updated"
        );

        assertEq(s_lending.getLoan(loanId).amount, amountToBorrow - interestAddition, "Loan amount not updated");
        assertEq(
            s_lending.getLoan(loanId).collateralAmount, collateralAmount, "Loan collateral amount should not be updated"
        );

        assertEq(s_lending.getLoan(loanId).interestDue, 0, "Loan InterestDue not updated");

        assertEq(
            s_lending.getPool(assetToBorrow).totalBorrowed,
            amountToBorrow - interestAddition,
            "Pool total borrowed not updated"
        );
    }

    function testLiquidate__LoanNotFound() public {
        vm.startPrank(BOB);
        vm.expectRevert(Lending.Lending__LoanNotFound.selector);
        s_lending.liquidate(7);
        vm.stopPrank();
    }

    function testLiquidate__LiquidationForbidden() public {
        address assetToBorrow = s_usdc;
        uint256 amountToDeposit = 100 ether;
        uint256 amountToBorrow = 50 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 100 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToDeposit);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);

        uint256 loanId = borrowFor(BOB, assetToBorrow, amountToBorrow, collateral, collateralAmount);

        vm.startPrank(CHARLES);
        vm.expectRevert(Lending.Lending__LiquidationForbidden.selector);
        s_lending.liquidate(loanId);
        vm.stopPrank();
    }

    function testLiquidate__Success() public {
        address assetToBorrow = s_usdc;
        uint256 amountToBorrow = 100 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 180 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToBorrow);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);

        uint256 loanId = borrowFor(BOB, assetToBorrow, amountToBorrow, collateral, collateralAmount);

        vm.warp(block.timestamp + (2 * 365 days));
        s_lending.updateLoanInterest(loanId);

        uint256 interestDue = s_lending.getLoan(loanId).interestDue;
        uint256 repayAmount = amountToBorrow + interestDue;

        fundUserWithToken(CHARLES, assetToBorrow, repayAmount);

        vm.startPrank(CHARLES);
        IERC20(assetToBorrow).approve(address(s_lending), repayAmount);
        vm.expectEmit(true, true, true, true);
        emit Lending.Liquidated(CHARLES, loanId);
        s_lending.liquidate(loanId);
        vm.stopPrank();

        assertEq(
            IERC20(assetToBorrow).balanceOf(BOB), amountToBorrow, "Borrower assetToBorrow balance should not be updated"
        );

        assertEq(
            IERC20(assetToBorrow).balanceOf(address(s_lending)),
            repayAmount,
            "Contract assetToBorrow balance not updated"
        );
        assertEq(IERC20(collateral).balanceOf(address(s_lending)), 0, "Contract collateral balance not updated");
        assertEq(
            IERC20(collateral).balanceOf(BOB),
            INITIAL_BOB_BALANCE - collateralAmount,
            "Borrower collateral balance not updated"
        );
        assertEq(IERC20(collateral).balanceOf(CHARLES), collateralAmount, "Liquidater collateral balance not updated");

        assertEq(s_lending.getLoan(loanId).amount, 0, "Loan amount not updated");
        assertEq(s_lending.getLoan(loanId).collateralAmount, 0, "Loan collateral amount not updated");
        assertEq(s_lending.getPool(assetToBorrow).totalBorrowed, 0, "Pool total borrowed not updated");
    }

    function testUpdateLoanInterest__LoanNotFound() public {
        vm.expectRevert(Lending.Lending__LoanNotFound.selector);
        s_lending.updateLoanInterest(7);
    }

    function testUpdateLoanInterest__Success() public {
        address assetToBorrow = s_usdc;
        uint256 amountToDeposit = 100 ether;
        uint256 amountToBorrow = 50 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 100 ether;

        fundUserWithToken(ALICE, assetToBorrow, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, assetToBorrow, amountToDeposit);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);

        uint256 loanId = borrowFor(BOB, assetToBorrow, amountToBorrow, collateral, collateralAmount);

        uint256 dday = block.timestamp + 365 days;
        vm.warp(dday);

        uint256 interestDue = s_lending.updateLoanInterest(loanId);

        assertEq(
            interestDue,
            amountToBorrow * s_lending.getLoan(loanId).scaledBorrowRate / s_lending.SCALING_FACTOR(),
            "Interest rate not updated"
        );
        assertEq(interestDue, s_lending.getLoan(loanId).interestDue, "Loan interest due not updated");
        assertEq(s_lending.getLoan(loanId).lastUpdateTimestamp, dday, "Last interest update time not updated");
    }

    function testUpdatePoolInterestRate__PoolNotFound() public {
        vm.expectRevert(Lending.Lending__PoolNotFound.selector);
        s_lending.updatePoolInterestRate(s_usdc);
    }

    function testUpdatePoolInterestRate__Default() public {
        address asset = s_usdc;

        s_lending.createPool(asset);
        s_lending.updatePoolInterestRate(asset);

        assertEq(
            s_lending.getPool(asset).scaledInterestRate,
            s_lending.DEFAULT_SCALED_INTEREST_RATE(),
            "Interest rate not updated"
        );
    }

    //  @todo complete test for updatePoolInterestRate
    function testSkipUpdatePoolInterestRate__Success() public {
        address asset = s_usdc;
        uint256 amountToBorrow = 100 ether;
        address collateral = s_weth;
        uint256 collateralAmount = 200 ether;

        fundUserWithToken(ALICE, asset, INITIAL_ALICE_BALANCE);
        depositFor(ALICE, asset, amountToBorrow);
        fundUserWithToken(BOB, collateral, INITIAL_BOB_BALANCE);

        uint256 loanId = borrowFor(BOB, asset, amountToBorrow, collateral, collateralAmount);

        vm.startPrank(s_deployer);
        s_lending.updatePoolInterestRate(asset);
        vm.stopPrank();

        // assertEq(s_lending.getPool(asset).scaledInterestRate, scaledInterestRate, "Interjest rate not updated");
    }
}
