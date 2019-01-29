const MultiSigWallet = artifacts.require("./MultiSigWallet.sol")
const UpgradableContract = artifacts.require("./UpgradableContract.sol")
// const Web3 = require('web3')
// const web3 = new Web3(Web3.givenProvider || "ws://localhost:8545")
// const web3 = MultiSigWallet.web3

contract('UpgradableContract', accounts => {  

  let multiSigInstances = new Array(2)
  let governedInstances = new Array(5)

  before(async () => {

    // Upgradable contracts are owned by the multisig wallet via Governance
    // Deploy the multisig contract first in order to use its address in deploying the upgradable contracts
    multiSigInstances[0] = await MultiSigWallet.new(
      accounts, 
      1 // require only 1 confirmation
    )
    // Deploy second multisig contract
    multiSigInstances[1] = await MultiSigWallet.new(
      accounts, 
      1 // require only 1 confirmation
    )

    // Save the MultiSig's address to set the upgradable contracts' `governor`
    const governor1 = multiSigInstances[0].address
    console.log(`\tMultiSigWallet1 address: ${governor1}`)
    console.log(`\tMultiSigWallet2 address: ${multiSigInstances[1].address}`)

    // Init 5 Governed contracts
    governedInstances[0] = await UpgradableContract.new(governor1)
    governedInstances[1] = await UpgradableContract.new(governor1)
    governedInstances[2] = await UpgradableContract.new(governor1)
    governedInstances[3] = await UpgradableContract.new(governor1)
    governedInstances[4] = await UpgradableContract.new(governor1)

  })

  it("...should be owned by MultiSigWallet", async () => {
    const governor = await governedInstances[0].governor.call()
    assert(
      governor == multiSigInstances[0].address,
      "MultiSigWallet1 is the governor."
    )
    console.log(`\tGovernor of UpgradableContract1 is ${governor}`)
  })

  it("...should be able to transfer ownership of self to MultiSigWallet2", async () => {
    // const txData = await governedInstances[0].transferGovernance.getData(multiSigInstances[1].address)
    // const txData = await governedInstances[0].contract.methods.transferGovernance.getData(multiSigInstances[1].address)
    // const txData = governedInstances[0].transferGovernance(multiSigInstances[1]).encodeABI()
    // const txData = governedInstances[0].contract.methods.transferGovernance(multiSigInstances[1]).encodeABI()
    // const myContract = new web3.eth.Contract(governedInstances[1].contract._jsonInterface)
    // const txData = myContract.transferGovernance.getData(multiSigInstances[1].address)
    // console.log({
    //   txData,
    // })
  })
  
})
