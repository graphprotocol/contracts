import { Contract } from 'ethers'
import { ethers } from 'hardhat'
import hre from 'hardhat'

import { IStaking } from '@graphprotocol/contracts'
import L2StakingABI from '@graphprotocol/contracts/build/abis/L2Staking.json'
import { mergeABIs } from 'hardhat-graph-protocol/sdk'
import StakingExtensionABI from '@graphprotocol/contracts/build/abis/StakingExtension.json'

async function main() {
  console.log(getBanner())

  // Check that we're on a local network
  if (hre.network.name !== 'localhost' && hre.network.name !== 'hardhat') {
    throw new Error('This script can only be run on localhost or hardhat network')
  }

  console.log('\n--- STEP 0: Setup ---')

  // Get signers
  const signers = await ethers.getSigners()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const newGovernor = signers[1] as any
  const newSlasher = signers[2]

  console.log(`New governor will be: ${newGovernor.address}`)

  // Get contract addresses
  const addressesJson = require('@graphprotocol/contracts/addresses.json')
  const arbSepoliaAddresses = addressesJson['421614']
  const stakingAddress = arbSepoliaAddresses.L2Staking.address

  // Get ABIs
  const combinedStakingABI = mergeABIs(L2StakingABI, StakingExtensionABI)

  // Get contracts
  const staking = new Contract(stakingAddress, combinedStakingABI, ethers.provider) as unknown as IStaking
  const controller = hre.graph().horizon!.contracts.Controller
  const graphProxyAdmin = hre.graph().horizon!.contracts.GraphProxyAdmin

  // Get current owners
  const controllerGovernor = await controller.governor()
  const proxyAdminGovernor = await graphProxyAdmin.governor()

  console.log(`Current Controller governor: ${controllerGovernor}`)
  console.log(`Current GraphProxyAdmin governor: ${proxyAdminGovernor}`)

  // Get impersonated signers
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const controllerSigner = await ethers.getImpersonatedSigner(controllerGovernor) as any
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const proxyAdminSigner = await ethers.getImpersonatedSigner(proxyAdminGovernor) as any

  console.log('\n--- STEP 1: Transfer ownership of Controller ---')

  // Transfer Controller ownership
  console.log('Transferring Controller ownership...')
  const controllerTx = await controller.connect(controllerSigner).transferOwnership(newGovernor.address)
  await controllerTx.wait()
  console.log('Accepting Controller ownership...')

  // Accept ownership of Controller
  const acceptControllerTx = await controller.connect(newGovernor).acceptOwnership()
  await acceptControllerTx.wait()
  console.log(`New Controller governor: ${await controller.governor()}`)

  console.log('\n--- STEP 2: Transfer ownership of GraphProxyAdmin ---')

  // Transfer GraphProxyAdmin ownership
  console.log('Transferring GraphProxyAdmin ownership...')
  const proxyAdminTx = await graphProxyAdmin.connect(proxyAdminSigner).transferOwnership(newGovernor.address)
  await proxyAdminTx.wait()
  console.log('Accepting GraphProxyAdmin ownership...')

  // Accept ownership of GraphProxyAdmin
  const acceptProxyAdminTx = await graphProxyAdmin.connect(newGovernor).acceptOwnership()
  await acceptProxyAdminTx.wait()
  console.log(`New GraphProxyAdmin governor: ${await graphProxyAdmin.governor()}`)

  console.log('\n--- STEP 3: Assign new slasher ---')

  // Assign new slasher
  console.log('Assigning new slasher...')
  const slasherTx = await staking.connect(newGovernor).setSlasher(newSlasher.address, true)
  await slasherTx.wait()
  console.log(`New slasher: ${newSlasher.address}, allowed: ${await staking.slashers(newSlasher.address)}`)

  console.log('\n\n🎉 ✨ 🚀 ✅ Transfer ownership complete! 🎉 ✨ 🚀 ✅\n')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

function getBanner() {
  return `
  +-----------------------------------------------+
  |                                               |
  |         TRANSFER OWNERSHIP SCRIPT             |
  |                                               |
  +-----------------------------------------------+
  `
}
