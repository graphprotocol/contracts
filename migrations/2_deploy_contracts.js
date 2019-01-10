const Governance = artifacts.require("Governance")
const MultiSigWallet = artifacts.require("MultiSigWallet")
const GraphToken = artifacts.require("GraphToken")
const GNS = artifacts.require("GNS")
const Registry = artifacts.require("Registry")
const RewardManager = artifacts.require("RewardManager")
const Staking = artifacts.require("Staking")

module.exports = function(deployer, network, accounts) {

  // collect contract addresses to be owned by the multisig
  let contracts = []

  // deploy the ubgradable / owned contracts
  deployer.deploy(GraphToken) // contract 1
  .then(c => contracts.push(c.contract._address))

  .then(() => deployer.deploy(Staking)) // contract 2
  .then(c => contracts.push(c.contract._address))

  .then(() => deployer.deploy(GNS)) // contract 3
  .then(c => contracts.push(c.contract._address))

  .then(() => deployer.deploy(Registry)) // contract 4
  .then(c => contracts.push(c.contract._address))

  .then(() => deployer.deploy(RewardManager)) // contract 5
  .then(c => contracts.push(c.contract._address))

  // Multisig will own Governance, which will assign ownership of upgradable contracts
  .then(() => deployer.deploy(MultiSigWallet, accounts, Math.floor(accounts.length/2) || 1))
  .then(multiSigContract => deployer.deploy(
    Governance, 
    contracts, // upgradable contracts
    multiSigContract.contract._address // owner
  ))

}
