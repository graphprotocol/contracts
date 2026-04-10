import type { Environment } from '@rocketh/core/types'
import { expect } from 'chai'

import { getForkNetwork, getForkTargetChainId, getTargetChainIdFromEnv, isForkMode } from '../lib/address-book-utils.js'

describe('Chain ID Resolution', function () {
  // Store original env vars to restore after tests
  let originalHardhatFork: string | undefined
  let originalForkNetwork: string | undefined
  let originalHardhatNetwork: string | undefined

  beforeEach(function () {
    originalHardhatFork = process.env.HARDHAT_FORK
    originalForkNetwork = process.env.FORK_NETWORK
    originalHardhatNetwork = process.env.HARDHAT_NETWORK
  })

  afterEach(function () {
    // Restore original env vars
    if (originalHardhatFork === undefined) {
      delete process.env.HARDHAT_FORK
    } else {
      process.env.HARDHAT_FORK = originalHardhatFork
    }
    if (originalForkNetwork === undefined) {
      delete process.env.FORK_NETWORK
    } else {
      process.env.FORK_NETWORK = originalForkNetwork
    }
    if (originalHardhatNetwork === undefined) {
      delete process.env.HARDHAT_NETWORK
    } else {
      process.env.HARDHAT_NETWORK = originalHardhatNetwork
    }
  })

  describe('getForkTargetChainId', function () {
    it('should return null when not in fork mode', function () {
      delete process.env.HARDHAT_FORK
      delete process.env.FORK_NETWORK

      const result = getForkTargetChainId()
      expect(result).to.be.null
    })

    it('should return 421614 for arbitrumSepolia fork (HARDHAT_FORK)', function () {
      process.env.HARDHAT_FORK = 'arbitrumSepolia'
      delete process.env.FORK_NETWORK

      const result = getForkTargetChainId()
      expect(result).to.equal(421614)
    })

    it('should return 42161 for arbitrumOne fork (HARDHAT_FORK)', function () {
      process.env.HARDHAT_FORK = 'arbitrumOne'
      delete process.env.FORK_NETWORK

      const result = getForkTargetChainId()
      expect(result).to.equal(42161)
    })

    it('should return 421614 for arbitrumSepolia fork (FORK_NETWORK)', function () {
      delete process.env.HARDHAT_FORK
      process.env.FORK_NETWORK = 'arbitrumSepolia'

      const result = getForkTargetChainId()
      expect(result).to.equal(421614)
    })

    it('should return 42161 for arbitrumOne fork (FORK_NETWORK)', function () {
      delete process.env.HARDHAT_FORK
      process.env.FORK_NETWORK = 'arbitrumOne'

      const result = getForkTargetChainId()
      expect(result).to.equal(42161)
    })

    it('should prioritize HARDHAT_FORK over FORK_NETWORK', function () {
      process.env.HARDHAT_FORK = 'arbitrumOne'
      process.env.FORK_NETWORK = 'arbitrumSepolia'

      const result = getForkTargetChainId()
      expect(result).to.equal(42161) // arbitrumOne, not arbitrumSepolia
    })

    it('should throw error for unknown fork network', function () {
      process.env.FORK_NETWORK = 'unknownNetwork'

      expect(() => getForkTargetChainId()).to.throw('Unknown fork network: unknownNetwork')
    })

    it('should return null when FORK_NETWORK is set but network is a real network', function () {
      process.env.FORK_NETWORK = 'arbitrumSepolia'
      process.env.HARDHAT_NETWORK = 'arbitrumSepolia'

      const result = getForkTargetChainId()
      expect(result).to.be.null
    })

    it('should return chain ID when FORK_NETWORK is set and network is localhost', function () {
      process.env.FORK_NETWORK = 'arbitrumSepolia'
      process.env.HARDHAT_NETWORK = 'localhost'

      const result = getForkTargetChainId()
      expect(result).to.equal(421614)
    })

    it('should return chain ID when explicit networkName is localhost', function () {
      process.env.FORK_NETWORK = 'arbitrumSepolia'
      process.env.HARDHAT_NETWORK = 'arbitrumSepolia' // would normally prevent fork mode

      // Explicit networkName overrides HARDHAT_NETWORK
      const result = getForkTargetChainId('localhost')
      expect(result).to.equal(421614)
    })

    it('should return null when explicit networkName is a real network', function () {
      process.env.FORK_NETWORK = 'arbitrumSepolia'
      delete process.env.HARDHAT_NETWORK

      const result = getForkTargetChainId('arbitrumSepolia')
      expect(result).to.be.null
    })
  })

  describe('isForkMode (network-aware)', function () {
    it('should return false when no fork env vars are set', function () {
      delete process.env.HARDHAT_FORK
      delete process.env.FORK_NETWORK

      expect(isForkMode()).to.be.false
    })

    it('should return true when FORK_NETWORK is set and HARDHAT_NETWORK is localhost', function () {
      process.env.FORK_NETWORK = 'arbitrumSepolia'
      process.env.HARDHAT_NETWORK = 'localhost'

      expect(isForkMode()).to.be.true
    })

    it('should return true when FORK_NETWORK is set and HARDHAT_NETWORK is fork', function () {
      process.env.FORK_NETWORK = 'arbitrumSepolia'
      process.env.HARDHAT_NETWORK = 'fork'

      expect(isForkMode()).to.be.true
    })

    it('should return false when FORK_NETWORK is set but HARDHAT_NETWORK is a real network', function () {
      process.env.FORK_NETWORK = 'arbitrumSepolia'
      process.env.HARDHAT_NETWORK = 'arbitrumSepolia'

      expect(isForkMode()).to.be.false
    })

    it('should return false when FORK_NETWORK is set but HARDHAT_NETWORK is arbitrumOne', function () {
      process.env.FORK_NETWORK = 'arbitrumSepolia'
      process.env.HARDHAT_NETWORK = 'arbitrumOne'

      expect(isForkMode()).to.be.false
    })

    it('should use explicit networkName over HARDHAT_NETWORK', function () {
      process.env.FORK_NETWORK = 'arbitrumSepolia'
      process.env.HARDHAT_NETWORK = 'arbitrumSepolia' // real network

      // Explicit networkName says localhost - should be fork mode
      expect(isForkMode('localhost')).to.be.true
    })

    it('should return false with explicit real networkName even if HARDHAT_NETWORK is local', function () {
      process.env.FORK_NETWORK = 'arbitrumSepolia'
      process.env.HARDHAT_NETWORK = 'localhost'

      // Explicit networkName says real network - should not be fork mode
      expect(isForkMode('arbitrumSepolia')).to.be.false
    })

    it('should return true when FORK_NETWORK is set and no network context available', function () {
      process.env.FORK_NETWORK = 'arbitrumSepolia'
      delete process.env.HARDHAT_NETWORK

      // No context - preserves existing behavior (trusts env var)
      expect(isForkMode()).to.be.true
    })
  })

  describe('getForkNetwork (network-aware)', function () {
    it('should return null on real networks even if FORK_NETWORK is set', function () {
      process.env.FORK_NETWORK = 'arbitrumSepolia'
      process.env.HARDHAT_NETWORK = 'arbitrumSepolia'

      expect(getForkNetwork()).to.be.null
    })

    it('should return fork network name on localhost', function () {
      process.env.FORK_NETWORK = 'arbitrumSepolia'
      process.env.HARDHAT_NETWORK = 'localhost'

      expect(getForkNetwork()).to.equal('arbitrumSepolia')
    })
  })

  describe('getTargetChainIdFromEnv', function () {
    it('should return fork chain ID when in fork mode', async function () {
      process.env.FORK_NETWORK = 'arbitrumOne'

      // Mock environment - provider won't be called in fork mode
      const mockEnv = {
        name: 'localhost',
        network: {
          provider: {
            request: () => {
              throw new Error('Provider should not be called in fork mode')
            },
          },
        },
      } as unknown as Environment

      const result = await getTargetChainIdFromEnv(mockEnv)
      expect(result).to.equal(42161)
    })

    it('should return provider chain ID when not in fork mode', async function () {
      delete process.env.HARDHAT_FORK
      delete process.env.FORK_NETWORK

      // Mock environment with provider returning 421614
      const mockEnv = {
        name: 'arbitrumSepolia',
        network: {
          provider: {
            request: async ({ method }: { method: string }) => {
              if (method === 'eth_chainId') {
                return '0x66eee' // 421614 in hex
              }
              throw new Error(`Unexpected method: ${method}`)
            },
          },
        },
      } as unknown as Environment

      const result = await getTargetChainIdFromEnv(mockEnv)
      expect(result).to.equal(421614)
    })

    it('should handle different provider chain IDs correctly', async function () {
      delete process.env.HARDHAT_FORK
      delete process.env.FORK_NETWORK

      // Test Arbitrum One (42161 = 0xA4B1)
      const mockEnvArb = {
        name: 'arbitrumOne',
        network: {
          provider: {
            request: async () => '0xa4b1', // 42161 in hex
          },
        },
      } as unknown as Environment

      const resultArb = await getTargetChainIdFromEnv(mockEnvArb)
      expect(resultArb).to.equal(42161)

      // Test Ethereum mainnet (1 = 0x1)
      const mockEnvMainnet = {
        name: 'mainnet',
        network: {
          provider: {
            request: async () => '0x1', // 1 in hex
          },
        },
      } as unknown as Environment

      const resultMainnet = await getTargetChainIdFromEnv(mockEnvMainnet)
      expect(resultMainnet).to.equal(1)
    })

    it('should prefer fork chain ID over provider chain ID when forking', async function () {
      process.env.FORK_NETWORK = 'arbitrumOne' // Chain ID 42161

      // Mock provider returning 31337 (local hardhat node)
      const mockEnv = {
        name: 'localhost',
        network: {
          provider: {
            request: async () => '0x7a69', // 31337 in hex
          },
        },
      } as unknown as Environment

      const result = await getTargetChainIdFromEnv(mockEnv)
      // Should return fork target (42161), not provider chain ID (31337)
      expect(result).to.equal(42161)
    })

    it('should return provider chain ID on real network even if FORK_NETWORK is set', async function () {
      process.env.FORK_NETWORK = 'arbitrumSepolia'

      // Running on arbitrumOne - FORK_NETWORK should be ignored
      const mockEnv = {
        name: 'arbitrumOne',
        network: {
          provider: {
            request: async () => '0xa4b1', // 42161 in hex
          },
        },
      } as unknown as Environment

      const result = await getTargetChainIdFromEnv(mockEnv)
      // Should return provider chain ID (42161), not fork target (421614)
      expect(result).to.equal(42161)
    })
  })

  describe('Integration: Fork mode detection', function () {
    it('should correctly identify fork mode vs non-fork mode', async function () {
      // Test 1: Non-fork mode
      delete process.env.HARDHAT_FORK
      delete process.env.FORK_NETWORK

      const mockEnvNonFork = {
        name: 'arbitrumSepolia',
        network: {
          provider: {
            request: async () => '0x66eee', // 421614
          },
        },
      } as unknown as Environment

      const nonForkChainId = await getTargetChainIdFromEnv(mockEnvNonFork)
      const forkChainId1 = getForkTargetChainId('arbitrumSepolia')

      expect(forkChainId1).to.be.null
      expect(nonForkChainId).to.equal(421614)

      // Test 2: Fork mode
      process.env.FORK_NETWORK = 'arbitrumSepolia'

      const mockEnvFork = {
        name: 'localhost',
        network: {
          provider: {
            request: async () => '0x7a69', // 31337 (local node)
          },
        },
      } as unknown as Environment

      const forkModeChainId = await getTargetChainIdFromEnv(mockEnvFork)
      const forkChainId2 = getForkTargetChainId('localhost')

      expect(forkChainId2).to.equal(421614)
      expect(forkModeChainId).to.equal(421614) // Fork target, not 31337
    })
  })
})
