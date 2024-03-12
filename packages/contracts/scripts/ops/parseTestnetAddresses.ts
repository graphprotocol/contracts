#!ts-node

// Accepts a CSV file: field1 name, field2 Ethereum address
// Validates the address is valid, trims and exit on error
// Outputs a json in the format used by the distribution script

import fs from 'fs'
import { utils } from 'ethers'

const { getAddress } = utils

interface TeamMember {
  name: string
  address: string
}

export const teamAddresses: Array<TeamMember> = []

function main() {
  const data = fs.readFileSync('indexers.csv', 'utf8')
  const entries = data.split('\n').map(e => e.trim())
  for (const entry of entries) {
    if (!entry) continue

    const [name, address] = entry.split(',').map(e => e.trim())

    // Verify address
    try {
      getAddress(address.trim())
    } catch (_) {
      console.log('Invalid', name, address)
      process.exit(1)
    }

    // Add to member list
    const member = {
      name,
      address,
    }
    teamAddresses.push(member)
  }

  // Out
  console.log(JSON.stringify(teamAddresses))
}

main()
