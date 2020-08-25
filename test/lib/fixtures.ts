import { utils, Wallet, Signer } from 'ethers'

import * as deployment from './deployment'
import { evmSnapshot, evmRevert } from './testHelpers'

export class NetworkFixture {
  lastSnapshotId: number

  constructor() {
    this.lastSnapshotId = 0
  }

  async load(
    deployer: Signer,
    slasher: Signer = Wallet.createRandom() as Signer,
    arbitrator: Signer = Wallet.createRandom() as Signer,
  ) {
    // Roles
    const arbitratorAddress = await arbitrator.getAddress()
    const slasherAddress = await slasher.getAddress()

    // Deploy contracts
    const controller = await deployment.deployController(deployer)
    const epochManager = await deployment.deployEpochManager(deployer, controller.address)
    const grt = await deployment.deployGRT(deployer)
    const curation = await deployment.deployCuration(deployer, controller.address)
    const didRegistry = await deployment.deployEthereumDIDRegistry(deployer)
    const gns = await deployment.deployGNS(deployer, controller.address, didRegistry.address)
    const staking = await deployment.deployStaking(deployer, controller.address)
    const disputeManager = await deployment.deployDisputeManager(
      deployer,
      controller.address,
      arbitratorAddress,
    )
    const rewardsManager = await deployment.deployRewardsManager(deployer, controller.address)
    const serviceRegistry = await deployment.deployServiceRegistry(deployer)

    // Setup controller
    await controller.setContractProxy(utils.id('EpochManager'), epochManager.address)
    await controller.setContractProxy(utils.id('GraphToken'), grt.address)
    await controller.setContractProxy(utils.id('Curation'), curation.address)
    await controller.setContractProxy(utils.id('Staking'), staking.address)
    await controller.setContractProxy(utils.id('DisputeManager'), staking.address)
    await controller.setContractProxy(utils.id('RewardsManager'), rewardsManager.address)
    await controller.setContractProxy(utils.id('ServiceRegistry'), serviceRegistry.address)

    // Setup contracts
    await staking.connect(deployer).setSlasher(slasherAddress, true)
    await grt.connect(deployer).addMinter(rewardsManager.address)
    await gns.connect(deployer).approveAll()
    await rewardsManager.connect(deployer).setIssuanceRate(deployment.defaults.rewards.issuanceRate)

    return {
      controller,
      disputeManager,
      epochManager,
      grt,
      curation,
      gns,
      staking,
      rewardsManager,
      serviceRegistry,
    }
  }

  async setUp(): Promise<void> {
    this.lastSnapshotId = await evmSnapshot()
  }

  async tearDown(): Promise<void> {
    await evmRevert(this.lastSnapshotId)
  }
}
