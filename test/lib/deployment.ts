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

// contracts definitions
import { Curation } from '../../build/typechain/contracts/Curation'
import { DisputeManager } from '../../build/typechain/contracts/DisputeManager'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { Gns } from '../../build/typechain/contracts/Gns'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { ServiceRegistry } from '../../build/typechain/contracts/ServiceRegistry'
import { Staking } from '../../build/typechain/contracts/Staking'

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
