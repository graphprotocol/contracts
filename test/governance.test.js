const MultiSigWallet = artifacts.require("./MultiSigWallet.sol")
const UpgradableContract = artifacts.require("./GNS.sol")

contract('UpgradableContract', accounts => {  

  let multiSigInstances = new Array(2)
  let governedInstances = new Array(5)

  before(async () => {

    // Deploy the multisig contract first in order to use its address in deploying the upgradable contracts
    multiSigInstances[0] = await MultiSigWallet.new(
      [accounts[0], accounts[1], accounts[2]], // owners
      2 // required confirmations
    )

    // Deploy a second multisig contract to transfer ownership to
    multiSigInstances[1] = await MultiSigWallet.new(
      [accounts[3], accounts[4], accounts[5]], // owners
      2 // required confirmations
    )

    // Save the first MultiSig's address to set the upgradable contracts' `governor`
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
  })

  it("...should be able to transfer ownership of self to MultiSigWallet2", async () => {
    const txData = governedInstances[0].contract.methods.transferGovernance(
      multiSigInstances[1].address
    ).encodeABI()
    assert(txData.length, "Transaction data is constructed.")

    const transaction = await multiSigInstances[0].submitTransaction(
      governedInstances[0].address, // destination
      0, // value
      txData // byte data
    )
    assert.isObject(transaction, "Transaction saved.")

    const transactionId = getParamFromTxEvent(
      transaction,
      'transactionId',
      null,
      'Submission'
    )
    assert(!isNaN(transactionId.toNumber()), "Transaction ID returned.")

    let pendingTransactionCount = await multiSigInstances[0].getTransactionCount(
      true, // include pending
      false // include executed
    )
    assert(pendingTransactionCount.toNumber() === 1, "Transaction is pending.")

    // confirm transaction from a second multisig owner account
    await multiSigInstances[0].contract.methods.confirmTransaction(
      transactionId.toNumber()
    ).send({from: accounts[1]})

    // check pending status has changed
    pendingTransactionCount = await multiSigInstances[0].getTransactionCount(
      true, // include pending
      false // include executed
    )
    assert(pendingTransactionCount.toNumber() === 0, "Transaction is not pending.")

    // fetch confirmations
    const confirmations = await multiSigInstances[0].getConfirmations(transactionId.toNumber())
    assert(confirmations.length === 2, "Transaction has 2 confirmations.")

    // check confimation status
    const isConfirmed = await multiSigInstances[0].isConfirmed(transactionId.toNumber())
    assert(isConfirmed, "Transaction is confirmed.")

    // check transaction for executed status
    const executedTransactionCount = await multiSigInstances[0].getTransactionCount(
      false, // include pending
      true // include executed
    )
    assert(executedTransactionCount.toNumber() === 1, "Transaction has been executed.")

    assert.equal(
      await governedInstances[0].governor.call(), // contract's new governor
      multiSigInstances[1].address, // second multisig instance
      'Upgradable contract has new governor.'
    )

  })
  
})

// @todo Use a better method to parse event logs. This is limited
// @dev See possible replacment: https://github.com/rkalis/truffle-assertions
function getParamFromTxEvent(transaction, paramName, contractFactory, eventName) {
  assert.isObject(transaction)
  let logs = transaction.logs || transaction.events || []
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