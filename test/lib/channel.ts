import { getRandomPrivateKey, ChannelSigner } from '@connext/utils'
import { MultisigOperation } from '@connext/types'
import { Wallet, Signer } from 'ethers'
import {
  parseEther,
  BigNumber,
  Interface,
  randomBytes,
  solidityKeccak256,
  bigNumberify,
  solidityPack,
  keccak256,
  BigNumberish,
} from 'ethers/utils'

import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import MultisigArtifact from '../../build/contracts/MinimumViableMultisig.json'
import IndexerCTDTArtifact from '../../build/contracts/IndexerCTDT.json'
import { IndexerCtdt } from '../../build/typechain/contracts/IndexerCTDT'

export async function getRandomFundedChannelSigners(
  numSigners: number,
  wallet: Signer,
  graphContract?: GraphToken,
) {
  // Create signer array
  const signers = []

  // Fund all signers with eth + tokens
  // eslint-disable-next-line no-unused-vars
  for (const _ of Array(numSigners).fill(0)) {
    // Create random signer
    const privKey = getRandomPrivateKey()
    const signer = new ChannelSigner(privKey)
    const addr = await signer.getAddress()

    // Add signer to array
    signers.push(signer)

    // Send eth
    const ETH_DEPOSIT = parseEther('0.1')

    await wallet.sendTransaction({
      to: addr,
      value: ETH_DEPOSIT,
    })

    if (!graphContract) {
      continue
    }

    // Send tokens
    const GRT_DEPOSIT = parseEther('100')
    await graphContract.mint(addr, GRT_DEPOSIT)
  }

  return signers
}

export function fundMultisig(
  amount: BigNumber,
  multisigAddr: string,
  wallet?: Signer,
  tokenContract?: GraphToken,
) {
  if (tokenContract) {
    return tokenContract.mint(multisigAddr, amount)
  }
  return wallet.sendTransaction({
    to: multisigAddr,
    value: amount,
  })
}

export class MiniCommitment {
  constructor(
    readonly multisigAddress: string, // Address
    readonly owners: ChannelSigner[], // ChannelSigner[]
  ) {}

  getTransactionDetails(
    commitmentType: 'withdraw',
    params: {
      assetId: string
      amount: BigNumberish
      recipient: string
      withdrawInterpreterAddress: string
      ctdt: IndexerCtdt
    },
  ) {
    switch (commitmentType) {
      case 'withdraw': {
        // Destructure withdrawal commitment params
        const { withdrawInterpreterAddress, amount, assetId, recipient, ctdt } = params

        // Return properly encoded transaction values
        return {
          to: ctdt.address,
          value: 0,
          data: ctdt.interface.functions.executeWithdraw.encode([
            withdrawInterpreterAddress,
            randomBytes(32), // nonce
            solidityKeccak256(['address', 'uint256'], [recipient, bigNumberify(amount)]),
            solidityKeccak256(['uint256', 'address'], [bigNumberify(amount), assetId]),
          ]),
          operation: MultisigOperation.DelegateCall,
        }
      }
      default: {
        throw new Error(`Invalid commitment type: ${commitmentType}`)
      }
    }
  }

  // Returns the hash to sign from generated transaction details
  getDigestFromDetails(details: any) {
    // Parse tx details
    const { to, value, data, operation } = details

    // Generate properly hashed digest from tx details
    const encoded = solidityPack(
      ['uint8', 'address', 'address', 'uint256', 'bytes32', 'uint8'],
      ['0', this.multisigAddress, to, value, solidityKeccak256(['bytes'], [data]), operation],
    )
    return keccak256(encoded)
  }

  async getSignedTransaction(
    commitmentType: 'withdraw',
    params: {
      assetId: string
      amount: BigNumberish
      recipient: string
      withdrawInterpreterAddress: string
      ctdt: IndexerCtdt
    },
  ) {
    // Generate transaction details
    const details = this.getTransactionDetails(commitmentType, params)

    // Generate owner signatures
    const digest = this.getDigestFromDetails(details)
    console.log('owners are signing', digest)
    const signatures = await Promise.all(this.owners.map(owner => owner.signMessage(digest)))

    // Encode call to execute transaction
    const multisig = new Interface(MultisigArtifact.abi)
    const txData = multisig.functions.execTransaction.encode([
      details.to,
      details.value,
      details.data,
      details.operation,
      signatures,
    ])

    return { to: this.multisigAddress, value: 0, data: txData }
  }
}
