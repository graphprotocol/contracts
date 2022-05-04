/* eslint-disable  @typescript-eslint/no-explicit-any */
import { utils, Wallet, Signer } from 'ethers'

import * as deployment from './deployment'
import { evmSnapshot, evmRevert, initNetwork } from './testHelpers'

export class NetworkFixture {
  lastSnapshotId: number

  constructor() {
    this.lastSnapshotId = 0
  }

  async load(
    deployer: Signer,
    slasher: Signer = Wallet.createRandom() as Signer,
    arbitrator: Signer = Wallet.createRandom() as Signer,
  ): Promise<any> {
    await initNetwork()

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
    const curation = await deployment.deployCuration(deployer, controller.address, proxyAdmin)
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

    const l1GraphTokenGateway = await deployment.deployL1GraphTokenGateway(
      deployer,
      controller.address,
      proxyAdmin,
    )

    const bridgeEscrow = await deployment.deployBridgeEscrow(
      deployer,
      controller.address,
      proxyAdmin,
    )

    // Setup controller
    await controller.setContractProxy(utils.id('EpochManager'), epochManager.address)
    await controller.setContractProxy(utils.id('GraphToken'), grt.address)
    await controller.setContractProxy(utils.id('Curation'), curation.address)
    await controller.setContractProxy(utils.id('Staking'), staking.address)
    await controller.setContractProxy(utils.id('DisputeManager'), staking.address)
    await controller.setContractProxy(utils.id('RewardsManager'), rewardsManager.address)
    await controller.setContractProxy(utils.id('ServiceRegistry'), serviceRegistry.address)
    await controller.setContractProxy(utils.id('GraphTokenGateway'), l1GraphTokenGateway.address)

    // Setup contracts
    await curation.connect(deployer).syncAllContracts()
    await gns.connect(deployer).syncAllContracts()
    await serviceRegistry.connect(deployer).syncAllContracts()
    await disputeManager.connect(deployer).syncAllContracts()
    await rewardsManager.connect(deployer).syncAllContracts()
    await staking.connect(deployer).syncAllContracts()
    await l1GraphTokenGateway.connect(deployer).syncAllContracts()
    await bridgeEscrow.connect(deployer).syncAllContracts()

    await staking.connect(deployer).setSlasher(slasherAddress, true)
    await grt.connect(deployer).addMinter(rewardsManager.address)
    await gns.connect(deployer).approveAll()
    await rewardsManager.connect(deployer).setIssuanceRate(deployment.defaults.rewards.issuanceRate)

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
      l1GraphTokenGateway,
      bridgeEscrow,
    }
  }

  async loadL2(deployer: Signer): Promise<any> {
    await initNetwork()

    // Deploy contracts
    const proxyAdmin = await deployment.deployProxyAdmin(deployer)
    const controller = await deployment.deployController(deployer)

    const grt = await deployment.deployL2GRT(deployer, proxyAdmin)

    const l2GraphTokenGateway = await deployment.deployL2GraphTokenGateway(
      deployer,
      controller.address,
      proxyAdmin,
    )

    // Setup controller
    await controller.setContractProxy(utils.id('GraphToken'), grt.address)
    await controller.setContractProxy(utils.id('GraphTokenGateway'), l2GraphTokenGateway.address)

    // Setup contracts
    await l2GraphTokenGateway.connect(deployer).syncAllContracts()
    await grt.connect(deployer).addMinter(l2GraphTokenGateway.address)

    // Unpause the protocol
    await controller.connect(deployer).setPaused(false)

    return {
      controller,
      grt,
      proxyAdmin,
      l2GraphTokenGateway,
    }
  }

  async setUp(): Promise<void> {
    this.lastSnapshotId = await evmSnapshot()
  }

  async tearDown(): Promise<void> {
    await evmRevert(this.lastSnapshotId)
  }
}
