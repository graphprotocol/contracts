/**
 * RewardsEligibilityOracle deployment assertions — covers both the A and B
 * instances, which deploy as independent proxies of the same contract.
 *
 * Verifies the post-deploy / post-configure / post-transfer end-state: proxy
 * wiring, role grants (governor, pause guardian, network operator) and the
 * GIP-0088 parameter defaults. Integration with RewardsManager (which REO is
 * the active oracle, eligibility validation enabled) is a goal-level activation
 * verified by `deploy --tags GIP-0088,all`, not here.
 */

import { expect } from 'chai'

import { REO_DEFAULTS } from '../../lib/contract-checks.js'
import { REWARDS_ELIGIBILITY_ORACLE_ABI } from '../../lib/generated/abis.js'
import { checkDeployerRevoked } from '../../lib/preconditions.js'
import { type DeploymentContext, getDeploymentContext, requireAddress } from './context.js'
import { transparentProxyTests } from './proxy.js'

type RoleGetter = 'GOVERNOR_ROLE' | 'PAUSE_ROLE' | 'OPERATOR_ROLE'

function describeReo(entryName: string): void {
  describe(`${entryName} — deployment`, function () {
    let ctx: DeploymentContext

    before(async function () {
      const resolved = await getDeploymentContext()
      if (!resolved) {
        this.skip()
        return
      }
      ctx = resolved
    })

    async function accountHasRole(reo: string, roleGetter: RoleGetter, account: string): Promise<boolean> {
      const role = (await ctx.client.readContract({
        address: reo as `0x${string}`,
        abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
        functionName: roleGetter,
      })) as `0x${string}`
      return (await ctx.client.readContract({
        address: reo as `0x${string}`,
        abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
        functionName: 'hasRole',
        args: [role, account as `0x${string}`],
      })) as boolean
    }

    transparentProxyTests(() => {
      const entry = ctx.issuance.getEntry(entryName)
      return {
        client: ctx.client,
        proxyAddress: requireAddress(ctx.issuance, entryName),
        governor: ctx.governor,
        expectedImplementation: entry?.implementation,
        expectedProxyAdmin: entry?.proxyAdmin,
      }
    })

    it('grants GOVERNOR_ROLE to the governor', async function () {
      const reo = requireAddress(ctx.issuance, entryName)
      expect(await accountHasRole(reo, 'GOVERNOR_ROLE', ctx.governor)).to.equal(true)
    })

    it('grants PAUSE_ROLE to the pause guardian', async function () {
      const reo = requireAddress(ctx.issuance, entryName)
      expect(await accountHasRole(reo, 'PAUSE_ROLE', ctx.pauseGuardian)).to.equal(true)
    })

    it('grants OPERATOR_ROLE to the network operator', async function () {
      const reo = requireAddress(ctx.issuance, entryName)
      const networkOperator = requireAddress(ctx.issuance, 'NetworkOperator')
      expect(await accountHasRole(reo, 'OPERATOR_ROLE', networkOperator)).to.equal(true)
    })

    it('sets eligibilityPeriod and oracleUpdateTimeout to the GIP-0088 defaults', async function () {
      const reo = requireAddress(ctx.issuance, entryName)
      const eligibilityPeriod = (await ctx.client.readContract({
        address: reo as `0x${string}`,
        abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
        functionName: 'getEligibilityPeriod',
      })) as bigint
      const oracleUpdateTimeout = (await ctx.client.readContract({
        address: reo as `0x${string}`,
        abi: REWARDS_ELIGIBILITY_ORACLE_ABI,
        functionName: 'getOracleUpdateTimeout',
      })) as bigint
      expect(eligibilityPeriod, 'eligibilityPeriod').to.equal(REO_DEFAULTS.eligibilityPeriod)
      expect(oracleUpdateTimeout, 'oracleUpdateTimeout').to.equal(REO_DEFAULTS.oracleUpdateTimeout)
    })

    it('has revoked the deployer GOVERNOR_ROLE', async function () {
      if (!ctx.deployer) {
        this.skip()
        return
      }
      const reo = requireAddress(ctx.issuance, entryName)
      const result = await checkDeployerRevoked(ctx.client, reo, ctx.deployer)
      expect(result.done, result.reason).to.equal(true)
    })
  })
}

describeReo('RewardsEligibilityOracleA')
describeReo('RewardsEligibilityOracleB')
