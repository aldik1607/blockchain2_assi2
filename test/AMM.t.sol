// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AMM.sol";
import "../src/Token.sol";
import "../src/LPToken.sol";

contract AMMTest is Test {
    AMM amm;
    Token tokenA;
    Token tokenB;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant INITIAL = 1_000_000e18;

    function setUp() public {
        tokenA = new Token("Token A", "TKA", INITIAL * 10);
        tokenB = new Token("Token B", "TKB", INITIAL * 10);
        amm = new AMM(address(tokenA), address(tokenB));

        tokenA.mint(alice, INITIAL);
        tokenB.mint(alice, INITIAL);
        tokenA.mint(bob, INITIAL);
        tokenB.mint(bob, INITIAL);

        vm.startPrank(alice);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }


    function test_AddLiquidity_First() public {
        vm.prank(alice);
        uint256 lp = amm.addLiquidity(1000e18, 1000e18);

        assertGt(lp, 0);
        assertEq(amm.lpToken().balanceOf(alice), lp);
        (uint256 rA, uint256 rB) = amm.getReserves();
        assertEq(rA, 1000e18);
        assertEq(rB, 1000e18);
    }


    function test_AddLiquidity_Subsequent() public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        vm.prank(bob);
        uint256 lp = amm.addLiquidity(500e18, 500e18);

        assertGt(lp, 0);
        assertEq(amm.lpToken().balanceOf(bob), lp);
    }


    function test_AddLiquidity_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("Amounts must be > 0");
        amm.addLiquidity(0, 1000e18);
    }


    function test_RemoveLiquidity_Partial() public {
        vm.prank(alice);
        uint256 lp = amm.addLiquidity(1000e18, 1000e18);

        vm.prank(alice);
        amm.lpToken().approve(address(amm), lp);

        uint256 half = lp / 2;
        vm.prank(alice);
        (uint256 outA, uint256 outB) = amm.removeLiquidity(half);

        assertGt(outA, 0);
        assertGt(outB, 0);
        assertEq(amm.lpToken().balanceOf(alice), lp - half);
    }


    function test_RemoveLiquidity_Full() public {
        vm.prank(alice);
        uint256 lp = amm.addLiquidity(1000e18, 1000e18);

        vm.prank(alice);
        amm.lpToken().approve(address(amm), lp);

        vm.prank(alice);
        amm.removeLiquidity(lp);

        assertEq(amm.lpToken().totalSupply(), 0);
        (uint256 rA, uint256 rB) = amm.getReserves();
        assertEq(rA, 0);
        assertEq(rB, 0);
    }


    function test_RemoveLiquidity_RevertZero() public {
        vm.prank(alice);
        vm.expectRevert("LP amount must be > 0");
        amm.removeLiquidity(0);
    }


    function test_Swap_AtoB() public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        uint256 balBefore = tokenB.balanceOf(bob);

        vm.prank(bob);
        uint256 out = amm.swap(address(tokenA), 10e18, 0);

        assertGt(out, 0);
        assertEq(tokenB.balanceOf(bob), balBefore + out);
    }


    function test_Swap_BtoA() public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        uint256 balBefore = tokenA.balanceOf(bob);

        vm.prank(bob);
        uint256 out = amm.swap(address(tokenB), 10e18, 0);

        assertGt(out, 0);
        assertEq(tokenA.balanceOf(bob), balBefore + out);
    }


    function test_Swap_KInvariant() public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        (uint256 rA0, uint256 rB0) = amm.getReserves();
        uint256 kBefore = rA0 * rB0;

        vm.prank(bob);
        amm.swap(address(tokenA), 10e18, 0);

        (uint256 rA1, uint256 rB1) = amm.getReserves();
        uint256 kAfter = rA1 * rB1;

        assertGe(kAfter, kBefore);
    }


    function test_Swap_RevertSlippage() public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        uint256 expectedOut = amm.getAmountOut(10e18, 1000e18, 1000e18);

        vm.prank(bob);
        vm.expectRevert("Slippage: insufficient output");
        amm.swap(address(tokenA), 10e18, expectedOut + 1);
    }


    function test_Swap_RevertInvalidToken() public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        vm.prank(bob);
        vm.expectRevert("Invalid token");
        amm.swap(address(0xdead), 10e18, 0);
    }


    function test_Swap_RevertZeroAmount() public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        vm.prank(bob);
        vm.expectRevert("Amount must be > 0");
        amm.swap(address(tokenA), 0, 0);
    }


    function test_Swap_LargeSwap_HighPriceImpact() public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        uint256 amountIn = 500e18;
        uint256 amountOut = amm.getAmountOut(amountIn, 1000e18, 1000e18);

        assertLt(amountOut, amountIn);
    }


    function test_GetAmountOut() public view {
        uint256 out = amm.getAmountOut(100e18, 1000e18, 1000e18);
        assertGt(out, 90e18);
        assertLt(out, 100e18);
    }


    function test_Swap_Multiple() public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(bob);
            amm.swap(address(tokenA), 1e18, 0);
        }

        (uint256 rA, uint256 rB) = amm.getReserves();
        assertGt(rA, 1000e18);
        assertLt(rB, 1000e18);
    }


    function testFuzz_Swap_KInvariant(uint256 amountIn) public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        amountIn = bound(amountIn, 1e15, 100e18);

        (uint256 rA0, uint256 rB0) = amm.getReserves();
        uint256 kBefore = rA0 * rB0;

        vm.prank(bob);
        amm.swap(address(tokenA), amountIn, 0);

        (uint256 rA1, uint256 rB1) = amm.getReserves();
        assertGe(rA1 * rB1, kBefore);
    }


    function testFuzz_Swap_OutputLessThanReserve(uint256 amountIn) public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        amountIn = bound(amountIn, 1e15, 100e18);

        (, uint256 rB0) = amm.getReserves();

        vm.prank(bob);
        uint256 out = amm.swap(address(tokenA), amountIn, 0);

        assertLt(out, rB0);
    }
}
