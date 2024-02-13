/* eslint-disable  @typescript-eslint/no-explicit-any */
import { Signer, Wallet, providers } from 'ethers'

import { BridgeMock } from '../../../build/types/BridgeMock'
import { InboxMock } from '../../../build/types/InboxMock'
import { OutboxMock } from '../../../build/types/OutboxMock'
import { Controller } from '../../../build/types/Controller'
import { DisputeManager } from '../../../build/types/DisputeManager'
import { EpochManager } from '../../../build/types/EpochManager'
import { GraphToken } from '../../../build/types/GraphToken'
import { Curation } from '../../../build/types/Curation'
import { L2Curation } from '../../../build/types/L2Curation'
import { L1GNS } from '../../../build/types/L1GNS'
import { L2GNS } from '../../../build/types/L2GNS'
import { IL1Staking } from '../../../build/types/IL1Staking'
import { IL2Staking } from '../../../build/types/IL2Staking'
import { RewardsManager } from '../../../build/types/RewardsManager'
import { ServiceRegistry } from '../../../build/types/ServiceRegistry'
import { GraphProxyAdmin } from '../../../build/types/GraphProxyAdmin'
import { L1GraphTokenGateway } from '../../../build/types/L1GraphTokenGateway'
import { BridgeEscrow } from '../../../build/types/BridgeEscrow'
import { L2GraphTokenGateway } from '../../../build/types/L2GraphTokenGateway'
import { L2GraphToken } from '../../../build/types/L2GraphToken'
import { LibExponential } from '../../../build/types/LibExponential'
import {
  DeployType,
  GraphNetworkContracts,
  configureL1Bridge,
  configureL2Bridge,
  deploy,
  deployGraphNetwork,
  deployMockGraphNetwork,
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

export interface L2BridgeMocks {
  l2GRTMock: Wallet
  l2GRTGatewayMock: Wallet
  l2GNSMock: Wallet
  l2StakingMock: Wallet
}

export class NetworkFixture {
  lastSnapshot: any
  constructor(public provider: providers.Provider) {}

  async load(deployer: SignerWithAddress, l2Deploy?: boolean): Promise<GraphNetworkContracts> {
    return await deployGraphNetwork(
      './addresses-local.json',
      l2Deploy ? './config/graph.arbitrum-hardhat.yml' : './config/graph.hardhat.yml',
      1337,
      deployer,
      this.provider,
      {
        governor: deployer,
        skipConfirmation: true,
        forceDeploy: true,
        l2Deploy: l2Deploy,
        enableTxLogging: false,
      },
    )
  }

  async loadMock(l2Deploy: boolean): Promise<GraphNetworkContracts> {
    return await deployMockGraphNetwork(l2Deploy)
  }

  async loadL1ArbitrumBridge(deployer: SignerWithAddress): Promise<helpers.L1ArbitrumMocks> {
    return await helpers.deployL1MockBridge(
      deployer,
      'arbitrum-addresses-local.json',
      this.provider,
    )
  }

  async loadL2ArbitrumBridge(deployer: SignerWithAddress): Promise<helpers.L2ArbitrumMocks> {
    return await helpers.deployL2MockBridge(
      deployer,
      'arbitrum-addresses-local.json',
      this.provider,
    )
  }

  async configureL1Bridge(
    deployer: SignerWithAddress,
    l1FixtureContracts: GraphNetworkContracts,
    l2MockContracts: GraphNetworkContracts,
  ): Promise<any> {
    await configureL1Bridge(l1FixtureContracts, deployer, {
      l2GRTAddress: l2MockContracts.L2GraphToken.address,
      l2GRTGatewayAddress: l2MockContracts.L2GraphTokenGateway.address,
      l2GNSAddress: l2MockContracts.L2GNS.address,
      l2StakingAddress: l2MockContracts.L2Staking.address,
      arbAddressBookPath: './arbitrum-addresses-local.json',
      chainId: 1337,
    })
    await l1FixtureContracts.L1GraphTokenGateway.connect(deployer).setPaused(false)
  }

  async configureL2Bridge(
    deployer: SignerWithAddress,
    l2FixtureContracts: GraphNetworkContracts,
    l1MockContracts: GraphNetworkContracts,
  ): Promise<any> {
    await configureL2Bridge(l2FixtureContracts, deployer, {
      l1GRTAddress: l1MockContracts.GraphToken.address,
      l1GRTGatewayAddress: l1MockContracts.L1GraphTokenGateway.address,
      l1GNSAddress: l1MockContracts.L1GNS.address,
      l1StakingAddress: l1MockContracts.L1Staking.address,
      arbAddressBookPath: './arbitrum-addresses-local.json',
      chainId: 412346,
    })
    await l2FixtureContracts.L2GraphTokenGateway.connect(deployer).setPaused(false)
  }

  async setUp(): Promise<void> {
    this.lastSnapshot = await helpers.takeSnapshot()
  }

  async tearDown(): Promise<void> {
    await helpers.restoreSnapshot(this.lastSnapshot)
  }
}
