import { Wallet } from 'ethers'

import * as deployment from '../lib/deployment'

export const loadFixture = async (governor: Wallet, slasher: Wallet) => {
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

  // Configuration
  await staking.connect(governor).setSlasher(slasher.address, true)
  await curation.connect(governor).setStaking(staking.address)

  return {
    epochManager,
    grt,
    curation,
    staking,
  }
}
