import { Wallet } from 'ethers'
import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import { deployBilling } from '../../utils/deploy'
import { logger } from '../../utils/logging'

import { getAddressBook } from '../../utils/addressBook'
import { getContractAt } from '../../utils/contracts'
import { Billing } from '../../build/types'
import { promises as fs } from 'fs'

task('deploy-billing', 'Deploy the billing contract (use L2 network!)')
  .addParam('addressBook', 'Addressese json file name', process.env.ADDRESS_BOOK)
  .addParam('collector', 'Address of the collector')
  .addParam('token', 'Address of the token')
  .addParam('governor', 'Address of the governor, leave empty to use the deployer')
  .addParam('tokengateway', 'Address of the L2GraphTokenGateway')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const accounts = await hre.ethers.getSigners()
    const chainId = (hre.network.config.chainId as number).toString()
    const billing = await deployBilling(
      [taskArgs.collector, taskArgs.token, taskArgs.governor ?? accounts[0].address, taskArgs.tokengateway],
      accounts[0] as unknown as Wallet,
    )
    const addresses = getAddressBook(taskArgs.addressBook, chainId)
    addresses[chainId]['Billing'] = billing.address
    return fs.writeFile(taskArgs.addressBook, JSON.stringify(addresses, null, 2))
  })

task(
  'configure-billing',
  'Configure the billing contract to set billing connector address and transfer ownership to the governor (use L2 network!)',
)
  .addParam('addressBook', 'Addressese json file name', process.env.ADDRESS_BOOK)
  .addParam('governor', 'Address of the governor')
  .addParam('billingconnector', 'Address of the BillingConnector on L1')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const accounts = await hre.ethers.getSigners()
    const chainId = (hre.network.config.chainId as number).toString()
    const addresses = getAddressBook(taskArgs.addressBook, chainId)
    const addressBook = addresses[chainId]
    const wallet = accounts[0] as unknown as Wallet
    const billing = getContractAt('Billing', addressBook['Billing'], wallet) as unknown as Billing

    logger.log(`Setting L1 billing connector address to ${taskArgs.billingconnector}`)
    const tx1 = await billing.connect(wallet).setL1BillingConnector(taskArgs.billingconnector)
    const receipt1 = await tx1.wait()
    logger.log(`> Done. Tx hash: ${receipt1.transactionHash}`)

    const currentBillingGovernor = await billing.governor()
    if (currentBillingGovernor != taskArgs.governor) {
      logger.log(`Transferring Billing contract ownership to ${taskArgs.governor}`)
      const tx2 = await billing.connect(wallet).transferOwnership(taskArgs.governor)
      const receipt2 = await tx2.wait()
      logger.log(`> Done. Tx hash: ${receipt2.transactionHash}`)
    } else {
      logger.log('Billing is already owned by the right governor, so skipping ownership transfer.')
    }
  })
