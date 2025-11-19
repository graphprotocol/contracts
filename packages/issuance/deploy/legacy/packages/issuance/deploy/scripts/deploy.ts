#!/usr/bin/env tsx

import fs from 'fs'
import hre from 'hardhat'
import JSON5 from 'json5'
import path from 'path'

// Note: Governance transactions are orchestrated in packages/deploy; this script only deploys components

interface DeploymentOptions {
  network: string
  target: string
  parameters?: string
}

// Available deployment targets for issuance contracts only
const AVAILABLE_TARGETS = [
  // Component-only targets (issuance package)
  'service-quality-oracle',
  'issuance-allocator',
  // Demo/legacy (kept temporarily)
  'basic-issuance-infrastructure',
] as const

type DeploymentTarget = (typeof AVAILABLE_TARGETS)[number]

class GovernanceIntegratedDeployer {
  private network: string
  private target: string
  private parametersPath?: string

  constructor(options: DeploymentOptions) {
    this.network = options.network
    this.target = options.target
    this.parametersPath = options.parameters

    // Validate target
    if (!AVAILABLE_TARGETS.includes(this.target as DeploymentTarget)) {
      console.error(`❌ Invalid target: ${this.target}`)
      console.error(`Available targets: ${AVAILABLE_TARGETS.join(', ')}`)
      process.exit(1)
    }
  }

  async deploy(): Promise<void> {
    console.log(`🚀 Deploying target: ${this.target} to network: ${this.network}`)

    try {
      const targetModule = await this.loadTargetModule(this.target)
      const parameters = this.parametersPath ? this.loadParameters(this.parametersPath) : undefined

      const deploymentOptions = {
        parameters,
        ...(this.network === 'hardhat' ? { confirmDeployment: true } : {}),
      }

      await hre.ignition.deploy(targetModule, deploymentOptions as never)

      console.log(`✅ Target ${this.target} deployed successfully`)
    } catch (error: unknown) {
      // Check if this is a governance-related revert
      if (this.isGovernanceRevert(error as Error)) {
        console.log('⏸️  Deployment paused - governance action required')
        await this.handleGovernanceRevert(error as Error)
        return
      }

      const errorMessage = error instanceof Error ? error.message : String(error)
      console.error(`❌ Deployment failed:`, errorMessage)
      process.exit(1)
    }
  }

  private async loadTargetModule(target: string) {
    // Convert kebab-case to PascalCase for module names
    const moduleName = target
      .split('-')
      .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
      .join('')

    console.log(`📦 Loading target module: ${moduleName}`)

    const modulePath = `../ignition/modules/targets/${moduleName}`
    try {
      const module = await import(modulePath)
      return module.default
    } catch (error) {
      console.error(`❌ Failed to load target module: ${modulePath}`)
      console.error(`   Error: ${(error as Error).message}`)
      throw error
    }
  }

  private loadParameters(parametersPath: string): unknown {
    const fullPath = path.resolve(parametersPath)
    const content = fs.readFileSync(fullPath, 'utf8')
    return JSON5.parse(content) as unknown
  }

  /**
   * Check if error is due to governance precondition failure
   * Note: Issuance contracts typically don't have governance checkpoints
   */
  private isGovernanceRevert(error: Error): boolean {
    const errorMessage = error.message.toLowerCase()

    // Issuance contract deployments should not have governance checkpoints
    // Integration governance is handled by packages/deploy orchestration
    return errorMessage.includes('governance') || errorMessage.includes('unauthorized')
  }

  /**
   * Handle governance revert by generating required transactions
   */
  private async handleGovernanceRevert(error: Error): Promise<void> {
    console.log('🔍 Analyzing governance requirements...')
    console.log(`   Error: ${error.message}`)

    try {
      console.log('This package does not generate governance transactions. Use packages/deploy for orchestration.')
    } catch (_govError) {
      // no-op
    }
  }
}

async function main() {
  const args = process.argv.slice(2)
  const network = args.find((arg) => arg.startsWith('--network='))?.split('=')[1] || 'hardhat'
  const target = args.find((arg) => arg.startsWith('--target='))?.split('=')[1]
  const parameters = args.find((arg) => arg.startsWith('--parameters='))?.split('=')[1]

  if (!target) {
    console.error('❌ Target required. Use --target=<target-name>')
    process.exit(1)
  }

  const deployer = new GovernanceIntegratedDeployer({ network, target, parameters })
  await deployer.deploy()
}

if (require.main === module) {
  main().catch(console.error)
}

export { GovernanceIntegratedDeployer }
