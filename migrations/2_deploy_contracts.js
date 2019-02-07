const GraphToken = artifacts.require("GraphToken")
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

  // Deploy the token contract
  .then(multiSigContract => deployer.deploy(
    GraphToken, 
    multiSigContract.contract._address, // governor
    1000000 // initial supply
  ))

}
