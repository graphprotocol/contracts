import { task, types } from 'hardhat/config'
import { printBanner } from '@graphprotocol/toolshed/utils'
import { requireLocalNetwork } from '@graphprotocol/toolshed/hardhat'

// This is required because we cannot impersonate Ignition accounts
// so we impersonate current governor and transfer ownership to accounts that Ignition can control
task('test:transfer-ownership', 'Transfer ownership of protocol contracts to a new governor')
  .addOptionalParam('governorIndex', 'Derivation path index for the new governor account', 1, types.int)
  .addOptionalParam('slasherIndex', 'Derivation path index for the new slasher account', 2, types.int)
  .setAction(async (taskArgs, hre) => {
    printBanner('TRANSFER OWNERSHIP')

    const graph = hre.graph()

    // this task uses impersonation so we NEED a local network
    requireLocalNetwork(hre)

    console.log('\n--- STEP 0: Setup ---')

    // Get signers
    const newGovernor = await graph.accounts.getGovernor(taskArgs.governorIndex)
    const newSlasher = await graph.accounts.getArbitrator(taskArgs.slasherIndex)

    console.log(`New governor will be: ${newGovernor.address}`)

    // Get contracts
    const staking = graph.horizon.contracts.LegacyStaking
    const controller = graph.horizon.contracts.Controller
    const graphProxyAdmin = graph.horizon.contracts.GraphProxyAdmin

    // Get current owners
    const controllerGovernor = await controller.governor()
    const proxyAdminGovernor = await graphProxyAdmin.governor()

    console.log(`Current Controller governor: ${controllerGovernor}`)
    console.log(`Current GraphProxyAdmin governor: ${proxyAdminGovernor}`)

    // Get impersonated signers
    const controllerSigner = await hre.ethers.getImpersonatedSigner(controllerGovernor)
    const proxyAdminSigner = await hre.ethers.getImpersonatedSigner(proxyAdminGovernor)

    console.log('\n--- STEP 1: Transfer ownership of Controller ---')

    // Transfer Controller ownership
    console.log('Transferring Controller ownership...')
    await controller.connect(controllerSigner).transferOwnership(newGovernor.address)
    console.log('Accepting Controller ownership...')

    // Accept ownership of Controller
    await controller.connect(newGovernor).acceptOwnership()
    console.log(`New Controller governor: ${await controller.governor()}`)

    console.log('\n--- STEP 2: Transfer ownership of GraphProxyAdmin ---')

    // Transfer GraphProxyAdmin ownership
    console.log('Transferring GraphProxyAdmin ownership...')
    await graphProxyAdmin.connect(proxyAdminSigner).transferOwnership(newGovernor.address)
    console.log('Accepting GraphProxyAdmin ownership...')

    // Accept ownership of GraphProxyAdmin
    await graphProxyAdmin.connect(newGovernor).acceptOwnership()
    console.log(`New GraphProxyAdmin governor: ${await graphProxyAdmin.governor()}`)

    console.log('\n--- STEP 3: Assign new slasher ---')

    // Assign new slasher
    console.log('Assigning new slasher...')
    await staking.connect(newGovernor).setSlasher(newSlasher.address, true)
    console.log(`New slasher: ${newSlasher.address}, allowed: ${await staking.slashers(newSlasher.address)}`)

    console.log('\n\n🎉 ✨ 🚀 ✅ Transfer ownership complete! 🎉 ✨ 🚀 ✅\n')
  })
