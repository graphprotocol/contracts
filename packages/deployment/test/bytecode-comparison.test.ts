import { expect } from 'chai'

import { computeBytecodeHash, stripMetadata } from '../lib/bytecode-utils.js'
import { loadContractsArtifact } from '../lib/deploy-implementation.js'

/**
 * Bytecode utility tests
 *
 * These tests verify the bytecode hashing utilities used for change detection:
 * 1. stripMetadata - removes Solidity CBOR metadata suffix
 * 2. computeBytecodeHash - computes stable hash for comparison
 *
 * The approach for detecting code changes:
 * - At deployment: compute bytecodeHash of artifact and store in address book
 * - At sync/deploy: compare stored hash with current artifact hash
 * - This avoids unreliable on-chain bytecode comparison with immutable masking
 */

// =============================================================================
// TEST DATA
// =============================================================================

// Simplified bytecode samples for testing
const BASE_CODE = '608060405234801561001057600080fd5b50'

// Metadata suffix (48 bytes = 0x0030)
// Format: CBOR-encoded {ipfs: <hash>} + 2-byte length indicator
const METADATA_A = 'a264697066735822' + '1234'.repeat(20) + '0030'
const METADATA_B = 'a264697066735822' + 'abcd'.repeat(20) + '0030' // Different hash

// =============================================================================
// TESTS
// =============================================================================

describe('Bytecode Utilities', function () {
  describe('stripMetadata', function () {
    it('should strip valid metadata suffix', function () {
      const code = BASE_CODE + METADATA_A
      const stripped = stripMetadata(code)
      expect(stripped).to.equal(BASE_CODE)
    })

    it('should handle 0x prefix', function () {
      const code = '0x' + BASE_CODE + METADATA_A
      const stripped = stripMetadata(code)
      expect(stripped).to.equal('0x' + BASE_CODE)
    })

    it('should return unchanged if no valid metadata', function () {
      const code = BASE_CODE + 'ffff' // Invalid metadata length
      const stripped = stripMetadata(code)
      expect(stripped).to.equal(code)
    })

    it('should return unchanged for short bytecode', function () {
      expect(stripMetadata('0x')).to.equal('0x')
      expect(stripMetadata('')).to.equal('')
    })

    it('should handle bytecode without metadata', function () {
      const stripped = stripMetadata(BASE_CODE)
      // Without valid metadata, returns unchanged
      expect(stripped).to.equal(BASE_CODE)
    })
  })

  describe('computeBytecodeHash', function () {
    it('should compute consistent hash for same bytecode', function () {
      const code = BASE_CODE + METADATA_A
      const hash1 = computeBytecodeHash(code)
      const hash2 = computeBytecodeHash(code)
      expect(hash1).to.equal(hash2)
    })

    it('should compute same hash regardless of metadata', function () {
      // Same code, different metadata should produce same hash
      // because metadata is stripped before hashing
      const codeA = BASE_CODE + METADATA_A
      const codeB = BASE_CODE + METADATA_B
      const hashA = computeBytecodeHash(codeA)
      const hashB = computeBytecodeHash(codeB)
      expect(hashA).to.equal(hashB)
    })

    it('should compute different hash for different code', function () {
      const code1 = BASE_CODE + METADATA_A
      const code2 = BASE_CODE + '6001' + METADATA_A // Added opcode
      const hash1 = computeBytecodeHash(code1)
      const hash2 = computeBytecodeHash(code2)
      expect(hash1).to.not.equal(hash2)
    })

    it('should handle 0x prefix', function () {
      const code = '0x' + BASE_CODE + METADATA_A
      const hash = computeBytecodeHash(code)
      expect(hash).to.be.a('string')
      expect(hash).to.match(/^0x[a-f0-9]{64}$/)
    })

    it('should handle empty bytecode', function () {
      const hash = computeBytecodeHash('0x')
      expect(hash).to.be.a('string')
      expect(hash).to.match(/^0x[a-f0-9]{64}$/)
    })
  })
})

// =============================================================================
// INTEGRATION TEST WITH ACTUAL ARTIFACT
// =============================================================================

describe('Bytecode Hash with Real Artifacts', function () {
  let rewardsManagerArtifact: { deployedBytecode: string }
  let artifactLoaded = false

  before(async function () {
    try {
      const artifact = await import(
        '@graphprotocol/contracts/artifacts/contracts/rewards/RewardsManager.sol/RewardsManager.json',
        { with: { type: 'json' } }
      )
      rewardsManagerArtifact = artifact.default as { deployedBytecode: string }
      artifactLoaded = true
    } catch (e) {
      console.log('    Could not load artifact:', (e as Error).message)
    }
  })

  beforeEach(function () {
    if (!artifactLoaded) {
      this.skip()
    }
  })

  it('should correctly strip metadata from RewardsManager artifact', function () {
    const original = rewardsManagerArtifact.deployedBytecode
    const stripped = stripMetadata(original)
    // Metadata should be stripped (length should decrease)
    expect(stripped.length).to.be.lessThan(original.length)
    console.log(`    Original: ${original.length} chars, Stripped: ${stripped.length} chars`)
  })

  it('should compute consistent hash for RewardsManager', function () {
    const hash1 = computeBytecodeHash(rewardsManagerArtifact.deployedBytecode)
    const hash2 = computeBytecodeHash(rewardsManagerArtifact.deployedBytecode)
    expect(hash1).to.equal(hash2)
    console.log(`    Hash: ${hash1.slice(0, 18)}...`)
  })
})

// =============================================================================
// DEPLOY IMPLEMENTATION HELPER TESTS
// =============================================================================

describe('Deploy Implementation Helper', function () {
  describe('loadContractsArtifact', function () {
    it('should load RewardsManager artifact from @graphprotocol/contracts', function () {
      const artifact = loadContractsArtifact('rewards', 'RewardsManager')

      expect(artifact).to.have.property('abi')
      expect(artifact).to.have.property('bytecode')
      expect(artifact).to.have.property('deployedBytecode')
      expect(artifact).to.have.property('metadata')

      expect(artifact.abi).to.be.an('array')
      expect(artifact.bytecode).to.be.a('string').and.match(/^0x/)
      expect(artifact.deployedBytecode).to.be.a('string').and.match(/^0x/)

      // Verify it's a substantial contract
      expect(artifact.bytecode.length).to.be.greaterThan(1000)
      expect(artifact.deployedBytecode!.length).to.be.greaterThan(1000)
    })

    it('should throw for non-existent contract', function () {
      expect(() => loadContractsArtifact('nonexistent', 'FakeContract')).to.throw()
    })

    it('should load different contracts with correct paths', function () {
      const staking = loadContractsArtifact('staking', 'Staking')
      expect(staking.abi).to.be.an('array')
      expect(staking.bytecode).to.match(/^0x/)

      const curation = loadContractsArtifact('curation', 'Curation')
      expect(curation.abi).to.be.an('array')
      expect(curation.bytecode).to.match(/^0x/)
    })
  })
})
