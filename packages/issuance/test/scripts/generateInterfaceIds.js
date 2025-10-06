#!/usr/bin/env node

/**
 * Generate interface ID constants by deploying and calling InterfaceIdExtractor contract
 */

const fs = require('fs')
const path = require('path')
const { spawn } = require('child_process')

const OUTPUT_FILE = path.join(__dirname, '../tests/helpers/interfaceIds.js')
const SILENT = process.argv.includes('--silent')

function log(...args) {
  if (!SILENT) {
    console.log(...args)
  }
}

async function runHardhatTask() {
  return new Promise((resolve, reject) => {
    const hardhatScript = `
const hre = require('hardhat')

async function main() {
  const InterfaceIdExtractor = await hre.ethers.getContractFactory('InterfaceIdExtractor')
  const extractor = await InterfaceIdExtractor.deploy()
  await extractor.waitForDeployment()
  
  const results = {
    IRewardsEligibilityOracle: await extractor.getIRewardsEligibilityOracleId(),
  }
  
  console.log(JSON.stringify(results))
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
`

    // Write temporary script
    const tempScript = path.join(__dirname, 'temp-extract.js')
    fs.writeFileSync(tempScript, hardhatScript)

    // Run the script with hardhat
    const child = spawn('npx', ['hardhat', 'run', tempScript, '--network', 'hardhat'], {
      cwd: path.join(__dirname, '../..'),
      stdio: 'pipe',
    })

    let output = ''
    let errorOutput = ''

    child.stdout.on('data', (data) => {
      output += data.toString()
    })

    child.stderr.on('data', (data) => {
      errorOutput += data.toString()
    })

    child.on('close', (code) => {
      // Clean up temp script
      try {
        fs.unlinkSync(tempScript)
      } catch {
        // Ignore cleanup errors
      }

      if (code === 0) {
        // Extract JSON from output
        const lines = output.split('\n')
        for (const line of lines) {
          try {
            const result = JSON.parse(line.trim())
            if (result && typeof result === 'object') {
              resolve(result)
              return
            }
          } catch {
            // Not JSON, continue
          }
        }
        reject(new Error('Could not parse interface IDs from output'))
      } else {
        reject(new Error(`Hardhat script failed with code ${code}: ${errorOutput}`))
      }
    })
  })
}

async function extractInterfaceIds() {
  const extractorPath = path.join(
    __dirname,
    '../../artifacts/contracts/test/InterfaceIdExtractor.sol/InterfaceIdExtractor.json',
  )

  if (!fs.existsSync(extractorPath)) {
    console.error('❌ InterfaceIdExtractor artifact not found')
    console.error('Run: pnpm compile to build the extractor contract')
    throw new Error('InterfaceIdExtractor not compiled')
  }

  log('Deploying InterfaceIdExtractor contract to extract interface IDs...')

  try {
    const results = await runHardhatTask()

    // Convert from ethers BigNumber format to hex strings
    const processed = {}
    for (const [name, value] of Object.entries(results)) {
      processed[name] = typeof value === 'string' ? value : `0x${value.toString(16).padStart(8, '0')}`
      log(`✅ Extracted ${name}: ${processed[name]}`)
    }

    return processed
  } catch (error) {
    console.error('Error extracting interface IDs:', error.message)
    throw error
  }
}

async function main() {
  log('Extracting interface IDs from Solidity compilation...')

  const results = await extractInterfaceIds()

  const content = `// Auto-generated interface IDs from Solidity compilation
module.exports = {
${Object.entries(results)
  .map(([name, id]) => `  ${name}: '${id}',`)
  .join('\n')}
}
`

  fs.writeFileSync(OUTPUT_FILE, content)
  log(`✅ Generated ${OUTPUT_FILE}`)
}

if (require.main === module) {
  main().catch(console.error)
}
