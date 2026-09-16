/**
 * RecurringAgreementManager deployment assertions.
 *
 * Verifies the post-deploy / post-configure / post-transfer end-state: proxy
 * wiring, role grants (governor, pause guardian, RecurringCollector as
 * COLLECTOR_ROLE, SubgraphService as DATA_SERVICE_ROLE), and the IssuanceAllocator
 * reference.
 */

import { expect } from 'chai'

import { checkDeployerRevoked, checkRAMConfigured } from '../../lib/preconditions.js'
import { type DeploymentContext, getDeploymentContext, requireAddress } from './context.js'
import { transparentProxyTests } from './proxy.js'

describe('RecurringAgreementManager — deployment', function () {
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
    const entry = ctx.issuance.getEntry('RecurringAgreementManager')
    return {
      client: ctx.client,
      proxyAddress: requireAddress(ctx.issuance, 'RecurringAgreementManager'),
      governor: ctx.governor,
      expectedImplementation: entry?.implementation,
      expectedProxyAdmin: entry?.proxyAdmin,
    }
  })

  it('grants the governor, pause, collector and data-service roles and sets the IssuanceAllocator', async function () {
    const ram = requireAddress(ctx.issuance, 'RecurringAgreementManager')
    const rc = requireAddress(ctx.horizon, 'RecurringCollector')
    const ss = requireAddress(ctx.subgraphService, 'SubgraphService')
    const ia = requireAddress(ctx.issuance, 'IssuanceAllocator')
    const result = await checkRAMConfigured(ctx.client, ram, rc, ss, ia, ctx.governor, ctx.pauseGuardian)
    expect(result.done, result.reason).to.equal(true)
  })

  it('has revoked the deployer GOVERNOR_ROLE', async function () {
    if (!ctx.deployer) {
      this.skip()
      return
    }
    const ram = requireAddress(ctx.issuance, 'RecurringAgreementManager')
    const result = await checkDeployerRevoked(ctx.client, ram, ctx.deployer)
    expect(result.done, result.reason).to.equal(true)
  })
})
