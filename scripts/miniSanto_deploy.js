async function main() {
    const [deployer] = await ethers.getSigners();
    const beginBalance = await deployer.getBalance();
  
    console.log("Deployer:", deployer.address);
    console.log("Balance:", ethers.utils.formatEther(beginBalance));

    const signer = "0x0";
    const startId = 1;
    const saleStartTime = 1721221200;
    const base = "ipfs://QmdB4AfzMsUTAwFfBLnVBoEtR9SfKZFA7L5aMDRfpzyACC/";
    const ext = "";

    const factory = await ethers.getContractFactory("LineaMiniSanto");
    const contract = await upgrades.deployProxy(factory, ["LineaMiniSanto", "MSTC", startId, saleStartTime, signer, base, ext]);
    await contract.deployed();
    console.log("contract: ", contract.address);

    // +++
    const endBalance = await deployer.getBalance();
    const gasSpend = beginBalance.sub(endBalance);

    console.log("\nLatest balance:", ethers.utils.formatEther(endBalance));
    console.log("Gas:", ethers.utils.formatEther(gasSpend));
  }

  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });