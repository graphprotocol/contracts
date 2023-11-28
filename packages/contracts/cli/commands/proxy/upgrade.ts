import yargs, { Argv } from 'yargs'

import { logger } from '../../logging'
import { getContractAt, isContractDeployed, sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { confirm } from '../../helpers'

export const upgradeProxy = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const contractName = cliArgs.contract
  const implAddress = cliArgs.impl
  const initArgs = cliArgs.init
  const buildAcceptProxyTx = cliArgs.buildTx
  const skipConfirmation = cliArgs.skipConfirmation

  // Warn about upgrade
  const sure = await confirm(
    `Are you sure you want to upgrade ${contractName} to ${implAddress}?`,
    skipConfirmation,
  )
  if (!sure) return

  logger.info(`Upgrading contract ${contractName}...`)

  // Get address book info
  const addressEntry = cli.addressBook.getEntry(contractName)
  const savedAddress = addressEntry && addressEntry.address

  if (!savedAddress) {
    logger.error(`Contract ${contractName} not found in address book`)
    return
  }

  // Only work with addresses deployed with a proxy
  if (!addressEntry.proxy) {
    logger.error(`Contract ${contractName} was not deployed using a proxy`)
    return
  }

  // Check if contract already deployed
  const isDeployed = await isContractDeployed(
    contractName,
    savedAddress,
    cli.addressBook,
    cli.wallet.provider,
    false,
  )
  if (!isDeployed) {
    logger.error(
      `Proxy for ${contractName} was not deployed, please run migrate to deploy all contracts`,
    )
    return
  }

  // Get the proxy admin
  const proxyAdminEntry = cli.addressBook.getEntry('GraphProxyAdmin')
  if (!proxyAdminEntry || !proxyAdminEntry.address) {
    logger.crit('Missing GraphProxyAdmin configuration')
    return
  }
  const proxyAdmin = getContractAt('GraphProxyAdmin', proxyAdminEntry.address).connect(cli.wallet)

  // Get the current proxy and the new implementation contract
  const proxy = getContractAt('GraphProxy', addressEntry.address).connect(cli.wallet)
  const contract = getContractAt(contractName, implAddress).connect(cli.wallet)

  // Check if implementation already set
  const currentImpl = await proxyAdmin.getProxyImplementation(proxy.address)
  if (currentImpl === implAddress) {
    logger.error(
      `Contract ${implAddress} is already the current implementation for proxy ${proxy.address}`,
    )
    return
  }

  // Upgrade to new implementation
  if (buildAcceptProxyTx) {
    logger.info(
      `
        Copy this data in the gnosis multisig UI, or a similar app and call upgrade()
        You must call upgrade() BEFORE calling acceptProxy()

          contract address:  ${proxyAdmin.address}
          proxy:             ${proxy.address}
          implementation:    ${implAddress}
        `,
    )
    if (initArgs) {
      const initTx = await contract.populateTransaction.initialize(...initArgs.split(','))
      logger.info(
        `
        Copy this data in the gnosis multisig UI, or a similar app and call acceptProxyAndCall()

          contract address:  ${proxyAdmin.address}
          implementation:    ${contract.address}
          proxy:             ${proxy.address}
          data:              ${initTx.data}
        `,
      )
    } else {
      logger.info(
        `
        Copy this data in the gnosis multisig UI, or a similar app and call acceptProxy()

          contract address:  ${proxyAdmin.address}
          implementation:    ${contract.address}
          proxy:             ${proxy.address}
        `,
      )
    }
  } else {
    const receipt = await sendTransaction(cli.wallet, proxyAdmin, 'upgrade', [
      proxy.address,
      implAddress,
    ])
    if (receipt.status == 1) {
      logger.info('> upgrade() tx successful!')
    } else {
      logger.info('> upgrade() tx failed!')
      return
    }

    // Accept upgrade from the implementation
    if (initArgs) {
      const initTx = await contract.populateTransaction.initialize(...initArgs.split(','))
      await sendTransaction(cli.wallet, proxyAdmin, 'acceptProxyAndCall', [
        implAddress,
        proxy.address,
        initTx.data,
      ])
    } else {
      await sendTransaction(cli.wallet, proxyAdmin, 'acceptProxy', [implAddress, proxy.address])
    }
  }

  // TODO
  // -- update address book entry
}

export const upgradeCommand = {
  command: 'upgrade',
  describe: 'Upgrade a proxy contract implementation',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .option('impl', {
        description: 'Address of the contract implementation',
        type: 'string',
        requiresArg: true,
        demandOption: true,
      })
      .option('init', {
        description: 'Init arguments as comma-separated values',
        type: 'string',
        requiresArg: true,
      })
      .option('contract', {
        description: 'Contract name to upgrade',
        type: 'string',
        requiresArg: true,
        demandOption: true,
      })
      .option('b', {
        alias: 'build-tx',
        description: 'Build the acceptProxy tx and print it. Then use tx data with a multisig',
      })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return upgradeProxy(await loadEnv(argv), argv)
  },
}
