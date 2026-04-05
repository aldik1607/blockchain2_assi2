// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MyToken.sol";

contract MyTokenTest is Test {
    MyToken token;
    address owner = address(1);
    address alice = address(2);
    address bob   = address(3);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;

    function setUp() public {
        vm.prank(owner);
        token = new MyToken("MyToken", "MTK", INITIAL_SUPPLY);
    }

    // ─── UNIT TESTS ────────────────────────────────────────────────

    // 1. Проверка начального состояния
    function test_InitialSupply() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
    }

    // 2. Mint увеличивает totalSupply и баланс
    function test_Mint() public {
        token.mint(alice, 500e18);
        assertEq(token.balanceOf(alice), 500e18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + 500e18);
    }

    // 3. Mint на нулевой адрес revert
    function test_Mint_RevertZeroAddress() public {
        vm.expectRevert("Mint to zero address");
        token.mint(address(0), 100e18);
    }

    // 4. Transfer списывает и зачисляет
    function test_Transfer() public {
        vm.prank(owner);
        token.transfer(alice, 100e18);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - 100e18);
        assertEq(token.balanceOf(alice), 100e18);
    }

    // 5. Transfer при недостатке баланса revert
    function test_Transfer_RevertInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert("Insufficient balance");
        token.transfer(bob, 1e18);
    }

    // 6. Transfer на нулевой адрес revert
    function test_Transfer_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Transfer to zero address");
        token.transfer(address(0), 1e18);
    }

    // 7. Approve устанавливает allowance
    function test_Approve() public {
        vm.prank(owner);
        token.approve(alice, 200e18);
        assertEq(token.allowance(owner, alice), 200e18);
    }

    // 8. Approve на нулевой адрес revert
    function test_Approve_RevertZeroAddress() public {
        vm.expectRevert("Approve to zero address");
        token.approve(address(0), 100e18);
    }

    // 9. TransferFrom списывает allowance и переводит
    function test_TransferFrom() public {
        vm.prank(owner);
        token.approve(alice, 300e18);

        vm.prank(alice);
        token.transferFrom(owner, bob, 100e18);

        assertEq(token.balanceOf(bob), 100e18);
        assertEq(token.allowance(owner, alice), 200e18);
    }

    // 10. TransferFrom без allowance revert
    function test_TransferFrom_RevertNoAllowance() public {
        vm.prank(alice);
        vm.expectRevert("Insufficient allowance");
        token.transferFrom(owner, bob, 1e18);
    }

    // 11. TransferFrom недостаток баланса revert
    function test_TransferFrom_RevertInsufficientBalance() public {
        token.mint(alice, 50e18);
        vm.prank(alice);
        token.approve(bob, 1000e18);

        vm.prank(bob);
        vm.expectRevert("Insufficient balance");
        token.transferFrom(alice, bob, 100e18);
    }

    // 12. Transfer самому себе не меняет баланс
    function test_Transfer_ToSelf() public {
        vm.prank(owner);
        token.transfer(owner, 100e18);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
    }

    // ─── FUZZ TESTS ────────────────────────────────────────────────

    // Fuzz: transfer на произвольную сумму в пределах баланса
    function testFuzz_Transfer(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(to != owner);
        amount = bound(amount, 0, INITIAL_SUPPLY);

        vm.prank(owner);
        token.transfer(to, amount);

        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - amount);
    }

    // Fuzz: approve + transferFrom на произвольные суммы
    function testFuzz_TransferFrom(address spender, address to, uint256 amount) public {
        vm.assume(spender != address(0));
        vm.assume(to != address(0));
        vm.assume(spender != owner);
        amount = bound(amount, 0, INITIAL_SUPPLY);

        vm.prank(owner);
        token.approve(spender, amount);

        vm.prank(spender);
        token.transferFrom(owner, to, amount);

        assertEq(token.balanceOf(to == owner ? owner : to),
                 to == owner ? INITIAL_SUPPLY : amount);
    }

    // Fuzz: mint на произвольный адрес и сумму
    function testFuzz_Mint(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 1, type(uint128).max);

        uint256 supplyBefore = token.totalSupply();
        token.mint(to, amount);

        assertEq(token.totalSupply(), supplyBefore + amount);
    }

    function test_Burn() public {
    token.mint(alice, 500e18);
    token.burn(alice, 200e18);
    assertEq(token.balanceOf(alice), 300e18);
    assertEq(token.totalSupply(), INITIAL_SUPPLY + 300e18);
}

    // Burn — revert при недостатке баланса
    function test_Burn_RevertInsufficientBalance() public {
        vm.expectRevert("Insufficient balance");
        token.burn(alice, 1e18);
    }

    // Burn до нуля
    function test_Burn_EntireBalance() public {
        token.mint(alice, 100e18);
        token.burn(alice, 100e18);
        assertEq(token.balanceOf(alice), 0);
    }

    // TransferFrom на нулевой адрес revert
    function test_TransferFrom_RevertZeroAddress() public {
        vm.prank(owner);
        token.approve(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert("Transfer to zero address");
        token.transferFrom(owner, address(0), 50e18);
    }

    // Approve перезаписывает старый allowance
    function test_Approve_Overwrite() public {
        vm.prank(owner);
        token.approve(alice, 100e18);
        vm.prank(owner);
        token.approve(alice, 999e18);
        assertEq(token.allowance(owner, alice), 999e18);
    }

    // Transfer нулевой суммы
    function test_Transfer_ZeroAmount() public {
        vm.prank(owner);
        token.transfer(alice, 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
    }

    // Fuzz burn
    function testFuzz_Burn(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 1, type(uint128).max);
        burnAmount = bound(burnAmount, 0, mintAmount);

        token.mint(alice, mintAmount);
        uint256 supplyBefore = token.totalSupply();

        token.burn(alice, burnAmount);

        assertEq(token.balanceOf(alice), mintAmount - burnAmount);
        assertEq(token.totalSupply(), supplyBefore - burnAmount);
    }
}