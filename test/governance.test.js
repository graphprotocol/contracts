const MultiSigWallet = artifacts.require('./MultiSigWallet.sol')
const ServiceRegistry = artifacts.require('./ServiceRegistry.sol')

// helpers
const helpers = require('./lib/testHelpers')
const GraphProtocol = require('../graphProtocol.js')
const gp = GraphProtocol() // initialize GraphProtocol library

contract('Governance', accounts => {
  let multiSigInstance1, multiSigInstance2

  before(async () => {
    // Deploy a first multisig contract to be used as `governor` when deploying the upgradable contracts
    multiSigInstance1 = await MultiSigWallet.new(
      [accounts[0], accounts[1], accounts[2]], // owners
      2, // required confirmations
    )

    // Deploy a second multisig contract to test transferring governance to a new governor
    multiSigInstance2 = await MultiSigWallet.new(
      [accounts[3], accounts[4], accounts[5]], // owners
      2, // required confirmations
    )

    // Deploy a Governed contract with multiSigInstance1 as the `governor`
    this.governedContractInstance = await ServiceRegistry.new(
      multiSigInstance1.address,
    )
  })

  it('...should be governed by MultiSigWallet #1', async () => {
    const governor = await this.governedContractInstance.governor.call()
    assert(
      governor === multiSigInstance1.address,
      'MultiSigWallet1 is not the governor.',
    )
  })

  it('...should be able to transfer governance of self to MultiSigWallet #2', async () => {
    const txData = gp.abiEncode(
      this.governedContractInstance.contract.methods.transferGovernance,
      [multiSigInstance2.address],
    )
    assert(txData.length, 'Transaction data was not constructed.')

    // Submit the transaction to the multisig for confirmation
    const transaction = await multiSigInstance1.submitTransaction(
      this.governedContractInstance.address, // destination contract
      0, // value
      txData, // transaction data
    )

    // Get the `transactionId` from the logs
    const transactionId = helpers.getParamFromTxEvent(
      transaction,
      'transactionId',
      null,
      'Submission',
    )
    assert(!isNaN(transactionId.toNumber()), 'Transaction ID was not found.')

    // The transaction should be pending with only 1 confirmation
    let pendingTransactionCount = await multiSigInstance1.getTransactionCount(
      true, // include pending
      false, // include executed
    )
    assert(
      pendingTransactionCount.toNumber() === 1,
      'Transaction is not pending.',
    )

    // Confirm transaction from a second multisig owner account
    await multiSigInstance1.contract.methods
      .confirmTransaction(transactionId.toNumber())
      .send({ from: accounts[1], gas: 6e6 })

    // Check status is no longer `pending`
    pendingTransactionCount = await multiSigInstance1.getTransactionCount(
      true, // include pending
      false, // include executed
    )
    assert(
      pendingTransactionCount.toNumber() === 0,
      'Transaction is not pending.',
    )

    // Check that we now have 2 confirmations
    const confirmations = await multiSigInstance1.getConfirmations(
      transactionId.toNumber(),
    )
    assert(
      confirmations.length === 2,
      'Transaction does not have 2 confirmations.',
    )

    // Check that transaction status is `confirmed`
    const isConfirmed = await multiSigInstance1.isConfirmed(
      transactionId.toNumber(),
    )
    assert(isConfirmed, 'Transaction is not confirmed.')

    // Check that 1 transaction has been `executed`
    const executedTransactionCount = await multiSigInstance1.getTransactionCount(
      false, // include pending
      true, // include executed
    )
    assert(
      executedTransactionCount.toNumber() === 1,
      'Transaction has not been executed.',
    )

    // Governor of the upgradable contract should now be the second multisig contract
    assert.equal(
      await this.governedContractInstance.governor.call(), // contract's new governor
      multiSigInstance2.address, // second multisig instance
      'Upgradable contract does not have a new governor.',
    )
  })
})
