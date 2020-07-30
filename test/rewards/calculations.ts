import { expect } from 'chai'
import { constants, BigNumber, Event } from 'ethers'

import { NetworkFixture } from '../lib/fixtures'

import { Curation } from '../../build/typechain/contracts/Curation'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { RewardsManager } from '../../build/typechain/contracts/RewardsManager'
import { Staking } from '../../build/typechain/contracts/Staking'

import {
  advanceBlockTo,
  getAccounts,
  randomHexBytes,
  latestBlock,
  toBN,
  toGRT,
  formatGRT,
  Account,
  advanceToNextEpoch,
} from '../lib/testHelpers'

describe('Rewards:Calculations', () => {
  let me: Account
  let governor: Account
  let curator: Account
  let indexer: Account
  let assetHolder: Account

  let fixture: NetworkFixture

  let grt: GraphToken
  let curation: Curation
  let epochManager: EpochManager
  let staking: Staking
  let rewardsManager: RewardsManager

  const subgraphDeploymentID = randomHexBytes()
  const allocationID = '0x6367E9dD7641e0fF221740b57B8C730031d72530'
  const channelPubKey =
    '0x0456708870bfd5d8fc956fe33285dcf59b075cd7a25a21ee00834e480d3754bcda180e670145a290bb4bebca8e105ea7776a7b39e16c4df7d4d1083260c6f05d53'

  before(async function () {
    ;[me, governor, curator, indexer, assetHolder] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ grt, curation, epochManager, staking, rewardsManager } = await fixture.load(
      governor.signer,
    ))

    // Distribute test funds
    for (const wallet of [indexer, curator]) {
      await grt.connect(governor.signer).mint(wallet.address, toGRT('1000000'))
      await grt.connect(wallet.signer).approve(staking.address, toGRT('1000000'))
      await grt.connect(wallet.signer).approve(curation.address, toGRT('1000000'))
    }
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('calc', function () {
    it('do something', async function () {
      // curator signal
      await curation.connect(curator.signer).mint(subgraphDeploymentID, toGRT('1000'))

      const b1 = await latestBlock()

      // indexer allocate
      await staking.connect(indexer.signer).stake(toGRT('10000'))
      await staking
        .connect(indexer.signer)
        .allocate(
          subgraphDeploymentID,
          toGRT('5000'),
          channelPubKey,
          assetHolder.address,
          toGRT('0.1'),
        )

      // await advanceToNextEpoch(epochManager)

      // await rewardsManager.updateAccRewardsPerSignal()

      const b2 = await latestBlock()

      const r = await rewardsManager.issuanceRate()
      const p = await grt.totalSupply()
      const s = await curation.getCurationPoolTokens(subgraphDeploymentID)
      const rs = await rewardsManager.getAccRewardsPerSignal()

      console.log('r', formatGRT(r))
      console.log('t', b2.sub(b1).toString())
      console.log('p', formatGRT(p))
      console.log('s', formatGRT(s))
      console.log('rs', formatGRT(rs))

      console.log('----')

      await rewardsManager.updateAccRewardsPerSignal()
    })
  })
})
