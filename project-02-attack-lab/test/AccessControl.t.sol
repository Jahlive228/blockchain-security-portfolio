// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/AccessControl.sol";
import "../src/TxOriginAttacker.sol";
import "../src/AccessControlSecure.sol";

contract AccessControlTest is Test {

    VulnerableVault    public vulnVault;
    SecureVault        public secureVault;
    TxOriginAttacker   public txAttacker;

    address public admin     = makeAddr("admin");
    address public attacker  = makeAddr("attacker");
    address public user      = makeAddr("user");

    function setUp() public {
        vm.prank(admin);
        vulnVault = new VulnerableVault();

        vm.prank(admin);
        secureVault = new SecureVault();

        // Dépose 10 ETH dans les deux vaults
        vm.deal(address(vulnVault),  10 ether);
        vm.deal(address(secureVault), 10 ether);

        // Déploie l'attaquant tx.origin
        vm.prank(attacker);
        txAttacker = new TxOriginAttacker(address(vulnVault));
    }

    // ── VULN 1 : mint sans restriction ───────────────────
    function test_unauthorizedMint() public {
        uint256 before = vulnVault.balances(attacker);

        vm.prank(attacker);
        vulnVault.mint(attacker, 1_000_000 ether);

        uint256 afterMint = vulnVault.balances(attacker);
        emit log_named_decimal_uint("Minted by attacker", afterMint, 18);

        assertEq(afterMint - before, 1_000_000 ether);
    }

    function test_mintBlockedOnSecureVault() public {
        vm.prank(attacker);
        vm.expectRevert("Not admin");
        secureVault.mint(attacker, 1_000_000 ether);
    }

    // ── VULN 2 : tx.origin bypass ────────────────────────
    function test_txOriginExploit() public {
        uint256 vaultBefore    = address(vulnVault).balance;
        uint256 attackerBefore = attacker.balance;

        emit log_named_decimal_uint("Vault before  ", vaultBefore, 18);
        emit log_named_decimal_uint("Attacker before", attackerBefore, 18);

        // vm.startPrank(addr, txOrigin) — set les deux
        // simule : admin initie la tx → appelle claimReward()
        // tx.origin == admin → emergencyDrain passe
        vm.startPrank(admin, admin);
        txAttacker.claimReward();
        vm.stopPrank();

        uint256 vaultAfter    = address(vulnVault).balance;
        uint256 attackerAfter = attacker.balance;

        emit log_named_decimal_uint("Vault after   ", vaultAfter, 18);
        emit log_named_decimal_uint("Attacker after", attackerAfter, 18);

        assertEq(vaultAfter,    0,        "Vault should be drained");
        assertEq(attackerAfter, 10 ether, "Attacker should have 10 ETH");
    }

    function test_txOriginBlockedOnSecureVault() public {
        vm.startPrank(admin, admin);
        TxOriginAttacker secureAttacker = new TxOriginAttacker(
            address(secureVault)
        );
        vm.expectRevert("Not admin");
        secureAttacker.claimReward();
        vm.stopPrank();
    }

    // ── VULN 3 : timelock sur changement d'admin ─────────
    function test_timelockEnforced() public {
        vm.prank(admin);
        secureVault.proposeAdmin(attacker);

        // Tentative immédiate — doit revert
        vm.prank(attacker);
        vm.expectRevert("Timelock active");
        secureVault.acceptAdmin();

        // Avance le temps de 2 jours (Foundry cheat code)
        vm.warp(block.timestamp + 2 days);

        // Maintenant ça passe
        vm.prank(attacker);
        secureVault.acceptAdmin();

        assertEq(secureVault.admin(), attacker, "Admin should have changed");
    }

    // ── FUZZ : mint ne doit jamais marcher sans admin ─────
    function testFuzz_onlyAdminCanMint(
        address caller,
        uint256 amount
    ) public {
        vm.assume(caller != admin);
        vm.assume(caller != address(0));
        vm.assume(amount > 0 && amount < type(uint128).max);

        vm.prank(caller);
        vm.expectRevert("Not admin");
        secureVault.mint(caller, amount);
    }
}