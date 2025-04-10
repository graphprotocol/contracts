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

    // this task uses impersonation so we NEED a local network
    requireLocalNetwork(hre)

    console.log('\n--- STEP 0: Setup ---')

    // Get signers
    const signers = await hre.ethers.getSigners()
    const newGovernor = signers[taskArgs.governorIndex]
    const newSlasher = signers[taskArgs.slasherIndex]

    console.log(`New governor will be: ${newGovernor.address}`)

    // Get contracts
    const graph = hre.graph()
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
  })
