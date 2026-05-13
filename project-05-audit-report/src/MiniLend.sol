// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title MiniLend
 * @notice Protocole de prêt simplifié inspiré de Compound V2
 *         Contient 4 vulnérabilités intentionnelles pour l'audit
 *
 *         VULN-01 : Reentrancy dans withdraw()
 *         VULN-02 : Price oracle manipulable (spot price)
 *         VULN-03 : Liquidation sans vérification de health factor
 *         VULN-04 : Pas de vérification de retour sur transfer
 */
contract MiniLend {

    // ── State ─────────────────────────────────────────────
    address public owner;
    address public priceOracle;

    // Dépôts des utilisateurs (collatéral)
    mapping(address => uint256) public deposits;
    // Emprunts des utilisateurs
    mapping(address => uint256) public borrows;
    // Réserves du protocole
    uint256 public totalReserves;
    // Taux d'intérêt annuel (en BPS, 500 = 5%)
    uint256 public interestRateBPS = 500;
    // Dernier timestamp de mise à jour des intérêts
    mapping(address => uint256) public lastInterestUpdate;

    // Health factor minimum pour emprunter : 150%
    uint256 public constant MIN_HEALTH_FACTOR = 150;
    // Health factor de liquidation : 110%
    uint256 public constant LIQ_HEALTH_FACTOR = 110;
    // Bonus de liquidation : 5%
    uint256 public constant LIQ_BONUS = 105;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Liquidate(
        address indexed liquidator,
        address indexed borrower,
        uint256 repaid,
        uint256 collateralSeized
    );
    event OracleUpdated(address indexed newOracle);

    constructor(address _oracle) {
        owner        = msg.sender;
        priceOracle  = _oracle;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ── Oracle ────────────────────────────────────────────

    function setOracle(address _oracle) external onlyOwner {
        priceOracle = _oracle;
        emit OracleUpdated(_oracle);
    }

    /**
     * @notice Retourne le prix ETH/USD depuis l'oracle
     * @dev VULN-02 : l'oracle est un contrat externe non vérifié
     *      Un owner malicieux ou compromis peut pointer vers
     *      un oracle malicieux
     */
    function getPrice() public view returns (uint256) {
        return IPriceOracle(priceOracle).getPrice();
    }

    // ── Core functions ────────────────────────────────────

    function deposit() external payable {
        require(msg.value > 0, "Zero deposit");
        deposits[msg.sender]      += msg.value;
        totalReserves             += msg.value;
        lastInterestUpdate[msg.sender] = block.timestamp;
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Retire le collatéral déposé
     * @dev VULN-01 : reentrancy — ETH envoyé avant mise à jour de l'état
     */
    function withdraw(uint256 amount) external {
        require(deposits[msg.sender] >= amount, "Insufficient deposit");

        // VULN-01 : appel externe AVANT mise à jour de l'état
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");

        // unchecked simule le comportement pré-0.8
        // sans ça, Solidity 0.8 revert sur underflow
        unchecked {
            deposits[msg.sender] -= amount;
            totalReserves        -= amount;
        }

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @notice Emprunte des ETH contre collatéral
     * @dev VULN-03 partielle : pas de vérification que le collatéral
     *      couvre bien le borrow après l'opération
     */
    function borrow(uint256 amount) external {
        require(amount > 0,           "Zero borrow");
        require(totalReserves >= amount, "Insufficient liquidity");

        uint256 price         = getPrice();
        uint256 depositValue  = (deposits[msg.sender] * price) / 1e18;
        uint256 currentDebt   = _debtWithInterest(msg.sender);
        uint256 newDebt       = currentDebt + amount;
        uint256 hf  = (depositValue * 100) / newDebt;

        require(hf >= MIN_HEALTH_FACTOR, "Undercollateralized");

        borrows[msg.sender]            = newDebt;
        lastInterestUpdate[msg.sender] = block.timestamp;
        totalReserves                  -= amount;

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Borrow transfer failed");

        emit Borrow(msg.sender, amount);
    }

    function repay() external payable {
        require(msg.value > 0, "Zero repay");
        uint256 debt = _debtWithInterest(msg.sender);
        require(debt > 0, "No debt");

        uint256 repaid = msg.value > debt ? debt : msg.value;
        borrows[msg.sender]            = debt - repaid;
        lastInterestUpdate[msg.sender] = block.timestamp;
        totalReserves                  += msg.value;

        emit Repay(msg.sender, repaid);
    }

    /**
     * @notice Liquide une position sous-collatéralisée
     * @dev VULN-03 : pas de vérification du health factor avant liquidation
     *      N'importe qui peut liquider n'importe quelle position
     *      même si elle est saine
     */
    function liquidate(address borrower) external payable {
        uint256 debt = _debtWithInterest(borrower);
        require(debt > 0, "No debt");

        // VULN-03 : la vérification du health factor est absente
        // Un liquidateur peut attaquer des positions saines

        uint256 repaid          = msg.value;
        uint256 collateralValue = (repaid * LIQ_BONUS) / 100;

        require(
            deposits[borrower] >= collateralValue,
            "Insufficient collateral"
        );

        borrows[borrower]   -= repaid > debt ? debt : repaid;
        deposits[borrower]  -= collateralValue;
        deposits[msg.sender] += collateralValue;
        totalReserves        += repaid;

        emit Liquidate(msg.sender, borrower, repaid, collateralValue);
    }

    // ── Internal ──────────────────────────────────────────

    function _debtWithInterest(address user) internal view returns (uint256) {
        uint256 principal = borrows[user];
        if (principal == 0) return 0;

        uint256 elapsed  = block.timestamp - lastInterestUpdate[user];
        uint256 interest = (principal * interestRateBPS * elapsed)
                         / (10000 * 365 days);
        return principal + interest;
    }

    function healthFactor(address user) public view returns (uint256) {
        uint256 debt = _debtWithInterest(user);
        if (debt == 0) return type(uint256).max;
        uint256 price        = getPrice();
        uint256 depositValue = (deposits[user] * price) / 1e18;
        return (depositValue * 100) / debt;
    }

    receive() external payable {}
}

interface IPriceOracle {
    function getPrice() external view returns (uint256);
}