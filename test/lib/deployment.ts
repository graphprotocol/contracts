import { utils, Contract, Signer, Wallet } from 'ethers'
import { TransactionReceipt } from '@connext/types'
import { ChannelSigner } from '@connext/utils'
import { ethers, waffle } from '@nomiclabs/buidler'

import { defaults } from './testHelpers'

// contracts artifacts
import MinimumViableMultisigArtifact from '../../build/contracts/MinimumViableMultisig.json'

// contracts definitions
import { GraphProxy } from '../../build/typechain/contracts/GraphProxy'
import { Curation } from '../../build/typechain/contracts/Curation'
import { DisputeManager } from '../../build/typechain/contracts/DisputeManager'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { Gns } from '../../build/typechain/contracts/Gns'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { ServiceRegistry } from '../../build/typechain/contracts/ServiceRegistry'
import { Staking } from '../../build/typechain/contracts/Staking'

import { EthereumDidRegistry } from '../../build/typechain/contracts/EthereumDidRegistry'

import { MinimumViableMultisig } from '../../build/typechain/contracts/MinimumViableMultisig'
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

export async function deployGRT(owner: Signer): Promise<GraphToken> {
  const factory = await ethers.getContractFactory('GraphToken')
  return factory.connect(owner).deploy(defaults.token.initialSupply) as Promise<GraphToken>
}

export async function deployCuration(owner: Signer, graphToken: string): Promise<Curation> {
  // Impl
  const factory = await ethers.getContractFactory('Curation')
  const contract = (await factory.connect(owner).deploy()) as Curation

  // Proxy
  const proxyFactory = await ethers.getContractFactory('GraphProxy')
  const proxy = (await proxyFactory.connect(owner).deploy()) as GraphProxy
  await proxy.connect(owner).upgradeTo(contract.address)

  // Impl accept and initialize
  await contract
    .connect(owner)
    .upgradeFrom(
      proxy.address,
      graphToken,
      defaults.curation.reserveRatio,
      defaults.curation.minimumCurationStake,
    )

  // Use proxy to forward calls to implementation contract
  return Promise.resolve(factory.attach(proxy.address) as Curation)
}

export async function deployDisputeManager(
  owner: Signer,
  graphToken: string,
  arbitrator: string,
  staking: string,
): Promise<DisputeManager> {
  const factory = await ethers.getContractFactory('DisputeManager')
  return factory
    .connect(owner)
    .deploy(
      arbitrator,
      graphToken,
      staking,
      defaults.dispute.minimumDeposit,
      defaults.dispute.fishermanRewardPercentage,
      defaults.dispute.slashingPercentage,
    ) as Promise<DisputeManager>
}

export async function deployEpochManager(owner: Signer): Promise<EpochManager> {
  const factory = await ethers.getContractFactory('EpochManager')
  return factory.connect(owner).deploy(defaults.epochs.lengthInBlocks) as Promise<EpochManager>
}

export async function deployGNS(owner: Signer, didRegistry: string): Promise<Gns> {
  const factory = await ethers.getContractFactory('GNS')
  return factory.connect(owner).deploy(didRegistry) as Promise<Gns>
}

export async function deployEthereumDIDRegistry(): Promise<EthereumDidRegistry> {
  const factory = await ethers.getContractFactory('EthereumDIDRegistry')
  return factory.deploy() as Promise<EthereumDidRegistry>
}

export async function deployServiceRegistry(): Promise<ServiceRegistry> {
  const factory = await ethers.getContractFactory('ServiceRegistry')
  return factory.deploy() as Promise<ServiceRegistry>
}

export async function deployStaking(
  owner: Signer,
  graphToken: string,
  epochManager: string,
  curation: string,
): Promise<Staking> {
  const factory = await ethers.getContractFactory('Staking')
  const contract = (await factory.connect(owner).deploy(graphToken, epochManager)) as Staking
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
  const factory = await ethers.getContractFactory('MinimumViableMultisig')
  const contract = await factory.deploy(
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
  const factory = await ethers.getContractFactory('Proxy')
  const contract = await factory.deploy(masterCopy)
  await contract.deployed()
  return contract as Proxy
}

// Note: this cannot be typed properly because "ProxyFactory" is generated by the Proxy contract
async function deployProxyFactory(): Promise<Contract> {
  const factory = await ethers.getContractFactory('ProxyFactory')
  const contract = await factory.deploy()
  await contract.deployed()
  return contract as Contract
}

async function deployIndexerCtdt(): Promise<IndexerCtdt> {
  const factory = await ethers.getContractFactory('IndexerCtdt')
  const contract = await factory.deploy()
  await contract.deployed()
  return contract as IndexerCtdt
}

async function deploySingleAssetInterpreter(): Promise<IndexerSingleAssetInterpreter> {
  const factory = await ethers.getContractFactory('IndexerSingleAssetInterpreter')
  const contract = await factory.deploy()
  await contract.deployed()
  return contract as IndexerSingleAssetInterpreter
}

async function deployMultiAssetInterpreter(): Promise<IndexerMultiAssetInterpreter> {
  const factory = await ethers.getContractFactory('IndexerMultiAssetInterpreter')
  const contract = await factory.deploy()
  await contract.deployed()
  return contract as IndexerMultiAssetInterpreter
}

async function deployWithdrawInterpreter(): Promise<IndexerWithdrawInterpreter> {
  const factory = await ethers.getContractFactory('IndexerWithdrawInterpreter')
  const contract = await factory.deploy()
  await contract.deployed()
  return contract as IndexerWithdrawInterpreter
}

async function deployMockStaking(tokenAddress: string): Promise<MockStaking> {
  const factory = await ethers.getContractFactory('MockStaking')
  const contract = await factory.deploy(tokenAddress)
  await contract.deployed()
  return contract as MockStaking
}

async function deployMockDispute(): Promise<MockDispute> {
  const factory = await ethers.getContractFactory('MockDispute')
  const contract = await factory.deploy()
  await contract.deployed()
  return contract as MockDispute
}

async function deployAppWithAction(): Promise<AppWithAction> {
  const factory = await ethers.getContractFactory('AppWithAction')
  const contract = await factory.deploy()
  await contract.deployed()
  return contract as AppWithAction
}

async function deployIdentityApp(): Promise<IdentityApp> {
  const factory = await ethers.getContractFactory('IdentityApp')
  const contract = await factory.deploy()
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
    masterCopy.interface.encodeFunctionData('setup', [owners.map((owner) => owner.address)]),
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
