// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title SecureBank
 * @notice Version corrigée de VulnerableBank
 * @dev Applique le pattern CEI + ReentrancyGuard
 */
contract SecureBank {
    mapping(address => uint256) public balances;
    bool private _locked;

    // Events — bonne pratique pour l'audit trail
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);

    // ReentrancyGuard maison (même logique qu'OpenZeppelin)
    modifier nonReentrant() {
        require(!_locked, "ReentrancyGuard: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    function deposit() public payable {
        require(msg.value > 0, "Amount must be > 0");
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw() public nonReentrant {
        // CHECK : vérifier les conditions
        uint256 amount = balances[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        // EFFECT : mettre à jour l'état EN PREMIER
        balances[msg.sender] = 0;

        // INTERACT : seulement après les mises à jour
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");

        emit Withdrawal(msg.sender, amount);
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}