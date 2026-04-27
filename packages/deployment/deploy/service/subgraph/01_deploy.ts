import { linkArtifactLibraries } from '@graphprotocol/deployment/lib/artifact-loaders.js'
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import {
  deployImplementation,
  getImplementationConfig,
  loadArtifactFromSource,
} from '@graphprotocol/deployment/lib/deploy-implementation.js'
import { ComponentTags, DeploymentActions, shouldSkipAction } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { syncComponentsFromRegistry } from '@graphprotocol/deployment/lib/sync-utils.js'
import { deploy } from '@graphprotocol/deployment/rocketh/deploy.js'
import type { DeployScriptModule } from '@rocketh/core/types'

// SubgraphService Implementation Deployment
//
// SubgraphService uses external Solidity libraries that must be deployed first
// and linked into the implementation bytecode before deployment.
//
// Library dependency order:
// 1. StakeClaims           (standalone, from horizon)
// 2. AllocationHandler     (standalone)
// 3. IndexingAgreementDecoderRaw (standalone)
// 4. IndexingAgreementDecoder    (links IndexingAgreementDecoderRaw)
// 5. IndexingAgreement           (links IndexingAgreementDecoder)
// 6. SubgraphService             (links all above)
//
// Workflow:
// 1. Deploy libraries in dependency order
// 2. Deploy SS implementation with linked libraries
// 3. Store as "pendingImplementation" in subgraph-service/addresses.json
// 4. Upgrade task (separate) handles TX generation and execution

const func: DeployScriptModule = async (env) => {
  if (shouldSkipAction(DeploymentActions.DEPLOY)) return
  await syncComponentsFromRegistry(env, [
    Contracts.horizon.Controller,
    Contracts['subgraph-service'].DisputeManager,
    Contracts.horizon.GraphTallyCollector,
    Contracts.horizon.L2Curation,
    Contracts.horizon.RecurringCollector,
    Contracts['subgraph-service'].SubgraphService,
  ])

  // Get constructor args from imported deployments
  const controllerDep = env.getOrNull('Controller')
  const disputeManagerDep = env.getOrNull('DisputeManager')
  const graphTallyCollectorDep = env.getOrNull('GraphTallyCollector')
  const curationDep = env.getOrNull('L2Curation')
  const recurringCollectorDep = env.getOrNull('RecurringCollector')

  if (!controllerDep || !disputeManagerDep || !graphTallyCollectorDep || !curationDep || !recurringCollectorDep) {
    throw new Error(
      'Missing required contract deployments after sync ' +
        '(Controller, DisputeManager, GraphTallyCollector, L2Curation, RecurringCollector).',
    )
  }

  // Deploy libraries in dependency order
  const deployFn = deploy(env)
  const deployer = env.namedAccounts.deployer
  if (!deployer) throw new Error('No deployer account configured')

  env.showMessage('\n📚 Deploying SubgraphService libraries...')

  // 1. StakeClaims (from horizon, standalone)
  const stakeClaimsArtifact = loadArtifactFromSource({
    type: 'horizon',
    path: 'contracts/data-service/libraries/StakeClaims.sol/StakeClaims',
  })
  const stakeClaims = await deployFn('StakeClaims', {
    account: deployer,
    artifact: stakeClaimsArtifact,
    args: [],
  })
  env.showMessage(`   StakeClaims: ${stakeClaims.address}`)

  // 2. AllocationHandler (standalone)
  const allocationHandlerArtifact = loadArtifactFromSource({
    type: 'subgraph-service',
    name: 'libraries/AllocationHandler',
  })
  const allocationHandler = await deployFn('AllocationHandler', {
    account: deployer,
    artifact: allocationHandlerArtifact,
    args: [],
  })
  env.showMessage(`   AllocationHandler: ${allocationHandler.address}`)

  // 3. IndexingAgreementDecoderRaw (standalone)
  const decoderRawArtifact = loadArtifactFromSource({
    type: 'subgraph-service',
    name: 'libraries/IndexingAgreementDecoderRaw',
  })
  const decoderRaw = await deployFn('IndexingAgreementDecoderRaw', {
    account: deployer,
    artifact: decoderRawArtifact,
    args: [],
  })
  env.showMessage(`   IndexingAgreementDecoderRaw: ${decoderRaw.address}`)

  // 4. IndexingAgreementDecoder (links IndexingAgreementDecoderRaw)
  // Pre-link libraries into artifact so rocketh stores linked bytecode
  // (rocketh's bytecode comparison breaks for unlinked artifacts — see linkArtifactLibraries)
  const decoderArtifact = linkArtifactLibraries(
    loadArtifactFromSource({ type: 'subgraph-service', name: 'libraries/IndexingAgreementDecoder' }),
    { IndexingAgreementDecoderRaw: decoderRaw.address as `0x${string}` },
  )
  const decoder = await deployFn('IndexingAgreementDecoder', { account: deployer, artifact: decoderArtifact, args: [] })
  env.showMessage(`   IndexingAgreementDecoder: ${decoder.address}`)

  // 5. IndexingAgreement (links IndexingAgreementDecoder)
  const indexingAgreementArtifact = linkArtifactLibraries(
    loadArtifactFromSource({ type: 'subgraph-service', name: 'libraries/IndexingAgreement' }),
    { IndexingAgreementDecoder: decoder.address as `0x${string}` },
  )
  const indexingAgreement = await deployFn('IndexingAgreement', {
    account: deployer,
    artifact: indexingAgreementArtifact,
    args: [],
  })
  env.showMessage(`   IndexingAgreement: ${indexingAgreement.address}`)

  env.showMessage('   ✓ Libraries deployed\n')

  // 6. Deploy SubgraphService implementation with all libraries linked
  const config = getImplementationConfig('subgraph-service', 'SubgraphService', {
    constructorArgs: [
      controllerDep.address,
      disputeManagerDep.address,
      graphTallyCollectorDep.address,
      curationDep.address,
      recurringCollectorDep.address,
    ],
  })

  await deployImplementation(env, config, {
    StakeClaims: stakeClaims.address,
    AllocationHandler: allocationHandler.address,
    IndexingAgreement: indexingAgreement.address,
    IndexingAgreementDecoder: decoder.address,
  })
}

func.tags = [ComponentTags.SUBGRAPH_SERVICE]
func.dependencies = [ComponentTags.RECURRING_COLLECTOR]
func.skip = async () => shouldSkipAction(DeploymentActions.DEPLOY)
export default func
