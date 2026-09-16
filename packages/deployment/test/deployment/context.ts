/**
 * Shared context for the GIP-0088 deployment test suites.
 *
 * These suites assert on-chain end-state of a real deployment, so they need a
 * network. The target network is selected by `TEST_DEPLOYMENT_NETWORK`:
 *
 *   TEST_DEPLOYMENT_NETWORK=localhost      pnpm test:deployment   # fork rehearsal
 *   TEST_DEPLOYMENT_NETWORK=arbitrumSepolia pnpm test:deployment  # testnet
 *
 * When the variable is unset the suites skip — so `pnpm test` (unit tests) and
 * accidental runs never touch a network. When it IS set the context must
 * resolve or the run fails: a deployment gate must not silently pass.
 */

import { createPublicClient, http, type PublicClient } from 'viem'

import type { AddressBookOps } from '../../lib/address-book-ops.js'
import {
  getForkTargetChainId,
  getHorizonAddressBook,
  getIssuanceAddressBook,
  getSubgraphServiceAddressBook,
} from '../../lib/address-book-utils.js'
import { CONTROLLER_ABI } from '../../lib/generated/abis.js'

/** Controller `pauseGuardian` is a public storage getter, not part of CONTROLLER_ABI. */
const PAUSE_GUARDIAN_ABI = [
  { inputs: [], name: 'pauseGuardian', outputs: [{ type: 'address' }], stateMutability: 'view', type: 'function' },
] as const

const DEFAULT_RPC_URLS: Record<string, string> = {
  arbitrumOne: 'https://arb1.arbitrum.io/rpc',
  arbitrumSepolia: 'https://sepolia-rollup.arbitrum.io/rpc',
}

export interface DeploymentContext {
  /** Network name from TEST_DEPLOYMENT_NETWORK */
  network: string
  /** Chain id the address books are keyed by (fork target when on a fork node) */
  chainId: number
  client: PublicClient
  horizon: AddressBookOps
  issuance: AddressBookOps
  subgraphService: AddressBookOps
  /** Protocol governor (Controller.getGovernor()) */
  governor: string
  /** Pause guardian (Controller.pauseGuardian()) */
  pauseGuardian: string
  /** Deployer EOA — only present when TEST_DEPLOYMENT_DEPLOYER is set */
  deployer?: string
}

function resolveRpcUrl(network: string): string {
  if (network === 'arbitrumSepolia') return process.env.ARBITRUM_SEPOLIA_RPC ?? DEFAULT_RPC_URLS.arbitrumSepolia
  if (network === 'arbitrumOne') return process.env.ARBITRUM_ONE_RPC ?? DEFAULT_RPC_URLS.arbitrumOne
  // localhost / fork
  return process.env.TEST_DEPLOYMENT_RPC ?? 'http://127.0.0.1:8545'
}

let cached: Promise<DeploymentContext | null> | undefined

/**
 * Resolve the deployment context once per `test:deployment` run.
 *
 * Returns `null` when `TEST_DEPLOYMENT_NETWORK` is unset — suites then skip.
 * Throws when the variable is set but the network or Controller is unreachable.
 */
export function getDeploymentContext(): Promise<DeploymentContext | null> {
  if (!cached) cached = resolveContext()
  return cached
}

async function resolveContext(): Promise<DeploymentContext | null> {
  const network = process.env.TEST_DEPLOYMENT_NETWORK
  if (!network) return null

  const client = createPublicClient({ transport: http(resolveRpcUrl(network)) }) as PublicClient
  const actualChainId = await client.getChainId()

  // On a fork / local node (31337 or 1337) the address books are keyed by the
  // forked network's chain id, resolved from FORK_NETWORK / HARDHAT_FORK.
  const isLocalNode = actualChainId === 31337 || actualChainId === 1337
  const chainId = isLocalNode ? (getForkTargetChainId() ?? actualChainId) : actualChainId

  const horizon = getHorizonAddressBook(chainId)
  const issuance = getIssuanceAddressBook(chainId)
  const subgraphService = getSubgraphServiceAddressBook(chainId)

  if (!horizon.entryExists('Controller')) {
    throw new Error(`Controller not found in the horizon address book for chainId ${chainId}`)
  }
  const controller = horizon.getEntry('Controller')!.address as `0x${string}`

  const governor = (await client.readContract({
    address: controller,
    abi: CONTROLLER_ABI,
    functionName: 'getGovernor',
  })) as string
  const pauseGuardian = (await client.readContract({
    address: controller,
    abi: PAUSE_GUARDIAN_ABI,
    functionName: 'pauseGuardian',
  })) as string

  return {
    network,
    chainId,
    client,
    horizon,
    issuance,
    subgraphService,
    governor,
    pauseGuardian,
    deployer: process.env.TEST_DEPLOYMENT_DEPLOYER,
  }
}

/** Resolve an address-book entry, failing clearly if the contract is missing. */
export function requireAddress(book: AddressBookOps, name: string): string {
  if (!book.entryExists(name)) {
    throw new Error(`${name} is missing from the address book — is the deployment complete?`)
  }
  const address = book.getEntry(name)?.address
  if (!address) throw new Error(`${name} has no address in the address book`)
  return address
}
