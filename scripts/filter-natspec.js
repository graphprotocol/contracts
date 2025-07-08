#!/usr/bin/env node

/**
 * Filter out "return $ is missing" errors from natspec-smells output
 * This script reads the natspec-smells output and filters out complete error blocks
 * that contain "@return $ is missing" messages.
 */

const { spawn } = require('child_process')

// Run natspec-smells with the provided arguments
const args = process.argv.slice(2)
const natspecProcess = spawn('npx', ['natspec-smells', ...args], {
  stdio: ['inherit', 'pipe', 'pipe'],
})

let output = ''
let errorOutput = ''

natspecProcess.stdout.on('data', (data) => {
  output += data.toString()
})

natspecProcess.stderr.on('data', (data) => {
  errorOutput += data.toString()
})

natspecProcess.on('close', (_code) => {
  // Combine stdout and stderr
  const fullOutput = output + errorOutput

  // Check if the output is just "No issues found"
  if (fullOutput.trim() === 'No issues found') {
    console.log('No issues found')
    process.exit(0)
    return
  }

  // Split into blocks (separated by empty lines)
  const blocks = fullOutput.split(/\n\s*\n/)

  // Filter out blocks that contain "@return $ is missing"
  const filteredBlocks = blocks.filter((block) => {
    return !block.includes('@return $ is missing')
  })

  // Print filtered output
  const filteredOutput = filteredBlocks.join('\n\n').trim()
  if (filteredOutput) {
    console.log(filteredOutput)
    // Exit with error code if there are still issues (but not for "return $ is missing")
    process.exit(1)
  } else {
    // No issues after filtering
    process.exit(0)
  }
})

natspecProcess.on('error', (err) => {
  console.error('Error running natspec-smells:', err)
  process.exit(1)
})
