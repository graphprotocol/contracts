import { Signer, utils } from 'ethers'
import { NetworkContracts } from '../../../cli/contracts'

const { hexlify, randomBytes } = utils

export const publishNewSubgraph = async (
  contracts: NetworkContracts,
  publisher: Signer,
  deploymentId: string,
): Promise<void> => {
  const tx = await contracts.GNS.connect(publisher).publishNewSubgraph(
    deploymentId,
    hexlify(randomBytes(32)),
    hexlify(randomBytes(32)),
  )
  await tx.wait()
}
