require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: {
    compilers: [
      { version: "0.8.28" },
    ]
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
    }
  }
};