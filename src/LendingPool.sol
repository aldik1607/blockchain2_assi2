// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract LendingPool {
    IERC20 public token;

    uint256 public constant LTV              = 75;   
    uint256 public constant LIQUIDATION_THRESHOLD = 80; 
    uint256 public constant LIQUIDATION_BONUS     = 5;  
    uint256 public constant INTEREST_RATE_PER_SEC = 317097919; 
    uint256 public constant PRECISION        = 1e18;

    struct Position {
        uint256 deposited;       
        uint256 borrowed;        
        uint256 borrowTimestamp; 
        uint256 interestAccrued; 
    }

    mapping(address => Position) public positions;

    uint256 public totalDeposits;
    uint256 public totalBorrows;

    uint256 public collateralPrice = 1e18; 
    address public owner;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(
        address indexed liquidator,
        address indexed user,
        uint256 debtRepaid,
        uint256 collateralSeized
    );

    constructor(address _token) {
        token = IERC20(_token);
        owner = msg.sender;
    }

    function setPrice(uint256 _price) external {
        require(msg.sender == owner, "Only owner");
        collateralPrice = _price;
    }

    function _accrueInterest(address user) internal {
        Position storage pos = positions[user];
        if (pos.borrowed == 0 || pos.borrowTimestamp == 0) return;

        uint256 timeElapsed = block.timestamp - pos.borrowTimestamp;
        uint256 interest = (pos.borrowed * INTEREST_RATE_PER_SEC * timeElapsed) / PRECISION;

        pos.interestAccrued += interest;
        pos.borrowTimestamp  = block.timestamp;
    }

    function getTotalDebt(address user) public view returns (uint256) {
        Position storage pos = positions[user];
        if (pos.borrowed == 0) return 0;

        uint256 timeElapsed  = block.timestamp - pos.borrowTimestamp;
        uint256 interest     = (pos.borrowed * INTEREST_RATE_PER_SEC * timeElapsed) / PRECISION;
        return pos.borrowed + pos.interestAccrued + interest;
    }

    function getHealthFactor(address user) public view returns (uint256) {
        Position storage pos = positions[user];
        if (pos.borrowed == 0 && pos.interestAccrued == 0) return type(uint256).max;

        uint256 totalDebt         = getTotalDebt(user);
        uint256 collateralValue   = (pos.deposited * collateralPrice) / PRECISION;
        uint256 adjustedCollateral = (collateralValue * LIQUIDATION_THRESHOLD) / 100;

        if (totalDebt == 0) return type(uint256).max;
        return (adjustedCollateral * PRECISION) / totalDebt;
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");

        token.transferFrom(msg.sender, address(this), amount);
        positions[msg.sender].deposited += amount;
        totalDeposits += amount;

        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        Position storage pos = positions[msg.sender];
        require(amount > 0,                          "Amount must be > 0");
        require(pos.deposited >= amount,             "Insufficient deposit");

        pos.deposited -= amount;

        if (pos.borrowed > 0 || pos.interestAccrued > 0) {
            require(getHealthFactor(msg.sender) >= PRECISION, "Health factor too low");
        }

        totalDeposits -= amount;
        token.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function borrow(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");

        _accrueInterest(msg.sender);

        Position storage pos = positions[msg.sender];
        require(pos.deposited > 0, "No collateral");

        uint256 collateralValue = (pos.deposited * collateralPrice) / PRECISION;
        uint256 maxBorrow       = (collateralValue * LTV) / 100;
        uint256 totalDebt       = getTotalDebt(msg.sender);

        require(totalDebt + amount <= maxBorrow, "Exceeds LTV");
        require(totalBorrows + amount <= totalDeposits, "Insufficient pool liquidity");

        if (pos.borrowTimestamp == 0) {
            pos.borrowTimestamp = block.timestamp;
        }

        pos.borrowed   += amount;
        totalBorrows   += amount;

        token.transfer(msg.sender, amount);

        emit Borrowed(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");

        _accrueInterest(msg.sender);

        Position storage pos = positions[msg.sender];
        uint256 totalDebt    = pos.borrowed + pos.interestAccrued;
        require(totalDebt > 0, "No debt");

        uint256 repayAmount = amount > totalDebt ? totalDebt : amount;

        token.transferFrom(msg.sender, address(this), repayAmount);

        if (repayAmount >= pos.interestAccrued) {
            repayAmount        -= pos.interestAccrued;
            pos.interestAccrued = 0;
            uint256 principalRepaid = repayAmount > pos.borrowed
                ? pos.borrowed
                : repayAmount;
            pos.borrowed   -= principalRepaid;
            totalBorrows   -= principalRepaid;
        } else {
            pos.interestAccrued -= repayAmount;
        }

        if (pos.borrowed == 0 && pos.interestAccrued == 0) {
            pos.borrowTimestamp = 0;
        }

        emit Repaid(msg.sender, amount);
    }

    function liquidate(address user) external {
        require(getHealthFactor(user) < PRECISION, "Position is healthy");

        _accrueInterest(user);

        Position storage pos = positions[user];
        uint256 totalDebt    = pos.borrowed + pos.interestAccrued;
        require(totalDebt > 0, "No debt to liquidate");

        token.transferFrom(msg.sender, address(this), totalDebt);

        uint256 collateralToSeize = (totalDebt * (100 + LIQUIDATION_BONUS)) / 100;
        if (collateralToSeize > pos.deposited) {
            collateralToSeize = pos.deposited;
        }

        totalBorrows         -= pos.borrowed;
        totalDeposits        -= collateralToSeize;
        pos.deposited        -= collateralToSeize;
        pos.borrowed          = 0;
        pos.interestAccrued   = 0;
        pos.borrowTimestamp   = 0;

        token.transfer(msg.sender, collateralToSeize);

        emit Liquidated(msg.sender, user, totalDebt, collateralToSeize);
    }
}