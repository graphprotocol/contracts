import fs from 'fs'
import { addCustomNetwork } from '@arbitrum/sdk'
import { applyL1ToL2Alias } from '../utils/arbitrum/'
import { impersonateAccount } from './impersonate'
import { Wallet, ethers, providers } from 'ethers'

import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { DeployType, deploy } from '../deployments'
import type { BridgeMock, InboxMock, OutboxMock } from '@graphprotocol/contracts'
import { setCode } from './code'

export interface L1ArbitrumMocks {
  bridgeMock: BridgeMock
  inboxMock: InboxMock
  outboxMock: OutboxMock
  routerMock: Wallet
}

export interface L2ArbitrumMocks {
  routerMock: Wallet
}

export async function deployL1MockBridge(
  deployer: SignerWithAddress,
  arbitrumAddressBook: string,
  provider: providers.Provider,
): Promise<L1ArbitrumMocks> {
  // Deploy mock contracts
  const bridgeMock = (await deploy(DeployType.Deploy, deployer, { name: 'BridgeMock' }))
    .contract as BridgeMock
  const inboxMock = (await deploy(DeployType.Deploy, deployer, { name: 'InboxMock' }))
    .contract as InboxMock
  const outboxMock = (await deploy(DeployType.Deploy, deployer, { name: 'OutboxMock' }))
    .contract as OutboxMock

  // "deploy" router - set dummy code so that it appears as a contract
  const routerMock = Wallet.createRandom()
  await setCode(routerMock.address, '0x1234')

  // Configure mock contracts
  await bridgeMock.connect(deployer).setInbox(inboxMock.address, true)
  await bridgeMock.connect(deployer).setOutbox(outboxMock.address, true)
  await inboxMock.connect(deployer).setBridge(bridgeMock.address)
  await outboxMock.connect(deployer).setBridge(bridgeMock.address)

  // Update address book
  const deployment = fs.existsSync(arbitrumAddressBook)
    ? JSON.parse(fs.readFileSync(arbitrumAddressBook, 'utf-8'))
    : {}
  const addressBook = {
    '1337': {
      L1GatewayRouter: {
        address: routerMock.address,
      },
      IInbox: {
        address: inboxMock.address,
      },
    },
    '412346': {
      L2GatewayRouter: {
        address: deployment['412346']?.L2GatewayRouter?.address ?? '',
      },
    },
  }

  fs.writeFileSync(arbitrumAddressBook, JSON.stringify(addressBook))

  return {
    bridgeMock: bridgeMock.connect(provider),
    inboxMock: inboxMock.connect(provider),
    outboxMock: outboxMock.connect(provider),
    routerMock: routerMock.connect(provider),
  }
}

export async function deployL2MockBridge(
  deployer: SignerWithAddress,
  arbitrumAddressBook: string,
  provider: providers.Provider,
): Promise<L2ArbitrumMocks> {
  // "deploy" router - set dummy code so that it appears as a contract
  const routerMock = Wallet.createRandom()
  await setCode(routerMock.address, '0x1234')

  // Update address book
  const deployment = fs.existsSync(arbitrumAddressBook)
    ? JSON.parse(fs.readFileSync(arbitrumAddressBook, 'utf-8'))
    : {}
  const addressBook = {
    '1337': {
      L1GatewayRouter: {
        address: deployment['1337']?.L1GatewayRouter?.address,
      },
      IInbox: {
        address: deployment['1337']?.IInbox?.address,
      },
    },
    '412346': {
      L2GatewayRouter: {
        address: routerMock.address,
      },
    },
  }

  fs.writeFileSync(arbitrumAddressBook, JSON.stringify(addressBook))

  return {
    routerMock: routerMock.connect(provider),
  }
}

export async function getL2SignerFromL1(l1Address: string): Promise<SignerWithAddress> {
  const l2Address = applyL1ToL2Alias(l1Address)
  return impersonateAccount(l2Address)
}

export function addLocalNetwork(deploymentFile: string) {
  if (!fs.existsSync(deploymentFile)) {
    throw new Error(`Deployment file not found: ${deploymentFile}`)
  }
  const deployment = JSON.parse(fs.readFileSync(deploymentFile, 'utf-8'))
  addCustomNetwork({
    customL1Network: deployment.l1Network,
    customL2Network: deployment.l2Network,
  })
}

// Use prefunded genesis address to fund accounts
// See: https://docs.arbitrum.io/node-running/how-tos/local-dev-node#default-endpoints-and-addresses
export async function fundLocalAccounts(
  accounts: SignerWithAddress[],
  provider: providers.Provider,
) {
  for (const account of accounts) {
    const amount = ethers.utils.parseEther('10')
    const wallet = new Wallet('b6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659')
    const tx = await wallet.connect(provider).sendTransaction({
      value: amount,
      to: account.address,
    })
    await tx.wait()
  }
}
