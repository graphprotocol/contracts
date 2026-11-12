import { Wallet } from 'ethers'
import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import { getAddressBook } from '../../utils/addressBook'
import { deployBillingConnector } from '../../utils/deploy'
import { promises as fs } from 'fs'

task('deploy-billing-connector', 'Deploy the billing connector contract (use L1 network!)')
  .addParam('addressBook', 'Addressese json file name', process.env.ADDRESS_BOOK)
  .addParam('tokengateway', 'Address of the L1GraphTokenGateway')
  .addParam('billing', 'Address of the Billing contract on L2')
  .addParam('token', 'Address of the token')
  .addParam('governor', 'Address of the governor')
  .addParam('inbox', 'Address of the Arbitrum DelayedInbox')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const accounts = await hre.ethers.getSigners()
    const chainId = (hre.network.config.chainId as number).toString()
    const addresses = getAddressBook(taskArgs.addressBook, chainId)
    const billingConnector = await deployBillingConnector(
      [taskArgs.tokengateway, taskArgs.billing, taskArgs.token, taskArgs.governor, taskArgs.inbox],
      accounts[0] as unknown as Wallet,
    )
    addresses[chainId]['BillingConnector'] = billingConnector.address
    return fs.writeFile(taskArgs.addressBook, JSON.stringify(addresses, null, 2))
  })
