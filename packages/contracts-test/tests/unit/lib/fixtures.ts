/* eslint-disable  @typescript-eslint/no-explicit-any */
import { Controller } from '@graphprotocol/contracts'
import { DisputeManager } from '@graphprotocol/contracts'
import { EpochManager } from '@graphprotocol/contracts'
import { GraphToken } from '@graphprotocol/contracts'
import { Curation } from '@graphprotocol/contracts'
import { L2Curation } from '@graphprotocol/contracts'
import { L1GNS } from '@graphprotocol/contracts'
import { L2GNS } from '@graphprotocol/contracts'
import { IL1Staking } from '@graphprotocol/contracts'
import { IL2Staking } from '@graphprotocol/contracts'
import { RewardsManager } from '@graphprotocol/contracts'
import { ServiceRegistry } from '@graphprotocol/contracts'
import { GraphProxyAdmin } from '@graphprotocol/contracts'
import { L1GraphTokenGateway } from '@graphprotocol/contracts'
import { BridgeEscrow } from '@graphprotocol/contracts'
import { L2GraphTokenGateway } from '@graphprotocol/contracts'
import { L2GraphToken } from '@graphprotocol/contracts'
import { LibExponential } from '@graphprotocol/contracts'
import {
  configureL1Bridge,
  configureL2Bridge,
  deployGraphNetwork,
  deployMockGraphNetwork,
  GraphNetworkContracts,
  helpers,
} from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { providers, Wallet } from 'ethers'

import { isRunningUnderCoverage } from '../../../utils/coverage'

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
    // Use instrumented artifacts when running coverage tests, otherwise use local artifacts
    const artifactsDir = isRunningUnderCoverage() ? './artifacts' : '../contracts/artifacts'

    const contracts = await deployGraphNetwork(
      'addresses-local.json',
      l2Deploy ? 'graph.arbitrum-hardhat.yml' : 'graph.hardhat.yml',
      1337,
      deployer,
      this.provider,
      {
        governor: deployer,
        skipConfirmation: true,
        forceDeploy: true,
        l2Deploy: l2Deploy,
        enableTxLogging: false,
        artifactsDir: artifactsDir,
      } as any, // Type assertion to bypass TypeScript issue
    )
    if (!contracts) {
      throw new Error('Failed to deploy contracts')
    }
    return contracts
  }

  async loadMock(l2Deploy: boolean): Promise<GraphNetworkContracts> {
    return await deployMockGraphNetwork(l2Deploy)
  }

  async loadL1ArbitrumBridge(deployer: SignerWithAddress): Promise<helpers.L1ArbitrumMocks> {
    return await helpers.deployL1MockBridge(deployer, 'arbitrum-addresses-local.json', this.provider)
  }

  async loadL2ArbitrumBridge(deployer: SignerWithAddress): Promise<helpers.L2ArbitrumMocks> {
    return await helpers.deployL2MockBridge(deployer, 'arbitrum-addresses-local.json', this.provider)
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
