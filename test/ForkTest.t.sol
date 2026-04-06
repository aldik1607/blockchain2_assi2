// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";


interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

interface IUniswapV2Router {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);

    function WETH() external pure returns (address);
}

contract ForkTest is Test {
    address constant USDC         = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNISWAP_V2   = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant WETH         = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI          = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    IERC20           usdc;
    IUniswapV2Router router;

    uint256 forkId;

    function setUp() public {
        forkId = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        usdc   = IERC20(USDC);
        router = IUniswapV2Router(UNISWAP_V2);
    }


    function test_USDC_TotalSupply() public view {
        uint256 supply = usdc.totalSupply();
        console.log("USDC Total Supply:", supply / 1e6, "USDC");

        assertGt(supply, 1_000_000_000 * 1e6);
    }

    function test_USDC_Metadata() public view {
        assertEq(usdc.decimals(), 6);
        assertEq(usdc.symbol(), "USDC");
    }

    function test_USDC_WhaleBalance() public view {
        address binance = 0x28C6c06298d514Db089934071355E5743bf21d60;
        uint256 balance = usdc.balanceOf(binance);
        console.log("Binance USDC balance:", balance / 1e6, "USDC");
        assertGt(balance, 0);
    }


    function test_Uniswap_GetAmountsOut() public view {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;

        uint256[] memory amounts = router.getAmountsOut(1 ether, path);
        console.log("1 ETH =", amounts[1] / 1e6, "USDC");

        assertGt(amounts[1], 100 * 1e6);
    }

    function test_Uniswap_SwapETHForUSDC() public {
        address trader = makeAddr("trader");
        vm.deal(trader, 10 ether); 

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;

        uint256 balanceBefore = usdc.balanceOf(trader);

        vm.prank(trader);
        uint256[] memory amounts = router.swapExactETHForTokens{value: 1 ether}(
            0,                          
            path,
            trader,
            block.timestamp + 300
        );

        uint256 balanceAfter = usdc.balanceOf(trader);

        console.log("Swapped 1 ETH for", amounts[1] / 1e6, "USDC");
        assertGt(balanceAfter, balanceBefore);
    }

    function test_Uniswap_SwapETHForDAI() public {
        address trader = makeAddr("trader");
        vm.deal(trader, 5 ether);

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        vm.prank(trader);
        uint256[] memory amounts = router.swapExactETHForTokens{value: 1 ether}(
            0,
            path,
            trader,
            block.timestamp + 300
        );

        console.log("Swapped 1 ETH for", amounts[1] / 1e18, "DAI");
        assertGt(amounts[1], 100 * 1e18); 
    }


    function test_RollFork() public {
        uint256 currentBlock = block.number;
        console.log("Current block:", currentBlock);

        uint256 supplyNow = usdc.totalSupply();

        vm.rollFork(currentBlock - 100);
        console.log("Rolled to block:", block.number);

        uint256 supplyOld = usdc.totalSupply();
        console.log("Supply now:", supplyNow / 1e6);
        console.log("Supply -100 blocks:", supplyOld / 1e6);

        assertEq(block.number, currentBlock - 100);
    }


    function test_MultipleForks() public {
        uint256 fork1 = vm.createFork(vm.envString("MAINNET_RPC_URL"), 19_000_000);
        uint256 fork2 = vm.createFork(vm.envString("MAINNET_RPC_URL"), 20_000_000);

        vm.selectFork(fork1);
        uint256 supply1 = usdc.totalSupply();
        console.log("Supply at block 19M:", supply1 / 1e6, "USDC");

        vm.selectFork(fork2);
        uint256 supply2 = usdc.totalSupply();
        console.log("Supply at block 20M:", supply2 / 1e6, "USDC");

        assertTrue(supply1 != supply2);
    }
}