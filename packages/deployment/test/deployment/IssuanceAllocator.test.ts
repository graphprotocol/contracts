/**
 * IssuanceAllocator deployment assertions.
 *
 * Verifies the post-deploy / post-configure / post-transfer end-state. Activation
 * wiring (IA connected to RM, minter role, target allocation) is a goal-level
 * concern verified by `deploy --tags GIP-0088,all` and is not asserted here.
 */

import { expect } from 'chai'

import { checkDeployerRevoked, checkIAConfigured } from '../../lib/preconditions.js'
import { type DeploymentContext, getDeploymentContext, requireAddress } from './context.js'
import { transparentProxyTests } from './proxy.js'

describe('IssuanceAllocator — deployment', function () {
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
    const entry = ctx.issuance.getEntry('IssuanceAllocator')
    return {
      client: ctx.client,
      proxyAddress: requireAddress(ctx.issuance, 'IssuanceAllocator'),
      governor: ctx.governor,
      expectedImplementation: entry?.implementation,
      expectedProxyAdmin: entry?.proxyAdmin,
    }
  })

  it('grants GOVERNOR_ROLE / PAUSE_ROLE and matches the RM issuance rate', async function () {
    const ia = requireAddress(ctx.issuance, 'IssuanceAllocator')
    const rm = requireAddress(ctx.horizon, 'RewardsManager')
    const result = await checkIAConfigured(ctx.client, ia, rm, ctx.governor, ctx.pauseGuardian)
    expect(result.done, result.reason).to.equal(true)
  })

  it('has revoked the deployer GOVERNOR_ROLE', async function () {
    if (!ctx.deployer) {
      this.skip()
      return
    }
    const ia = requireAddress(ctx.issuance, 'IssuanceAllocator')
    const result = await checkDeployerRevoked(ctx.client, ia, ctx.deployer)
    expect(result.done, result.reason).to.equal(true)
  })
})
