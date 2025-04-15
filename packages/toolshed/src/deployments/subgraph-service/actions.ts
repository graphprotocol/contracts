import { ethers, HDNodeWallet, Wallet } from 'ethers'

import type { ISubgraphService } from '@graphprotocol/subgraph-service'
import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { Interface } from 'ethers'

export function loadActions(contracts: { SubgraphService: ISubgraphService }) {
  return {
    /**
     * Collects the allocated funds for a subgraph deployment
     * @param signer - The signer that will execute the collect transaction
     * @param args Parameters:
     *   - `[indexer, paymentType, data]` - The collect parameters
     * @returns The payment collected
     */
    collect: (signer: HardhatEthersSigner | HDNodeWallet, args: Parameters<ISubgraphService['collect']>): Promise<bigint> => collect(contracts, signer, args),

    /**
     * Generates an allocation proof for the subgraph services
     * @param signer - The signer that will sign the allocation proof
     * @param args Parameters:
     *   - `[indexer, allocationId]` - The encodeAllocationProof parameters
     * @returns The allocation proof
     */
    generateAllocationProof: (allocationPrivateKey: string, args: Parameters<ISubgraphService['encodeAllocationProof']>): Promise<string> => generateAllocationProof(contracts, allocationPrivateKey, args),
  }
}

// Collects payment from the subgraph service
async function collect(
  contracts: { SubgraphService: ISubgraphService },
  signer: HardhatEthersSigner | HDNodeWallet,
  args: Parameters<ISubgraphService['collect']>,
): Promise<bigint> {
  const { SubgraphService } = contracts
  const [indexer, paymentType, data] = args

  const tx = await SubgraphService.connect(signer).collect(indexer, paymentType, data)
  const receipt = await tx.wait()
  if (!receipt) throw new Error('Transaction failed')

  const iface = new Interface(['event ServicePaymentCollected(address indexed serviceProvider, uint8 indexed feeType, uint256 tokens)'])
  const event = receipt.logs.find(log => log.topics[0] === iface.getEvent('ServicePaymentCollected')?.topicHash)
  if (!event) throw new Error('ServicePaymentCollected event not found')

  return BigInt(event.data)
}

// Generate allocation proof for the subgraph services
async function generateAllocationProof(
  contracts: { SubgraphService: ISubgraphService },
  allocationPrivateKey: string,
  args: Parameters<ISubgraphService['encodeAllocationProof']>,
): Promise<string> {
  const { SubgraphService } = contracts
  const [indexer, allocationId] = args

  const wallet = new ethers.Wallet(allocationPrivateKey)
  const messageHash = await SubgraphService.encodeAllocationProof(indexer, allocationId)
  const signature = wallet.signingKey.sign(messageHash)
  return ethers.Signature.from(signature).serialized
}