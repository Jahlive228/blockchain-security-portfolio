// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title CrossReentrancySecure
 * @notice Fix : nonReentrant sur TOUTES les fonctions
 *         qui lisent ou écrivent balances
 *         + pattern CEI dans withdraw()
 */
contract CrossReentrancySecure {
    mapping(address => uint256) public balances;
    bool private _locked;

    event Deposit(address indexed user, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);

    modifier nonReentrant() {
        require(!_locked, "Reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    function deposit() public payable nonReentrant {
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw() public nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        // CEI : state d'abord
        balances[msg.sender] = 0;

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");

        emit Withdrawal(msg.sender, amount);
    }

    // nonReentrant bloque l'appel depuis un callback
    function transfer(address to, uint256 amount) public nonReentrant {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to]         += amount;
        emit Transfer(msg.sender, to, amount);
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}