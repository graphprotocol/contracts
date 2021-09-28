/* eslint-disable  @typescript-eslint/no-explicit-any */
import { utils, Wallet, Signer } from 'ethers'

import * as deployment from './deployment'
import { evmSnapshot, evmRevert } from './testHelpers'

interface loadOptions {
  curationOptions?: deployment.CurationLoadOptions
}

export class NetworkFixture {
  lastSnapshotId: number

  constructor() {
    this.lastSnapshotId = 0
  }

  async load(
    deployer: Signer,
    options: loadOptions = {},
    slasher: Signer = Wallet.createRandom() as Signer,
    arbitrator: Signer = Wallet.createRandom() as Signer,
  ): Promise<any> {
    // Roles
    const arbitratorAddress = await arbitrator.getAddress()
    const slasherAddress = await slasher.getAddress()

    // Deploy contracts
    const proxyAdmin = await deployment.deployProxyAdmin(deployer)
    const controller = await deployment.deployController(deployer)
    const epochManager = await deployment.deployEpochManager(
      deployer,
      controller.address,
      proxyAdmin,
    )
    const grt = await deployment.deployGRT(deployer)
    const curation = await deployment.deployCuration(
      deployer,
      controller.address,
      proxyAdmin,
      options?.curationOptions,
    )
    const gns = await deployment.deployGNS(deployer, controller.address, proxyAdmin)
    const staking = await deployment.deployStaking(deployer, controller.address, proxyAdmin)
    const disputeManager = await deployment.deployDisputeManager(
      deployer,
      controller.address,
      arbitratorAddress,
      proxyAdmin,
    )
    const rewardsManager = await deployment.deployRewardsManager(
      deployer,
      controller.address,
      proxyAdmin,
    )
    const serviceRegistry = await deployment.deployServiceRegistry(
      deployer,
      controller.address,
      proxyAdmin,
    )

    // Setup controller
    await controller.setContractProxy(utils.id('EpochManager'), epochManager.address)
    await controller.setContractProxy(utils.id('GraphToken'), grt.address)
    await controller.setContractProxy(utils.id('Curation'), curation.address)
    await controller.setContractProxy(utils.id('GNS'), gns.address)
    await controller.setContractProxy(utils.id('Staking'), staking.address)
    await controller.setContractProxy(utils.id('DisputeManager'), staking.address)
    await controller.setContractProxy(utils.id('RewardsManager'), rewardsManager.address)
    await controller.setContractProxy(utils.id('ServiceRegistry'), serviceRegistry.address)

    // Setup contracts
    await curation.connect(deployer).syncAllContracts()
    await gns.connect(deployer).syncAllContracts()
    await serviceRegistry.connect(deployer).syncAllContracts()
    await disputeManager.connect(deployer).syncAllContracts()
    await rewardsManager.connect(deployer).syncAllContracts()
    await staking.connect(deployer).syncAllContracts()

    await staking.connect(deployer).setSlasher(slasherAddress, true)
    await grt.connect(deployer).addMinter(rewardsManager.address)
    await gns.connect(deployer).approveAll()

    // Unpause the protocol
    await controller.connect(deployer).setPaused(false)

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
      proxyAdmin,
    }
  }

  async setUp(): Promise<void> {
    this.lastSnapshotId = await evmSnapshot()
  }

  async tearDown(): Promise<void> {
    await evmRevert(this.lastSnapshotId)
  }
}
