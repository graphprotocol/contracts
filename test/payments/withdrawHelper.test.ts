import { expect } from 'chai'
import { constants } from 'ethers'

import { GrtWithdrawHelper } from '../../build/typechain/contracts/GrtWithdrawHelper'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Staking } from '../../build/typechain/contracts/Staking'

import { NetworkFixture } from '../lib/fixtures'

import * as deployment from '../lib/deployment'
import { deriveChannelKey, getAccounts, randomHexBytes, toGRT, Account } from '../lib/testHelpers'

const { AddressZero } = constants

describe('WithdrawHelper', () => {
  let cmc: Account
  let governor: Account
  let indexer: Account

  let fixture: NetworkFixture

  let grt: GraphToken
  let staking: Staking
  let withdrawHelper: GrtWithdrawHelper

  function createWithdrawData(callData: string) {
    return {
      amount: 0,
      assetId: grt.address,
      callData,
      callTo: withdrawHelper.address,
      channelAddress: randomHexBytes(20),
      nonce: 1,
      recipient: withdrawHelper.address,
    }
  }

  before(async function () {
    ;[cmc, governor, indexer] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ grt, staking } = await fixture.load(governor.signer))
    withdrawHelper = ((await deployment.deployContract(
      'GRTWithdrawHelper',
      governor.signer,
      grt.address,
    )) as unknown) as GrtWithdrawHelper

    // Give some funds to the indexer and approve staking contract to use funds on indexer behalf
    const indexerTokens = toGRT('100000')
    await grt.connect(governor.signer).mint(indexer.address, indexerTokens)
    await grt.connect(indexer.signer).approve(staking.address, indexerTokens)

    // Give some funds to the CMC multisig fake account
    const cmcTokens = toGRT('2000')
    await grt.connect(governor.signer).mint(cmc.address, cmcTokens)

    // Allow WithdrawHelper to call the Staking contract
    await staking.connect(governor.signer).setAssetHolder(withdrawHelper.address, true)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('execute withdrawal', function () {
    it('withdraw tokens from the CMC to staking contract through WithdrawHelper', async function () {
      // Generate test data
      const channelKey = deriveChannelKey()
      const allocationID = channelKey.address
      const subgraphDeploymentID = randomHexBytes(32)
      const metadata = randomHexBytes(32)

      // Setup staking
      const stakeTokens = toGRT('100000')
      await staking.connect(indexer.signer).stake(stakeTokens)
      await staking
        .connect(indexer.signer)
        .allocate(
          subgraphDeploymentID,
          stakeTokens,
          allocationID,
          metadata,
          await channelKey.generateProof(indexer.address),
        )

      // Initiate a withdrawal
      // For the purpose of the test we skip the CMC and call WithdrawHelper
      // directly. Transfer tokens from the CMC -> WithdrawHelper being the recipient
      const actualAmount = toGRT('2000') // <- withdraw amount
      await grt.connect(cmc.signer).transfer(withdrawHelper.address, actualAmount)

      // Simulate callTo from the CMC to the WithdrawHelper
      const callData = await withdrawHelper.getCallData({
        staking: staking.address,
        allocationID,
      })
      const withdrawData = {
        amount: 0,
        assetId: grt.address,
        callData,
        callTo: withdrawHelper.address,
        channelAddress: cmc.address,
        nonce: 1,
        recipient: withdrawHelper.address,
      }
      await withdrawHelper.connect(cmc.signer).execute(withdrawData, actualAmount)

      // Allocation must have collected the withdrawn tokens
      const allocation = await staking.allocations(allocationID)
      expect(allocation.collectedFees).eq(actualAmount)

      // CMC should not have more funds
      expect(await grt.balanceOf(cmc.address)).eq(0)
    })

    it('withdraw tokens from the CMC to staking contract through WithdrawHelper (invalid allocation)', async function () {
      // Use an invalid allocation
      const allocationID = '0xfefefefefefefefefefefefefefefefefefefefe'

      // Initiate a withdrawal
      // For the purpose of the test we skip the CMC and call WithdrawHelper
      // directly. Transfer tokens from the CMC -> WithdrawHelper being the recipient
      const actualAmount = toGRT('2000') // <- withdraw amount
      await grt.connect(cmc.signer).transfer(withdrawHelper.address, actualAmount)

      // Simulate callTo from the CMC to the WithdrawHelper
      const callData = await withdrawHelper.getCallData({
        staking: staking.address,
        allocationID,
      })
      const withdrawData = {
        amount: 0,
        assetId: grt.address,
        callData,
        callTo: withdrawHelper.address,
        channelAddress: cmc.address,
        nonce: 1,
        recipient: withdrawHelper.address,
      }

      // This reverts!
      await withdrawHelper.connect(cmc.signer).execute(withdrawData, actualAmount)

      // There should not be collected fees
      const allocation = await staking.allocations(allocationID)
      expect(allocation.collectedFees).eq(0)

      // CMC should have the funds returned
      expect(await grt.balanceOf(cmc.address)).eq(actualAmount)
    })

    it('reject collect data with no staking address', async function () {
      // Simulate callTo from the CMC to the WithdrawHelper
      const callData = await withdrawHelper.getCallData({
        staking: AddressZero,
        allocationID: randomHexBytes(20),
      })
      const tx = withdrawHelper.execute(createWithdrawData(callData), toGRT('100'))
      await expect(tx).revertedWith('GRTWithdrawHelper: !staking')
    })

    it('reject collect data with no allocation', async function () {
      // Simulate callTo from the CMC to the WithdrawHelper
      const callData = await withdrawHelper.getCallData({
        staking: randomHexBytes(20),
        allocationID: AddressZero,
      })
      const tx = withdrawHelper.execute(createWithdrawData(callData), toGRT('100'))
      await expect(tx).revertedWith('GRTWithdrawHelper: !allocationID')
    })
  })
})
