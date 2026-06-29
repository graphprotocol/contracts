import { expect } from 'chai'

import {
  ELIGIBILITY_ORACLE_CONTRACTS,
  eligibilityOracleContract,
  type EligibilityOracleContractName,
} from '../lib/contract-registry.js'
import { getResolvedSettings } from '../lib/deployment-config.js'

/**
 * Eligibility-oracle config resolution
 *
 * Which REO contract RM / RAM point at is driven by config, by full contract
 * name, with omission meaning "no oracle" (no hidden default). These tests pin
 * the resolver and the omit=none semantics — deliberately NOT the per-network
 * oracle choices, which are operator decisions that may change.
 */
describe('Eligibility oracle config', () => {
  describe('eligibilityOracleContract', () => {
    const names: EligibilityOracleContractName[] = [
      'RewardsEligibilityOracleA',
      'RewardsEligibilityOracleB',
      'RewardsEligibilityOracleMock',
    ]
    for (const name of names) {
      it(`resolves ${name} to its issuance registry entry`, () => {
        const entry = eligibilityOracleContract(name)
        expect(entry.name).to.equal(name)
        expect(entry.addressBook).to.equal('issuance')
      })
    }

    it('lists the currently-deployable oracle contracts', () => {
      expect([...ELIGIBILITY_ORACLE_CONTRACTS]).to.deep.equal([
        'RewardsEligibilityOracleA',
        'RewardsEligibilityOracleB',
        'RewardsEligibilityOracleMock',
      ])
    })
  })

  describe('getResolvedSettings — omit = none (no hidden default)', () => {
    it('leaves RM and RAM oracles undefined for an unknown chain (nothing configured)', () => {
      const s = getResolvedSettings(999999)
      expect(s.rewardsManager.eligibilityOracle).to.equal(undefined)
      expect(s.recurringAgreementManager.eligibilityOracle).to.equal(undefined)
    })

    // For the real committed configs: a configured oracle must be a valid
    // contract name, and an omitted one must resolve to undefined (no default).
    // We assert validity, not which oracle — that is the operator's choice.
    for (const chainId of [42161, 421614, 1337]) {
      it(`resolves only valid (or no) oracles for chain ${chainId}`, () => {
        const s = getResolvedSettings(chainId)
        for (const oracle of [s.rewardsManager.eligibilityOracle, s.recurringAgreementManager.eligibilityOracle]) {
          if (oracle !== undefined) {
            expect(ELIGIBILITY_ORACLE_CONTRACTS as readonly string[]).to.include(oracle)
          }
        }
      })
    }
  })
})
