// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/CrossReentrancy.sol";
import "../src/CrossAttacker.sol";
import "../src/CrossReentrancySecure.sol";

contract CrossReentrancyTest is Test {

    CrossReentrancy        public vulnBank;
    CrossReentrancySecure  public secureBank;
    CrossAttacker          public attacker;
    address                public accomplice;

    function setUp() public {
        vulnBank   = new CrossReentrancy();
        secureBank = new CrossReentrancySecure();
        accomplice = makeAddr("accomplice");

        // Victim dépose 5 ETH
        address victim = makeAddr("victim");
        vm.deal(victim, 5 ether);
        vm.prank(victim);
        vulnBank.deposit{value: 5 ether}();
    }

    // ── EXPLOIT ──────────────────────────────────────────
    function test_crossReentrancyExploit() public {
        attacker = new CrossAttacker(address(vulnBank), accomplice);
        vm.deal(address(attacker), 1 ether);

        uint256 bankBefore       = address(vulnBank).balance;
        uint256 accompliceBefore = accomplice.balance;

        emit log_named_decimal_uint("Bank before   ", bankBefore, 18);
        emit log_named_decimal_uint("Accomplice before", accompliceBefore, 18);

        attacker.attack{value: 1 ether}();

        uint256 bankAfter       = address(vulnBank).balance;
        uint256 accompliceAfter = vulnBank.balances(accomplice);

        emit log_named_decimal_uint("Bank after    ", bankAfter, 18);
        emit log_named_decimal_uint("Accomplice balance in bank", accompliceAfter, 18);

        // L'accomplice a reçu un solde qu'il ne devrait pas avoir
        assertGt(accompliceAfter, 0, "Exploit failed");
    }

    // ── DEFENSE ──────────────────────────────────────────
    function test_crossReentrancyBlocked() public {
        // Recréer avec secureBank
        CrossAttacker secureAttacker = new CrossAttacker(
            address(secureBank),
            accomplice
        );

        address victim = makeAddr("victim2");
        vm.deal(victim, 5 ether);
        vm.prank(victim);
        secureBank.deposit{value: 5 ether}();

        vm.deal(address(secureAttacker), 1 ether);

        uint256 bankBefore = address(secureBank).balance;

        // L'attaque doit revert
        vm.expectRevert();
        secureAttacker.attack{value: 1 ether}();

        uint256 bankAfter = address(secureBank).balance;
        assertGe(bankAfter, bankBefore, "Bank drained despite nonReentrant");
    }

    // ── FUZZ TEST ─────────────────────────────────────────
    // Foundry génère 1000 valeurs aléatoires pour amount
    function testFuzz_transferNeverExceedsBalance(
        uint96 depositAmt,
        uint96 transferAmt
    ) public {
        vm.assume(depositAmt > 0);
        vm.assume(transferAmt > 0);
        vm.assume(transferAmt <= depositAmt);

        address user = makeAddr("fuzzer");
        vm.deal(user, depositAmt);
        vm.prank(user);
        secureBank.deposit{value: depositAmt}();

        uint256 balBefore = secureBank.balances(user);

        vm.prank(user);
        secureBank.transfer(accomplice, transferAmt);

        uint256 balAfter = secureBank.balances(user);
        assertEq(balAfter, balBefore - transferAmt, "Balance mismatch after transfer");
    }
}