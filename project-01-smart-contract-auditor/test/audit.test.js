const { expect }        = require("chai");
const { ethers }        = require("hardhat");

// helpers
const ETH = (n) => ethers.parseEther(String(n));
const bal = async (addr) => ethers.provider.getBalance(addr);

// ─────────────────────────────────────────────
// SUITE 1 — VulnerableBank
// ─────────────────────────────────────────────
describe("VulnerableBank — exploit proof", function () {

  let bank, attacker, deployer, victim, attackerSigner;

  beforeEach(async function () {
    [deployer, victim, attackerSigner] = await ethers.getSigners();

    // Déploie la banque vulnérable
    const Bank = await ethers.getContractFactory("VulnerableBank");
    bank = await Bank.deploy();
    await bank.waitForDeployment();

    // Victim dépose 5 ETH — simule d'autres utilisateurs
    await bank.connect(victim).deposit({ value: ETH(5) });

    // Déploie le contrat attaquant
    const Attacker = await ethers.getContractFactory("Attacker");
    attacker = await Attacker.deploy(await bank.getAddress());
    await attacker.waitForDeployment();
  });

  it("victim deposits are recorded correctly", async function () {
    const balance = await bank.balances(victim.address);
    expect(balance).to.equal(ETH(5));
  });

  it("EXPLOIT: attacker drains VulnerableBank via reentrancy", async function () {
    const bankAddress     = await bank.getAddress();
    const attackerAddress = await attacker.getAddress();

    // Solde initial de la banque : 5 ETH (déposés par victim)
    const bankBefore = await bal(bankAddress);
    expect(bankBefore).to.equal(ETH(5));

    console.log("\n    [ATTACK START]");
    console.log(`    Bank before   : ${ethers.formatEther(bankBefore)} ETH`);

    // L'attaquant lance l'attaque avec 1 ETH
    await attacker.connect(attackerSigner).attack({ value: ETH(1) });

    const bankAfter     = await bal(bankAddress);
    const attackerGains = await bal(attackerAddress);

    console.log(`    Bank after    : ${ethers.formatEther(bankAfter)} ETH`);
    console.log(`    Attacker hold : ${ethers.formatEther(attackerGains)} ETH`);
    console.log(`    Attack count  : ${await attacker.attackCount()}`);
    console.log("    [ATTACK END]\n");

    // La banque doit être vidée (ou presque)
    expect(bankAfter).to.be.lt(ETH(1));
    // L'attaquant doit avoir plus que son dépôt initial
    expect(attackerGains).to.be.gt(ETH(1));
  });

  it("normal withdraw works before exploit", async function () {
    const before = await bal(victim.address);
    await bank.connect(victim).withdraw();
    const after = await bal(victim.address);
    // Victim récupère ses 5 ETH (moins le gas)
    expect(after).to.be.gt(before);
  });
});

// ─────────────────────────────────────────────
// SUITE 2 — SecureBank
// ─────────────────────────────────────────────
describe("SecureBank — attack blocked", function () {

  let bank, attacker, deployer, victim, attackerSigner;

  beforeEach(async function () {
    [deployer, victim, attackerSigner] = await ethers.getSigners();

    // Déploie la banque sécurisée
    const Bank = await ethers.getContractFactory("SecureBank");
    bank = await Bank.deploy();
    await bank.waitForDeployment();

    // Victim dépose 5 ETH
    await bank.connect(victim).deposit({ value: ETH(5) });

    // Réutilise Attacker en le pointant vers SecureBank
    const Attacker = await ethers.getContractFactory("Attacker");
    attacker = await Attacker.deploy(await bank.getAddress());
    await attacker.waitForDeployment();
  });

  it("DEFENSE: reentrancy attack reverts on SecureBank", async function () {
    const bankAddress = await bank.getAddress();
    const bankBefore  = await bal(bankAddress);

    console.log("\n    [ATTACK ATTEMPT ON SECURE BANK]");
    console.log(`    Bank before   : ${ethers.formatEther(bankBefore)} ETH`);

    // L'attaque doit être revertée par nonReentrant
    await expect(
      attacker.connect(attackerSigner).attack({ value: ETH(1) })
    ).to.be.reverted;

    const bankAfter = await bal(bankAddress);
    console.log(`    Bank after    : ${ethers.formatEther(bankAfter)} ETH`);
    console.log("    [ATTACK BLOCKED]\n");

    // La banque conserve ses fonds
    expect(bankAfter).to.be.gte(ETH(5));
  });

  it("normal deposit and withdraw still works", async function () {
    const before = await bal(victim.address);
    await bank.connect(victim).withdraw();
    const after = await bal(victim.address);
    expect(after).to.be.gt(before);
  });

  it("double withdraw is blocked", async function () {
    await bank.connect(victim).withdraw();
    // Deuxième withdraw doit échouer — solde = 0
    await expect(
      bank.connect(victim).withdraw()
    ).to.be.revertedWith("Nothing to withdraw");
  });
});