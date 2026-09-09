import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { createStatusModule } from '@graphprotocol/deployment/lib/script-factories.js'

/**
 * DefaultAllocation status — show detailed state of the default allocation proxy
 *
 * Usage:
 *   pnpm hardhat deploy --tags DefaultAllocation --network <network>
 */
export default createStatusModule(Contracts.issuance.DefaultAllocation)
