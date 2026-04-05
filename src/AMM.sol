// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./LPToken.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract AMM {
    IERC20 public tokenA;
    IERC20 public tokenB;
    LPToken public lpToken;

    uint256 public reserveA;
    uint256 public reserveB;

    uint256 private constant FEE_NUMERATOR = 997;
    uint256 private constant FEE_DENOMINATOR = 1000;

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpMinted);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpBurned);
    event Swap(address indexed user, address tokenIn, uint256 amountIn, uint256 amountOut);

    constructor(address _tokenA, address _tokenB) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        lpToken = new LPToken(address(this));
    }

    // ─── getAmountOut: constant product formula with 0.3% fee ───

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        require(amountIn > 0, "Amount must be > 0");
        require(reserveIn > 0 && reserveOut > 0, "Empty reserves");

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        return numerator / denominator;
    }

    // ─── addLiquidity ────────────────────────────────────────────

    function addLiquidity(uint256 amountA, uint256 amountB) external returns (uint256 lpMinted) {
        require(amountA > 0 && amountB > 0, "Amounts must be > 0");

        uint256 totalLP = lpToken.totalSupply();

        if (totalLP == 0) {
            // Первый провайдер — geometric mean
            lpMinted = _sqrt(amountA * amountB);
        } else {
            // Последующие — пропорционально
            uint256 lpFromA = (amountA * totalLP) / reserveA;
            uint256 lpFromB = (amountB * totalLP) / reserveB;
            lpMinted = lpFromA < lpFromB ? lpFromA : lpFromB;
        }

        require(lpMinted > 0, "Insufficient liquidity minted");

        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);

        reserveA += amountA;
        reserveB += amountB;

        lpToken.mint(msg.sender, lpMinted);

        emit LiquidityAdded(msg.sender, amountA, amountB, lpMinted);
    }

    // ─── removeLiquidity ─────────────────────────────────────────

    function removeLiquidity(uint256 lpAmount) external returns (uint256 amountA, uint256 amountB) {
        require(lpAmount > 0, "LP amount must be > 0");

        uint256 totalLP = lpToken.totalSupply();
        require(totalLP > 0, "No liquidity");

        amountA = (lpAmount * reserveA) / totalLP;
        amountB = (lpAmount * reserveB) / totalLP;

        require(amountA > 0 && amountB > 0, "Insufficient liquidity burned");

        lpToken.burn(msg.sender, lpAmount);

        reserveA -= amountA;
        reserveB -= amountB;

        tokenA.transfer(msg.sender, amountA);
        tokenB.transfer(msg.sender, amountB);

        emit LiquidityRemoved(msg.sender, amountA, amountB, lpAmount);
    }

    // ─── swap ────────────────────────────────────────────────────

    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut) external returns (uint256 amountOut) {
        require(tokenIn == address(tokenA) || tokenIn == address(tokenB), "Invalid token");
        require(amountIn > 0, "Amount must be > 0");

        bool isTokenA = tokenIn == address(tokenA);

        (uint256 reserveIn, uint256 reserveOut) = isTokenA ? (reserveA, reserveB) : (reserveB, reserveA);

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);

        require(amountOut >= minAmountOut, "Slippage: insufficient output");

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        if (isTokenA) {
            reserveA += amountIn;
            reserveB -= amountOut;
            tokenB.transfer(msg.sender, amountOut);
        } else {
            reserveB += amountIn;
            reserveA -= amountOut;
            tokenA.transfer(msg.sender, amountOut);
        }

        emit Swap(msg.sender, tokenIn, amountIn, amountOut);
    }

    // ─── helpers ─────────────────────────────────────────────────

    function getReserves() external view returns (uint256, uint256) {
        return (reserveA, reserveB);
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
