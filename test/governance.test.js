const MultiSigWallet = artifacts.require("./MultiSigWallet.sol")
const UpgradableContract = artifacts.require("./ServiceRegistry.sol")

contract('UpgradableContract', accounts => {  

  let multiSigInstances = new Array(2)
  let governedInstances = new Array(5)

  before(async () => {

    // Deploy a first multisig contract to be used as `governor` when deploying the upgradable contracts
    multiSigInstances[0] = await MultiSigWallet.new(
      [accounts[0], accounts[1], accounts[2]], // owners
      2 // required confirmations
    )

    // Deploy a second multisig contract to test transferring governance to a new governor
    multiSigInstances[1] = await MultiSigWallet.new(
      [accounts[3], accounts[4], accounts[5]], // owners
      2 // required confirmations
    )

    // Init 5 Governed contracts
    const governor1 = multiSigInstances[0].address
    governedInstances[0] = await UpgradableContract.new(governor1)
    governedInstances[1] = await UpgradableContract.new(governor1)
    governedInstances[2] = await UpgradableContract.new(governor1)
    governedInstances[3] = await UpgradableContract.new(governor1)
    governedInstances[4] = await UpgradableContract.new(governor1)

  })

  it("...should be governed by MultiSigWallet #1", async () => {
    const governor = await governedInstances[0].governor.call()
    assert(
      governor == multiSigInstances[0].address,
      "MultiSigWallet1 is the governor."
    )
  })

  it("...should be able to transfer governance of self to MultiSigWallet #2", async () => {
    // Encode transaction data to be executed by the multisig upon confirmation
    const txData = governedInstances[0].contract.methods.transferGovernance(
      multiSigInstances[1].address
    ).encodeABI()
    assert(txData.length, "Transaction data is constructed.")

    // Submit the transaction to the multisig for confirmation
    const transaction = await multiSigInstances[0].submitTransaction(
      governedInstances[0].address, // destination contract
      0, // value
      txData // transaction data
    )
    assert.isObject(transaction, "Transaction saved.")

    // Get the `transactionId` from the logs
    const transactionId = getParamFromTxEvent(
      transaction,
      'transactionId',
      null,
      'Submission'
    )
    assert(!isNaN(transactionId.toNumber()), "Transaction ID found.")

    // The transaction should be pending with only 1 confirmation
    let pendingTransactionCount = await multiSigInstances[0].getTransactionCount(
      true, // include pending
      false // include executed
    )
    assert(pendingTransactionCount.toNumber() === 1, "Transaction is pending.")

    // Confirm transaction from a second multisig owner account
    await multiSigInstances[0].contract.methods.confirmTransaction(
      transactionId.toNumber()
    ).send({from: accounts[1]})

    // Check status is no longer `pending`
    pendingTransactionCount = await multiSigInstances[0].getTransactionCount(
      true, // include pending
      false // include executed
    )
    assert(pendingTransactionCount.toNumber() === 0, "Transaction is not pending.")

    // Check that we now have 2 confirmations
    const confirmations = await multiSigInstances[0].getConfirmations(transactionId.toNumber())
    assert(confirmations.length === 2, "Transaction has 2 confirmations.")

    // Check that transaction status is `confirmed`
    const isConfirmed = await multiSigInstances[0].isConfirmed(transactionId.toNumber())
    assert(isConfirmed, "Transaction is confirmed.")

    // Check that 1 transaction has been `executed` 
    const executedTransactionCount = await multiSigInstances[0].getTransactionCount(
      false, // include pending
      true // include executed
    )
    assert(executedTransactionCount.toNumber() === 1, "Transaction has been executed.")

    // Governor of the upgradable contract should now be the second multisig contract
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