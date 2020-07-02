import { getRandomPrivateKey, ChannelSigner, getRandomBytes32, stringify } from '@connext/utils'
import {
  MultisigOperation,
  tidy,
  singleAssetTwoPartyCoinTransferInterpreterParamsEncoding,
} from '@connext/types'
import { Signer } from 'ethers'
import { constants, utils, BigNumber, BigNumberish } from 'ethers'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import MultisigArtifact from '../../build/contracts/MinimumViableMultisig.json'
import { IndexerCtdt } from '../../build/typechain/contracts/IndexerCtdt'
import { toBN } from './testHelpers'
import { MockDispute } from '../../build/typechain/contracts/MockDispute'

const { Zero, AddressZero } = constants
const {
  parseEther,
  Interface,
  randomBytes,
  solidityKeccak256,
  solidityPack,
  keccak256,
  defaultAbiCoder,
} = utils

export async function getRandomFundedChannelSigners(
  numSigners: number,
  wallet: Signer,
  graphContract?: GraphToken,
) {
  // Create signer array
  const signers = []

  // Fund all signers with eth + tokens
  // eslint-disable-next-line no-unused-vars
  for (const _ of Array(numSigners)) {
    // Create random signer
    const privKey = getRandomPrivateKey()
    const signer = new ChannelSigner(privKey, wallet.provider! as any)
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

export const withdrawOutcomeEncoding = tidy(`tuple(
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

export const appWithCounterStateEncoding = tidy(
  `tuple(uint256 counter, tuple(address to, uint256 amount)[2] transfers)`,
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

export const encode = (encoding: string, state: any) => {
  return defaultAbiCoder.encode([encoding], [state])
}

export const getAppInitialState = (appDeposit: BigNumber, participants: string[]) => {
  return {
    counter: toBN(1),
    transfers: [
      {
        to: participants[0],
        amount: appDeposit,
      },
      {
        to: participants[1],
        amount: Zero,
      },
    ],
  }
}

export const getFreeBalanceState = (
  multisigOwners: string[],
  totalChannelEth: BigNumber,
  totalChannelTokens: BigNumber,
  beneficiary: ChannelSigner,
  appInfo: [{ identityHash: string; deposit: BigNumber; assetId: string }],
) => {
  // Generate active apps
  const activeApps = appInfo.map((appInfo) => appInfo.identityHash)

  // Generate token addresses
  const tokenAddresses = [AddressZero].concat(
    appInfo.filter((app) => app.assetId !== AddressZero).map((app) => app.assetId),
  )

  // Get total app deposits
  const depositInfo = appInfo.map(({ deposit, assetId }) => {
    return { deposit, assetId }
  })
  const totalAppsEth = depositInfo.reduce(
    (prev, curr) => {
      const isEth = curr.assetId === AddressZero
      return {
        assetId: curr.assetId,
        deposit: prev.deposit.add(isEth ? curr.deposit : Zero),
      }
    },
    {
      assetId: AddressZero,
      deposit: BigNumber.from(0),
    },
  )

  const totalAppsToken = depositInfo.reduce(
    (prev, curr) => {
      const isToken = curr.assetId !== AddressZero
      return {
        assetId: curr.assetId,
        deposit: prev.deposit.add(isToken ? curr.deposit : Zero),
      }
    },
    {
      assetId: AddressZero,
      deposit: BigNumber.from(0),
    },
  )

  // Generate balances assuming all apps have the same beneficiary
  const isOwner0 = beneficiary.address === multisigOwners[0]
  const balances = [
    [
      {
        to: multisigOwners[0],
        amount: totalChannelEth.div(2).sub(isOwner0 ? totalAppsEth.deposit : Zero),
      },
      {
        to: multisigOwners[1],
        amount: totalChannelEth.div(2).sub(!isOwner0 ? totalAppsEth.deposit : Zero),
      },
    ],
    [
      {
        to: multisigOwners[0],
        amount: totalChannelTokens.div(2).sub(isOwner0 ? totalAppsToken.deposit : Zero),
      },
      {
        to: multisigOwners[1],
        amount: totalChannelTokens.div(2).sub(!isOwner0 ? totalAppsToken.deposit : Zero),
      },
    ],
  ]
  return {
    tokenAddresses,
    activeApps,
    balances,
  }
}

// defaults are for app instance not free balance dispute
export async function createAppDispute(
  mockDispute: MockDispute,
  appDefinition: string,
  multisigAddress: string,
  multisigOwners: string[],
  appState: any,
  stateEncoding: string = freeBalanceStateEncoding,
  participants: string[] = multisigOwners,
): Promise<string> {
  // Create app-instance constants
  const identity = {
    multisigAddress,
    channelNonce: toBN(Math.floor(Math.random() * Math.floor(10))),
    // nonce should be unique per app
    participants,
    appDefinition,
    defaultTimeout: toBN(0),
  }
  const encoded = encode(stateEncoding, appState)

  // Create inputs for dispute
  const req = {
    appStateHash: keccak256(encoded),
    versionNumber: Math.floor(Math.random() * Math.floor(10)),
    timeout: toBN(0),
    signatures: [getRandomBytes32(), getRandomBytes32()], // mock disutes dont check sigs
  }

  // Send dispute tx
  const tx = await mockDispute.functions.setStateAndOutcome(identity, req, encoded)
  await tx.wait()

  return computeAppIdentityHash(identity)
}

export const CommitmentTypes = {
  withdraw: 'withdraw',
  conditional: 'conditional',
  setup: 'setup',
} as const
export type CommitmentType = keyof typeof CommitmentTypes

type WithdrawParams = {
  assetId: string
  amount: BigNumberish
  recipient: string
  withdrawInterpreterAddress: string
  ctdt: IndexerCtdt
}

type ConditionalParams = {
  ctdt: IndexerCtdt
  assetId: string
  amount: BigNumberish
  freeBalanceIdentityHash: string
  appIdentityHash: string
  interpreterAddr: string
  mockDispute: MockDispute
}

type SetupParams = {
  ctdt: IndexerCtdt
  freeBalanceIdentityHash: string
  interpreterAddr: string
  mockDispute: MockDispute
}

interface CommitmentInputMap {
  [CommitmentTypes.withdraw]: WithdrawParams
  [CommitmentTypes.conditional]: ConditionalParams
  [CommitmentTypes.setup]: SetupParams
}
export type CommitmentInputs = {
  [P in keyof CommitmentInputMap]: CommitmentInputMap[P]
}

// This class helps create commitments for testing the multisig
// and the disputes. In the case of disputes, an app is needed,
// and is created on instantiation of a class. This class is
// intended to be used 1:1 with a multisig and will always use
// the simple AppWithCounter app for testing
export class MiniCommitment {
  constructor(readonly multisigAddress: string, readonly owners: ChannelSigner[]) {}

  getTransactionDetails<T extends CommitmentType>(commitmentType: T, params: CommitmentInputs[T]) {
    switch (commitmentType) {
      case CommitmentTypes.withdraw: {
        // Destructure withdrawal commitment params
        const {
          withdrawInterpreterAddress,
          amount,
          assetId,
          recipient,
          ctdt,
        } = params as WithdrawParams

        // Return properly encoded transaction values
        return {
          to: ctdt.address,
          value: 0,
          data: ctdt.interface.encodeFunctionData('executeWithdraw', [
            withdrawInterpreterAddress,
            randomBytes(32), // nonce
            encode(withdrawOutcomeEncoding, { to: recipient, amount: BigNumber.from(amount) }),
            encode(withdrawOutcomeInterpreterParamsEncoding, {
              limit: BigNumber.from(amount),
              tokenAddress: assetId,
            }),
          ]),
          operation: MultisigOperation.DelegateCall,
        }
      }
      case CommitmentTypes.conditional: {
        const {
          ctdt,
          freeBalanceIdentityHash,
          appIdentityHash,
          interpreterAddr,
          amount,
          assetId,
          mockDispute,
        } = params as ConditionalParams

        // Uses single asset interpreter addr
        const interpreterParams = {
          limit: amount,
          tokenAddress: assetId,
        }
        const encodedParams = encode(
          singleAssetTwoPartyCoinTransferInterpreterParamsEncoding,
          interpreterParams,
        )
        return {
          to: ctdt.address,
          value: 0,
          data: ctdt.interface.encodeFunctionData('executeEffectOfInterpretedAppOutcome', [
            mockDispute.address,
            freeBalanceIdentityHash,
            appIdentityHash,
            interpreterAddr,
            encodedParams,
          ]),
          operation: MultisigOperation.DelegateCall,
        }
      }

      // TODO: returns signed app execute effect tx
      case CommitmentTypes.setup: {
        const {
          ctdt,
          freeBalanceIdentityHash,
          interpreterAddr,
          mockDispute,
        } = params as SetupParams
        return {
          to: ctdt.address,
          value: 0,
          data: ctdt.interface.encodeFunctionData('executeEffectOfFreeBalance', [
            mockDispute.address,
            freeBalanceIdentityHash,
            interpreterAddr,
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

  async getSignedTransaction<T extends CommitmentType>(
    commitmentType: T,
    params: CommitmentInputs[T],
  ) {
    // Generate transaction details
    const details = this.getTransactionDetails(commitmentType, params)

    // Generate owner signatures
    const digest = this.getDigestFromDetails(details)
    const signatures = await Promise.all(this.owners.map((owner) => owner.signMessage(digest)))

    // Encode call to execute transaction
    const multisig = new Interface(MultisigArtifact.abi)

    const txData = multisig.encodeFunctionData('execTransaction', [
      details.to,
      details.value,
      details.data,
      details.operation,
      signatures,
    ])

    return { to: this.multisigAddress, value: 0, data: txData }
  }
}
