import { expect } from 'chai'

import { CONTRACT_REGISTRY } from '../lib/contract-registry.js'
import { loadArtifactFromSource } from '../lib/deploy-implementation.js'

/**
 * Every registry entry with an artifact source must load. The sync flow uses
 * tryLoadArtifactFromSource, which swallows a missing artifact, so only this
 * test fails when an entry points at an artifact that no longer exists.
 */
describe('Registry artifacts', () => {
  for (const [addressBook, contracts] of Object.entries(CONTRACT_REGISTRY)) {
    for (const [name, metadata] of Object.entries(contracts)) {
      const artifact = (metadata as { artifact?: Parameters<typeof loadArtifactFromSource>[0] }).artifact
      if (!artifact) continue

      it(`${addressBook}/${name} artifact loads with non-empty bytecode`, () => {
        const loaded = loadArtifactFromSource(artifact)
        expect(loaded.deployedBytecode, `${name} deployedBytecode`).to.be.a('string')
        expect(loaded.deployedBytecode!.length, `${name} deployedBytecode`).to.be.greaterThan(2)
      })
    }
  }
})
