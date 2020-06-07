import { utils } from 'ethers'

import * as Curation from '../../build/contracts/Curation.json'
import * as DisputeManager from '../../build/contracts/DisputeManager.json'
import * as EpochManager from '../../build/contracts/EpochManager.json'
import * as GraphToken from '../../build/contracts/GraphToken.json'
import * as GNS from '../../build/contracts/GNS.json'
import * as RewardManager from '../../build/contracts/RewardsManager.json'
import * as ServiceRegistry from '../../build/contracts/ServiceRegistry.json'
import * as Staking from '../../build/contracts/Staking.json'

import * as IndexerCTDT from '../../build/contracts/IndexerCTDT.json'
import * as IndexerMultiAssetInterpreter from '../../build/contracts/IndexerMultiAssetInterpreter.json'
import * as IndexerSingleAssetInterpreter from '../../build/contracts/IndexerSingleAssetInterpreter.json'
import * as IndexerWithdrawInterpreter from '../../build/contracts/IndexerWithdrawInterpreter.json'
import * as MinimumViableMultisig from '../../build/contracts/MinimumViableMultisig.json'

type Abi = Array<string | utils.FunctionFragment | utils.EventFragment | utils.ParamType>

type Artifact = {
  contractName: string
  abi: Abi
  bytecode: string
  deployedBytecode: string
}

type Artifacts = { [contractName: string]: Artifact }

export const artifacts = {
  Curation,
  DisputeManager,
  EpochManager,
  GraphToken,
  GNS,
  RewardManager,
  ServiceRegistry,
  Staking,
  IndexerCTDT,
  IndexerMultiAssetInterpreter,
  IndexerSingleAssetInterpreter,
  IndexerWithdrawInterpreter,
  MinimumViableMultisig,
} as Artifacts

export { EpochManager, GraphToken }
