// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title MonitorTarget
 * @notice Simule un protocole DeFi avec fonctions sensibles
 *         Le monitor surveille les appels à ces fonctions
 */
contract MonitorTarget {
    address public admin;
    address public pendingAdmin;

    mapping(address => uint256) public balances;
    uint256 public totalSupply;
    bool    public paused;

    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);
    event AdminProposed(address indexed proposed);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event LargeTransfer(address indexed from, address indexed to, uint256 amount);
    event EmergencyDrain(address indexed to, uint256 amount);

    uint256 public constant LARGE_TRANSFER_THRESHOLD = 100 ether;

    constructor() {
        admin = msg.sender;
        // Mint initial supply
        totalSupply          = 1_000_000 ether;
        balances[msg.sender] = totalSupply;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    // ── Fonctions sensibles surveillées ──────────────────

    function proposeAdmin(address newAdmin) external onlyAdmin {
        pendingAdmin = newAdmin;
        emit AdminProposed(newAdmin);
    }

    function acceptAdmin() external {
        require(msg.sender == pendingAdmin, "Not pending admin");
        emit AdminChanged(admin, pendingAdmin);
        admin        = pendingAdmin;
        pendingAdmin = address(0);
    }

    function mint(address to, uint256 amount) external onlyAdmin {
        balances[to] += amount;
        totalSupply  += amount;
        emit Mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyAdmin {
        require(balances[from] >= amount, "Insufficient");
        balances[from] -= amount;
        totalSupply    -= amount;
        emit Burn(from, amount);
    }

    function pause() external onlyAdmin {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyAdmin {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function transfer(address to, uint256 amount) external whenNotPaused {
        require(balances[msg.sender] >= amount, "Insufficient");
        balances[msg.sender] -= amount;
        balances[to]         += amount;

        if (amount >= LARGE_TRANSFER_THRESHOLD) {
            emit LargeTransfer(msg.sender, to, amount);
        }
    }

    function emergencyDrain(address to) external onlyAdmin {
        uint256 supply = totalSupply;
        balances[to]  += supply;
        balances[admin] = 0;
        emit EmergencyDrain(to, supply);
    }

    receive() external payable {}
}