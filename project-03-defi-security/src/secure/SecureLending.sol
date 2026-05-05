// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SecureAMM} from "./SecureAMM.sol";

/**
 * @title SecureLending
 * @notice Fix : utilise getTWAPPrice() au lieu de getSpotPrice()
 *         Le prix TWAP ne peut pas être manipulé en une transaction
 */
contract SecureLending {
    SecureAMM public amm;

    mapping(address => uint256) public collateral;
    mapping(address => uint256) public debt;

    uint256 public constant COLLATERAL_RATIO  = 150;
    uint256 public constant LIQUIDATION_RATIO = 110;

    event Deposited(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);

    constructor(address _amm) {
        amm = SecureAMM(_amm);
    }

    function depositCollateral(uint256 amount) external {
        require(amount > 0, "Zero amount");
        require(amm.balanceA(msg.sender) >= amount, "Insufficient A");
        collateral[msg.sender] += amount;
        emit Deposited(msg.sender, amount);
    }

    function borrow(uint256 amountB) external {
        require(amountB > 0, "Zero amount");

        // FIX : TWAP au lieu de spot price
        uint256 priceA = amm.getTWAPPrice();

        uint256 collateralValue = (collateral[msg.sender] * priceA) / 1e18;
        uint256 maxBorrow       = (collateralValue * 100) / COLLATERAL_RATIO;

        require(
            debt[msg.sender] + amountB <= maxBorrow,
            "Undercollateralized"
        );

        debt[msg.sender] += amountB;
        emit Borrowed(msg.sender, amountB);
    }

    function repay(uint256 amountB) external {
        require(amountB > 0,                  "Zero amount");
        require(debt[msg.sender] >= amountB,  "Overpayment");
        debt[msg.sender] -= amountB;
        emit Repaid(msg.sender, amountB);
    }

    function isHealthy(address user) public view returns (bool) {
        if (debt[user] == 0) return true;
        uint256 priceA        = amm.getTWAPPrice();
        uint256 collateralVal = (collateral[user] * priceA) / 1e18;
        uint256 minCollateral = (debt[user] * LIQUIDATION_RATIO) / 100;
        return collateralVal >= minCollateral;
    }
}