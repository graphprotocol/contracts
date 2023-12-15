import type { GraphNetworkAction } from './types'
import type { GraphNetworkContracts } from '../deployment/contracts/load'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { SimpleAddressBook } from '../../lib/address-book'

export const configureL1Bridge: GraphNetworkAction<{
  l2GRTAddress: string
  l2GRTGatewayAddress: string
  arbAddressBookPath: string
  chainId: number
}> = async (
  contracts: GraphNetworkContracts,
  signer: SignerWithAddress,
  args: {
    l2GRTAddress: string
    l2GRTGatewayAddress: string
    arbAddressBookPath: string
    chainId: number
  },
): Promise<void> => {
  const { l2GRTAddress, l2GRTGatewayAddress, arbAddressBookPath, chainId } = args
  console.info(`>>> Setting L1 Bridge Configuration <<<\n`)

  const arbAddressBook = new SimpleAddressBook(arbAddressBookPath, chainId)

  const gateway = contracts.L1GraphTokenGateway!

  console.info('L2 GRT address: ' + l2GRTAddress)
  await gateway.connect(signer).setL2TokenAddress(l2GRTAddress)

  console.info('L2 Gateway address: ' + l2GRTGatewayAddress)
  await gateway.connect(signer).setL2CounterpartAddress(l2GRTGatewayAddress)

  const bridgeEscrow = contracts.BridgeEscrow!
  console.info('Escrow address: ' + bridgeEscrow.address)
  await gateway.connect(signer).setEscrowAddress(bridgeEscrow.address)
  await bridgeEscrow.connect(signer).approveAll(gateway.address)

  const l1Inbox = arbAddressBook.getEntry('IInbox')
  const l1Router = arbAddressBook.getEntry('L1GatewayRouter')
  console.info(
    'L1 Inbox address: ' + l1Inbox.address + ' and L1 Router address: ' + l1Router.address,
  )
  await gateway.connect(signer).setArbitrumAddresses(l1Inbox.address, l1Router.address)
}

export const configureL2Bridge: GraphNetworkAction<{
  l1GRTAddress: string
  l1GRTGatewayAddress: string
  arbAddressBookPath: string
  chainId: number
}> = async (
  contracts: GraphNetworkContracts,
  signer: SignerWithAddress,
  args: {
    l1GRTAddress: string
    l1GRTGatewayAddress: string
    arbAddressBookPath: string
    chainId: number
  },
): Promise<void> => {
  const { l1GRTAddress, l1GRTGatewayAddress, arbAddressBookPath, chainId } = args
  console.info(`>>> Setting L2 Bridge Configuration <<<\n`)

  const arbAddressBook = new SimpleAddressBook(arbAddressBookPath, chainId)

  const gateway = contracts.L2GraphTokenGateway!
  const token = contracts.L2GraphToken!

  console.info('L1 GRT address: ' + l1GRTAddress)
  await gateway.connect(signer).setL1TokenAddress(l1GRTAddress)
  await token.connect(signer).setL1Address(l1GRTAddress)

  console.info('L1 Gateway address: ' + l1GRTGatewayAddress)
  await gateway.connect(signer).setL1CounterpartAddress(l1GRTGatewayAddress)

  const l2Router = arbAddressBook.getEntry('L2GatewayRouter')
  console.info('L2 Router address: ' + l2Router.address)
  await gateway.connect(signer).setL2Router(l2Router.address)

  console.info('L2 Gateway address: ' + gateway.address)
  await token.connect(signer).setGateway(gateway.address)
}
