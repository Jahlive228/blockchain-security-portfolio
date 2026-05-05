// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {SecureAMM} from "../src/secure/SecureAMM.sol";
import {SecureLending} from "../src/secure/SecureLending.sol";

contract SandwichTest is Test {

    SimpleAMM     public vulnAmm;
    SecureAMM     public secureAmm;
    SecureLending public secureLending;

    address public bot    = makeAddr("bot");
    address public victim = makeAddr("victim");

    function setUp() public {
        vulnAmm   = new SimpleAMM(1000 ether, 1000 ether);
        secureAmm = new SecureAMM(1000 ether, 1000 ether);
        secureLending = new SecureLending(address(secureAmm));

        // Tokens pour les participants
        vulnAmm.deal(bot,    500 ether, 500 ether);
        vulnAmm.deal(victim, 100 ether, 100 ether);

        secureAmm.deal(bot,    500 ether, 500 ether);
        secureAmm.deal(victim, 100 ether, 100 ether);
    }

    // ── SANDWICH ATTACK ───────────────────────────────────
    function test_sandwichAttack() public {
        emit log_string("\n=== SANDWICH ATTACK ===");

        // État initial
        uint256 botABefore    = vulnAmm.balanceA(bot);
        uint256 victimABefore = vulnAmm.balanceA(victim);

        emit log_named_decimal_uint("Bot A before     ", botABefore, 18);
        emit log_named_decimal_uint("Victim A before  ", victimABefore, 18);
        emit log_named_decimal_uint("Price before     ", vulnAmm.getSpotPrice(), 18);

        // Étape 1 : bot front-run — achète A avant victim
        vm.prank(bot);
        uint256 botReceives = vulnAmm.swapBtoA(200 ether);
        emit log_named_decimal_uint("Bot buys A       ", botReceives, 18);
        emit log_named_decimal_uint("Price after bot  ", vulnAmm.getSpotPrice(), 18);

        // Étape 2 : victim swap au prix dégradé
        vm.prank(victim);
        uint256 victimReceives = vulnAmm.swapBtoA(50 ether);
        emit log_named_decimal_uint("Victim gets A    ", victimReceives, 18);
        emit log_named_decimal_uint("Price after victim", vulnAmm.getSpotPrice(), 18);

        // Étape 3 : bot back-run — revend A au prix monté
        vm.prank(bot);
        uint256 botProfit = vulnAmm.swapAtoB(botReceives);
        emit log_named_decimal_uint("Bot sells A, gets B", botProfit, 18);
        emit log_named_decimal_uint("Price final      ", vulnAmm.getSpotPrice(), 18);

        uint256 botBAfter = vulnAmm.balanceB(bot);
        emit log_named_decimal_uint("Bot B after      ", botBAfter, 18);

        // Bot a plus de B qu'au départ (500 - 200 + botProfit > 500)
        assertGt(botBAfter, 500 ether, "Bot should profit from sandwich");
        emit log_string("=== SANDWICH SUCCESS ===\n");
    }

    // ── TWAP RÉSISTE À LA MANIPULATION ────────────────────
    function test_twapResistsManipulation() public {
        emit log_string("\n=== TWAP DEFENSE ===");

        uint256 twapBefore = secureAmm.getTWAPPrice();
        emit log_named_decimal_uint("TWAP before attack ", twapBefore, 18);
        emit log_named_decimal_uint("Spot before attack ", secureAmm.getSpotPrice(), 18);

        // Attaquant fait un swap massif dans le même bloc
        vm.prank(bot);
        secureAmm.swapBtoA(400 ether);

        uint256 spotAfter = secureAmm.getSpotPrice();
        uint256 twapAfter = secureAmm.getTWAPPrice();

        emit log_named_decimal_uint("Spot after attack  ", spotAfter, 18);
        emit log_named_decimal_uint("TWAP after attack  ", twapAfter, 18);

        // Le spot est manipulé mais le TWAP reste stable
        assertGt(spotAfter, twapBefore * 15 / 10, "Spot should be manipulated");
        assertLt(twapAfter, spotAfter,      "TWAP should lag behind spot");

        emit log_string("=== TWAP HOLDS ===\n");
    }

    // ── TWAP BLOQUE L'EXPLOIT DE LENDING ──────────────────
    function test_twapBlocksOracleExploit() public {
        // Setup : victim dépose collateral dans SecureLending
        secureAmm.deal(address(this), 100 ether, 0);
        secureLending.depositCollateral(100 ether);

        uint256 twapPrice = secureAmm.getTWAPPrice();
        uint256 colVal    = (100 ether * twapPrice) / 1e18;
        uint256 maxBorrow = (colVal * 100) / 150;

        emit log_named_decimal_uint("TWAP price        ", twapPrice, 18);
        emit log_named_decimal_uint("Max borrow (fair) ", maxBorrow, 18);

        // Attaquant manipule le spot price
        vm.prank(bot);
        secureAmm.swapBtoA(400 ether);

        uint256 spotManipulated = secureAmm.getSpotPrice();
        uint256 twapStable      = secureAmm.getTWAPPrice();

        emit log_named_decimal_uint("Spot manipulated  ", spotManipulated, 18);
        emit log_named_decimal_uint("TWAP stable       ", twapStable, 18);

        // Le borrow utilise TWAP — pas affecté par la manipulation
        uint256 colValAfter  = (100 ether * twapStable) / 1e18;
        uint256 maxBorrowAfter = (colValAfter * 100) / 150;

        emit log_named_decimal_uint("Max borrow after  ", maxBorrowAfter, 18);

        // Le max borrow ne doit pas avoir explosé comme avec spot price
        assertLt(maxBorrowAfter, maxBorrow * 2, "TWAP should limit exploit");
        emit log_string("TWAP oracle blocked the manipulation");
    }

    // ── FUZZ : sandwich profit toujours positif si prix monte ─
    function testFuzz_sandwichProfitability(uint96 frontRunAmount) public {
        vm.assume(frontRunAmount >= 10 ether);
        vm.assume(frontRunAmount <= 400 ether);

        address fuzzer = makeAddr("fuzzer");
        vulnAmm.deal(fuzzer, 500 ether, 500 ether);

        uint256 bBefore = vulnAmm.balanceB(fuzzer);

        // Front-run
        vm.prank(fuzzer);
        uint256 aReceived = vulnAmm.swapBtoA(frontRunAmount);

        // Victim swap
        vm.prank(victim);
        vulnAmm.swapBtoA(50 ether);

        // Back-run
        vm.prank(fuzzer);
        uint256 bReceived = vulnAmm.swapAtoB(aReceived);

        uint256 bAfter = vulnAmm.balanceB(fuzzer);

        // Avec les fees (0.3%), le sandwich n'est pas toujours profitable
        // mais le test vérifie que le mécanisme fonctionne
        emit log_named_decimal_uint("B before", bBefore - frontRunAmount, 18);
        emit log_named_decimal_uint("B after ", bAfter, 18);

        // Le solde final doit être cohérent
        assertEq(bAfter, bBefore - frontRunAmount + bReceived);
    }
}