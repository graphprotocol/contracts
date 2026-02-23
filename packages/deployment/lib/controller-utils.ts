import type { Environment } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

import { CONTROLLER_ABI } from './abis.js'
import { Contracts } from './contract-registry.js'
import { requireContract } from './issuance-deploy-utils.js'
import { graph } from '../rocketh/deploy.js'

/**
 * Get the protocol governor address from the Controller contract
 *
 * The Controller contract is the governance registry for the Graph Protocol.
 * It stores the address of the protocol governor (typically a multi-sig).
 *
 * @param env - Deployment environment
 * @returns Governor address from Controller.getGovernor()
 */
export async function getGovernor(env: Environment): Promise<string> {
  const client = graph.getPublicClient(env) as PublicClient

  // Get Controller from deployments (synced from Horizon address book)
  const controller = requireContract(env, Contracts.horizon.Controller)

  // Query governor from Controller
  const governor = (await client.readContract({
    address: controller.address as `0x${string}`,
    abi: CONTROLLER_ABI,
    functionName: 'getGovernor',
  })) as string

  return governor
}

/**
 * Get pause guardian address from the Controller contract
 *
 * @param env - Deployment environment
 * @returns Pause guardian address from Controller.pauseGuardian()
 */
export async function getPauseGuardian(env: Environment): Promise<string> {
  const client = graph.getPublicClient(env) as PublicClient
  const controller = requireContract(env, Contracts.horizon.Controller)

  // Query pauseGuardian from Controller
  // Use minimal ABI since pauseGuardian() is auto-generated getter, not in IController interface
  const pauseGuardian = (await client.readContract({
    address: controller.address as `0x${string}`,
    abi: [
      {
        inputs: [],
        name: 'pauseGuardian',
        outputs: [{ internalType: 'address', name: '', type: 'address' }],
        stateMutability: 'view',
        type: 'function',
      },
    ],
    functionName: 'pauseGuardian',
  })) as string

  return pauseGuardian
}
