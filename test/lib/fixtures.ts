/* eslint-disable  @typescript-eslint/no-explicit-any */
import { utils, Wallet, Signer } from 'ethers'

import * as deployment from './deployment'
import { evmSnapshot, evmRevert, initNetwork, toBN } from './testHelpers'
import { BridgeMock } from '../../build/types/BridgeMock'
import { InboxMock } from '../../build/types/InboxMock'
import { OutboxMock } from '../../build/types/OutboxMock'
import { deployContract } from './deployment'
import { Controller } from '../../build/types/Controller'
import { DisputeManager } from '../../build/types/DisputeManager'
import { EpochManager } from '../../build/types/EpochManager'
import { GraphToken } from '../../build/types/GraphToken'
import { Curation } from '../../build/types/Curation'
import { GNS } from '../../build/types/GNS'
import { Staking } from '../../build/types/Staking'
import { RewardsManager } from '../../build/types/RewardsManager'
import { ServiceRegistry } from '../../build/types/ServiceRegistry'
import { GraphProxyAdmin } from '../../build/types/GraphProxyAdmin'
import { L1GraphTokenGateway } from '../../build/types/L1GraphTokenGateway'
import { BridgeEscrow } from '../../build/types/BridgeEscrow'
import { L2GraphTokenGateway } from '../../build/types/L2GraphTokenGateway'
import { L2GraphToken } from '../../build/types/L2GraphToken'

export interface L1FixtureContracts {
  controller: Controller
  disputeManager: DisputeManager
  epochManager: EpochManager
  grt: GraphToken
  curation: Curation
  gns: GNS
  staking: Staking
  rewardsManager: RewardsManager
  serviceRegistry: ServiceRegistry
  proxyAdmin: GraphProxyAdmin
  l1GraphTokenGateway: L1GraphTokenGateway
  bridgeEscrow: BridgeEscrow
}

export interface L2FixtureContracts {
  controller: Controller
  disputeManager: DisputeManager
  epochManager: EpochManager
  grt: L2GraphToken
  curation: Curation
  gns: GNS
  staking: Staking
  rewardsManager: RewardsManager
  serviceRegistry: ServiceRegistry
  proxyAdmin: GraphProxyAdmin
  l2GraphTokenGateway: L2GraphTokenGateway
}

export interface ArbitrumL1Mocks {
  bridgeMock: BridgeMock
  inboxMock: InboxMock
  outboxMock: OutboxMock
}

export class NetworkFixture {
  lastSnapshotId: number

  constructor() {
    this.lastSnapshotId = 0
  }

  async _loadLayer(
    deployer: Signer,
    slasher: Signer = Wallet.createRandom() as Signer,
    arbitrator: Signer = Wallet.createRandom() as Signer,
    isL2: boolean,
  ): Promise<L1FixtureContracts | L2FixtureContracts> {
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
    let grt: GraphToken | L2GraphToken
    if (isL2) {
      grt = await deployment.deployL2GRT(deployer, proxyAdmin)
    } else {
      grt = await deployment.deployGRT(deployer)
    }

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

    let l1GraphTokenGateway: L1GraphTokenGateway
    let l2GraphTokenGateway: L2GraphTokenGateway
    let bridgeEscrow: BridgeEscrow
    if (isL2) {
      l2GraphTokenGateway = await deployment.deployL2GraphTokenGateway(
        deployer,
        controller.address,
        proxyAdmin,
      )
    } else {
      l1GraphTokenGateway = await deployment.deployL1GraphTokenGateway(
        deployer,
        controller.address,
        proxyAdmin,
      )
      bridgeEscrow = await deployment.deployBridgeEscrow(deployer, controller.address, proxyAdmin)
    }

    // Setup controller
    await controller.setContractProxy(utils.id('EpochManager'), epochManager.address)
    await controller.setContractProxy(utils.id('GraphToken'), grt.address)
    await controller.setContractProxy(utils.id('Curation'), curation.address)
    await controller.setContractProxy(utils.id('Staking'), staking.address)
    await controller.setContractProxy(utils.id('DisputeManager'), staking.address)
    await controller.setContractProxy(utils.id('RewardsManager'), rewardsManager.address)
    await controller.setContractProxy(utils.id('ServiceRegistry'), serviceRegistry.address)
    if (isL2) {
      await controller.setContractProxy(utils.id('GraphTokenGateway'), l2GraphTokenGateway.address)
    } else {
      await controller.setContractProxy(utils.id('GraphTokenGateway'), l1GraphTokenGateway.address)
    }

    // Setup contracts
    await curation.connect(deployer).syncAllContracts()
    await gns.connect(deployer).syncAllContracts()
    await serviceRegistry.connect(deployer).syncAllContracts()
    await disputeManager.connect(deployer).syncAllContracts()
    await rewardsManager.connect(deployer).syncAllContracts()
    await staking.connect(deployer).syncAllContracts()
    if (isL2) {
      await l2GraphTokenGateway.connect(deployer).syncAllContracts()
    } else {
      await l1GraphTokenGateway.connect(deployer).syncAllContracts()
      await bridgeEscrow.connect(deployer).syncAllContracts()
    }

    await staking.connect(deployer).setSlasher(slasherAddress, true)
    await gns.connect(deployer).approveAll()
    if (!isL2) {
      await grt.connect(deployer).addMinter(rewardsManager.address)
    }

    // Unpause the protocol
    await controller.connect(deployer).setPaused(false)

    if (isL2) {
      return {
        controller,
        disputeManager,
        epochManager,
        grt: grt as L2GraphToken,
        curation,
        gns,
        staking,
        rewardsManager,
        serviceRegistry,
        proxyAdmin,
        l2GraphTokenGateway,
      } as L2FixtureContracts
    } else {
      return {
        controller,
        disputeManager,
        epochManager,
        grt: grt as GraphToken,
        curation,
        gns,
        staking,
        rewardsManager,
        serviceRegistry,
        proxyAdmin,
        l1GraphTokenGateway,
        bridgeEscrow,
      } as L1FixtureContracts
    }
  }

  async load(
    deployer: Signer,
    slasher: Signer = Wallet.createRandom() as Signer,
    arbitrator: Signer = Wallet.createRandom() as Signer,
  ): Promise<L1FixtureContracts> {
    return this._loadLayer(deployer, slasher, arbitrator, false) as unknown as L1FixtureContracts
  }

  async loadL2(
    deployer: Signer,
    slasher: Signer = Wallet.createRandom() as Signer,
    arbitrator: Signer = Wallet.createRandom() as Signer,
  ): Promise<L2FixtureContracts> {
    return this._loadLayer(deployer, slasher, arbitrator, true) as unknown as L2FixtureContracts
  }

  async loadArbitrumL1Mocks(deployer: Signer): Promise<ArbitrumL1Mocks> {
    const bridgeMock = (await deployContract('BridgeMock', deployer)) as unknown as BridgeMock
    const inboxMock = (await deployContract('InboxMock', deployer)) as unknown as InboxMock
    const outboxMock = (await deployContract('OutboxMock', deployer)) as unknown as OutboxMock
    return {
      bridgeMock,
      inboxMock,
      outboxMock,
    }
  }

  async configureL1Bridge(
    deployer: Signer,
    arbitrumMocks: ArbitrumL1Mocks,
    l1FixtureContracts: L1FixtureContracts,
    mockRouterAddress: string,
    mockL2GRTAddress: string,
    mockL2GatewayAddress: string,
  ): Promise<any> {
    // First configure the Arbitrum bridge mocks
    await arbitrumMocks.bridgeMock.connect(deployer).setInbox(arbitrumMocks.inboxMock.address, true)
    await arbitrumMocks.bridgeMock
      .connect(deployer)
      .setOutbox(arbitrumMocks.outboxMock.address, true)
    await arbitrumMocks.inboxMock.connect(deployer).setBridge(arbitrumMocks.bridgeMock.address)
    await arbitrumMocks.outboxMock.connect(deployer).setBridge(arbitrumMocks.bridgeMock.address)

    // Configure the gateway
    await l1FixtureContracts.l1GraphTokenGateway
      .connect(deployer)
      .setArbitrumAddresses(arbitrumMocks.inboxMock.address, mockRouterAddress)
    await l1FixtureContracts.l1GraphTokenGateway
      .connect(deployer)
      .setL2TokenAddress(mockL2GRTAddress)
    await l1FixtureContracts.l1GraphTokenGateway
      .connect(deployer)
      .setL2CounterpartAddress(mockL2GatewayAddress)
    await l1FixtureContracts.l1GraphTokenGateway
      .connect(deployer)
      .setEscrowAddress(l1FixtureContracts.bridgeEscrow.address)
    await l1FixtureContracts.bridgeEscrow
      .connect(deployer)
      .approveAll(l1FixtureContracts.l1GraphTokenGateway.address)
    await l1FixtureContracts.l1GraphTokenGateway.connect(deployer).setPaused(false)
  }

  async configureL2Bridge(
    deployer: Signer,
    l2FixtureContracts: L2FixtureContracts,
    mockRouterAddress: string,
    mockL1GRTAddress: string,
    mockL1GatewayAddress: string,
  ): Promise<any> {
    // Configure the L2 GRT
    // Configure the gateway
    await l2FixtureContracts.grt
      .connect(deployer)
      .setGateway(l2FixtureContracts.l2GraphTokenGateway.address)
    await l2FixtureContracts.grt.connect(deployer).setL1Address(mockL1GRTAddress)
    // Configure the gateway
    await l2FixtureContracts.l2GraphTokenGateway.connect(deployer).setL2Router(mockRouterAddress)
    await l2FixtureContracts.l2GraphTokenGateway
      .connect(deployer)
      .setL1TokenAddress(mockL1GRTAddress)
    await l2FixtureContracts.l2GraphTokenGateway
      .connect(deployer)
      .setL1CounterpartAddress(mockL1GatewayAddress)
    await l2FixtureContracts.l2GraphTokenGateway.connect(deployer).setPaused(false)
  }

  async setUp(): Promise<void> {
    this.lastSnapshotId = await evmSnapshot()
    await initNetwork()
  }

  async tearDown(): Promise<void> {
    await evmRevert(this.lastSnapshotId)
  }
}
