// helpers
const helpers = require('../lib/testHelpers')
const GraphProtocol = require('../../graphProtocol.js')

// contracts
const GraphToken = artifacts.require('./GraphToken.sol')
const Staking = artifacts.require('./Staking.sol')
const MultiSigWallet = artifacts.require('./MultiSigWallet.sol')

/**
 * testing constants
 */
const initialSupply = 1000000,
  minimumCurationStakingAmount = 100,
  defaultReserveRatio = 10,
  minimumIndexingStakingAmount = 100,
  maximumIndexers = 10,
  slashingPercent = 10,
  thawingPeriod = 7

let deployedGraphToken, deployedMultiSigWallet, deployedStaking, gp

contract('Staking (Upgradability)', ([deployment, ...accounts]) => {
  before(async () => {
    // deploy the multisig contract
    deployedMultiSigWallet = await MultiSigWallet.new(
      accounts, // owners
      1, // required confirmations
      { from: deployment },
    )
    assert.isObject(deployedMultiSigWallet, 'Deploy MultiSigWallet contract.')
    assert(
      web3.utils.isAddress(deployedMultiSigWallet.address),
      'MultiSigWallet address is address.',
    )

    // deploy GraphToken with multisig as governor
    deployedGraphToken = await GraphToken.new(
      deployedMultiSigWallet.address, // <address> governor
      initialSupply, // <uint256> initialSupply
      { from: deployment },
    )
    assert.isObject(deployedGraphToken, 'Deploy GraphToken contract.')
    assert(
      web3.utils.isAddress(deployedGraphToken.address),
      'GraphToken address is address.',
    )

    // deploy a contract we can encode a transaction for
    deployedStaking = await Staking.new(
      deployedMultiSigWallet.address, // <address> governor
      minimumCurationStakingAmount, // <uint256> minimumCurationStakingAmount
      defaultReserveRatio, // <uint256> defaultReserveRatio
      minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
      maximumIndexers, // <uint256> maximumIndexers
      slashingPercent, // <uint256> slashingPercent
      thawingPeriod, // <uint256> thawingPeriod
      deployedGraphToken.address, // <address> token
      { from: deployment },
    )
    assert.isObject(deployedStaking, 'Deploy Staking contract.')
    assert(
      web3.utils.isAddress(deployedStaking.address),
      'Staking address is address.',
    )

    // init Graph Protocol JS library with deployed staking contract
    gp = GraphProtocol({
      GraphToken: deployedGraphToken,
      Staking: deployedStaking,
      MultiSigWallet: deployedMultiSigWallet,
    })
    assert.isObject(gp, 'Initialize the Graph Protocol library.')
  })

  it('...should be able to submit a transaction to the mulitsig contract', async () => {
    // Submit a transaction to the mulitsig via graphProtocol.js
    const setMinimumCurationStakingAmount = await gp.governance.setMinimumCurationStakingAmount(
      100, // amount
      accounts[0], // any multisigwallet owner can submit proposed transaction
    )
    assert.isObject(
      setMinimumCurationStakingAmount,
      'Transaction submitted to multisig.',
    )

    // Get the `transactionId` from the logs
    const transactionId = helpers.getParamFromTxEvent(
      setMinimumCurationStakingAmount,
      'transactionId',
      null,
      'Submission',
    )
    assert(!isNaN(transactionId.toNumber()), 'Transaction ID found.')
  })
})
