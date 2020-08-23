import { Wallet, Signer, utils } from 'ethers'

import * as deployment from './deployment'
import { evmSnapshot, evmRevert } from './testHelpers'

export class NetworkFixture {
  lastSnapshotId: number

  constructor() {
    this.lastSnapshotId = 0
  }

  stringToBytes32 = (str: string) => {
    return utils.keccak256(utils.toUtf8Bytes(str))
  }

  async load(
    governor: Signer,
    slasher: Signer = Wallet.createRandom() as Signer,
    arbitrator: Signer = Wallet.createRandom() as Signer,
  ) {
    const arbitratorAddress = await arbitrator.getAddress()
    const slasherAddress = await slasher.getAddress()

    // Deploy contracts
    const controller = await deployment.deployController(governor)

    const epochManager = await deployment.deployEpochManager(governor)
    await controller.setContract(this.stringToBytes32('EpochManager'), epochManager.address)
    const grt = await deployment.deployGRT(governor)
    await controller.setContract(this.stringToBytes32('GraphToken'), grt.address)

    const curation = await deployment.deployCuration(governor)
    await controller.setContract(this.stringToBytes32('Curation'), curation.address)

    const didRegistry = await deployment.deployEthereumDIDRegistry(governor)

    const gns = await deployment.deployGNS(governor, didRegistry.address)
    // GMMM TODO - manybe i need the prtoxuy addrodes, not the adhfuclt adrers!

    const staking = await deployment.deployStaking(governor)
    await controller.setContract(this.stringToBytes32('Staking'), staking.address)

    const disputeManager = await deployment.deployDisputeManager(governor, arbitratorAddress)

    const rewardsManager = await deployment.deployRewardsManager(governor)
    await controller.setContract(this.stringToBytes32('RewardsManager'), rewardsManager.address)

    // Function calls
    await staking.connect(governor).setSlasher(slasherAddress, true)
    await grt.connect(governor).addMinter(rewardsManager.address)

    return {
      controller,
      disputeManager,
      epochManager,
      grt,
      curation,
      gns,
      staking,
      rewardsManager,
    }
  }

  async setUp(): Promise<void> {
    this.lastSnapshotId = await evmSnapshot()
  }

  async tearDown(): Promise<void> {
    await evmRevert(this.lastSnapshotId)
  }
}
