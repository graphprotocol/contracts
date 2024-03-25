import '@nomiclabs/hardhat-ethers'
import { ethers, network } from 'hardhat'

import addresses from '../addresses.json'

import { promises as fs } from 'fs'

async function main() {
  const factory = await ethers.getContractFactory('EventfulDataEdge')

  // If we had constructor arguments, they would be passed into deploy()
  console.log(`Deploying contract...`)
  const contract = await factory.deploy()
  const tx = contract.deployTransaction

  // The address the Contract WILL have once mined
  console.log(`> deployer: ${await contract.signer.getAddress()}`)
  console.log(`> contract: ${contract.address}`)
  console.log(`> tx: ${tx.hash} nonce:${tx.nonce} limit: ${tx.gasLimit.toString()} gas: ${tx.gasPrice.toNumber() / 1e9} (gwei)`)

  // The contract is NOT deployed yet; we must wait until it is mined
  await contract.deployed()
  console.log(`Done!`)

  // Update addresses.json
  const chainId = (network.config.chainId).toString()
  if (!addresses[chainId]) {
    addresses[chainId] = {}
  }
  addresses[chainId]['EventfulDataEdge'] = contract.address
  return fs.writeFile('addresses.json', JSON.stringify(addresses, null, 2))
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
