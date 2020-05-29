import { Wallet } from 'ethers'
import { deployContract } from 'ethereum-waffle'

// contracts artifacts
import CurationArtifact from '../../build/contracts/Curation.json'
import DisputeManagerArtifact from '../../build/contracts/DisputeManager.json'
import EpochManagerArtifact from '../../build/contracts/EpochManager.json'
import GNSArtifact from '../../build/contracts/GNS.json'
import GraphTokenArtifact from '../../build/contracts/GraphToken.json'
import ServiceRegistyArtifact from '../../build/contracts/ServiceRegistry.json'
import StakingArtifact from '../../build/contracts/Staking.json'
import MultisigArtifact from '../../build/contracts/MinimumViableMultisig.json'
import IndexerCTDTArtifact from '../../build/contracts/IndexerCTDT.json'
import SingleAssetInterpreterArtifact from '../../build/contracts/IndexerSingleAssetInterpreter.json'
import MultiAssetInterpreterArtifact from '../../build/contracts/IndexerMultiAssetInterpreter.json'
import WithdrawInterpreterArtifact from '../../build/contracts/IndexerWithdrawInterpreter.json'
import MockStakingArtifact from '../../build/contracts/MockStaking.json'
import ProxyArtifact from '../../build/contracts/Proxy.json'

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
import { Proxy } from '../../build/typechain/contracts/Proxy'

// helpers
import { defaults } from './testHelpers'

const deployGasLimit = 9000000

export function deployGRT(owner: string, wallet: Wallet): Promise<GraphToken> {
  return deployContract(wallet, GraphTokenArtifact, [
    owner,
    defaults.token.initialSupply,
  ]) as Promise<GraphToken>
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

export function deployIndexerMultisig(
  node: string,
  staking: string,
  ctdt: string,
  singleAssetInterpreter: string,
  multiAssetInterpreter: string,
  withdrawInterpreter: string,
  wallet: Wallet,
): Promise<MinimumViableMultisig> {
  return deployContract(wallet, MultisigArtifact, [
    node,
    staking,
    ctdt,
    singleAssetInterpreter,
    multiAssetInterpreter,
    withdrawInterpreter,
  ]) as Promise<MinimumViableMultisig>
}

function deployProxy(masterCopy: string, wallet: Wallet): Promise<Proxy> {
  return deployContract(wallet, ProxyArtifact, [masterCopy]) as Promise<Proxy>
}

function deployIndexerCTDT(wallet: Wallet): Promise<IndexerCtdt> {
  return deployContract(wallet, IndexerCTDTArtifact) as Promise<IndexerCtdt>
}

function deploySingleAssetInterpreter(wallet: Wallet): Promise<IndexerSingleAssetInterpreter> {
  return deployContract(wallet, SingleAssetInterpreterArtifact) as Promise<
    IndexerSingleAssetInterpreter
  >
}

function deployMultiAssetInterpreter(wallet: Wallet): Promise<IndexerMultiAssetInterpreter> {
  return deployContract(wallet, MultiAssetInterpreterArtifact) as Promise<
    IndexerMultiAssetInterpreter
  >
}

function deployWithdrawInterpreter(wallet: Wallet): Promise<IndexerWithdrawInterpreter> {
  return deployContract(wallet, WithdrawInterpreterArtifact) as Promise<IndexerWithdrawInterpreter>
}

function deployMockStaking(wallet: Wallet): Promise<MockStaking> {
  return deployContract(wallet, MockStakingArtifact) as Promise<MockStaking>
}

export async function deployIndexerMultisigWithContext(node: string, wallet: Wallet) {
  const ctdt = await deployIndexerCTDT(wallet)
  const singleAssetInterpreter = await deploySingleAssetInterpreter(wallet)
  const multiAssetInterpreter = await deployMultiAssetInterpreter(wallet)
  const withdrawInterpreter = await deployWithdrawInterpreter(wallet)
  const mockStaking = await deployMockStaking(wallet)

  const multisig = await deployIndexerMultisig(
    node,
    mockStaking.address,
    ctdt.address,
    singleAssetInterpreter.address,
    multiAssetInterpreter.address,
    withdrawInterpreter.address,
    wallet,
  )

  const proxy = await deployProxy(multisig.address, wallet)

  return {
    ctdt,
    singleAssetInterpreter,
    multiAssetInterpreter,
    withdrawInterpreter,
    mockStaking,
    multisig: proxy,
    masterCopy: multisig,
  }
}
