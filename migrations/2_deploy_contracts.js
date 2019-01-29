const MultiSigWallet = artifacts.require("MultiSigWallet")
const UpgradableContract = artifacts.require("UpgradableContract")

module.exports = function(deployer, network, accounts) {

  // We need the Multisig contract address to set as `governor for all upgradable contracts
  deployer.deploy(
    MultiSigWallet,
    accounts, // owners
    Math.floor(accounts.length/2) + 1 || 1 // require a majority
  )
  
  // Deploy the ubgradable / owned contracts
  .then(multiSigContract => deployer.deploy(
    UpgradableContract, 
    multiSigContract.contract._address // governor
  ))

}
