import { utils, Wallet, Contract } from 'ethers'
import { TransactionReceipt } from '@connext/types'
import { ChannelSigner } from '@connext/utils'
import { ethers, waffle } from '@nomiclabs/buidler'

import { defaults } from './testHelpers'

// contracts artifacts
import MinimumViableMultisigArtifact from '../../build/contracts/MinimumViableMultisig.json'

// contracts definitions
import { Curation } from '../../build/typechain/contracts/Curation'
import { DisputeManager } from '../../build/typechain/contracts/DisputeManager'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { Gns } from '../../build/typechain/contracts/Gns'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { ServiceRegistry } from '../../build/typechain/contracts/ServiceRegistry'
import { Staking } from '../../build/typechain/contracts/Staking'
import { MinimumViableMultisig } from '../../build/typechain/contracts/MinimumViableMultisig'

import { EthereumDidRegistry } from '../../build/typechain/contracts/EthereumDidRegistry'

import { IndexerCtdt } from '../../build/typechain/contracts/IndexerCtdt'
import { IndexerSingleAssetInterpreter } from '../../build/typechain/contracts/IndexerSingleAssetInterpreter'
import { IndexerMultiAssetInterpreter } from '../../build/typechain/contracts/IndexerMultiAssetInterpreter'
import { IndexerWithdrawInterpreter } from '../../build/typechain/contracts/IndexerWithdrawInterpreter'
import { MockStaking } from '../../build/typechain/contracts/MockStaking'
import { MockDispute } from '../../build/typechain/contracts/MockDispute'
import { AppWithAction } from '../../build/typechain/contracts/AppWithAction'
import { Proxy } from '../../build/typechain/contracts/Proxy'
import { IdentityApp } from '../../build/typechain/contracts/IdentityApp'

const { solidityKeccak256 } = utils

export async function deployGRT(owner: string): Promise<GraphToken> {
  const GraphToken = await ethers.getContractFactory('GraphToken')
  return GraphToken.deploy(owner, defaults.token.initialSupply) as Promise<GraphToken>
}

export async function deployCuration(owner: string, graphToken: string): Promise<Curation> {
  const Curation = await ethers.getContractFactory('Curation')
  return Curation.deploy(
    owner,
    graphToken,
    defaults.curation.reserveRatio,
    defaults.curation.minimumCurationStake,
  ) as Promise<Curation>
}

export async function deployDisputeManager(
  owner: string,
  graphToken: string,
  arbitrator: string,
  staking: string,
): Promise<DisputeManager> {
  const DisputeManager = await ethers.getContractFactory('DisputeManager')
  return DisputeManager.deploy(
    owner,
    arbitrator,
    graphToken,
    staking,
    defaults.dispute.minimumDeposit,
    defaults.dispute.fishermanRewardPercentage,
    defaults.dispute.slashingPercentage,
  ) as Promise<DisputeManager>
}

export async function deployEpochManager(owner: string): Promise<EpochManager> {
  const EpochManager = await ethers.getContractFactory('EpochManager')
  return EpochManager.deploy(owner, defaults.epochs.lengthInBlocks) as Promise<EpochManager>
}

export async function deployGNS(owner: string, didRegistry: string): Promise<Gns> {
  const GNS = await ethers.getContractFactory('GNS')
  return GNS.deploy(owner, didRegistry) as Promise<Gns>
}

export async function deployEthereumDIDRegistry(): Promise<EthereumDidRegistry> {
  const EthereumDIDRegistry = await ethers.getContractFactory('EthereumDIDRegistry')
  return EthereumDIDRegistry.deploy() as Promise<EthereumDidRegistry>
}

export async function deployServiceRegistry(): Promise<ServiceRegistry> {
  const ServiceRegistry = await ethers.getContractFactory('ServiceRegistry')
  return ServiceRegistry.deploy() as Promise<ServiceRegistry>
}

export async function deployStaking(
  owner: Wallet,
  graphToken: string,
  epochManager: string,
  curation: string,
): Promise<Staking> {
  const Staking = await ethers.getContractFactory('Staking')
  const contract = (await Staking.deploy(owner.address, graphToken, epochManager)) as Staking
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

async function deployIndexerCtdt(): Promise<IndexerCtdt> {
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

export async function deployChannelContracts(node: string, tokenAddress: string) {
  const ctdt = await deployIndexerCtdt()
  const singleAssetInterpreter = await deploySingleAssetInterpreter()
  const multiAssetInterpreter = await deployMultiAssetInterpreter()
  const withdrawInterpreter = await deployWithdrawInterpreter()
  const mockStaking = await deployMockStaking(tokenAddress)
  const mockDispute = await deployMockDispute()
  const app = await deployAppWithAction()
  const identity = await deployIdentityApp()
  const proxyFactory = await deployProxyFactory()

  const multisigMaster = await deployIndexerMultisig(
    node,
    mockStaking.address,
    ctdt.address,
    singleAssetInterpreter.address,
    multiAssetInterpreter.address,
    withdrawInterpreter.address,
  )

  return {
    ctdt,
    singleAssetInterpreter,
    multiAssetInterpreter,
    withdrawInterpreter,
    mockStaking,
    masterCopy: multisigMaster,
    mockDispute,
    app,
    identity,
    proxyFactory,
  }
}

export async function deployMultisigWithProxy(
  node: string,
  tokenAddress: string,
  owners: ChannelSigner[],
  existingContext?: any,
) {
  const ctx = existingContext || (await deployChannelContracts(node, tokenAddress))
  const {
    ctdt,
    singleAssetInterpreter,
    multiAssetInterpreter,
    withdrawInterpreter,
    mockStaking,
    proxyFactory,
    masterCopy,
    mockDispute,
    app,
    identity,
  } = ctx
  const tx = await proxyFactory.functions.createProxyWithNonce(
    masterCopy.address,
    masterCopy.interface.encodeFunctionData('setup(address[])', [
      owners.map((owner) => owner.address),
    ]),
    // hardcode ganache chainId
    solidityKeccak256(['uint256', 'uint256'], [4447, 0]),
  )
  const receipt = (await tx.wait()) as TransactionReceipt
  const { proxy: multisigAddr } = proxyFactory.interface.parseLog(receipt.logs[0]).args

  const multisig = new Contract(
    multisigAddr,
    MinimumViableMultisigArtifact.abi,
    waffle.provider,
  ) as MinimumViableMultisig

  return {
    ctdt,
    singleAssetInterpreter,
    multiAssetInterpreter,
    withdrawInterpreter,
    mockStaking,
    masterCopy,
    mockDispute,
    app,
    identity,
    proxyFactory,
    multisig,
  }
}
