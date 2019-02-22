// helpers
const helpers = require('./lib/testHelpers')
const GraphProtocol = require('../graphProtocol.js')

// contracts
const Staking = artifacts.require("./Staking.sol")
const MultiSigWallet = artifacts.require("./MultiSigWallet.sol")

// test scope variables
let deployedMultiSigWallet, deployedStaking, gp

contract('Staking (Upgradability)', accounts => {
  
  before(async () => {

    // deploy the multisig contract
    deployedMultiSigWallet = await MultiSigWallet.new(
      accounts, // owners
      1 // required confirmations
    )
    assert.isObject(deployedMultiSigWallet, "Deploy MultiSigWallet contract.")

    // deploy a contract we can encode a transaction for
    deployedStaking = await Staking.new(
      deployedMultiSigWallet.address // governor
    )
    assert.isObject(deployedStaking, "Deploy Staking contract.")

    // init Graph Protocol JS library with deployed staking contract
    gp = GraphProtocol({
      Staking: deployedStaking,
      MultiSigWallet: deployedMultiSigWallet
    })
    assert.isObject(gp, "Initialize the Graph Protocol library.")

  })

  it("...should be able to submit a transaction to the mulitsig contract", async () => {

    // Submit a transaction to the mulitsig via graphProtocol.js
    const setMinimumCurationStakingAmount = await gp.governance.setMinimumCurationStakingAmount(
      100, // amount
    )
    assert.isObject(
      setMinimumCurationStakingAmount, 
      "Transaction submitted to multisig."
    )

    // Get the `transactionId` from the logs
    const transactionId = helpers.getParamFromTxEvent(
      setMinimumCurationStakingAmount,
      'transactionId',
      null,
      'Submission'
    )
    assert(!isNaN(transactionId.toNumber()), "Transaction ID found.")

  })
  
})