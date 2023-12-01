import {
  L1ToL2MessageReader,
  L1ToL2MessageStatus,
  L1ToL2MessageWriter,
  L1TransactionReceipt,
  L2ToL1MessageReader,
  L2ToL1MessageStatus,
  L2ToL1MessageWriter,
  L2TransactionReceipt,
} from '@arbitrum/sdk'

import type { Provider } from '@ethersproject/abstract-provider'
import type { providers, Signer } from 'ethers'

// L1 -> L2
export async function getL1ToL2MessageWriter(
  txHashOrReceipt: string | providers.TransactionReceipt,
  l1Provider: Provider,
  l2Provider: Provider,
): Promise<L1ToL2MessageWriter> {
  return (await getL1ToL2Message(txHashOrReceipt, l1Provider, l2Provider)) as L1ToL2MessageWriter
}

export async function getL1ToL2MessageReader(
  txHashOrReceipt: string | providers.TransactionReceipt,
  l1Provider: Provider,
  l2Provider: Provider,
): Promise<L1ToL2MessageReader> {
  return await getL1ToL2Message(txHashOrReceipt, l1Provider, l2Provider)
}

export async function getL1ToL2MessageStatus(
  txHashOrReceipt: string | providers.TransactionReceipt,
  l1Provider: Provider,
  l2Provider: Provider,
): Promise<L1ToL2MessageStatus> {
  const message = await getL1ToL2Message(txHashOrReceipt, l1Provider, l2Provider)
  return await message.status()
}

async function getL1ToL2Message(
  txHashOrReceipt: string | providers.TransactionReceipt,
  l1Provider: Provider,
  l2Provider: Provider,
): Promise<L1ToL2MessageWriter | L1ToL2MessageReader> {
  const txReceipt =
    typeof txHashOrReceipt === 'string'
      ? await l1Provider.getTransactionReceipt(txHashOrReceipt)
      : txHashOrReceipt
  const l1Receipt = new L1TransactionReceipt(txReceipt)
  const l1ToL2Messages = await l1Receipt.getL1ToL2Messages(l2Provider)
  return l1ToL2Messages[0]
}

// L2 -> L1
export async function getL2ToL1MessageWriter(
  txHashOrReceipt: string | providers.TransactionReceipt,
  l1Provider: Provider,
  l2Provider: Provider,
  signer: Signer,
): Promise<L2ToL1MessageWriter> {
  return (await getL2ToL1Message(
    txHashOrReceipt,
    l1Provider,
    l2Provider,
    signer,
  )) as L2ToL1MessageWriter
}

export async function getL2ToL1MessageReader(
  txHashOrReceipt: string | providers.TransactionReceipt,
  l1Provider: Provider,
  l2Provider: Provider,
): Promise<L2ToL1MessageReader> {
  return await getL2ToL1Message(txHashOrReceipt, l1Provider, l2Provider)
}

export async function getL2ToL1MessageStatus(
  txHashOrReceipt: string | providers.TransactionReceipt,
  l1Provider: Provider,
  l2Provider: Provider,
): Promise<L2ToL1MessageStatus> {
  const message = await getL2ToL1Message(txHashOrReceipt, l1Provider, l2Provider)
  return await message.status(l2Provider)
}

async function getL2ToL1Message(
  txHashOrReceipt: string | providers.TransactionReceipt,
  l1Provider: Provider,
  l2Provider: Provider,
  signer?: Signer,
) {
  const txReceipt =
    typeof txHashOrReceipt === 'string'
      ? await l2Provider.getTransactionReceipt(txHashOrReceipt)
      : txHashOrReceipt
  const l1SignerOrProvider = signer ? signer.connect(l1Provider) : l1Provider
  const l2Receipt = new L2TransactionReceipt(txReceipt)
  const l2ToL1Messages = await l2Receipt.getL2ToL1Messages(l1SignerOrProvider)
  return l2ToL1Messages[0]
}
