import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumber, ethers } from 'ethers'

import { setGRTAllowances } from './graph-token'
import { buildSubgraphId } from '../../../utils/subgraph'
import { randomHexBytes } from '../../../utils/bytes'

import type { GraphNetworkAction } from './types'
import type { GraphNetworkContracts } from '../deployment/contracts/load'

export const mintSignal: GraphNetworkAction<{ subgraphId: string; amount: BigNumber }> = async (
  contracts: GraphNetworkContracts,
  curator: SignerWithAddress,
  args: {
    subgraphId: string
    amount: BigNumber
  },
): Promise<void> => {
  const { subgraphId, amount } = args

  // Approve
  await setGRTAllowances(contracts, curator, [
    { spender: contracts.GNS.address, allowance: amount },
  ])

  // Add signal
  console.log(
    `\nCurator ${curator.address} add ${ethers.utils.formatEther(
      amount,
    )} in signal to subgraphId ${subgraphId}..`,
  )
  const tx = await contracts.GNS.connect(curator).mintSignal(subgraphId, amount, 0, {
    gasLimit: 4_000_000,
  })
  await tx.wait()
}

export const publishNewSubgraph: GraphNetworkAction<
  { deploymentId: string; chainId: number },
  string
> = async (
  contracts: GraphNetworkContracts,
  publisher: SignerWithAddress,
  args: { deploymentId: string; chainId: number },
): Promise<string> => {
  const { deploymentId, chainId } = args

  console.log(`\nPublishing new subgraph with deploymentId ${deploymentId}...`)
  const subgraphId = await buildSubgraphId(
    publisher.address,
    await contracts.GNS.nextAccountSeqID(publisher.address),
    chainId,
  )
  const tx = await contracts.GNS.connect(publisher).publishNewSubgraph(
    deploymentId,
    randomHexBytes(),
    randomHexBytes(),
    { gasLimit: 4_000_000 },
  )
  await tx.wait()

  return subgraphId
}

export const recreatePreviousSubgraphId: GraphNetworkAction<
  {
    owner: string
    previousIndex: number
    chainId: number
  },
  string
> = async (
  contracts: GraphNetworkContracts,
  _signer: SignerWithAddress,
  args: { owner: string; previousIndex: number; chainId: number },
): Promise<string> => {
  const { owner, previousIndex, chainId } = args
  const seqID = (await contracts.GNS.nextAccountSeqID(owner)).sub(previousIndex)
  return buildSubgraphId(owner, seqID, chainId)
}
