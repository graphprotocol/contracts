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
    console.log(`\tMultiSigWallet1 address: ${multiSigInstances[0].address}`)

    // Deploy second multisig contract
    multiSigInstances[1] = await MultiSigWallet.new(
      accounts, 
      1 // require only 1 confirmation
    )
    console.log(`\tMultiSigWallet2 address: ${multiSigInstances[1].address}`)

    // Save the MultiSig's address to set the upgradable contracts' `governor`
    const governor1 = multiSigInstances[0].address

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
    const txData = governedInstances[0].contract.methods.transferGovernance(multiSigInstances[1].address).encodeABI()
    // console.log({txData})

    const transaction = await multiSigInstances[0].submitTransaction(
      governedInstances[0].address, // destination
      0, // value
      txData // byte data
    )
    // console.log({transaction})

    const transactionId = getParamFromTxEvent(
      transaction,
      'transactionId',
      null,
      'Submission'
    )
    // console.log({transactionId})

    // await multiSigInstances[0].contract.methods.confirmTransaction(transactionId).call({from: accounts[1]})
    assert.equal(await governedInstances[0].governor.call(), multiSigInstances[1].address)

  })
  
})

function getParamFromTxEvent(transaction, paramName, contractFactory, eventName) {
  assert.isObject(transaction)
  let logs = transaction.logs || []
  if(eventName != null) {
      logs = logs.filter((l) => l.event === eventName)
  }
  assert.equal(logs.length, 1, 'too many logs found!')
  let param = logs[0].args[paramName]
  if(contractFactory != null) {
      let contract = contractFactory.at(param)
      assert.isObject(contract, `getting ${paramName} failed for ${param}`)
      return contract
  } else {
      return param
  }
}