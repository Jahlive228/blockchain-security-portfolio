// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title VulnerableVault
 * @notice Trois failles d'access control distinctes :
 *   1. mint() — pas de restriction, n'importe qui peut créer des tokens
 *   2. emergencyDrain() — vérifie tx.origin au lieu de msg.sender (bypassable)
 *   3. setAdmin() — l'admin actuel peut transférer les droits sans confirmation
 */
contract VulnerableVault {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;
    address public admin;

    event Mint(address indexed to, uint256 amount);
    event Drain(address indexed to, uint256 amount);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    constructor() {
        admin = msg.sender;
    }

    // VULN 1 : aucune restriction — tout le monde peut mint
    function mint(address to, uint256 amount) public {
        balances[to] += amount;
        totalSupply  += amount;
        emit Mint(to, amount);
    }

    // VULN 2 : tx.origin au lieu de msg.sender
    // Un contrat intermédiaire peut appeler cette fonction
    // si la victime (tx.origin == admin) interagit avec lui
    function emergencyDrain(address to) public {
        require(tx.origin == admin, "Not admin");
        uint256 amount = address(this).balance;
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "Transfer failed");
        emit Drain(to, amount);
    }

    // VULN 3 : changement d'admin sans timelock ni confirmation
    // Un admin compromis peut immédiatement transférer le contrôle
    function setAdmin(address newAdmin) public {
        require(msg.sender == admin, "Not admin");
        emit AdminChanged(admin, newAdmin);
        admin = newAdmin;
    }

    function deposit() public payable {
        balances[msg.sender] += msg.value;
    }

    receive() external payable {}
}