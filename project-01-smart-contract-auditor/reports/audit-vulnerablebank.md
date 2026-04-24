# Smart Contract Security Audit Report
**Contract:** VulnerableBank.sol  
**Auditor:** KOUMONDJI Komlan Jah Live  
**Date:** 2026-04-11  
**Tool:** Slither v[ta version]  
**Severity scale:** Critical / High / Medium / Low / Informational

---

## Executive Summary

L'audit du contrat `VulnerableBank` a révélé **1 vulnérabilité critique**
exploitable permettant le vol de la totalité des fonds du contrat via une
attaque reentrancy. Deux findings supplémentaires de niveau moyen et
informatif ont également été identifiés.

| Severity     | Count |
|--------------|-------|
| Critical     | 1     |
| High         | 0     |
| Medium       | 1     |
| Informational| 1     |

---

## Finding #1 — CRITICAL : Reentrancy

**Location:** `VulnerableBank.withdraw()` — ligne 16  
**Detector:** `reentrancy-eth`

**Description:**  
La fonction `withdraw()` effectue un appel externe via `.call{value}()`
avant de mettre à jour le solde de l'utilisateur. Un contrat attaquant
peut re-appeler `withdraw()` depuis son `receive()/fallback()` avant
que `balances[msg.sender] = 0` soit exécuté.

**Impact:** Perte totale des fonds du contrat (Critical).

**Proof of Concept:**
1. Attaquant déploie `Attacker.sol` pointant vers `VulnerableBank`
2. Appelle `attack()` avec 1 ETH
3. Chaque réception d'ETH déclenche `fallback()` → re-appelle `withdraw()`
4. Le solde n'étant pas encore mis à jour, le `require` passe à chaque fois

**Remediation:** Appliquer le pattern Checks-Effects-Interactions :
```solidity
// EFFECT avant INTERACT
balances[msg.sender] = 0;
(bool success, ) = msg.sender.call{value: amount}("");
```
Ou utiliser `ReentrancyGuard` d'OpenZeppelin.

---

## Finding #2 — MEDIUM : Version Solidity non épinglée

**Location:** `pragma solidity ^0.8.0`  
**Detector:** `solc-version`

**Description:** Le caret `^` autorise toute version `0.8.x`, incluant
des versions avec des bugs compilateur documentés (KeccakCaching, etc.).

**Remediation:** Épingler une version précise : `pragma solidity 0.8.19;`

---

## Finding #3 — INFORMATIONAL : Low-level call

**Location:** `VulnerableBank.withdraw()` — ligne 16  
**Detector:** `low-level-calls`

**Description:** Usage de `.call{}()` sans limite de gas explicite.
Accepté dans ce contexte mais nécessite la vérification du retour
(`require(success)`), ce qui est fait.

**Remediation:** Aucune action requise si le finding #1 est corrigé.

---

## Conclusion

Le contrat `VulnerableBank` ne doit **pas être déployé en production**
dans son état actuel. Le contrat corrigé `SecureBank.sol` adresse
l'ensemble des findings critiques identifiés.