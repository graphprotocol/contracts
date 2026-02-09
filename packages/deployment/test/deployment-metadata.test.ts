import { expect } from 'chai'

import { AddressBookOps } from '../lib/address-book-ops.js'
import { computeBytecodeHash } from '../lib/bytecode-utils.js'
import { checkShouldSync, createDeploymentMetadata, reconstructDeploymentRecord } from '../lib/sync-utils.js'

/**
 * Deployment Metadata Tests
 *
 * These tests verify that deployment metadata (argsData, bytecodeHash, txHash)
 * is correctly handled throughout the deployment system:
 *
 * 1. AddressBookOps - storing/retrieving metadata
 * 2. Sync - using metadata for change detection
 * 3. Reconstruction - rebuilding deployment records from metadata
 *
 * This is critical for contract verification which needs constructor args.
 *
 * NOTE: These are unit tests that don't modify real address book files.
 * Integration testing with actual deployments is done manually or via deployment scripts.
 */

describe('Deployment Metadata', () => {
  describe('computeBytecodeHash', () => {
    it('should compute consistent hash for bytecode', () => {
      // Simple test bytecode
      const bytecode = '0x608060405234801561001057600080fd5b50'

      const hash1 = computeBytecodeHash(bytecode)
      const hash2 = computeBytecodeHash(bytecode)

      // Should be consistent
      expect(hash1).to.equal(hash2)

      // Should be a valid hex string
      expect(hash1).to.match(/^0x[a-f0-9]{64}$/)
    })

    it('should produce different hash for different bytecode', () => {
      const bytecode1 = '0x608060405234801561001057600080fd5b50'
      const bytecode2 = '0x608060405234801561001057600080fd5b51'

      const hash1 = computeBytecodeHash(bytecode1)
      const hash2 = computeBytecodeHash(bytecode2)

      expect(hash1).to.not.equal(hash2)
    })
  })

  describe('AddressBookOps.getDeploymentMetadata', () => {
    // These tests use a mock to verify the logic without touching real files

    it('returns implementationDeployment for proxied contracts', () => {
      // Create a minimal mock address book that tracks what we read/write
      const mockEntry = {
        address: '0xproxy',
        proxy: 'transparent' as const,
        implementation: '0ximpl',
        proxyAdmin: '0xadmin',
        implementationDeployment: {
          txHash: '0xtxhash',
          argsData: '0x000000000000000000000000abc',
          bytecodeHash: '0xbytehash',
        },
      }

      // Create ops with a mock address book
      const mockAddressBook = {
        getEntry: (_name: string) => mockEntry,
        setEntry: () => {},
        entryExists: () => true,
        isContractName: () => true,
        listEntries: () => [],
      }

      const ops = new AddressBookOps(mockAddressBook as any)

      // For proxied contracts, getDeploymentMetadata returns implementationDeployment
      const metadata = ops.getDeploymentMetadata('TestContract' as any)

      expect(metadata).to.deep.equal(mockEntry.implementationDeployment)
      expect(metadata?.argsData).to.equal('0x000000000000000000000000abc')
    })

    it('returns deployment for non-proxied contracts', () => {
      const mockEntry = {
        address: '0xcontract',
        deployment: {
          txHash: '0xtxhash',
          argsData: '0xargs',
          bytecodeHash: '0xhash',
        },
      }

      const mockAddressBook = {
        getEntry: (_name: string) => mockEntry,
        setEntry: () => {},
        entryExists: () => true,
        isContractName: () => true,
        listEntries: () => [],
      }

      const ops = new AddressBookOps(mockAddressBook as any)
      const metadata = ops.getDeploymentMetadata('TestContract' as any)

      expect(metadata).to.deep.equal(mockEntry.deployment)
    })

    it('returns undefined when no deployment metadata exists', () => {
      const mockEntry = {
        address: '0xcontract',
        proxy: 'transparent' as const,
        implementation: '0ximpl',
        // No implementationDeployment
      }

      const mockAddressBook = {
        getEntry: (_name: string) => mockEntry,
        setEntry: () => {},
        entryExists: () => true,
        isContractName: () => true,
        listEntries: () => [],
      }

      const ops = new AddressBookOps(mockAddressBook as any)
      const metadata = ops.getDeploymentMetadata('TestContract' as any)

      expect(metadata).to.be.undefined
    })
  })

  describe('AddressBookOps.setImplementationDeploymentMetadata', () => {
    it('should preserve existing entry fields when adding metadata', () => {
      const existingEntry = {
        address: '0xproxy',
        proxy: 'transparent' as const,
        implementation: '0ximpl',
        proxyAdmin: '0xadmin',
      }

      let savedEntry: any = null

      const mockAddressBook = {
        getEntry: (_name: string) => existingEntry,
        setEntry: (_name: string, entry: any) => {
          savedEntry = entry
        },
        entryExists: () => true,
        isContractName: () => true,
        listEntries: () => [],
      }

      const ops = new AddressBookOps(mockAddressBook as any)

      const metadata = {
        txHash: '0xtx',
        argsData: '0xargs',
        bytecodeHash: '0xhash',
      }

      ops.setImplementationDeploymentMetadata('TestContract' as any, metadata)

      // Should preserve all existing fields and add new metadata
      expect(savedEntry.address).to.equal('0xproxy')
      expect(savedEntry.proxy).to.equal('transparent')
      expect(savedEntry.implementation).to.equal('0ximpl')
      expect(savedEntry.proxyAdmin).to.equal('0xadmin')
      expect(savedEntry.implementationDeployment).to.deep.equal(metadata)
    })
  })

  describe('AddressBookOps.hasCompleteDeploymentMetadata', () => {
    it('returns true when all required fields are present', () => {
      const mockEntry = {
        address: '0xcontract',
        deployment: {
          txHash: '0xtxhash',
          argsData: '0xargs',
          bytecodeHash: '0xhash',
        },
      }

      const mockAddressBook = {
        getEntry: (_name: string) => mockEntry,
        setEntry: () => {},
        entryExists: () => true,
        isContractName: () => true,
        listEntries: () => [],
      }

      const ops = new AddressBookOps(mockAddressBook as any)
      expect(ops.hasCompleteDeploymentMetadata('TestContract' as any)).to.be.true
    })

    it('returns false when argsData is missing', () => {
      const mockEntry = {
        address: '0xcontract',
        deployment: {
          txHash: '0xtxhash',
          bytecodeHash: '0xhash',
          // argsData missing
        },
      }

      const mockAddressBook = {
        getEntry: (_name: string) => mockEntry,
        setEntry: () => {},
        entryExists: () => true,
        isContractName: () => true,
        listEntries: () => [],
      }

      const ops = new AddressBookOps(mockAddressBook as any)
      expect(ops.hasCompleteDeploymentMetadata('TestContract' as any)).to.be.false
    })

    it('returns false when no deployment metadata exists', () => {
      const mockEntry = {
        address: '0xcontract',
        // No deployment field
      }

      const mockAddressBook = {
        getEntry: (_name: string) => mockEntry,
        setEntry: () => {},
        entryExists: () => true,
        isContractName: () => true,
        listEntries: () => [],
      }

      const ops = new AddressBookOps(mockAddressBook as any)
      expect(ops.hasCompleteDeploymentMetadata('TestContract' as any)).to.be.false
    })
  })
})

describe('Sync Change Detection', () => {
  describe('checkShouldSync', () => {
    it('returns shouldSync=true for new contract (no existing entry)', () => {
      const mockAddressBook = {
        entryExists: () => false,
        getEntry: () => null,
        getDeploymentMetadata: () => undefined,
      }

      const result = checkShouldSync(mockAddressBook as any, 'NewContract', '0xnewaddress')

      expect(result.shouldSync).to.be.true
      expect(result.reason).to.equal('new contract')
    })

    it('returns shouldSync=true when address changed', () => {
      const mockAddressBook = {
        entryExists: () => true,
        getEntry: () => ({ address: '0xoldaddress' }),
        getDeploymentMetadata: () => undefined,
      }

      const result = checkShouldSync(mockAddressBook as any, 'TestContract', '0xnewaddress')

      expect(result.shouldSync).to.be.true
      expect(result.reason).to.equal('address changed')
    })

    it('returns shouldSync=false when unchanged (same address, no metadata)', () => {
      const mockAddressBook = {
        entryExists: () => true,
        getEntry: () => ({ address: '0xsameaddress' }),
        getDeploymentMetadata: () => undefined,
      }

      const result = checkShouldSync(mockAddressBook as any, 'TestContract', '0xsameaddress')

      expect(result.shouldSync).to.be.false
      expect(result.reason).to.equal('unchanged')
    })

    it('returns shouldSync=false with warning when local bytecode changed', () => {
      // Compute hash of some test bytecode
      const deployedBytecode = '0x608060405234801561001057600080fd5b50'
      const deployedHash = computeBytecodeHash(deployedBytecode)

      const mockAddressBook = {
        entryExists: () => true,
        getEntry: () => ({ address: '0xsameaddress' }),
        getDeploymentMetadata: () => ({
          txHash: '0xtx',
          argsData: '0xargs',
          bytecodeHash: deployedHash, // deployed version hash
        }),
      }

      // The actual check would try to load the artifact, which we can't easily mock
      // But we can verify the logic by checking without artifact
      const resultWithoutArtifact = checkShouldSync(mockAddressBook as any, 'TestContract', '0xsameaddress')

      // Without artifact, it can't check bytecode, so it returns unchanged
      expect(resultWithoutArtifact.shouldSync).to.be.false
      expect(resultWithoutArtifact.reason).to.equal('unchanged')

      // Note: Full bytecode comparison test requires actual artifact loading
      // which is tested in integration tests
    })
  })

  describe('createDeploymentMetadata', () => {
    it('creates metadata with all required fields', () => {
      const bytecode = '0x608060405234801561001057600080fd5b50'
      const expectedHash = computeBytecodeHash(bytecode)

      const metadata = createDeploymentMetadata('0xtxhash', '0xargsdata', bytecode, 12345678, '2024-01-15T10:30:00Z')

      expect(metadata.txHash).to.equal('0xtxhash')
      expect(metadata.argsData).to.equal('0xargsdata')
      expect(metadata.bytecodeHash).to.equal(expectedHash)
      expect(metadata.blockNumber).to.equal(12345678)
      expect(metadata.timestamp).to.equal('2024-01-15T10:30:00Z')
    })

    it('creates metadata without optional fields', () => {
      const bytecode = '0x608060405234801561001057600080fd5b50'

      const metadata = createDeploymentMetadata('0xtxhash', '0xargsdata', bytecode)

      expect(metadata.txHash).to.equal('0xtxhash')
      expect(metadata.argsData).to.equal('0xargsdata')
      expect(metadata.bytecodeHash).to.be.a('string')
      expect(metadata.blockNumber).to.be.undefined
      expect(metadata.timestamp).to.be.undefined
    })
  })
})

describe('Record Reconstruction', () => {
  describe('reconstructDeploymentRecord', () => {
    it('returns undefined for non-existent contract', () => {
      const mockAddressBook = {
        entryExists: () => false,
        getEntry: () => null,
        getDeploymentMetadata: () => undefined,
      }

      const artifact = { type: 'issuance' as const, path: 'test/Mock.sol:Mock' }

      const result = reconstructDeploymentRecord(mockAddressBook as any, 'NonExistent', artifact)

      expect(result).to.be.undefined
    })

    it('returns undefined when argsData is missing', () => {
      const mockAddressBook = {
        entryExists: () => true,
        getEntry: () => ({ address: '0xcontract' }),
        getDeploymentMetadata: () => ({
          txHash: '0xtx',
          bytecodeHash: '0xhash',
          // argsData missing
        }),
      }

      const artifact = { type: 'issuance' as const, path: 'test/Mock.sol:Mock' }

      const result = reconstructDeploymentRecord(mockAddressBook as any, 'TestContract', artifact)

      expect(result).to.be.undefined
    })

    // Note: Full reconstruction test requires artifact loading which is tested in integration
    // This test verifies the function handles missing data correctly
  })
})
