import { ethers } from 'hardhat'
import hre from 'hardhat'

async function main() {
  console.log(getBanner())

  // Check that we're on a local network
  if (hre.network.name !== 'localhost' && hre.network.name !== 'hardhat') {
    throw new Error('This script can only be run on localhost or hardhat network')
  }

  console.log('\n--- STEP 0: Setup ---')

  // Get signers
  const signers = await ethers.getSigners()
  const newGovernor = signers[1]

  console.log(`New governor will be: ${newGovernor.address}`)

  // Get contracts
  const controller = hre.graph().horizon!.contracts.Controller
  const graphProxyAdmin = hre.graph().horizon!.contracts.GraphProxyAdmin
  
  // Get current owners
  const controllerGovernor = await controller.governor()
  const proxyAdminGovernor = await graphProxyAdmin.governor()
  
  console.log(`Current Controller governor: ${controllerGovernor}`)
  console.log(`Current GraphProxyAdmin governor: ${proxyAdminGovernor}`)

  // Impersonate accounts
  await ethers.provider.send('hardhat_impersonateAccount', [controllerGovernor])
  await ethers.provider.send('hardhat_impersonateAccount', [proxyAdminGovernor])
  
  try {
    const controllerSigner = await ethers.getSigner(controllerGovernor)
    const proxyAdminSigner = await ethers.getSigner(proxyAdminGovernor)

    console.log('\n--- STEP 1: Transfer ownership of Controller ---')
    
    // Transfer Controller ownership
    console.log('Transferring Controller ownership...')
    // TODO: Can we fix this?
    // @ts-ignore - TypeScript doesn't understand the compatibility here, but it works at runtime
    const controllerTx = await controller.connect(controllerSigner).transferOwnership(newGovernor.address)
    await controllerTx.wait()
    console.log('Accepting Controller ownership...')
    // TODO: Can we fix this?
    // @ts-ignore - TypeScript doesn't understand the compatibility here, but it works at runtime
    const acceptControllerTx = await controller.connect(newGovernor).acceptOwnership()
    await acceptControllerTx.wait()
    console.log(`New Controller governor: ${await controller.governor()}`)
    
    console.log('\n--- STEP 2: Transfer ownership of GraphProxyAdmin ---')

    // Transfer GraphProxyAdmin ownership
    console.log('Transferring GraphProxyAdmin ownership...')
    // TODO: Can we fix this?
    // @ts-ignore - TypeScript doesn't understand the compatibility here, but it works at runtime
    const proxyAdminTx = await graphProxyAdmin.connect(proxyAdminSigner).transferOwnership(newGovernor.address)
    await proxyAdminTx.wait()
    console.log('Accepting GraphProxyAdmin ownership...')
    // TODO: Can we fix this?
    // @ts-ignore - TypeScript doesn't understand the compatibility here, but it works at runtime
    const acceptProxyAdminTx = await graphProxyAdmin.connect(newGovernor).acceptOwnership()
    await acceptProxyAdminTx.wait()
    console.log(`New GraphProxyAdmin governor: ${await graphProxyAdmin.governor()}`)
  } finally {
    // Stop impersonating accounts
    await ethers.provider.send('hardhat_stopImpersonatingAccount', [controllerGovernor])
    await ethers.provider.send('hardhat_stopImpersonatingAccount', [proxyAdminGovernor])
  }

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