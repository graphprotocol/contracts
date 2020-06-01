import { Wallet, Contract } from 'ethers'
import { deployContract } from 'ethereum-waffle'
import { ethers } from '@nomiclabs/buidler'

// contracts artifacts
import CurationArtifact from '../../build/contracts/Curation.json'
import DisputeManagerArtifact from '../../build/contracts/DisputeManager.json'
import EpochManagerArtifact from '../../build/contracts/EpochManager.json'
import GNSArtifact from '../../build/contracts/GNS.json'
import GraphTokenArtifact from '../../build/contracts/GraphToken.json'
import ServiceRegistyArtifact from '../../build/contracts/ServiceRegistry.json'
import StakingArtifact from '../../build/contracts/Staking.json'

// contracts definitions
import { Curation } from '../../build/typechain/contracts/Curation'
import { DisputeManager } from '../../build/typechain/contracts/DisputeManager'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { Gns } from '../../build/typechain/contracts/Gns'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { ServiceRegistry } from '../../build/typechain/contracts/ServiceRegistry'
import { Staking } from '../../build/typechain/contracts/Staking'
import { MinimumViableMultisig } from '../../build/typechain/contracts/MinimumViableMultisig'
import { IndexerCtdt } from '../../build/typechain/contracts/IndexerCTDT'
import { IndexerSingleAssetInterpreter } from '../../build/typechain/contracts/IndexerSingleAssetInterpreter'
import { IndexerMultiAssetInterpreter } from '../../build/typechain/contracts/IndexerMultiAssetInterpreter'
import { IndexerWithdrawInterpreter } from '../../build/typechain/contracts/IndexerWithdrawInterpreter'
import { MockStaking } from '../../build/typechain/contracts/MockStaking'
import { MockDispute } from '../../build/typechain/contracts/MockDispute'
import { AppWithAction } from '../../build/typechain/contracts/AppWithAction'
import { Proxy } from '../../build/typechain/contracts/Proxy'
import { IdentityApp } from '../../build/typechain/contracts/IdentityApp'

// helpers
import { defaults } from './testHelpers'
import { solidityKeccak256 } from 'ethers/utils'

const deployGasLimit = 9000000

export function deployGRT(owner: string, wallet: Wallet): Promise<GraphToken> {
  return deployContract(wallet, GraphTokenArtifact, [
    owner,
    defaults.token.initialSupply,
  ]) as Promise<GraphToken>
}

export async function deployGRTWithFactory(owner: string): Promise<GraphToken> {
  const GraphToken = await ethers.getContractFactory('GraphToken')
  const contract = await GraphToken.deploy(owner, defaults.token.initialSupply)
  await contract.deployed()
  return contract as GraphToken
}

export function deployCuration(
  owner: string,
  graphToken: string,
  wallet: Wallet,
): Promise<Curation> {
  return deployContract(
    wallet,
    CurationArtifact,
    [owner, graphToken, defaults.curation.reserveRatio, defaults.curation.minimumCurationStake],
    { gasLimit: deployGasLimit },
  ) as Promise<Curation>
}

export function deployDisputeManager(
  owner: string,
  graphToken: string,
  arbitrator: string,
  staking: string,
  wallet: Wallet,
): Promise<DisputeManager> {
  return deployContract(wallet, DisputeManagerArtifact, [
    owner,
    arbitrator,
    graphToken,
    staking,
    defaults.dispute.minimumDeposit,
    defaults.dispute.fishermanRewardPercentage,
    defaults.dispute.slashingPercentage,
  ]) as Promise<DisputeManager>
}

export function deployEpochManager(owner: string, wallet: Wallet): Promise<EpochManager> {
  return deployContract(wallet, EpochManagerArtifact, [
    owner,
    defaults.epochs.lengthInBlocks,
  ]) as Promise<EpochManager>
}

export async function deployEpochManagerWithFactory(owner: string): Promise<EpochManager> {
  const EpochManager = await ethers.getContractFactory('EpochManager')
  const contract = await EpochManager.deploy(owner, defaults.token.initialSupply)
  await contract.deployed()
  return contract as EpochManager
}

export function deployGNS(owner: string, wallet: Wallet): Promise<Gns> {
  return deployContract(wallet, GNSArtifact, [owner]) as Promise<Gns>
}

export function deployServiceRegistry(wallet: Wallet): Promise<ServiceRegistry> {
  return deployContract(wallet, ServiceRegistyArtifact) as Promise<ServiceRegistry>
}

export async function deployStaking(
  owner: Wallet,
  graphToken: string,
  epochManager: string,
  curation: string,
  wallet: Wallet,
): Promise<Staking> {
  const contract: Staking = (await deployContract(wallet, StakingArtifact, [
    owner.address,
    graphToken,
    epochManager,
  ])) as Staking

  await contract.connect(owner).setCuration(curation)
  await contract.connect(owner).setChannelDisputeEpochs(defaults.staking.channelDisputeEpochs)
  await contract.connect(owner).setMaxAllocationEpochs(defaults.staking.maxAllocationEpochs)
  await contract.connect(owner).setThawingPeriod(defaults.staking.thawingPeriod)
  return contract
}

export async function deployIndexerMultisig(
  node: string,
  staking: string,
  ctdt: string,
  singleAssetInterpreter: string,
  multiAssetInterpreter: string,
  withdrawInterpreter: string,
): Promise<MinimumViableMultisig> {
  const MinimumViableMultisig = await ethers.getContractFactory('MinimumViableMultisig')
  const contract = await MinimumViableMultisig.deploy(
    node,
    staking,
    ctdt,
    singleAssetInterpreter,
    multiAssetInterpreter,
    withdrawInterpreter,
  )
  await contract.deployed()
  return contract as MinimumViableMultisig
}

async function deployProxy(masterCopy: string): Promise<Proxy> {
  const Proxy = await ethers.getContractFactory('Proxy')
  const contract = await Proxy.deploy(masterCopy)
  await contract.deployed()
  return contract as Proxy
}

// Note: this cannot be typed properly because "ProxyFactory" is generated by the Proxy contract
async function deployProxyFactory(): Promise<Contract> {
  const ProxyFactory = await ethers.getContractFactory('ProxyFactory')
  const contract = await ProxyFactory.deploy()
  await contract.deployed()
  return contract as Contract
}

async function deployIndexerCTDT(): Promise<IndexerCtdt> {
  const IndexerCtdt = await ethers.getContractFactory('IndexerCtdt')
  const contract = await IndexerCtdt.deploy()
  await contract.deployed()
  return contract as IndexerCtdt
}

async function deploySingleAssetInterpreter(): Promise<IndexerSingleAssetInterpreter> {
  const IndexerSingleAssetInterpreter = await ethers.getContractFactory(
    'IndexerSingleAssetInterpreter',
  )
  const contract = await IndexerSingleAssetInterpreter.deploy()
  await contract.deployed()
  return contract as IndexerSingleAssetInterpreter
}

async function deployMultiAssetInterpreter(): Promise<IndexerMultiAssetInterpreter> {
  const IndexerMultiAssetInterpreter = await ethers.getContractFactory(
    'IndexerMultiAssetInterpreter',
  )
  const contract = await IndexerMultiAssetInterpreter.deploy()
  await contract.deployed()
  return contract as IndexerMultiAssetInterpreter
}

async function deployWithdrawInterpreter(): Promise<IndexerWithdrawInterpreter> {
  const IndexerWithdrawInterpreter = await ethers.getContractFactory('IndexerWithdrawInterpreter')
  const contract = await IndexerWithdrawInterpreter.deploy()
  await contract.deployed()
  return contract as IndexerWithdrawInterpreter
}

async function deployMockStaking(tokenAddress: string): Promise<MockStaking> {
  const MockStaking = await ethers.getContractFactory('MockStaking')
  const contract = await MockStaking.deploy(tokenAddress)
  await contract.deployed()
  return contract as MockStaking
}

async function deployMockDispute(): Promise<MockDispute> {
  const MockDispute = await ethers.getContractFactory('MockDispute')
  const contract = await MockDispute.deploy()
  await contract.deployed()
  return contract as MockDispute
}

async function deployAppWithAction(): Promise<AppWithAction> {
  const AppWithAction = await ethers.getContractFactory('AppWithAction')
  const contract = await AppWithAction.deploy()
  await contract.deployed()
  return contract as AppWithAction
}

async function deployIdentityApp(): Promise<IdentityApp> {
  const IdentityApp = await ethers.getContractFactory('IdentityApp')
  const contract = await IdentityApp.deploy()
  await contract.deployed()
  return contract as IdentityApp
}

export async function deployIndexerMultisigWithContext(node: string, tokenAddress: string) {
  const ctdt = await deployIndexerCTDT()
  const singleAssetInterpreter = await deploySingleAssetInterpreter()
  const multiAssetInterpreter = await deployMultiAssetInterpreter()
  const withdrawInterpreter = await deployWithdrawInterpreter()
  const mockStaking = await deployMockStaking(tokenAddress)
  const mockDispute = await deployMockDispute()
  const app = await deployAppWithAction()
  const identity = await deployIdentityApp()

  const multisig = await deployIndexerMultisig(
    node,
    mockStaking.address,
    ctdt.address,
    singleAssetInterpreter.address,
    multiAssetInterpreter.address,
    withdrawInterpreter.address,
  )

  const proxy = await deployProxy(multisig.address)

  return {
    ctdt,
    singleAssetInterpreter,
    multiAssetInterpreter,
    withdrawInterpreter,
    mockStaking,
    multisig: proxy as MinimumViableMultisig,
    masterCopy: multisig,
    mockDispute,
    app,
    identity,
  }
}
