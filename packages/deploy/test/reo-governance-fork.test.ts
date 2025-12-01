import { expect } from 'chai'
import type { Signer } from 'ethers'
import { ethers, ignition, network } from 'hardhat'

import RewardsEligibilityOracleActive from '../ignition/modules/issuance/RewardsEligibilityOracleActive'
import RewardsEligibilityOracleArtifact from '../../issuance/artifacts/contracts/eligibility/RewardsEligibilityOracle.sol/RewardsEligibilityOracle.json'

// Note: This test requires contracts from @graphprotocol/issuance and @graphprotocol/horizon
// These are available through workspace dependencies and Hardhat's artifact resolution

/**
 * Fork-Based Governance Workflow Test
 *
 * This test validates the complete governance workflow for RewardsEligibilityOracle integration:
 * 1. Forks Arbitrum network at current block (mainnet or testnet)
 * 2. Deploys RewardsEligibilityOracle (from issuance package)
 * 3. Impersonates governance Safe/Controller
 * 4. Executes governance transactions to integrate REO
 * 5. Validates integration using checkpoint modules
 *
 * Network Selection:
 * - Default: Arbitrum One (mainnet) - Most realistic for governance testing
 * - Alternative: Arbitrum Sepolia - For testnet deployment validation
 *
 * Set environment variable to choose fork target:
 * - FORK_NETWORK=arbitrum-one (default) - Uses ARBITRUM_ONE_RPC
 * - FORK_NETWORK=arbitrum-sepolia - Uses ARBITRUM_SEPOLIA_RPC
 *
 * Examples:
 *   npx hardhat test test/reo-governance-fork.test.ts
 *   FORK_NETWORK=arbitrum-sepolia npx hardhat test test/reo-governance-fork.test.ts
 */

describe('REO Governance Workflow (Fork)', function () {
  // Increase timeout for fork tests
  this.timeout(120000)

  let deployer: Signer
  let governance: Signer
  let rewardsManagerAddress: string
  let graphProxyAdminAddress: string
  let controllerAddress: string
  let networkName: string

  before(async function () {
    // Check if we're on a fork or if we should skip
    const chainId = network.config.chainId
    if (chainId !== 31337) {
      this.skip()
      return
    }

    // Get test accounts
    const signers = await ethers.getSigners()
    deployer = signers[0]

    // Determine which network is being forked based on env var
    const forkNetwork = process.env.FORK_NETWORK || 'arbitrum-one'

    if (forkNetwork === 'arbitrum-sepolia') {
      // Arbitrum Sepolia (testnet) addresses
      networkName = 'Arbitrum Sepolia'
      rewardsManagerAddress = '0x1F49caE7669086c8ba53CC35d1E9f80176d67E79'
      graphProxyAdminAddress = '0x23Db5D2e68810ca71cEEe44B16B1b8396e133783'
      controllerAddress = '0x9DB3ee191681f092607035d9BDA6e59FbEaCa695'
    } else {
      // Arbitrum One (mainnet) addresses - default
      networkName = 'Arbitrum One'
      rewardsManagerAddress = '0x971B9d3d0Ae3ECa029CAB5eA1fB0F72c85e6a525'
      graphProxyAdminAddress = '0x2983936aC20202a6555993448E0d5654AC8Ca5fd'
      controllerAddress = '0x0a8491544221dd212964fbb96487467291b2C97e'
    }

    // Impersonate the Controller (governance)
    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [controllerAddress],
    })

    governance = await ethers.getSigner(controllerAddress)

    // Fund governance account for gas
    await deployer.sendTransaction({
      to: controllerAddress,
      value: ethers.parseEther('1.0'),
    })

    console.log('\n🔧 Fork Test Setup')
    console.log('='.repeat(50))
    console.log(`Fork Network: ${networkName}`)
    console.log(`Hardhat Network: ${network.name}`)
    console.log(`ChainId: ${chainId}`)
    console.log(`Deployer: ${await deployer.getAddress()}`)
    console.log(`Governance (Controller): ${controllerAddress}`)
    console.log(`RewardsManager: ${rewardsManagerAddress}`)
    console.log(`GraphProxyAdmin: ${graphProxyAdminAddress}`)
  })

  it('should detect that REO is not yet integrated (checkpoint fails)', async function () {
    // This test verifies that BEFORE governance executes, the checkpoint module fails
    // We expect this to revert because the REO hasn't been set on RewardsManager yet

    console.log('\n📋 Test 1: Verify checkpoint fails before governance')
    console.log('-'.repeat(30))

    // Deploy a mock REO for testing (in real scenario, this would be the actual deployment)
    const reoFactory = await ethers.getContractFactoryFromArtifact(RewardsEligibilityOracleArtifact)
    const graphTokenAddress = deployer.address // Use dummy address for testing
    const mockREO = await reoFactory.deploy(graphTokenAddress)
    await mockREO.waitForDeployment()
    const mockREOAddress = await mockREO.getAddress()

    console.log(`Mock REO deployed: ${mockREOAddress}`)

    try {
      // Try to run the checkpoint module - this should FAIL
      await ignition.deploy(RewardsEligibilityOracleActive, {
        parameters: {
          RewardsManagerRef: {
            address: rewardsManagerAddress,
          },
          REORef: {
            address: mockREOAddress,
          },
        },
      })

      // If we get here, the checkpoint didn't fail (unexpected)
      expect.fail('Checkpoint should have failed before governance integration')
    } catch (error: any) {
      // Expected: Checkpoint should fail because REO is not set on RewardsManager
      console.log('✅ Checkpoint correctly failed (REO not integrated)')
      expect(error.message).to.match(/revert/i)
    }
  })

  it('should execute governance transactions to integrate REO', async function () {
    console.log('\n📋 Test 2: Execute governance integration')
    console.log('-'.repeat(30))

    // Deploy REO
    const reoFactory = await ethers.getContractFactoryFromArtifact(RewardsEligibilityOracleArtifact)
    const graphTokenAddress = deployer.address // Use dummy address for testing
    const reo = await reoFactory.deploy(graphTokenAddress)
    await reo.waitForDeployment()

    console.log(`REO deployed: ${await reo.getAddress()}`)

    // Get RewardsManager contract
    const rewardsManager = await ethers.getContractAt('IRewardsManager', rewardsManagerAddress)

    // Execute governance transaction to set REO (as Controller)
    console.log('Executing setRewardsEligibilityOracle...')
    const reoAddress = await reo.getAddress()
    const tx = await rewardsManager.connect(governance).setRewardsEligibilityOracle(reoAddress)
    await tx.wait()

    console.log('✅ Governance transaction executed')

    // Verify integration
    const actualREO = await rewardsManager.rewardsEligibilityOracle()
    expect(actualREO).to.equal(reoAddress)
    console.log(`✅ REO integrated: ${actualREO}`)
  })

  it('should validate integration using checkpoint module after governance', async function () {
    console.log('\n📋 Test 3: Verify checkpoint passes after governance')
    console.log('-'.repeat(30))

    // Deploy REO
    const reoFactory = await ethers.getContractFactoryFromArtifact(RewardsEligibilityOracleArtifact)
    const graphTokenAddress = deployer.address // Use dummy address for testing
    const reo = await reoFactory.deploy(graphTokenAddress)
    await reo.waitForDeployment()

    // Integrate via governance (from previous test pattern)
    const reoAddress = await reo.getAddress()
    const rewardsManager = await ethers.getContractAt('IRewardsManager', rewardsManagerAddress)
    await rewardsManager.connect(governance).setRewardsEligibilityOracle(reoAddress)

    console.log('REO integrated via governance')

    // Now run checkpoint module - this should SUCCEED
    const result = await ignition.deploy(RewardsEligibilityOracleActive, {
      parameters: {
        RewardsManagerRef: {
          address: rewardsManagerAddress,
        },
        REORef: {
          address: reoAddress,
        },
      },
    })

    console.log('✅ Checkpoint module passed successfully')
    expect(result.rewardsManager).to.exist
    expect(result.rewardsEligibilityOracle).to.exist
  })

  it('should execute complete workflow: deploy → integrate → verify', async function () {
    console.log('\n📋 Test 4: Complete E2E Workflow')
    console.log('-'.repeat(30))

    // Step 1: Deploy REO
    console.log('Step 1: Deploy REO...')
    const reoFactory = await ethers.getContractFactoryFromArtifact(RewardsEligibilityOracleArtifact)
    const graphTokenAddress = deployer.address // Use dummy address for testing
    const reo = await reoFactory.deploy(graphTokenAddress)
    await reo.waitForDeployment()
    const reoAddress = await reo.getAddress()
    console.log(`  ✅ REO deployed: ${reoAddress}`)

    // Step 2: Generate governance transaction (in real workflow, this would create Safe TX)
    console.log('Step 2: Generate governance transaction...')
    const rewardsManager = await ethers.getContractAt('IRewardsManager', rewardsManagerAddress)
    const setREOData = rewardsManager.interface.encodeFunctionData('setRewardsEligibilityOracle', [reoAddress])
    console.log(`  ✅ TX data generated: ${setREOData.slice(0, 20)}...`)

    // Step 3: Execute governance (simulate Safe execution)
    console.log('Step 3: Execute via governance...')
    await rewardsManager.connect(governance).setRewardsEligibilityOracle(reoAddress)
    console.log('  ✅ Governance executed')

    // Step 4: Verify with checkpoint module
    console.log('Step 4: Verify integration...')
    await ignition.deploy(RewardsEligibilityOracleActive, {
      parameters: {
        RewardsManagerRef: {
          address: rewardsManagerAddress,
        },
        REORef: {
          address: reoAddress,
        },
      },
    })
    console.log('  ✅ Checkpoint verification passed')

    console.log('\n🎉 Complete workflow validated successfully!')
  })

  after(async function () {
    // Stop impersonating
    if (controllerAddress) {
      await network.provider.request({
        method: 'hardhat_stopImpersonatingAccount',
        params: [controllerAddress],
      })
    }
  })
})
