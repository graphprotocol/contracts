/**
 * InnovationAllocation deployment assertions (GIP-0089).
 *
 * InnovationAllocation is an allocator-minted IssuanceAllocator target receiving 20%
 * of issuance. It is a transparent proxy backed by the shared DirectAllocation
 * implementation. Its IA allocation is an activation step verified by
 * `deploy --tags GIP-0089,all`, not here — this suite covers contract end-state.
 */

import { expect } from 'chai'

import { checkOperatorRole } from '../../lib/contract-checks.js'
import { checkDeployerRevoked, checkInnovationAllocationConfigured } from '../../lib/preconditions.js'
import { type DeploymentContext, getDeploymentContext, requireAddress } from './context.js'
import { transparentProxyTests } from './proxy.js'

describe('InnovationAllocation — deployment', function () {
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
    const entry = ctx.issuance.getEntry('InnovationAllocation')
    return {
      client: ctx.client,
      proxyAddress: requireAddress(ctx.issuance, 'InnovationAllocation'),
      governor: ctx.governor,
      expectedImplementation: entry?.implementation,
      expectedProxyAdmin: entry?.proxyAdmin,
    }
  })

  it('shares the DirectAllocation implementation with the other allocation proxies', function () {
    const innovation = ctx.issuance.getEntry('InnovationAllocation')?.implementation
    const shared = ctx.issuance.getEntry('DirectAllocation_Implementation')?.address
    expect(innovation?.toLowerCase()).to.equal(
      shared?.toLowerCase(),
      'InnovationAllocation is on a different DirectAllocation implementation than the shared one',
    )
  })

  it('grants GOVERNOR_ROLE, PAUSE_ROLE and OPERATOR_ROLE to the expected accounts', async function () {
    const operator = ctx.issuance.entryExists('InnovationOperator')
      ? ctx.issuance.getEntry('InnovationOperator')?.address
      : undefined
    expect(operator, 'InnovationOperator missing from the issuance address book').to.be.a('string')
    const address = requireAddress(ctx.issuance, 'InnovationAllocation')
    const result = await checkInnovationAllocationConfigured(
      ctx.client,
      address,
      ctx.governor,
      ctx.pauseGuardian,
      operator!,
    )
    expect(result.done, result.reason).to.equal(true)
  })

  it('has exactly one OPERATOR_ROLE holder', async function () {
    const operator = ctx.issuance.entryExists('InnovationOperator')
      ? (ctx.issuance.getEntry('InnovationOperator')?.address ?? null)
      : null
    const address = requireAddress(ctx.issuance, 'InnovationAllocation')
    const result = await checkOperatorRole(ctx.client, address, operator, 'InnovationOperator')
    expect(result.ok, result.message).to.equal(true)
    expect(result.count, 'an extra OPERATOR_ROLE holder can call sendTokens').to.equal(1)
  })

  it('has revoked the deployer GOVERNOR_ROLE', async function () {
    if (!ctx.deployer) {
      this.skip()
      return
    }
    const address = requireAddress(ctx.issuance, 'InnovationAllocation')
    const result = await checkDeployerRevoked(ctx.client, address, ctx.deployer)
    expect(result.done, result.reason).to.equal(true)
  })
})
