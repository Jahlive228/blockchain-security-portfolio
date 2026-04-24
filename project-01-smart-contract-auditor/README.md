# Smart Contract Security Auditor

Automated security audit pipeline for Solidity smart contracts.
Built as part of a blockchain security career path (2026).

## What this project demonstrates

- Identification and exploitation of Reentrancy vulnerabilities (DAO attack vector)
- Remediation using the Checks-Effects-Interactions pattern + ReentrancyGuard
- Static analysis automation with Slither
- Proof-of-exploit via Hardhat v2 tests (6/6 passing)
- REST audit API exposing Slither as a service
- n8n workflow for real-time Discord security alerts
- GitHub Actions CI blocking merges on critical findings

## Audit Results

| Contract        | Critical | High | Medium | Info | Status  |
|-----------------|----------|------|--------|------|---------|
| VulnerableBank  | 1        | 0    | 1      | 1    | UNSAFE  |
| SecureBank      | 0        | 0    | 0      | 1    | CLEAN   |

## Exploit Proof

Attack on `VulnerableBank` (Hardhat test):
- Victim deposits: 5 ETH
- Attacker deposits: 1 ETH
- After attack — Bank: 0 ETH | Attacker: 6 ETH
- Reentrancy loop count: 5

Attack on `SecureBank` → reverted by `nonReentrant` modifier.

## Stack

Solidity 0.8.28 · Hardhat 2.28 · Slither · Python · n8n · GitHub Actions

## Project Structure

contracts/
├── VulnerableBank.sol   # Intentionally vulnerable (reentrancy)
├── SecureBank.sol       # Fixed — CEI pattern + ReentrancyGuard
└── Attacker.sol         # Exploit contract
scripts/
├── run_audit.py         # Slither → structured JSON
├── audit_server.py      # REST API (port 8765)
└── submit_audit.sh      # CLI audit submission
test/
└── audit.test.js        # 6 Hardhat tests — exploit + defense
n8n-workflows/
└── smart-contract-auditor.json
reports/
└── audit-vulnerablebank.md

## Running the project

```bash
# Tests
npx hardhat test

# Static analysis
python scripts/run_audit.py contracts/VulnerableBank.sol

# Audit API
python scripts/audit_server.py

# n8n pipeline
n8n start  # then import n8n-workflows/smart-contract-auditor.json
```

## Key vulnerability — Reentrancy

Root cause in `VulnerableBank.withdraw()`:
```solidity
// State updated AFTER external call — exploitable
(bool success, ) = msg.sender.call{value: amount}("");
balances[msg.sender] = 0; // too late
```

Fix in `SecureBank.withdraw()`:
```solidity
// CEI: state updated BEFORE external call
balances[msg.sender] = 0;
(bool success, ) = msg.sender.call{value: amount}("");
```