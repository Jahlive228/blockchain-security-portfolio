# Blockchain Security Portfolio

Hands-on blockchain security projects built toward a professional
audit career (2026 roadmap).

Each project targets real-world vulnerability classes with
proof-of-exploit tests, remediation, and automated tooling.

## Projects

### Project 01 — Smart Contract Auditor
Reentrancy detection and exploitation pipeline.
- Slither static analysis → structured JSON
- REST audit API + n8n alert workflow (Discord)
- Hardhat v2 proof-of-exploit : 5 ETH drained, attack blocked
- GitHub Actions CI blocking merges on critical findings

**Stack:** Solidity · Hardhat v2 · Slither · Python · n8n

---

### Project 02 — Attack Lab
Three vulnerability classes with Foundry — exploit + fix + fuzz.

| Vulnerability | Impact | Status |
|---|---|---|
| Cross-function reentrancy | Balance duplication | Exploited + Fixed |
| Integer overflow (BEC-style) | Infinite token mint | Exploited + Fixed |
| Access control (tx.origin, mint, timelock) | Full vault drain | Exploited + Fixed |

**Stack:** Solidity · Foundry · Fuzz testing (768 runs)

---

### Project 03 — DeFi Security *(coming soon)*
Flash loan attacks, price manipulation, sandwich attacks on
a Uniswap V2 fork.

---

### Project 04 — On-chain Monitor *(coming soon)*
Real-time suspicious transaction monitoring with n8n + SIEM.

## Vulnerability Coverage

- Reentrancy (same-function, cross-function)
- Integer overflow / underflow
- Access control bypass (tx.origin, missing modifier, no timelock)
- Flash loan price manipulation *(P03)*
- Sandwich attack *(P03)*

## Tools

Slither · Foundry · Hardhat · Python · n8n · GitHub Actions