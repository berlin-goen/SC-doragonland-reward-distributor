const { ethers, upgrades } = require('hardhat');


async function deployErc() {
  let contractFactory;
  contractFactory = await ethers.getContractFactory('DualTokenLocker');
  contractFactoryDeploy = await upgrades.upgradeProxy('0x7Dace7db804Ba53e9e33503354eF45c620222132', contractFactory);
  await contractFactoryDeploy.deployed();
  console.log('DualTokenLocker upgrade to: ' + "0x6cA3741C6cd5020Ce9C93650A28124600A33edcE");
}

deployErc()
  .then(async () => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });