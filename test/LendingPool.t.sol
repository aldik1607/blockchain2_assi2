// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/LendingPool.sol";
import "../src/Token.sol";

contract LendingPoolTest is Test {
    LendingPool pool;
    Token token;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address liquidator = makeAddr("liquidator");

    uint256 constant INITIAL = 100_000e18;

    function setUp() public {
        token = new Token("USD Coin", "USDC", INITIAL * 10);
        pool = new LendingPool(address(token));

        token.mint(alice, INITIAL);
        token.mint(bob, INITIAL);
        token.mint(liquidator, INITIAL);

        token.approve(address(pool), type(uint256).max);
        pool.deposit(INITIAL * 5);

        vm.prank(alice);
        token.approve(address(pool), type(uint256).max);

        vm.prank(bob);
        token.approve(address(pool), type(uint256).max);

        vm.prank(liquidator);
        token.approve(address(pool), type(uint256).max);
    }


    function test_Deposit() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        (uint256 deposited,,,) = pool.positions(alice);
        assertEq(deposited, 1000e18);
    }


    function test_Deposit_RevertZero() public {
        vm.prank(alice);
        vm.expectRevert("Amount must be > 0");
        pool.deposit(0);
    }


    function test_Withdraw() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        uint256 balBefore = token.balanceOf(alice);

        vm.prank(alice);
        pool.withdraw(500e18);

        assertEq(token.balanceOf(alice), balBefore + 500e18);

        (uint256 deposited,,,) = pool.positions(alice);
        assertEq(deposited, 500e18);
    }


    function test_Borrow_WithinLTV() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        uint256 balBefore = token.balanceOf(alice);

        vm.prank(alice);
        pool.borrow(700e18); 

        assertEq(token.balanceOf(alice), balBefore + 700e18);
    }


    function test_Borrow_RevertExceedsLTV() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        vm.expectRevert("Exceeds LTV");
        pool.borrow(800e18);
    }


    function test_Borrow_RevertNoCollateral() public {
        vm.prank(alice);
        vm.expectRevert("No collateral");
        pool.borrow(100e18);
    }


    function test_Repay_Full() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.borrow(500e18);

        vm.prank(alice);
        pool.repay(500e18);

        (, uint256 borrowed,,) = pool.positions(alice);
        assertEq(borrowed, 0);
    }


    function test_Repay_Partial() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.borrow(500e18);

        vm.prank(alice);
        pool.repay(200e18);

        (, uint256 borrowed,,) = pool.positions(alice);
        assertEq(borrowed, 300e18);
    }


    function test_Withdraw_RevertWithDebt() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.borrow(700e18);

        vm.prank(alice);
        vm.expectRevert("Health factor too low");
        pool.withdraw(500e18); 
    }


    function test_InterestAccrual() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.borrow(500e18);

        uint256 debtBefore = pool.getTotalDebt(alice);

        vm.warp(block.timestamp + 365 days);

        uint256 debtAfter = pool.getTotalDebt(alice);
        assertGt(debtAfter, debtBefore);

        uint256 interest = debtAfter - debtBefore;
        assertGt(interest, 4e18);
        assertLt(interest, 10e18);
    }


    function test_HealthFactor_DropsOnPriceDrop() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.borrow(700e18);

        uint256 hfBefore = pool.getHealthFactor(alice);

        pool.setPrice(0.5e18);

        uint256 hfAfter = pool.getHealthFactor(alice);
        assertLt(hfAfter, hfBefore);
    }


    function test_Liquidate() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.borrow(700e18);

        pool.setPrice(0.5e18);

        uint256 hf = pool.getHealthFactor(alice);
        assertLt(hf, 1e18);

        uint256 liquidatorBalBefore = token.balanceOf(liquidator);

        vm.prank(liquidator);
        pool.liquidate(alice);

        uint256 liquidatorBalAfter = token.balanceOf(liquidator);
        assertGt(liquidatorBalAfter, liquidatorBalBefore); // liquidator profited

        (, uint256 borrowed,,) = pool.positions(alice);
        assertEq(borrowed, 0); 
    }


    function test_Liquidate_RevertHealthy() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.borrow(500e18);

        vm.prank(liquidator);
        vm.expectRevert("Position is healthy");
        pool.liquidate(alice);
    }


    function test_HealthFactor_AfterFullRepay() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.borrow(500e18);

        vm.prank(alice);
        pool.repay(500e18);

        uint256 hf = pool.getHealthFactor(alice);
        assertEq(hf, type(uint256).max);
    }


    function testFuzz_Borrow_NeverExceedsLTV(uint256 depositAmount, uint256 borrowAmount) public {
        depositAmount = bound(depositAmount, 1e18, 10_000e18);
        borrowAmount = bound(borrowAmount, 1, (depositAmount * 75) / 100);

        token.mint(alice, depositAmount);

        vm.prank(alice);
        pool.deposit(depositAmount);

        vm.prank(alice);
        pool.borrow(borrowAmount);

        uint256 hf = pool.getHealthFactor(alice);
        assertGe(hf, 1e18);
    }
}
