require('@nomiclabs/hardhat-waffle');
require('@nomiclabs/hardhat-etherscan');
require('@nomiclabs/hardhat-ethers');
require('@openzeppelin/hardhat-upgrades');

const fs = require('fs');
const mnemonic = fs.readFileSync('.secret').toString().trim();
const bsc_scan_key = fs.readFileSync('.bsc_scan_key').toString().trim();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  // defaultNetwork: 'mainnet',
  networks: {
    localhost: {
      url: 'http://127.0.0.1:8545',
    },
    hardhat: {
      gas: 'auto',
    },
    localhost: {
      url: 'http://127.0.0.1:8545',
    },
    hardhat: {},
    testnet: {
      url: 'https://data-seed-prebsc-1-s1.binance.org:8545',
      chainId: 97,
      gasPrice: 10000000000,
      accounts: [mnemonic],
      gas: 9000000,
      timeout: 200000,
    },
    mainnet: {
      url: 'https://bsc-dataseed.binance.org/',
      chainId: 56,
      gasPrice: 10000000000,
      accounts: [mnemonic],
      gasLimit: 200000,
    },
  },
  solidity: {
    version: '0.6.12',
    settings: {
      evmVersion: 'istanbul',
      optimizer: {
        enabled: true,
        runs: 1,
      },
    },
  },
  etherscan: {
    apiKey: bsc_scan_key,
  },
};
