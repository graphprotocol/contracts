import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumber } from 'ethers'
import { solidityKeccak256 } from 'ethers/lib/utils'
import { NetworkContracts } from '../../../cli/contracts'
import { randomHexBytes, sendTransaction } from '../../../cli/network'

export const recreatePreviousSubgraphId = async (
  contracts: NetworkContracts,
  owner: string,
  previousIndex: number,
): Promise<string> => {
  const seqID = (await contracts.GNS.nextAccountSeqID(owner)).sub(previousIndex)
  return buildSubgraphID(owner, seqID)
}

export const buildSubgraphID = (account: string, seqID: BigNumber): string =>
  solidityKeccak256(['address', 'uint256'], [account, seqID])

export const publishNewSubgraph = async (
  contracts: NetworkContracts,
  publisher: SignerWithAddress,
  deploymentId: string,
): Promise<string> => {
  console.log(`\nPublishing new subgraph with deploymentId ${deploymentId}...`)
  const subgraphId = buildSubgraphID(
    publisher.address,
    await contracts.GNS.nextAccountSeqID(publisher.address),
  )
  await sendTransaction(
    publisher,
    contracts.GNS,
    'publishNewSubgraph',
    [deploymentId, randomHexBytes(), randomHexBytes()],
    {
      gasLimit: 4_000_000,
    },
  )
  return subgraphId
}
