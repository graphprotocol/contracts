import { SpecialTags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { runFullSync } from '@graphprotocol/deployment/lib/sync-utils.js'
import type { DeployScriptModule } from '@rocketh/core/types'

// Sync — full reconciliation between on-chain state and address books.
//
// For every deployable contract in every address book (Horizon, SubgraphService,
// Issuance):
// - Reconcile proxy implementations with on-chain state
// - Import contract addresses into rocketh deployment records
// - Validate prerequisites exist on-chain
//
// This script is the only one tagged with `SpecialTags.SYNC`. It runs when:
// - The user invokes `npx hardhat deploy --tags sync` directly
// - The `deploy:sync` Hardhat task is run (which delegates to the above)
//
// Per-component actions sync the contracts they touch immediately before and
// after their work, so this full sync is no longer required as an automatic
// dependency on every deployment script.

const func: DeployScriptModule = async (env) => {
  await runFullSync(env)
}

func.tags = [SpecialTags.SYNC]
export default func
