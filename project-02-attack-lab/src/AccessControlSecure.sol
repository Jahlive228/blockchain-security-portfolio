// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title SecureVault
 * @notice Fixes :
 *   1. mint() — onlyAdmin modifier
 *   2. emergencyDrain() — msg.sender au lieu de tx.origin
 *   3. setAdmin() — two-step transfer avec timelock 2 jours
 */
contract SecureVault {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;
    address public admin;

    // Two-step admin transfer
    address public pendingAdmin;
    uint256 public adminTransferETA;
    uint256 public constant TIMELOCK = 2 days;

    event Mint(address indexed to, uint256 amount);
    event Drain(address indexed to, uint256 amount);
    event AdminChangeProposed(address indexed proposed, uint256 eta);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    constructor() {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    // FIX 1 : mint réservé à l'admin
    function mint(address to, uint256 amount) public onlyAdmin {
        balances[to] += amount;
        totalSupply  += amount;
        emit Mint(to, amount);
    }

    // FIX 2 : msg.sender — un contrat intermédiaire ne peut pas bypasser
    function emergencyDrain(address to) public onlyAdmin {
        uint256 amount = address(this).balance;
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "Transfer failed");
        emit Drain(to, amount);
    }

    // FIX 3 : two-step transfer avec timelock
    function proposeAdmin(address newAdmin) public onlyAdmin {
        require(newAdmin != address(0), "Zero address");
        pendingAdmin     = newAdmin;
        adminTransferETA = block.timestamp + TIMELOCK;
        emit AdminChangeProposed(newAdmin, adminTransferETA);
    }

    function acceptAdmin() public {
        require(msg.sender == pendingAdmin,         "Not pending admin");
        require(block.timestamp >= adminTransferETA, "Timelock active");
        emit AdminChanged(admin, pendingAdmin);
        admin        = pendingAdmin;
        pendingAdmin = address(0);
    }

    function deposit() public payable {
        balances[msg.sender] += msg.value;
    }

    receive() external payable {}
}