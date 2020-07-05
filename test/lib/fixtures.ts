import { Wallet } from 'ethers'

import * as deployment from './deployment'
import { evmSnapshot, evmRevert } from './testHelpers'

export class NetworkFixture {
  lastSnapshotId: number

  constructor() {
    this.lastSnapshotId = 0
  }

  async load(
    governor: Wallet,
    slasher: Wallet = Wallet.createRandom(),
    arbitrator: Wallet = Wallet.createRandom(),
  ) {
    // Deploy contracts
    const epochManager = await deployment.deployEpochManager(governor.address)
    const grt = await deployment.deployGRT(governor.address)
    const curation = await deployment.deployCuration(governor.address, grt.address)
    const staking = await deployment.deployStaking(
      governor,
      grt.address,
      epochManager.address,
      curation.address,
    )
    const disputeManager = await deployment.deployDisputeManager(
      governor.address,
      grt.address,
      arbitrator.address,
      staking.address,
    )

    // Configuration
    await staking.connect(governor).setSlasher(slasher.address, true)
    await curation.connect(governor).setStaking(staking.address)

    return {
      disputeManager,
      epochManager,
      grt,
      curation,
      staking,
    }
  }

  async setUp(): Promise<void> {
    this.lastSnapshotId = await evmSnapshot()
  }

  async tearDown(): Promise<void> {
    await evmRevert(this.lastSnapshotId)
  }
}
