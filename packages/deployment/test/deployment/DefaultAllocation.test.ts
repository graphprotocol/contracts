/**
 * DefaultAllocation deployment assertions.
 *
 * DefaultAllocation is the IssuanceAllocator's default target (safety net for
 * unallocated issuance). It is a transparent proxy backed by the shared
 * DirectAllocation implementation. Being wired as the IA default target is an
 * activation step (issuance-connect), verified by `deploy --tags GIP-0088,all`,
 * not here.
 */

import { expect } from 'chai'

import { checkDefaultAllocationConfigured, checkDeployerRevoked } from '../../lib/preconditions.js'
import { type DeploymentContext, getDeploymentContext, requireAddress } from './context.js'
import { transparentProxyTests } from './proxy.js'

describe('DefaultAllocation — deployment', function () {
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
    const entry = ctx.issuance.getEntry('DefaultAllocation')
    return {
      client: ctx.client,
      proxyAddress: requireAddress(ctx.issuance, 'DefaultAllocation'),
      governor: ctx.governor,
      expectedImplementation: entry?.implementation,
      expectedProxyAdmin: entry?.proxyAdmin,
    }
  })

  it('grants GOVERNOR_ROLE to the governor and PAUSE_ROLE to the pause guardian', async function () {
    const da = requireAddress(ctx.issuance, 'DefaultAllocation')
    const result = await checkDefaultAllocationConfigured(ctx.client, da, ctx.governor, ctx.pauseGuardian)
    expect(result.done, result.reason).to.equal(true)
  })

  it('has revoked the deployer GOVERNOR_ROLE', async function () {
    if (!ctx.deployer) {
      this.skip()
      return
    }
    const da = requireAddress(ctx.issuance, 'DefaultAllocation')
    const result = await checkDeployerRevoked(ctx.client, da, ctx.deployer)
    expect(result.done, result.reason).to.equal(true)
  })
})
