import { Wallet } from 'ethers'

import * as deployment from '../lib/deployment'

export const loadFixture = async (governor: Wallet, staking: Wallet) => {
  // Deploy contracts
  const grt = await deployment.deployGRT(governor.address)
  const curation = await deployment.deployCuration(governor.address, grt.address)

  // Configuration
  await curation.connect(governor).setStaking(staking.address)

  return {
    curation,
    grt,
  }
}
