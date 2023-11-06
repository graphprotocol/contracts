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
  acceptOwnership,
  deploy,
  deployGraphNetwork,
  helpers,
  loadGraphNetworkContracts,
  toBN,
  toGRT,
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

  async load(deployer: SignerWithAddress): Promise<GraphNetworkContracts> {
    await helpers.setIntervalMining(0)
    await helpers.setAutoMine(true)

    // Deploy contracts
    await deployGraphNetwork(
      './addresses.json',
      './config/graph.localhost.yml',
      1337,
      deployer,
      this.provider,
      {
        skipConfirmation: true,
        forceDeploy: true,
        autoMine: true,
      },
    )

    const contracts = loadGraphNetworkContracts('./addresses.json', 1337, this.provider)

    // Post deploy configuration
    await contracts.GraphToken.connect(deployer).addMinter(deployer.address)
    await contracts.Controller.connect(deployer).setPaused(false)

    // TODO: fix this
    // Tests asume network parameters previously defined in the tests.
    // We are now using graph config files, so some of them have different values
    await contracts.Curation.connect(deployer).setDefaultReserveRatio(toBN('500000'))
    await contracts.Curation.connect(deployer).setMinimumCurationDeposit(toGRT('100'))
    await contracts.Curation.connect(deployer).setCurationTaxPercentage(0)
    await contracts.DisputeManager.connect(deployer).setMinimumDeposit(toGRT('100'))
    await contracts.DisputeManager.connect(deployer).setFishermanRewardPercentage(toBN('1000'))
    await contracts.DisputeManager.connect(deployer).setSlashingPercentage(
      toBN('1000'),
      toBN('100000'),
    )
    await contracts.Staking.connect(deployer).setProtocolPercentage(0)
    await contracts.Staking.connect(deployer).setCurationPercentage(0)
    await contracts.Staking.connect(deployer).setDelegationParameters(0, 0, 0)
    await contracts.Staking.connect(deployer).setDelegationTaxPercentage(0)
    await contracts.Staking.connect(deployer).setMinimumIndexerStake(toGRT('10'))
    await contracts.Staking.connect(deployer).setMaxAllocationEpochs(5)
    await contracts.Staking.connect(deployer).setThawingPeriod(20)
    await contracts.Staking.connect(deployer).setDelegationUnbondingPeriod(1)
    await contracts.Staking.connect(deployer).setRebateParameters(100, 100, 60, 100)
    await contracts.EpochManager.connect(deployer).setEpochLength((15 * 60) / 15)
    await contracts.RewardsManager.connect(deployer).setIssuancePerBlock(
      toGRT('114.155251141552511415'),
    )

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
    l2FixtureContracts: L2FixtureContracts,
    mockRouterAddress: string,
    mockL1GRTAddress: string,
    mockL1GatewayAddress: string,
    mockL1GNSAddress: string,
    mockL1StakingAddress: string,
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
    await l2FixtureContracts.gns.connect(deployer).setCounterpartGNSAddress(mockL1GNSAddress)
    await l2FixtureContracts.staking
      .connect(deployer)
      .setCounterpartStakingAddress(mockL1StakingAddress)
    await l2FixtureContracts.l2GraphTokenGateway.connect(deployer).setPaused(false)
  }

  async setUp(): Promise<void> {
    this.lastSnapshot = await helpers.takeSnapshot()
    await helpers.setIntervalMining(0)
    await helpers.setAutoMine(true)
  }

  async tearDown(): Promise<void> {
    await helpers.restoreSnapshot(this.lastSnapshot)
  }
}
