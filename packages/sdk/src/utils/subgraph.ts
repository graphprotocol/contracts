import { BigNumber, ethers } from 'ethers'
import { solidityKeccak256 } from 'ethers/lib/utils'
import { base58ToHex, randomHexBytes } from './bytes'

export interface PublishSubgraph {
  subgraphDeploymentID: string
  versionMetadata: string
  subgraphMetadata: string
}

export interface Subgraph {
  vSignal: BigNumber
  nSignal: BigNumber
  subgraphDeploymentID: string
  reserveRatioDeprecated: number
  disabled: boolean
  withdrawableGRT: BigNumber
  id?: string
}

export const buildSubgraphId = async (
  account: string,
  seqId: number | BigNumber,
  chainId: number | BigNumber,
): Promise<string> => {
  return solidityKeccak256(['address', 'uint256', 'uint256'], [account, seqId, chainId])
}

export const buildLegacySubgraphId = (account: string, seqID: BigNumber): string =>
  solidityKeccak256(['address', 'uint256'], [account, seqID])

export const buildSubgraph = (): PublishSubgraph => {
  return {
    subgraphDeploymentID: randomHexBytes(),
    versionMetadata: randomHexBytes(),
    subgraphMetadata: randomHexBytes(),
  }
}

export const subgraphIdToHex = (id: string): string => {
  id = id.startsWith('Qm') ? id : `Qm${id}`
  return `0x${base58ToHex(id).slice(6)}`
}
