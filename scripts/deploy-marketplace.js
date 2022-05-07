const hre = require("hardhat");
var argv = require('minimist')(process.argv.slice(2));

async function main() {
    console.log(argv)
    if(argv){
        const env = argv._[0]
        if(env == "test"){
            const Market = await hre.ethers.getContractFactory("Turtlesea");
            const market = await Market.deploy();

            await market.deployed();
            console.log("Market deployed to:", market.address);
        }
        else{

        }
    }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });