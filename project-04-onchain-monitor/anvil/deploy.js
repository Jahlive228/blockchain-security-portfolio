/**
 * deploy.js — déploie MonitorTarget sur Anvil local
 * Usage : node anvil/deploy.js
 */

const { execSync } = require("child_process");
const fs           = require("fs");
const path         = require("path");

const RPC_URL   = "http://127.0.0.1:8545";
// Clé privée du compte 0 d'Anvil (publique, réseau local uniquement)
const PRIV_KEY  = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

async function deploy() {
    console.log("[*] Compiling contracts...");
    execSync("forge build", { stdio: "inherit" });

    // Lit l'ABI et le bytecode compilés par Forge
    const artifactPath = path.join(
        __dirname, "..", "out", "MonitorTarget.sol", "MonitorTarget.json"
    );

    if (!fs.existsSync(artifactPath)) {
        console.error("[-] Artifact not found. Run: forge build");
        process.exit(1);
    }

    const artifact = JSON.parse(fs.readFileSync(artifactPath));
    const bytecode = artifact.bytecode.object;

    console.log("[*] Deploying MonitorTarget to Anvil...");

    // Déploie via forge create
    const result = execSync(
        `forge create contracts/MonitorTarget.sol:MonitorTarget \
         --rpc-url ${RPC_URL} \
         --private-key ${PRIV_KEY} \
         --broadcast`,
        { encoding: "utf8" }
    );

    // Extrait l'adresse déployée
    const match = result.match(/Deployed to: (0x[a-fA-F0-9]{40})/);
    if (!match) {
        console.error("[-] Could not extract deployed address");
        console.log(result);
        process.exit(1);
    }

    const contractAddress = match[1];
    console.log(`[+] MonitorTarget deployed at: ${contractAddress}`);

    // Sauvegarde l'adresse pour le monitor
    const config = {
        contractAddress,
        rpcUrl:     RPC_URL,
        deployedAt: new Date().toISOString(),
    };

    fs.writeFileSync(
        path.join(__dirname, "..", "monitor", "config.json"),
        JSON.stringify(config, null, 2)
    );

    console.log("[+] Config saved to monitor/config.json");
    return contractAddress;
}

deploy().catch(console.error);