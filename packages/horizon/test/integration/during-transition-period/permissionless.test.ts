import hre from 'hardhat'
import { expect } from 'chai'
import { ethers } from 'hardhat'
import { IHorizonStaking, IGraphToken, IRewardsManager, IEpochManager } from '../../../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import { indexers } from '../../../scripts/e2e/fixtures/indexers'
import { keccak256 } from 'ethers'
import { toUtf8Bytes } from 'ethers'
import EpochManager from '../../../ignition/modules/periphery/EpochManager'

describe('Permissionless', () => {
  let horizonStaking: IHorizonStaking
  let rewardsManager: IRewardsManager
  let epochManager: IEpochManager
  let graphToken: IGraphToken
  let snapshotId: string

  // TODO: FIX THIS
  const subgraphServiceAddress = '0x254dffcd3277C0b1660F6d42EFbB754edaBAbC2B'

  before(async () => {
    const graph = hre.graph()

    // Get contracts
    horizonStaking = graph.horizon!.contracts.HorizonStaking as unknown as IHorizonStaking
    rewardsManager = graph.horizon!.contracts.RewardsManager as unknown as IRewardsManager
    epochManager = graph.horizon!.contracts.EpochManager as unknown as IEpochManager
    graphToken = graph.horizon!.contracts.L2GraphToken as unknown as IGraphToken
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('After max allocation epochs', () => {
    let indexer: SignerWithAddress
    let anySigner: SignerWithAddress
    let allocationID: string
    let allocationTokens: bigint

    before(async () => {
      // Get signers
      indexer = await ethers.getSigner(indexers[0].address)
      anySigner = (await ethers.getSigners())[19]

      // Get allocation details
      allocationID = indexers[0].allocations[0].allocationID
      allocationTokens = indexers[0].allocations[0].tokens
    })

    it('should allow any user to close an allocation with zero POI', async () => {
      // Get indexer's idle stake before closing allocation
      const idleStakeBefore = await horizonStaking.getIdleStake(indexer.address)

      // Mine blocks to simulate 28 epochs passing
      const startingEpoch = await epochManager.currentEpoch()
      while (await epochManager.currentEpoch() - startingEpoch < 28) {
        await ethers.provider.send('evm_mine', [])
      }

      // Close allocation
      await horizonStaking.connect(anySigner).closeAllocation(allocationID, ethers.getBytes(keccak256(toUtf8Bytes("poi"))))

      // Get indexer's idle stake after closing allocation
      const idleStakeAfter = await horizonStaking.getIdleStake(indexer.address)

      // Verify allocation tokens were added to indexer's idle stake but no rewards were collected
      expect(idleStakeAfter).to.be.equal(idleStakeBefore + allocationTokens)
    })
  })
})
