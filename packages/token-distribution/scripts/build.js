#!/usr/bin/env node

/**
 * Efficient build script for token-distribution
 *
 * This script:
 * 1. Checks if GraphClient source files are newer than target files
 * 2. Only runs GraphClient build if needed
 * 3. Checks if contract source files are newer than compiled artifacts
 * 4. Only runs contract compilation if needed
 * 5. Provides succinct output when no work is needed
 */

const { execSync } = require('child_process')
const fs = require('fs')
const { readdir } = require('fs/promises')
const path = require('path')

// Get the directory name
const rootDir = path.resolve(__dirname, '..')

// GraphClient paths
const graphClientDir = path.join(rootDir, '.graphclient')
const graphClientSrcDir = path.join(rootDir, 'graphclient')
const graphClientSchema = path.join(graphClientDir, 'schema.graphql')
const graphClientIndex = path.join(graphClientDir, 'index.js')

// Contract paths
const contractsDir = path.join(rootDir, 'contracts')
const artifactsDir = path.join(rootDir, 'artifacts')

// Check if a file exists
function fileExists(filePath) {
  try {
    return fs.statSync(filePath).isFile()
  } catch {
    return false
  }
}

// Get file modification time
function getModTime(filePath) {
  try {
    return fs.statSync(filePath).mtimeMs
  } catch {
    return 0
  }
}

// Get all files in a directory recursively
async function getAllFiles(dir, fileList = []) {
  try {
    if (!fs.existsSync(dir)) {
      return fileList
    }

    const files = await readdir(dir, { withFileTypes: true })

    for (const file of files) {
      const filePath = path.join(dir, file.name)

      if (file.isDirectory()) {
        // Recursively get files from subdirectories
        await getAllFiles(filePath, fileList)
      } else {
        // Add file to the list
        fileList.push(filePath)
      }
    }

    return fileList
  } catch {
    return fileList
  }
}

// Get directory modification time (latest file in directory)
async function getDirModTime(dirPath) {
  try {
    if (!fs.existsSync(dirPath)) {
      return 0
    }

    const files = await getAllFiles(dirPath)
    if (files.length === 0) {
      return 0
    }

    const fileTimes = files.map((file) => getModTime(file))
    return Math.max(...fileTimes)
  } catch {
    return 0
  }
}

// Check if GraphClient build is needed
async function needsGraphClientBuild() {
  // If GraphClient output doesn't exist, build is needed
  if (!fileExists(graphClientSchema) || !fileExists(graphClientIndex)) {
    return true
  }

  // Check if any GraphClient source file is newer than the output
  const graphClientSrcTime = await getDirModTime(graphClientSrcDir)
  const graphClientOutputTime = Math.min(getModTime(graphClientSchema), getModTime(graphClientIndex))

  return graphClientSrcTime > graphClientOutputTime
}

// Check if contract compilation is needed
async function needsContractCompilation() {
  // If artifacts directory doesn't exist, compilation is needed
  if (!fs.existsSync(artifactsDir)) {
    return true
  }

  // Check if any contract source file is newer than the artifacts
  const contractsSrcTime = await getDirModTime(contractsDir)
  const artifactsTime = await getDirModTime(artifactsDir)

  return contractsSrcTime > artifactsTime
}

// Main build function
async function build() {
  const graphClientBuildNeeded = await needsGraphClientBuild()
  const contractCompilationNeeded = await needsContractCompilation()

  // If no build is needed, exit early
  if (!graphClientBuildNeeded && !contractCompilationNeeded) {
    console.log('All build targets are up to date.')
    return
  }

  // Build GraphClient if needed
  if (graphClientBuildNeeded) {
    console.log('Building GraphClient...')
    execSync('pnpm graphclient build --fileType json', { stdio: 'inherit' })
  } else {
    console.log('GraphClient is up to date.')
  }

  // Compile contracts if needed
  if (contractCompilationNeeded) {
    console.log('Compiling contracts...')

    // // Copy working TypeChain modules from contracts package to fix compatibility
    // console.log('Copying TypeChain modules from contracts package...')
    // execSync('cp -r ../contracts/node_modules/@typechain ../contracts/node_modules/typechain ./node_modules/', {
    //   stdio: 'inherit',
    // })

    execSync('pnpm run compile', { stdio: 'inherit' })
  } else {
    console.log('Contracts are up to date.')
  }

  console.log('Build completed successfully.')
}

// Run the build
build().catch((error) => {
  console.error('Build failed:', error)
  process.exit(1)
})

// Export the build function for testing
module.exports = { build }
