# Security Audit Report — MiniLend Protocol

**Auditor:** KOUMONDJI Komlan Jah Live  
**Date:** 2026  
**Commit audited:** `main`  
**Severity scale:** Critical · High · Medium · Low · Informational  
**Test framework:** Foundry (forge test -vv) — 4/4 passing  

---

## Executive Summary

The audit of the `MiniLend` protocol identified **4 vulnerabilities** ranging
from Critical to Informational. Two vulnerabilities allow direct loss of user
funds. The protocol should not be deployed to mainnet in its current state.

| ID       | Title                              | Severity     | Status   |
|----------|------------------------------------|--------------|----------|
| VULN-01  | Reentrancy in `withdraw()`         | Critical     | Unresolved |
| VULN-02  | Manipulable price oracle           | High         | Unresolved |
| VULN-03  | Liquidation without health check   | High         | Unresolved |
| VULN-04  | Interest accrual inconsistency     | Medium       | Unresolved |

---

## VULN-01 — Critical : Reentrancy in `withdraw()`

**Location:** `MiniLend.sol` — `withdraw()` function  
**Severity:** Critical  
**Impact:** Direct loss of funds — attacker can drain protocol reserves  

### Description

The `withdraw()` function sends ETH to the caller via `.call{value}()`
**before** updating `deposits[msg.sender]`. A malicious contract can
re-enter `withdraw()` from its `receive()` fallback before the balance
is zeroed, effectively withdrawing the same funds multiple times.

### Vulnerable Code

```solidity
function withdraw(uint256 amount) external {
    require(deposits[msg.sender] >= amount, "Insufficient deposit");

    // ❌ External call BEFORE state update
    (bool ok, ) = msg.sender.call{value: amount}("");
    require(ok, "Transfer failed");

    // Too late — attacker has already re-entered
    deposits[msg.sender] -= amount;
    totalReserves        -= amount;
}
```

### Proof of Concept

```
1. Victim users deposit 5 ETH into protocol
2. Attacker deposits 1 ETH → deposits[attacker] = 1 ETH
3. Attacker calls withdraw(1 ETH)
4. Protocol sends 1 ETH → triggers attacker.receive()
5. receive() calls withdraw(1 ETH) again — deposits[attacker] still = 1 ETH
6. Protocol sends 1 ETH again
7. State finally updated: deposits[attacker] = 0 (twice)

Result: Attacker deposited 1 ETH, withdrew 2 ETH
        Protocol lost 1 ETH from other users' funds
```

**Foundry test output:**
```
Protocol ETH before: 5.0 ETH
Attacker ETH before: 1.0 ETH
Protocol ETH after : 4.0 ETH
Attacker ETH after : 3.0 ETH  ← 2x the deposited amount
Reentrance count   : 1
```

### Remediation

Apply the Checks-Effects-Interactions pattern:

```solidity
function withdraw(uint256 amount) external nonReentrant {
    require(deposits[msg.sender] >= amount, "Insufficient deposit");

    // ✅ State update BEFORE external call
    deposits[msg.sender] -= amount;
    totalReserves        -= amount;

    (bool ok, ) = msg.sender.call{value: amount}("");
    require(ok, "Transfer failed");

    emit Withdraw(msg.sender, amount);
}
```

---

## VULN-02 — High : Manipulable Price Oracle

**Location:** `MiniLend.sol` — `getPrice()`, `borrow()`  
**Severity:** High  
**Impact:** Attacker can borrow far beyond collateral value  

### Description

The protocol fetches price from an external oracle contract with no
access control on `setPrice()`. Any address can manipulate the price,
inflating collateral value and enabling undercollateralized borrowing.

### Proof of Concept

```
Initial price  : 2,000 USD/ETH
Max borrow (1 ETH collateral): 1,333 USD

Manipulated price: 20,000 USD/ETH  
Max borrow (1 ETH collateral): 13,333 USD ← 10x overborrow
```

### Remediation

- Use a decentralized oracle (Chainlink) with manipulation resistance
- Add TWAP pricing (time-weighted average — resistant to flash loan attacks)
- Restrict `setPrice()` to a multisig or DAO governance contract
- Add circuit breakers: reject price updates > 20% change per block

---

## VULN-03 — High : Liquidation Without Health Factor Check

**Location:** `MiniLend.sol` — `liquidate()`  
**Severity:** High  
**Impact:** Healthy positions can be liquidated, stealing user collateral  

### Description

The `liquidate()` function does not verify that the target position is
actually undercollateralized before seizing collateral. Any caller can
liquidate any position regardless of health factor.

### Proof of Concept

```
Alice health factor: 800,000 (extremely healthy, >> 150 minimum)
Alice deposit: 2.0 ETH

Liquidator calls liquidate(alice) with 0.1 ETH
→ Alice loses 0.105 ETH collateral (liquidation bonus taken)
→ Liquidator gains 0.105 ETH
→ Alice never consented, position was healthy
```

### Remediation

```solidity
function liquidate(address borrower) external payable {
    // ✅ Add health factor check
    require(
        healthFactor(borrower) < LIQ_HEALTH_FACTOR,
        "Position is healthy"
    );
    // ... rest of liquidation logic
}
```

---

## VULN-04 — Medium : Interest Accrual Inconsistency

**Location:** `MiniLend.sol` — `_debtWithInterest()`  
**Severity:** Medium  
**Impact:** Interest not accrued on collateral changes, state drift  

### Description

`lastInterestUpdate` is only updated on `borrow()` and `repay()` calls.
Deposit and withdrawal operations do not trigger interest settlement,
causing the interest calculation to be based on stale timestamps when
collateral changes affect borrowing capacity.

### Remediation

- Accrue interest before any state-changing operation
- Implement a `_accrueInterest(address user)` internal function
  called at the start of `deposit()`, `withdraw()`, `borrow()`, `repay()`

---

## Fuzz Testing Results

| Test | Runs | Result |
|------|------|--------|
| `testFuzz_VULN04_healthFactorConsistency` | 1,000 | PASS |

The fuzz test confirmed that health factor remains ≥ 150 for all valid
borrow amounts within collateral bounds across 1,000 random inputs.

---

## Recommendations Summary

1. **Immediate** — Fix VULN-01 with CEI pattern + `nonReentrant` modifier
2. **Immediate** — Replace oracle with Chainlink + access control on updates  
3. **Immediate** — Add health factor check in `liquidate()`
4. **Short term** — Implement consistent interest accrual across all operations
5. **Best practice** — Add pause mechanism for emergency response
6. **Best practice** — Consider formal verification for core accounting logic

---

## Tools Used

- Slither — static analysis
- Foundry — proof-of-exploit tests (4/4)
- Manual review — business logic analysis

---

## Disclaimer

This audit was performed for educational purposes as part of a blockchain
security portfolio. It does not constitute a guarantee of security. Smart
contracts should undergo multiple independent audits before mainnet deployment.