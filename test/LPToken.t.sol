// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/LPToken.sol";

contract LPTokenTest is Test {
    LPToken token;

    address amm = address(1);
    address user1 = address(2);
    address user2 = address(3);

    function setUp() public {
        token = new LPToken(amm);
    }

    function testMintRevert_NotAMM() public {
        vm.expectRevert("Only AMM");
        token.mint(user1, 100);
    }

    function testTransfer() public {
        vm.prank(amm);
        token.mint(user1, 100);

        vm.prank(user1);
        token.transfer(user2, 50);

        assertEq(token.balanceOf(user2), 50);
    }

    function testTransferRevert() public {
        vm.prank(user1);

        vm.expectRevert("Insufficient balance");
        token.transfer(user2, 10);
    }

    function testTransferFrom() public {
        vm.prank(amm);
        token.mint(user1, 100);

        vm.prank(user1);
        token.approve(user2, 50);

        vm.prank(user2);
        token.transferFrom(user1, user2, 30);

        assertEq(token.balanceOf(user2), 30);
    }
}