/* eslint-disable  @typescript-eslint/no-explicit-any */
import { Signer, providers } from 'ethers'

import { BridgeMock } from '../../build/types/BridgeMock'
import { InboxMock } from '../../build/types/InboxMock'
import { OutboxMock } from '../../build/types/OutboxMock'
import { Controller } from '../../build/types/Controller'
import { DisputeManager } from '../../build/types/DisputeManager'
import { EpochManager } from '../../build/types/EpochManager'
import { GraphToken } from '../../build/types/GraphToken'
import { Curation } from '../../build/types/Curation'
import { L2Curation } from '../../build/types/L2Curation'
import { L1GNS } from '../../build/types/L1GNS'
import { L2GNS } from '../../build/types/L2GNS'
import { IL1Staking } from '../../build/types/IL1Staking'
import { IL2Staking } from '../../build/types/IL2Staking'
import { RewardsManager } from '../../build/types/RewardsManager'
import { ServiceRegistry } from '../../build/types/ServiceRegistry'
import { GraphProxyAdmin } from '../../build/types/GraphProxyAdmin'
import { L1GraphTokenGateway } from '../../build/types/L1GraphTokenGateway'
import { BridgeEscrow } from '../../build/types/BridgeEscrow'
import { L2GraphTokenGateway } from '../../build/types/L2GraphTokenGateway'
import { L2GraphToken } from '../../build/types/L2GraphToken'
import { LibExponential } from '../../build/types/LibExponential'
import {
  DeployType,
  GraphNetworkContracts,
  deploy,
  deployGraphNetwork,
  helpers,
  loadGraphNetworkContracts,
} from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

export interface L1FixtureContracts {
  controller: Controller
  disputeManager: DisputeManager
  epochManager: EpochManager
  grt: GraphToken
  curation: Curation
  gns: L1GNS
  staking: IL1Staking
  libExponential: LibExponential
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
  curation: L2Curation
  gns: L2GNS
  staking: IL2Staking
  libExponential: LibExponential
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
  lastSnapshot: any
  constructor(public provider: providers.Provider) {}

  async load(deployer: SignerWithAddress, l2Deploy?: boolean): Promise<GraphNetworkContracts> {
    // Ensure we are auto mining
    // await helpers.setAutoMine(true)

    // Deploy contracts
    await deployGraphNetwork(
      './addresses.json',
      l2Deploy ? './config/graph.arbitrum-hardhat.yml' : './config/graph.hardhat.yml',
      1337,
      deployer,
      this.provider,
      {
        skipConfirmation: true,
        forceDeploy: true,
        l2Deploy: l2Deploy,
      },
    )

    const contracts = loadGraphNetworkContracts(
      './addresses.json',
      1337,
      this.provider,
      undefined,
      {
        l2Load: l2Deploy,
        enableTxLogging: false,
      },
    )

    // Post deploy configuration
    await contracts.GraphToken.connect(deployer).addMinter(deployer.address)
    await contracts.Controller.connect(deployer).setPaused(false)

    return contracts
  }

  async loadArbitrumL1Mocks(deployer: Signer): Promise<ArbitrumL1Mocks> {
    const bridgeMock = (await deploy(DeployType.Deploy, deployer, { name: 'BridgeMock' }))
      .contract as BridgeMock
    const inboxMock = (await deploy(DeployType.Deploy, deployer, { name: 'InboxMock' }))
      .contract as InboxMock
    const outboxMock = (await deploy(DeployType.Deploy, deployer, { name: 'OutboxMock' }))
      .contract as OutboxMock
    return {
      bridgeMock,
      inboxMock,
      outboxMock,
    }
  }

  async configureL1Bridge(
    deployer: Signer,
    arbitrumMocks: ArbitrumL1Mocks,
    l1FixtureContracts: GraphNetworkContracts,
    mockRouterAddress: string,
    mockL2GRTAddress: string,
    mockL2GatewayAddress: string,
    mockL2GNSAddress: string,
    mockL2StakingAddress: string,
  ): Promise<any> {
    // First configure the Arbitrum bridge mocks
    await arbitrumMocks.bridgeMock.connect(deployer).setInbox(arbitrumMocks.inboxMock.address, true)
    await arbitrumMocks.bridgeMock
      .connect(deployer)
      .setOutbox(arbitrumMocks.outboxMock.address, true)
    await arbitrumMocks.inboxMock.connect(deployer).setBridge(arbitrumMocks.bridgeMock.address)
    await arbitrumMocks.outboxMock.connect(deployer).setBridge(arbitrumMocks.bridgeMock.address)

    // Configure the gateway
    await l1FixtureContracts.L1GraphTokenGateway.connect(deployer).setArbitrumAddresses(
      arbitrumMocks.inboxMock.address,
      mockRouterAddress,
    )
    await l1FixtureContracts.L1GraphTokenGateway.connect(deployer).setL2TokenAddress(
      mockL2GRTAddress,
    )
    await l1FixtureContracts.L1GraphTokenGateway.connect(deployer).setL2CounterpartAddress(
      mockL2GatewayAddress,
    )
    await l1FixtureContracts.L1GraphTokenGateway.connect(deployer).setEscrowAddress(
      l1FixtureContracts.BridgeEscrow.address,
    )
    await l1FixtureContracts.BridgeEscrow.connect(deployer).approveAll(
      l1FixtureContracts.L1GraphTokenGateway.address,
    )
    await l1FixtureContracts.GNS.connect(deployer).setCounterpartGNSAddress(mockL2GNSAddress)
    await l1FixtureContracts.L1GraphTokenGateway.connect(deployer).addToCallhookAllowlist(
      l1FixtureContracts.GNS.address,
    )
    await l1FixtureContracts.Staking.connect(deployer).setCounterpartStakingAddress(
      mockL2StakingAddress,
    )
    await l1FixtureContracts.L1GraphTokenGateway.connect(deployer).addToCallhookAllowlist(
      l1FixtureContracts.Staking.address,
    )
    await l1FixtureContracts.L1GraphTokenGateway.connect(deployer).setPaused(false)
  }

  async configureL2Bridge(
    deployer: Signer,
    l2FixtureContracts: GraphNetworkContracts,
    mockRouterAddress: string,
    mockL1GRTAddress: string,
    mockL1GatewayAddress: string,
    mockL1GNSAddress: string,
    mockL1StakingAddress: string,
  ): Promise<any> {
    // Configure the L2 GRT
    // Configure the gateway
    await l2FixtureContracts.L2GraphToken.connect(deployer).setGateway(
      l2FixtureContracts.L2GraphTokenGateway.address,
    )
    await l2FixtureContracts.L2GraphToken.connect(deployer).setL1Address(mockL1GRTAddress)
    // Configure the gateway
    await l2FixtureContracts.L2GraphTokenGateway.connect(deployer).setL2Router(mockRouterAddress)
    await l2FixtureContracts.L2GraphTokenGateway.connect(deployer).setL1TokenAddress(
      mockL1GRTAddress,
    )
    await l2FixtureContracts.L2GraphTokenGateway.connect(deployer).setL1CounterpartAddress(
      mockL1GatewayAddress,
    )
    await l2FixtureContracts.GNS.connect(deployer).setCounterpartGNSAddress(mockL1GNSAddress)
    await l2FixtureContracts.Staking.connect(deployer).setCounterpartStakingAddress(
      mockL1StakingAddress,
    )
    await l2FixtureContracts.L2GraphTokenGateway.connect(deployer).setPaused(false)
  }

  async setUp(): Promise<void> {
    this.lastSnapshot = await helpers.takeSnapshot()
  }

  async tearDown(): Promise<void> {
    await helpers.restoreSnapshot(this.lastSnapshot)
  }
}
