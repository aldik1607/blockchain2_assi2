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

        // Seed pool with liquidity
        token.approve(address(pool), type(uint256).max);
        pool.deposit(INITIAL * 5);

        vm.prank(alice);
        token.approve(address(pool), type(uint256).max);

        vm.prank(bob);
        token.approve(address(pool), type(uint256).max);

        vm.prank(liquidator);
        token.approve(address(pool), type(uint256).max);
    }

    // ─── 1. Deposit basic ────────────────────────────────────────

    function test_Deposit() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        (uint256 deposited,,,) = pool.positions(alice);
        assertEq(deposited, 1000e18);
    }

    // ─── 2. Deposit revert zero ──────────────────────────────────

    function test_Deposit_RevertZero() public {
        vm.prank(alice);
        vm.expectRevert("Amount must be > 0");
        pool.deposit(0);
    }

    // ─── 3. Withdraw after deposit ───────────────────────────────

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

    // ─── 4. Borrow within LTV ────────────────────────────────────

    function test_Borrow_WithinLTV() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        uint256 balBefore = token.balanceOf(alice);

        vm.prank(alice);
        pool.borrow(700e18); // 70% LTV, within 75% limit

        assertEq(token.balanceOf(alice), balBefore + 700e18);
    }

    // ─── 5. Borrow exceeding LTV revert ──────────────────────────

    function test_Borrow_RevertExceedsLTV() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        vm.expectRevert("Exceeds LTV");
        pool.borrow(800e18); // 80% > 75% LTV
    }

    // ─── 6. Borrow with no collateral revert ─────────────────────

    function test_Borrow_RevertNoCollateral() public {
        vm.prank(alice);
        vm.expectRevert("No collateral");
        pool.borrow(100e18);
    }

    // ─── 7. Repay full debt ──────────────────────────────────────

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

    // ─── 8. Repay partial ────────────────────────────────────────

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

    // ─── 9. Withdraw with outstanding debt revert ────────────────

    function test_Withdraw_RevertWithDebt() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.borrow(700e18);

        vm.prank(alice);
        vm.expectRevert("Health factor too low");
        pool.withdraw(500e18); // would drop health factor below 1
    }

    // ─── 10. Interest accrual over time ──────────────────────────

    function test_InterestAccrual() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.borrow(500e18);

        uint256 debtBefore = pool.getTotalDebt(alice);

        // Warp 1 year forward
        vm.warp(block.timestamp + 365 days);

        uint256 debtAfter = pool.getTotalDebt(alice);
        assertGt(debtAfter, debtBefore);

        // ~1% APR on 500 tokens = ~5 tokens interest
        uint256 interest = debtAfter - debtBefore;
        assertGt(interest, 4e18);
        assertLt(interest, 10e18);
    }

    // ─── 11. Health factor drops after price drop ─────────────────

    function test_HealthFactor_DropsOnPriceDrop() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.borrow(700e18);

        uint256 hfBefore = pool.getHealthFactor(alice);

        // Price drops 50%
        pool.setPrice(0.5e18);

        uint256 hfAfter = pool.getHealthFactor(alice);
        assertLt(hfAfter, hfBefore);
    }

    // ─── 12. Liquidation after price drop ────────────────────────

    function test_Liquidate() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.borrow(700e18);

        // Price drops — alice becomes undercollateralized
        pool.setPrice(0.5e18);

        uint256 hf = pool.getHealthFactor(alice);
        assertLt(hf, 1e18);

        uint256 liquidatorBalBefore = token.balanceOf(liquidator);

        vm.prank(liquidator);
        pool.liquidate(alice);

        uint256 liquidatorBalAfter = token.balanceOf(liquidator);
        assertGt(liquidatorBalAfter, liquidatorBalBefore); // liquidator profited

        (, uint256 borrowed,,) = pool.positions(alice);
        assertEq(borrowed, 0); // debt cleared
    }

    // ─── 13. Liquidation revert on healthy position ───────────────

    function test_Liquidate_RevertHealthy() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.borrow(500e18);

        vm.prank(liquidator);
        vm.expectRevert("Position is healthy");
        pool.liquidate(alice);
    }

    // ─── 14. Health factor > 1 after full repay ───────────────────

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

    // ─── 15. Fuzz: borrow never exceeds LTV ──────────────────────

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
