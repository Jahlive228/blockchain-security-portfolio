// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract VulnerableBank {
    mapping(address => uint256) public balances;

    function deposit() public payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() public {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        // VULN : ETH envoyé AVANT la mise à jour du solde
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");

        // Trop tard — l'attaquant a déjà re-appelé withdraw()
        balances[msg.sender] = 0;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}