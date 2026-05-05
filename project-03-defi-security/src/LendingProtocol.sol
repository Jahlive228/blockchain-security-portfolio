// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SimpleAMM} from "./SimpleAMM.sol";

/**
 * @title LendingProtocol
 * @notice Protocole de prêt vulnérable à la manipulation d'oracle
 *
 *         Scénario d'attaque :
 *         1. Flash loan → emprunte énorme quantité de tokenA
 *         2. Swap massif A→B → price de A s'effondre dans le pool
 *         3. Dépose A comme collateral → protocol pense que ça vaut peu
 *            NON — inverse : price de B explose
 *         4. Emprunte B avec collateral A sous-évalué
 *         5. Rembourse flash loan
 *         6. Garde le profit
 *
 *         VULN : utilise le prix spot du pool AMM comme oracle
 */
contract LendingProtocol {
    SimpleAMM public amm;

    // Collateral déposé en tokenA
    mapping(address => uint256) public collateral;
    // Dette en tokenB
    mapping(address => uint256) public debt;

    // Ratio de collatéralisation minimum : 150%
    uint256 public constant COLLATERAL_RATIO = 150;
    // Ratio de liquidation : 110%
    uint256 public constant LIQUIDATION_RATIO = 110;

    event Deposited(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);

    constructor(address _amm) {
        amm = SimpleAMM(_amm);
    }

    /**
     * @notice Dépose tokenA comme collateral
     */
    function depositCollateral(uint256 amount) external {
        require(amount > 0, "Zero amount");
        require(amm.balanceA(msg.sender) >= amount, "Insufficient A");

        // Transfert simulé
        amm.balanceA(msg.sender);
        collateral[msg.sender] += amount;

        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Emprunte tokenB contre collateral tokenA
     * @dev VULN : utilise getSpotPrice() — manipulable
     */
    function borrow(uint256 amountB) external {
        require(amountB > 0, "Zero amount");

        // Prix spot — VULNÉRABLE à la manipulation
        uint256 priceA = amm.getSpotPrice(); // prix de A en B (1e18)

        // Valeur du collateral en B
        uint256 collateralValue = (collateral[msg.sender] * priceA) / 1e18;

        // Capacité d'emprunt : collateralValue * 100 / 150
        uint256 maxBorrow = (collateralValue * 100) / COLLATERAL_RATIO;

        require(
            debt[msg.sender] + amountB <= maxBorrow,
            "Undercollateralized"
        );

        debt[msg.sender]          += amountB;
        amm.balanceB(msg.sender);

        emit Borrowed(msg.sender, amountB);
    }

    /**
     * @notice Rembourse la dette
     */
    function repay(uint256 amountB) external {
        require(amountB > 0, "Zero amount");
        require(debt[msg.sender] >= amountB, "Overpayment");
        debt[msg.sender] -= amountB;
        emit Repaid(msg.sender, amountB);
    }

    /**
     * @notice Vérifie si une position est saine
     */
    function isHealthy(address user) public view returns (bool) {
        if (debt[user] == 0) return true;
        uint256 priceA       = amm.getSpotPrice();
        uint256 collateralVal = (collateral[user] * priceA) / 1e18;
        uint256 minCollateral = (debt[user] * LIQUIDATION_RATIO) / 100;
        return collateralVal >= minCollateral;
    }
}