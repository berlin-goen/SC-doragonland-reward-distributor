/**
 * Doragonland
 *
 * Description.
 *
 * @link   https://github.com/creator-blockchains/creator-token-distributor
 * a script file to deploy of locker contract
 * @author Doragonland.
 * @since  Aug 25, 2021
 */

const { ethers, upgrades } = require('hardhat');


const fs = require("fs");
const path = require("path");
require('dotenv').config();

const writeData = async (p, data) => {
    const fsPromises = fs.promises;
    await fsPromises
        .writeFile(p, JSON.stringify(data))
        .catch((err) => console.log("Failed to write file", err));
};

async function deployProxySC(name, args = null) {
    let contractFactoryDeploy;
    let contractFactory = await ethers.getContractFactory(name);
    if (args) {
        contractFactoryDeploy = await upgrades.deployProxy(contractFactory, args);
    } else {
        contractFactoryDeploy = await upgrades.deployProxy(contractFactory);
    }

    let deployedSC = await contractFactoryDeploy.deployed();
    return {
        contract: deployedSC,
        address: contractFactoryDeploy.address
    }
}

async function main() {
    let farmingPool = await deployProxySC('DualTokenLocker', [
        process.env.DOR_DISTR_TOKEN_ADDRESS, 
        process.env.GOLD_DISTR_TOKEN_ADDRESS
    ])
    console.log(farmingPool)
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
