// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title OverflowTokenSecure
 * @notice Fix : pas de unchecked sur les calculs critiques
 *         + validation explicite du total avant transfert
 */
contract OverflowTokenSecure {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;
    string  public name   = "SecureToken";
    string  public symbol = "SCT";

    event Transfer(address indexed from, address indexed to, uint256 amount);

    constructor() {
        totalSupply          = 1_000_000 ether;
        balances[msg.sender] = totalSupply;
    }

    function transfer(address to, uint256 amount) public {
        require(balances[msg.sender] >= amount, "Insufficient");
        balances[msg.sender] -= amount;
        balances[to]         += amount;
        emit Transfer(msg.sender, to, amount);
    }

    function batchTransfer(
        address[] calldata recipients,
        uint256   amount
    ) public {
        require(recipients.length > 0,  "No recipients");
        require(amount > 0,             "Amount must be > 0");

        // Checked math — revert automatique si overflow
        uint256 total = recipients.length * amount;

        require(balances[msg.sender] >= total, "Insufficient balance");
        balances[msg.sender] -= total;

        for (uint256 i = 0; i < recipients.length; i++) {
            balances[recipients[i]] += amount;
            emit Transfer(msg.sender, recipients[i], amount);
        }
    }
}