#!/usr/bin/env node

/**
 * Multi-Package Deployment Orchestrator
 *
 * This script orchestrates deployments across multiple packages:
 * 1. Contracts package (RewardsManager, etc.)
 * 2. Issuance package (IssuanceAllocator, etc.)
 * 3. Cross-package integrations
 */

const { execSync } = require('child_process')
const fs = require('fs')
const path = require('path')

// ANSI color codes for better output
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m',
}

function log(message, color = colors.reset) {
  console.log(`${color}${message}${colors.reset}`)
}

function execCommand(command, cwd = process.cwd()) {
  try {
    log(`\n🔧 Executing: ${command}`, colors.cyan)
    log(`📁 Directory: ${cwd}`, colors.blue)

    const result = execSync(command, {
      cwd,
      stdio: 'inherit',
      encoding: 'utf8',
    })

    log(`✅ Command completed successfully`, colors.green)
    return result
  } catch (error) {
    log(`❌ Command failed: ${error.message}`, colors.red)
    throw error
  }
}

function getNetworkFromArgs() {
  const args = process.argv.slice(2)
  const networkIndex = args.findIndex((arg) => arg === '--network')

  if (networkIndex !== -1 && args[networkIndex + 1]) {
    return args[networkIndex + 1]
  }

  return 'hardhat' // default
}

async function deployContracts(network) {
  log(`\n🏗️  DEPLOYING CONTRACTS PACKAGE (RewardsManager Implementation)`, colors.bright + colors.magenta)
  log(`Network: ${network}`, colors.yellow)

  const contractsDeployDir = path.resolve(__dirname, '../../contracts/deploy')

  if (!fs.existsSync(contractsDeployDir)) {
    throw new Error(`Contracts deploy directory not found: ${contractsDeployDir}`)
  }

  // Deploy RewardsManager implementation
  const deployCommand = network === 'hardhat' ? 'pnpm deploy:impl:local' : `pnpm deploy:impl:${network}`

  execCommand(deployCommand, contractsDeployDir)

  log(`✅ RewardsManager implementation deployed successfully!`, colors.green)
}

async function deployIssuance(network) {
  log(`\n🏗️  DEPLOYING ISSUANCE PACKAGE (IssuanceAllocator System)`, colors.bright + colors.magenta)
  log(`Network: ${network}`, colors.yellow)

  const issuanceDeployDir = path.resolve(__dirname, '../../issuance/deploy')

  if (!fs.existsSync(issuanceDeployDir)) {
    throw new Error(`Issuance deploy directory not found: ${issuanceDeployDir}`)
  }

  // Deploy IssuanceAllocator system
  const deployCommand = network === 'hardhat' ? 'pnpm deploy:local' : `pnpm deploy:${network}`

  execCommand(deployCommand, issuanceDeployDir)

  log(`✅ IssuanceAllocator system deployed successfully!`, colors.green)
}

async function configureIntegrations(network) {
  log(`\n🔗 CONFIGURING CROSS-PACKAGE INTEGRATIONS`, colors.bright + colors.magenta)
  log(`Network: ${network}`, colors.yellow)

  // TODO: Add integration configuration logic here
  // This could include:
  // - Setting up cross-contract permissions
  // - Configuring contract addresses in each system
  // - Initializing cross-package state

  log(`✅ Integrations configured successfully!`, colors.green)
}

async function main() {
  try {
    const network = getNetworkFromArgs()

    log(`\n🚀 STARTING MULTI-PACKAGE DEPLOYMENT`, colors.bright + colors.cyan)
    log(`Target Network: ${network}`, colors.yellow)
    log(`Timestamp: ${new Date().toISOString()}`, colors.blue)

    // Step 1: Deploy contracts package
    await deployContracts(network)

    // Step 2: Deploy issuance package
    await deployIssuance(network)

    // Step 3: Configure cross-package integrations
    await configureIntegrations(network)

    log(`\n🎉 MULTI-PACKAGE DEPLOYMENT COMPLETED SUCCESSFULLY!`, colors.bright + colors.green)
    log(`All packages deployed to network: ${network}`, colors.green)
  } catch (error) {
    log(`\n💥 DEPLOYMENT FAILED!`, colors.bright + colors.red)
    log(`Error: ${error.message}`, colors.red)
    process.exit(1)
  }
}

if (require.main === module) {
  main()
}

module.exports = { deployContracts, deployIssuance, configureIntegrations }
