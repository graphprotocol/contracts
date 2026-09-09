/**
 * Shared assertions for OpenZeppelin TransparentUpgradeableProxy contracts.
 *
 * All GIP-0088 issuance contracts (IssuanceAllocator, RewardsEligibilityOracle,
 * RecurringAgreementManager, and the DirectAllocation-backed DefaultAllocation /
 * ReclaimedRewards) deploy behind an OZ v5 transparent proxy with a per-proxy
 * ProxyAdmin. `transparentProxyTests` registers the proxy-level checks the
 * `lib/` precondition functions do not cover: ERC-1967 slot wiring, ProxyAdmin
 * ownership, and that the implementation contract is initialization-locked.
 */

import { expect } from 'chai'
import { getAddress, type PublicClient } from 'viem'

import { OZ_PROXY_ADMIN_ABI } from '../../lib/generated/abis.js'

// ERC-1967 storage slots
const IMPLEMENTATION_SLOT = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
const ADMIN_SLOT = '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103'
// OZ v5 Initializable namespaced storage (ERC-7201)
const INITIALIZABLE_SLOT = '0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00'

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
const UINT64_MASK = 0xffffffffffffffffn

export interface ProxyContext {
  client: PublicClient
  /** The proxy (contract) address */
  proxyAddress: string
  /** Protocol governor — expected ProxyAdmin owner after transfer */
  governor: string
  /** Implementation address recorded in the address book, if any */
  expectedImplementation?: string
  /** ProxyAdmin address recorded in the address book, if any */
  expectedProxyAdmin?: string
}

/** Read a 32-byte storage slot and interpret its low 20 bytes as an address. */
async function readAddressSlot(client: PublicClient, address: string, slot: string): Promise<string> {
  const raw = await client.getStorageAt({ address: address as `0x${string}`, slot: slot as `0x${string}` })
  if (!raw || raw === '0x') return ZERO_ADDRESS
  return getAddress(`0x${raw.slice(-40)}`)
}

/**
 * Register the transparent-proxy assertions for a contract.
 *
 * `get` is called at test time (after the suite's `before` hook has resolved
 * the deployment context), so the proxy address can depend on resolved state.
 */
export function transparentProxyTests(get: () => ProxyContext): void {
  it('has contract code at the proxy address', async function () {
    const { client, proxyAddress } = get()
    const code = await client.getCode({ address: proxyAddress as `0x${string}` })
    expect(code, `no code at ${proxyAddress}`).to.be.a('string')
    expect(code).to.not.equal('0x')
  })

  it('proxy implementation slot points at the deployed implementation', async function () {
    const { client, proxyAddress, expectedImplementation } = get()
    const implementation = await readAddressSlot(client, proxyAddress, IMPLEMENTATION_SLOT)
    expect(implementation, 'ERC-1967 implementation slot is zero').to.not.equal(ZERO_ADDRESS)
    if (expectedImplementation) {
      expect(implementation.toLowerCase(), 'implementation slot != address book').to.equal(
        expectedImplementation.toLowerCase(),
      )
    }
  })

  it('proxy admin slot is set and the ProxyAdmin is owned by the governor', async function () {
    const { client, proxyAddress, governor, expectedProxyAdmin } = get()
    const proxyAdmin = await readAddressSlot(client, proxyAddress, ADMIN_SLOT)
    expect(proxyAdmin, 'ERC-1967 admin slot is zero').to.not.equal(ZERO_ADDRESS)
    if (expectedProxyAdmin) {
      expect(proxyAdmin.toLowerCase(), 'admin slot != address book').to.equal(expectedProxyAdmin.toLowerCase())
    }
    const owner = (await client.readContract({
      address: proxyAdmin as `0x${string}`,
      abi: OZ_PROXY_ADMIN_ABI,
      functionName: 'owner',
    })) as string
    expect(owner.toLowerCase(), 'ProxyAdmin is not owned by the governor').to.equal(governor.toLowerCase())
  })

  it('implementation contract is initialization-locked', async function () {
    const { client, proxyAddress, expectedImplementation } = get()
    const implementation = expectedImplementation ?? (await readAddressSlot(client, proxyAddress, IMPLEMENTATION_SLOT))
    const raw = await client.getStorageAt({
      address: implementation as `0x${string}`,
      slot: INITIALIZABLE_SLOT as `0x${string}`,
    })
    // OZ v5 Initializable packs `uint64 _initialized` in the low 8 bytes.
    // _disableInitializers() in the implementation constructor sets it to
    // type(uint64).max, so the implementation can never be initialized directly.
    const initialized = (raw ? BigInt(raw) : 0n) & UINT64_MASK
    expect(initialized, 'implementation is not initialization-locked').to.equal(UINT64_MASK)
  })
}
