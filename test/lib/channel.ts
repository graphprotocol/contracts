import { getRandomPrivateKey, ChannelSigner, getRandomBytes32 } from '@connext/utils'
import { MultisigOperation, tidy } from '@connext/types'
import { Signer } from 'ethers'
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
  defaultAbiCoder,
} from 'ethers/utils'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import MultisigArtifact from '../../build/contracts/MinimumViableMultisig.json'
import MockDisputeArtifact from '../../build/contracts/MockDispute.json'
import IndexerCTDTArtifact from '../../build/contracts/IndexerCTDT.json'
import { IndexerCtdt } from '../../build/typechain/contracts/IndexerCTDT'
import { toBN } from './testHelpers'

export async function getRandomFundedChannelSigners(
  numSigners: number,
  wallet: Signer,
  graphContract?: GraphToken,
) {
  // Create signer array
  const signers = []

  // TODO: properly connect signers to providers
  const provider = 'http:localhost:8545'

  // Fund all signers with eth + tokens
  // eslint-disable-next-line no-unused-vars
  for (const _ of Array(numSigners).fill(0)) {
    // Create random signer
    const privKey = getRandomPrivateKey()
    const signer = new ChannelSigner(privKey, provider)
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

export const outcomeEncoding = tidy(`tuple(
  address to,
  uint256 amount
)`)

export const withdrawOutcomeInterpreterParamsEncoding = tidy(`tuple(
  uint256 limit,
  address tokenAddress
)`)

export const freeBalanceStateEncoding = tidy(
  `tuple(address[] tokenAddresses, tuple(address to, uint256 amount)[][] balances, bytes32[] activeApps)`,
)

export const computeAppIdentityHash = (identity: any /* AppIdentity*/) => {
  return keccak256(
    solidityPack(
      ['address', 'uint256', 'bytes32', 'address', 'uint256'],
      [
        identity.multisigAddress,
        identity.channelNonce,
        keccak256(solidityPack(['address[]'], [identity.participants])),
        identity.appDefinition,
        identity.defaultTimeout,
      ],
    ),
  )
}

export const encodeAppState = (encoding: string, state: any) => {
  console.log(`encoding: ${encoding}, state:`, state)
  return defaultAbiCoder.encode([encoding], [state])
}

// defaults are for app instance not free balance dispute
export async function getInitialDisputeTx(
  mockDisputeAddr: string,
  appDefinition: string,
  multisigAddress: string,
  multisigOwners: string[],
  appState: any = { counter: toBN(1) },
  stateEncoding: string = `tuple(uint256 counter)`,
) {
  // Create app-instance constants
  const identity = {
    multisigAddress,
    channelNonce: toBN(Math.floor(Math.random() * Math.floor(10))),
    // nonce should be unique per app
    participants: multisigOwners,
    appDefinition,
    defaultTimeout: toBN(0),
  }
  const encoded = encodeAppState(stateEncoding, appState)
  const appStateHash = keccak256(encoded)

  // Create inputs for dispute
  const req = {
    appStateHash,
    versionNumber: Math.floor(Math.random() * Math.floor(10)),
    timeout: toBN(0),
    signatures: [getRandomBytes32(), getRandomBytes32()], // mock disutes dont check sigs
  }

  // Encode call to execute transaction
  const mockDispute = new Interface(MockDisputeArtifact.abi)
  const txData = mockDispute.functions.setStateAndOutcome.encode([identity, req, encoded])

  return {
    identityHash: computeAppIdentityHash(identity),
    transaction: { to: mockDisputeAddr, value: 0, data: txData },
  }
}

export enum CommitmentType {
  Withdraw = 'withdraw',
  App = 'app',
  FreeBalance = 'freebalance',
}

// This class helps create commitments for testing the multisig
// and the disputes. In the case of disputes, an app is needed,
// and is created on instantiation of a class. This class is
// intended to be used 1:1 with a multisig and will always use
// the simple AppWithCounter app for testing
export class MiniCommitment {
  constructor(readonly multisigAddress: string, readonly owners: ChannelSigner[]) {}

  getTransactionDetails(
    commitmentType: CommitmentType,
    params: {
      assetId: string
      amount: BigNumberish
      recipient: string
      withdrawInterpreterAddress: string
      ctdt: IndexerCtdt
    },
  ) {
    switch (commitmentType) {
      case CommitmentType.Withdraw: {
        // Destructure withdrawal commitment params
        const { withdrawInterpreterAddress, amount, assetId, recipient, ctdt } = params

        // Return properly encoded transaction values
        return {
          to: ctdt.address,
          value: 0,
          data: ctdt.interface.functions.executeWithdraw.encode([
            withdrawInterpreterAddress,
            randomBytes(32), // nonce
            defaultAbiCoder.encode(
              [outcomeEncoding],
              [{ to: recipient, amount: bigNumberify(amount) }],
            ),
            defaultAbiCoder.encode(
              [withdrawOutcomeInterpreterParamsEncoding],
              [{ limit: bigNumberify(amount), tokenAddress: assetId }],
            ),
          ]),
          operation: MultisigOperation.DelegateCall,
        }
      }
      // TODO: returns signed app execute effect tx
      case CommitmentType.App: {
        const {} = params
        return {
          to: '',
          value: 0,
          data: '',
        }
      }
      // TODO: returns signed app execute effect tx
      case CommitmentType.FreeBalance: {
        const {} = params
        return {
          to: '',
          value: 0,
          data: '',
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
    commitmentType: CommitmentType,
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
