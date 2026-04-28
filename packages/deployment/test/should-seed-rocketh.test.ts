import { expect } from 'chai'

import { getLibraryResolver, loadDirectAllocationArtifact } from '../lib/artifact-loaders.js'
import { computeBytecodeHash } from '../lib/bytecode-utils.js'
import { Contracts } from '../lib/contract-registry.js'
import { type ContractSpec, shouldSeedRocketh } from '../lib/sync-utils.js'

/**
 * shouldSeedRocketh — gate that decides whether sync should write rocketh's
 * deployment record from the local artifact.
 *
 * The gate exists to prevent a silent failure mode: seeding rocketh from a
 * stale local artifact masks rocketh's bytecode-change detection on the next
 * deployFn call (it ends up comparing the new artifact to itself), so the
 * impl never gets redeployed and dependent proxies never receive a pending
 * implementation. Concretely, this caused shared-impl proxies (DefaultAllocation,
 * ReclaimedRewards) to get stuck on stale code with no upgrade triggered.
 *
 * The rules below are the truth table that pins the gate against future
 * regressions of any of those failure modes.
 */

const sharedImpl = Contracts.issuance.DirectAllocation_Implementation

function specForSharedImpl(overrides: Partial<ContractSpec> = {}): ContractSpec {
  return {
    name: sharedImpl.name,
    addressBookType: 'issuance',
    address: '0x0000000000000000000000000000000000000aaa',
    prerequisite: false,
    artifact: sharedImpl.artifact,
    ...overrides,
  }
}

function localArtifactHash(): string {
  const artifact = loadDirectAllocationArtifact()
  return computeBytecodeHash(
    artifact.deployedBytecode ?? '0x',
    artifact.deployedLinkReferences,
    getLibraryResolver('issuance'),
  )
}

describe('shouldSeedRocketh', () => {
  it('seeds when name is unregistered (proxy-recursion synthetic name passthrough)', () => {
    // Regression: my first attempt of this gate broke RewardsManager sync because
    // the proxy path recurses with `${name}_Implementation` synthetic names that
    // aren't real registry entries. The gate must let those fall through.
    const spec = specForSharedImpl({ name: 'RewardsManager_Implementation' })
    const result = shouldSeedRocketh(spec, {})
    expect(result.seed).to.be.true
    expect(result.reason).to.match(/unregistered/)
  })

  it('seeds when contract is a prerequisite (e.g. L2GraphToken passthrough)', () => {
    // Regression: prerequisites are deployed externally and never run through
    // deployFn, so dedup-masking doesn't apply. They still need an env record
    // for downstream reads. Skipping the seed broke L2GraphToken.
    const spec = specForSharedImpl({ prerequisite: true })
    const result = shouldSeedRocketh(spec, {})
    expect(result.seed).to.be.true
    expect(result.reason).to.match(/prerequisite/)
  })

  it('seeds when no artifact is configured (legacy entries with no comparison possible)', () => {
    const spec = specForSharedImpl({ artifact: undefined })
    const result = shouldSeedRocketh(spec, {})
    expect(result.seed).to.be.true
    expect(result.reason).to.match(/no artifact/)
  })

  it('seeds when address-book has no entry (nothing to mask)', () => {
    const spec = specForSharedImpl()
    const addressBook = { entryExists: () => false }
    const result = shouldSeedRocketh(spec, addressBook)
    expect(result.seed).to.be.true
    expect(result.reason).to.match(/no entry/)
  })

  it('seeds when entry exists but has no stored bytecodeHash', () => {
    const spec = specForSharedImpl()
    const addressBook = {
      entryExists: () => true,
      getDeploymentMetadata: () => undefined,
    }
    const result = shouldSeedRocketh(spec, addressBook)
    expect(result.seed).to.be.true
    expect(result.reason).to.match(/no hash/)
  })

  it('seeds when stored hash matches local artifact hash (artifact verified)', () => {
    const spec = specForSharedImpl()
    const addressBook = {
      entryExists: () => true,
      getDeploymentMetadata: () => ({
        bytecodeHash: localArtifactHash(),
        txHash: '',
        argsData: '0x',
      }),
    }
    const result = shouldSeedRocketh(spec, addressBook)
    expect(result.seed).to.be.true
    expect(result.reason).to.match(/verified/)
  })

  it('skips seed when stored hash does not match local artifact hash', () => {
    // The core bug. Without this skip, sync seeds rocketh with the local
    // artifact bytecode; rocketh then sees its own seeded bytecode == artifact
    // and reports newlyDeployed=false on the next deployFn — masking the drift
    // and stranding any proxy that depends on this impl with code-changed but
    // no pendingImplementation.
    const spec = specForSharedImpl()
    const addressBook = {
      entryExists: () => true,
      getDeploymentMetadata: () => ({
        bytecodeHash: '0xstalehashfromearlierdeployment',
        txHash: '',
        argsData: '0x',
      }),
    }
    const result = shouldSeedRocketh(spec, addressBook)
    expect(result.seed).to.be.false
    expect(result.reason).to.match(/unverified/)
  })
})
