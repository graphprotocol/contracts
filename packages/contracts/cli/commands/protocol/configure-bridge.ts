import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { logger } from '../../logging'
import { getAddressBook } from '../../address-book'
import { sendTransaction } from '../../network'
import { chainIdIsL2, l1ToL2ChainIdMap, l2ToL1ChainIdMap } from '../../cross-chain'

export const configureL1Bridge = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.info(`>>> Setting L1 Bridge Configuration <<<\n`)

  if (chainIdIsL2(cli.chainId)) {
    throw new Error('Cannot set L1 configuration on an L2 network!')
  }
  const l2ChainId = cliArgs.l2ChainId ? cliArgs.l2ChainId : l1ToL2ChainIdMap[cli.chainId]
  logger.info('Connecting with the contracts on L2 chainId ' + l2ChainId)
  const l2AddressBook = getAddressBook(cliArgs.addressBook, l2ChainId)
  const arbAddressBook = getAddressBook(cliArgs.arbAddressBook, cli.chainId.toString())

  // Gateway
  const gateway = cli.contracts['L1GraphTokenGateway']

  const l2GRT = l2AddressBook.getEntry('L2GraphToken')
  logger.info('L2 GRT address: ' + l2GRT.address)
  await sendTransaction(cli.wallet, gateway, 'setL2TokenAddress', [l2GRT.address])

  const l2GatewayCounterpart = l2AddressBook.getEntry('L2GraphTokenGateway')
  logger.info('L2 Gateway address: ' + l2GatewayCounterpart.address)
  await sendTransaction(cli.wallet, gateway, 'setL2CounterpartAddress', [
    l2GatewayCounterpart.address,
  ])

  // Escrow
  const bridgeEscrow = cli.contracts.BridgeEscrow
  logger.info('Escrow address: ' + bridgeEscrow.address)
  await sendTransaction(cli.wallet, gateway, 'setEscrowAddress', [bridgeEscrow.address])
  await sendTransaction(cli.wallet, bridgeEscrow, 'approveAll', [gateway.address])

  const l1Inbox = arbAddressBook.getEntry('IInbox')
  const l1Router = arbAddressBook.getEntry('L1GatewayRouter')
  logger.info(
    'L1 Inbox address: ' + l1Inbox.address + ' and L1 Router address: ' + l1Router.address,
  )
  await sendTransaction(cli.wallet, gateway, 'setArbitrumAddresses', [
    l1Inbox.address,
    l1Router.address,
  ])

  // GNS
  const gns = cli.contracts.L1GNS
  const l2GNSCounterpart = l2AddressBook.getEntry('L2GNS')
  logger.info('L2 GNS address: ' + l2GNSCounterpart.address)
  await sendTransaction(cli.wallet, gns, 'setCounterpartGNSAddress', [l2GNSCounterpart.address])
  await sendTransaction(cli.wallet, gateway, 'addToCallhookAllowlist', [gns.address])

  // Staking
  const staking = cli.contracts.L1Staking
  const l2StakingCounterpart = l2AddressBook.getEntry('L2Staking')
  logger.info('L2 Staking address: ' + l2StakingCounterpart.address)
  await sendTransaction(cli.wallet, staking, 'setCounterpartStakingAddress', [
    l2StakingCounterpart.address,
  ])
  await sendTransaction(cli.wallet, gateway, 'addToCallhookAllowlist', [staking.address])
}

export const configureL2Bridge = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.info(`>>> Setting L2 Bridge Configuration <<<\n`)

  if (!chainIdIsL2(cli.chainId)) {
    throw new Error('Cannot set L2 configuration on an L1 network!')
  }
  const l1ChainId = cliArgs.l1ChainId ? cliArgs.l1ChainId : l2ToL1ChainIdMap[cli.chainId]
  logger.info('Connecting with the contracts on L1 chainId ' + l1ChainId)
  const l1AddressBook = getAddressBook(cliArgs.addressBook, l1ChainId)
  const arbAddressBook = getAddressBook(cliArgs.arbAddressBook, cli.chainId.toString())

  // Gateway
  const gateway = cli.contracts['L2GraphTokenGateway']
  const token = cli.contracts['L2GraphToken']

  const l1GRT = l1AddressBook.getEntry('GraphToken')
  logger.info('L1 GRT address: ' + l1GRT.address)
  await sendTransaction(cli.wallet, gateway, 'setL1TokenAddress', [l1GRT.address])
  await sendTransaction(cli.wallet, token, 'setL1Address', [l1GRT.address])

  const l1Counterpart = l1AddressBook.getEntry('L1GraphTokenGateway')
  logger.info('L1 Gateway address: ' + l1Counterpart.address)
  await sendTransaction(cli.wallet, gateway, 'setL1CounterpartAddress', [l1Counterpart.address])

  const l2Router = arbAddressBook.getEntry('L2GatewayRouter')
  logger.info('L2 Router address: ' + l2Router.address)
  await sendTransaction(cli.wallet, gateway, 'setL2Router', [l2Router.address])

  logger.info('L2 Gateway address: ' + gateway.address)
  await sendTransaction(cli.wallet, token, 'setGateway', [gateway.address])

  // GNS
  const gns = cli.contracts.L2GNS
  const l1GNSCounterpart = l1AddressBook.getEntry('L1GNS')
  logger.info('L1 GNS address: ' + l1GNSCounterpart.address)
  await sendTransaction(cli.wallet, gns, 'setCounterpartGNSAddress', [l1GNSCounterpart.address])

  // Staking
  const staking = cli.contracts.L2Staking
  const l1StakingCounterpart = l1AddressBook.getEntry('L1Staking')
  logger.info('L1 Staking address: ' + l1StakingCounterpart.address)
  await sendTransaction(cli.wallet, staking, 'setCounterpartStakingAddress', [
    l1StakingCounterpart.address,
  ])
}

export const configureL1BridgeCommand = {
  command: 'configure-l1-bridge [l2ChainId]',
  describe: 'Configure L1/L2 bridge parameters (L1 side) using the address book',
  handler: async (argv: CLIArgs): Promise<void> => {
    return configureL1Bridge(await loadEnv(argv), argv)
  },
}

export const configureL2BridgeCommand = {
  command: 'configure-l2-bridge [l1ChainId]',
  describe: 'Configure L1/L2 bridge parameters (L2 side) using the address book',
  handler: async (argv: CLIArgs): Promise<void> => {
    return configureL2Bridge(await loadEnv(argv), argv)
  },
}
