const { ethers, upgrades } = require('hardhat');


async function main() {
    let factory = await ethers.getContractFactory('DualTokenLocker');
    let sc = factory.attach('0x7Dace7db804Ba53e9e33503354eF45c620222132')
    await sc.batchUnlock([
        [7,8,9], 
        [4,4,4], 
        '0x2a9DC479b3fCC0F7904096c9dD888aAAdeDcdbA5', 
        [100000,100000,100000], 
        [100000,100000,100000], 
        [3,3,3], 
        [
            "0x2bd0ef0ded916b5ac67e3bfa4672cda2482facd385c3ab80ed5ec2bab767a7ad",
            "0x2e8ee23aaf7133fb68304eb857c356a0d4d00fcd0c4abddd132504f45e789c32",
            "0xec3e043a6404eb57851c7d0b87491b183dc0c5dd360ad0b40c10fd9bba8a9b96",
            "0x2bd0ef0ded916b5ac67e3bfa4672cda2482facd385c3ab80ed5ec2bab767a7ad",
            "0x2e8ee23aaf7133fb68304eb857c356a0d4d00fcd0c4abddd132504f45e789c32",
            "0xec3e043a6404eb57851c7d0b87491b183dc0c5dd360ad0b40c10fd9bba8a9b96",
            "0x2bd0ef0ded916b5ac67e3bfa4672cda2482facd385c3ab80ed5ec2bab767a7ad",
            "0x2e8ee23aaf7133fb68304eb857c356a0d4d00fcd0c4abddd132504f45e789c32",
            "0xec3e043a6404eb57851c7d0b87491b183dc0c5dd360ad0b40c10fd9bba8a9b96",
        ]
    ])
}


main()
  .then(async () => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });