// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MyToken.sol";

// Handler — посредник, через который Foundry вызывает функции
contract Handler is Test {
    MyToken public token;
    address[] public actors;

    constructor(MyToken _token) {
        token = _token;
        actors.push(address(1));
        actors.push(address(2));
        actors.push(address(3));

        // Дать каждому актору начальный баланс
        for (uint i = 0; i < actors.length; i++) {
            token.mint(actors[i], 1000e18);
        }
    }

    function transfer(uint256 actorSeed, uint256 toSeed, uint256 amount) public {
        address from = actors[actorSeed % actors.length];
        address to   = actors[toSeed   % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));

        vm.prank(from);
        token.transfer(to, amount);
    }

    function approve(uint256 actorSeed, uint256 spenderSeed, uint256 amount) public {
        address actor   = actors[actorSeed  % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, 1000e18);

        vm.prank(actor);
        token.approve(spender, amount);
    }
}

contract MyTokenInvariantTest is Test {
    MyToken  token;
    Handler  handler;

    address[] actors;

    function setUp() public {
        token   = new MyToken("MyToken", "MTK", 0);
        handler = new Handler(token);

        actors.push(address(1));
        actors.push(address(2));
        actors.push(address(3));

        // Foundry будет вызывать только функции Handler
        targetContract(address(handler));
    }

    // Инвариант 1: сумма балансов == totalSupply
    function invariant_TotalSupplyEqualsSumOfBalances() public view {
        uint256 sum = 0;
        for (uint i = 0; i < actors.length; i++) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, token.totalSupply());
    }

    // Инвариант 2: ни у кого нет больше totalSupply
    function invariant_NoAddressExceedsTotalSupply() public view {
        for (uint i = 0; i < actors.length; i++) {
            assertLe(token.balanceOf(actors[i]), token.totalSupply());
        }
    }
}