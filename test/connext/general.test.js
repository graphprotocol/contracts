const BN = web3.utils.BN
const { expect } = require('chai')

// helpers
const deployment = require('../lib/deployment')
const channel = require('../lib/channel')

// constants
const DEFAULT_GAS = 80000

contract('Indexer Channel Operations', ([governor]) => {
  beforeEach(async function() {
    // Deploy graph token
    this.token = await deployment.deployGRT(governor, { from: governor })

    // Get channel signers
    const [node, indexer] = await channel.getRandomFundedChannelSigners(
      2,
      'http://localhost:8545',
      governor,
      this.token,
    )
    this.node = node
    this.indexer = indexer

    // Deploy indexer multisig + CTDT + interpreters
    const channelContracts = await deployment.deployIndexerMultisigWithContext(this.node.address)
    this.multisig = channelContracts.multisig
    this.masterCopy = channelContracts.masterCopy
    this.indexerCTDT = channelContracts.ctdt
    this.interpreters = {
      singleAsset: channelContracts.singleAssetInterpreter,
      multiAsset: channelContracts.multiAssetInterpreter,
      withdraw: channelContracts.withdrawInterpreter,
    }
    this.mockStaking = channelContracts.mockStaking

    // Setup the multisig
    await this.masterCopy.setup([this.node.address, this.indexer.address])

    // Add channel to mock staking contract
    await this.mockStaking.setChannel(this.indexer.address)

    // Helpers
  })

  describe('funding + withdrawal', function() {
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
        amount: 5,
        recipient: this.node.address,
        withdrawInterpreterAddress: this.interpreters.withdraw.address,
        ctdt: this.indexerCTDT,
      }
      const tx = await commitment.getSignedTransaction(commitmentType, params)

      const { to, value, data, operation } = commitment.getTransactionDetails(
        commitmentType,
        params,
      )
      const hash = await this.masterCopy.getTransactionHash(to, value, data, operation)
      console.log('contract generated hash', hash)

      // TODO: remove this. trying to send directly to ctdt to debug where tx is failing
      const recipt = await new Promise((resolve, reject) => {
        web3.eth
          .sendTransaction({
            to: params.ctdt.address,
            value: 0,
            data,
            from: this.node.address,
            gas: DEFAULT_GAS * 10,
          })
          .on('error', reject)
          .on('receipt', resolve)
      })
      console.log('recipt: ', recipt)

      // Send transaction
      await new Promise((resolve, reject) => {
        web3.eth
          .sendTransaction({ ...tx, from: this.node.address, gas: DEFAULT_GAS * 10 })
          .on('error', reject)
          .on('receipt', resolve)
      })

      // Verify post withdrawal balances
      const postWithdrawalEth = await web3.eth.getBalance(this.multisig.address)
      expect(postWithdrawalEth).to.be.eq(ETH_DEPOSIT.toString())
      const postWithdrawalToken = await this.token.balanceOf(this.multisig.address)
      expect(postWithdrawalToken.toString()).to.be.eq(
        TOKEN_DEPOSIT.sub(new BN(params.amount)).toString(),
      )
    })

    it.skip('node should be able to withdraw eth', async function() {})

    it.skip('indexer should be able to withdraw tokens', async function() {})
  })
})
