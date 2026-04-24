// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title CrossReentrancy
 * @notice Vulnérable : withdraw() et transfer() partagent
 *         le même mapping balances non mis à jour avant l'appel externe
 */
contract CrossReentrancy {
    mapping(address => uint256) public balances;

    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function deposit() public payable {
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    // VULN : envoie ETH avant de mettre balances à zéro
    // pendant l'appel externe, transfer() voit encore l'ancien solde
    function withdraw() public {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");

        balances[msg.sender] = 0; // trop tard
    }

    // Appelable pendant le callback — balances pas encore remis à 0
    function transfer(address to, uint256 amount) public {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}