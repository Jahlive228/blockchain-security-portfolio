// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title OverflowToken
 * @notice Reproduit le bug BEC token (2018)
 *         batchTransfer utilise unchecked — overflow intentionnel
 *         uint256 max = 115792089237316195423570985008687907853269984665640564039457584007913129639935
 *         Si amount * recipients overflow → résultat minuscule
 *         → require(balance >= total) passe
 *         → chaque recipient reçoit amount énorme
 */
contract OverflowToken {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;
    string  public name   = "OverflowToken";
    string  public symbol = "OVF";

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

    // VULN : unchecked désactive la protection overflow de 0.8.x
    // Reproduit exactement le comportement de Solidity < 0.8.0
    function batchTransfer(
        address[] calldata recipients,
        uint256   amount
    ) public {
        uint256 total;
        unchecked {
            total = recipients.length * amount; // overflow ici si amount énorme
        }
        require(balances[msg.sender] >= total, "Insufficient balance");
        balances[msg.sender] -= total;

        for (uint256 i = 0; i < recipients.length; i++) {
            unchecked {
                balances[recipients[i]] += amount;
            }
            emit Transfer(msg.sender, recipients[i], amount);
        }
    }
}