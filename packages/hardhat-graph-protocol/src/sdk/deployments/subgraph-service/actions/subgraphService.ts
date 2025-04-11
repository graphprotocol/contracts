import { BytesLike, HDNodeWallet, Interface } from 'ethers'
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

import { ISubgraphService } from '@graphprotocol/subgraph-service'

import { PaymentTypes } from '../../horizon/utils/types'

/* //////////////////////////////////////////////////////////////
                            EXPORTS
////////////////////////////////////////////////////////////// */

export const SubgraphServiceActions = {
  collect,
  migrateLegacyAllocation,
  register,
  startService,
}

/* //////////////////////////////////////////////////////////////
                            REGISTRATION
////////////////////////////////////////////////////////////// */

interface RegisterParams {
  subgraphService: ISubgraphService
  indexer: HardhatEthersSigner
  data: BytesLike
}

/**
 * Registers an indexer with the subgraph service
 * @param subgraphService The subgraph service contract
 * @param indexer The indexer that is registering
 * @param data The encoded registration data
 */
export async function register({
  subgraphService,
  indexer,
  data,
}: RegisterParams) {
  const tx = await subgraphService.connect(indexer).register(indexer.address, data)
  await tx.wait()
}

/* //////////////////////////////////////////////////////////////
                        ALLOCATION MANAGEMENT
////////////////////////////////////////////////////////////// */

interface MigrateLegacyAllocationParams {
  subgraphService: ISubgraphService
  governor: HardhatEthersSigner
  indexer: string
  allocationId: string
  subgraphDeploymentId: string
}

/**
 * Migrates a legacy allocation from the old staking contract to the new subgraph service
 * @param subgraphService The subgraph service contract
 * @param governor The governor of the subgraph service
 * @param indexer The indexer owner of the legacy allocation
 * @param allocationId The allocation id of the legacy allocation
 * @param subgraphDeploymentId The subgraph deployment id for the legacy allocation
 */
export async function migrateLegacyAllocation({
  subgraphService,
  governor,
  indexer,
  allocationId,
  subgraphDeploymentId,
}: MigrateLegacyAllocationParams) {
  const tx = await subgraphService.connect(governor).migrateLegacyAllocation(indexer, allocationId, subgraphDeploymentId)
  await tx.wait()
}

interface StartServiceParams {
  subgraphService: ISubgraphService
  indexer: HardhatEthersSigner
  data: BytesLike
}

/**
 * Service provider starts providing service for a subgraph deployment
 * @param subgraphService The subgraph service contract
 * @param indexer The indexer that is starting the service
 * @param data The encoded data for the allocation
 */
export async function startService({
  subgraphService,
  indexer,
  data,
}: StartServiceParams) {
  const tx = await subgraphService.connect(indexer).startService(indexer.address, data)
  await tx.wait()
}

/* //////////////////////////////////////////////////////////////
                            COLLECT
////////////////////////////////////////////////////////////// */

interface CollectParams {
  subgraphService: ISubgraphService
  signer: HardhatEthersSigner | HDNodeWallet
  indexer: string
  paymentType: PaymentTypes
  data: BytesLike
}

/**
 * Collects the allocated funds for a subgraph deployment
 * @param subgraphService The subgraph service contract
 * @param indexer The indexer that is collecting the funds
 * @param data The encoded data for the allocation
 * @returns The payment collected
 */
export async function collect({ subgraphService, signer, indexer, paymentType, data }: CollectParams): Promise<bigint> {
  const tx = await subgraphService.connect(signer).collect(
    indexer,
    paymentType,
    data
  )
  const receipt = await tx.wait()
  if (!receipt) throw new Error('Transaction failed')

  const iface = new Interface(['event ServicePaymentCollected(address indexed serviceProvider, uint8 indexed feeType, uint256 tokens)'])
  const event = receipt.logs.find(log => log.topics[0] === iface.getEvent('ServicePaymentCollected')?.topicHash)
  if (!event) throw new Error('ServicePaymentCollected event not found')

  return BigInt(event.data)
}
