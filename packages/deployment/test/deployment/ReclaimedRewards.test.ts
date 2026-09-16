/**
 * ReclaimedRewards deployment assertions.
 *
 * ReclaimedRewards receives reclaimed indexing rewards. It is a transparent
 * proxy backed by the shared DirectAllocation implementation. Being set as
 * RewardsManager.defaultReclaimAddress is a governance step bundled into the
 * upgrade batch — verified by `deploy --tags GIP-0088,all`, not here. This
 * suite asserts only the deployer-scoped end-state (proxy wiring + roles).
 */

import { expect } from 'chai'

import { checkDeployerRevoked, checkReclaimRoles } from '../../lib/preconditions.js'
import { type DeploymentContext, getDeploymentContext, requireAddress } from './context.js'
import { transparentProxyTests } from './proxy.js'

describe('ReclaimedRewards — deployment', function () {
  let ctx: DeploymentContext

  before(async function () {
    const resolved = await getDeploymentContext()
    if (!resolved) {
      this.skip()
      return
    }
    ctx = resolved
  })

  transparentProxyTests(() => {
    const entry = ctx.issuance.getEntry('ReclaimedRewards')
    return {
      client: ctx.client,
      proxyAddress: requireAddress(ctx.issuance, 'ReclaimedRewards'),
      governor: ctx.governor,
      expectedImplementation: entry?.implementation,
      expectedProxyAdmin: entry?.proxyAdmin,
    }
  })

  it('grants GOVERNOR_ROLE to the governor and PAUSE_ROLE to the pause guardian', async function () {
    const reclaim = requireAddress(ctx.issuance, 'ReclaimedRewards')
    const result = await checkReclaimRoles(ctx.client, reclaim, ctx.governor, ctx.pauseGuardian)
    expect(result.done, result.reason).to.equal(true)
  })

  it('has revoked the deployer GOVERNOR_ROLE', async function () {
    if (!ctx.deployer) {
      this.skip()
      return
    }
    const reclaim = requireAddress(ctx.issuance, 'ReclaimedRewards')
    const result = await checkDeployerRevoked(ctx.client, reclaim, ctx.deployer)
    expect(result.done, result.reason).to.equal(true)
  })
})
