const BN = web3.utils.BN
const { expect } = require('chai')
const { constants } = require('@openzeppelin/test-helpers')
const { ZERO_ADDRESS } = constants

// helpers
const deployment = require('../lib/deployment')
const channel = require('../lib/channel')

// constants
const DEFAULT_GAS = 80000

contract('Indexer Channel Operations', ([governor]) => {
  beforeEach(async function() {
    // Deploy graph token
    this.token = await deployment.deployGRT(governor, { from: governor })

    // Deploy epoch contract
    this.epochManager = await deployment.deployEpochManagerContract(governor, {
      from: governor,
    })

    // Deploy staking contract
    this.staking = await deployment.deployStakingContract(
      governor,
      this.token.address,
      this.epochManager.address,
      ZERO_ADDRESS,
      { from: governor },
    )

    // Get channel signers
    const [node, indexer] = await channel.getRandomFundedChannelSigners(
      2,
      'http://localhost:8545',
      governor,
      this.token,
    )
    this.node = node
    this.indexer = indexer

    // Deploy indexer multisig + interpreters
    const channelContracts = await deployment.deployIndexerMultisigWithContext(
      this.node.address,
      this.node.address,
    )
    this.multisig = channelContracts.multisig
    this.interpreters = {
      singleAsset: channelContracts.singleAssetInterpreter,
      multiAsset: channelContracts.multiAssetInterpreter,
      withdraw: channelContracts.withdrawInterpreter,
    }

    // Setup the multisig
    await this.multisig.setup([this.node.address, this.indexer.address])

    // Helpers
  })

  describe.only('funding + withdrawal', function() {
    // Establish test constants
    const ETH_DEPOSIT = new BN(175)
    const TOKEN_DEPOSIT = web3.utils.toWei(new BN(4))

    beforeEach(async function() {
      // Verify pre-deposit balances
      const preDepositEth = await web3.eth.getBalance(this.multisig.address)
      expect(preDepositEth).to.be.eq('0')
      const preDepositToken = await this.token.balanceOf(this.multisig.address)
      expect(preDepositToken.toString()).to.be.eq('0')

      // Fund multisig with eth and tokens
      await channel.fundMultisig(ETH_DEPOSIT, this.multisig.address, governor)
      await channel.fundMultisig(TOKEN_DEPOSIT, this.multisig.address, governor, this.token)

      // Verify post-deposit balances
      const postDepositEth = await web3.eth.getBalance(this.multisig.address)
      expect(postDepositEth).to.be.eq(ETH_DEPOSIT.toString())
      const postDepositToken = await this.token.balanceOf(this.multisig.address)
      expect(postDepositToken.toString()).to.be.eq(TOKEN_DEPOSIT.toString())
    })

    it('node should be able to withdraw eth', async function() {})

    it.only('node should be able to withdraw tokens', async function() {
      // Generate withdrawal commitment for node
      const commitment = new channel.MiniCommitment(this.multisig.address, [
        this.node,
        this.indexer,
      ])

      // Get signed multisig transaction to withdraw tokens
      const commitmentType = 'withdraw'
      const params = {
        assetId: this.token.address,
        amount: new BN(5),
        recipient: this.node.address,
        withdrawInterpreter: this.interpreters.withdraw.address,
      }
      const tx = await commitment.getSignedTransaction(commitmentType, params)

      const { to, value, data, operation } = commitment.getTransactionDetails(
        commitmentType,
        params,
      )
      const hash = await this.multisig.getTransactionHash(to, value, data, operation)
      console.log('contract generated hash', hash)

      // Send transaction
      await new Promise((resolve, reject) => {
        web3.eth
          .sendTransaction({ ...tx, from: this.node.address, gas: DEFAULT_GAS })
          .on('error', reject)
          .on('receipt', resolve)
      })

      // Verify post withdrawal balances
      const postWithdrawalEth = await web3.eth.getBalance(this.multisig.address)
      expect(postWithdrawalEth).to.be.eq(ETH_DEPOSIT.toString())
      const postWithdrawalToken = await this.token.balanceOf(this.multisig.address)
      expect(postWithdrawalToken.toString()).to.be.eq(TOKEN_DEPOSIT.sub(params.amount).toString())
    })

    it.skip('node should be able to withdraw eth', async function() {})

    it.skip('indexer should be able to withdraw tokens', async function() {})
  })
})
