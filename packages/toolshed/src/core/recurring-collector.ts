import { BytesLike, ethers } from 'ethers'

// -- ABI tuple types for decoding --

const RCA_TUPLE =
  'tuple(uint64 deadline, uint64 endsAt, address payer, address dataService, address serviceProvider, uint256 maxInitialTokens, uint256 maxOngoingTokensPerSecond, uint32 minSecondsPerCollection, uint32 maxSecondsPerCollection, uint256 nonce, bytes metadata)'

const SIGNED_RCA_TUPLE = `tuple(${RCA_TUPLE} rca, bytes signature)`

const ACCEPT_METADATA_TUPLE = 'tuple(bytes32 subgraphDeploymentId, uint8 version, bytes terms)'

const TERMS_V1_TUPLE = 'tuple(uint256 tokensPerSecond, uint256 tokensPerEntityPerSecond)'

// -- Return types --

export interface RecurringCollectionAgreement {
  deadline: bigint
  endsAt: bigint
  payer: string
  dataService: string
  serviceProvider: string
  maxInitialTokens: bigint
  maxOngoingTokensPerSecond: bigint
  minSecondsPerCollection: bigint
  maxSecondsPerCollection: bigint
  nonce: bigint
  metadata: string
}

export interface SignedRCA {
  rca: RecurringCollectionAgreement
  signature: string
}

export interface AcceptIndexingAgreementMetadata {
  subgraphDeploymentId: string
  version: bigint
  terms: string
}

export interface IndexingAgreementTermsV1 {
  tokensPerSecond: bigint
  tokensPerEntityPerSecond: bigint
}

// -- Decoders --

export function decodeSignedRCA(data: BytesLike): SignedRCA {
  const [decoded] = ethers.AbiCoder.defaultAbiCoder().decode([SIGNED_RCA_TUPLE], data)
  return {
    rca: {
      deadline: decoded.rca.deadline,
      endsAt: decoded.rca.endsAt,
      payer: decoded.rca.payer,
      dataService: decoded.rca.dataService,
      serviceProvider: decoded.rca.serviceProvider,
      maxInitialTokens: decoded.rca.maxInitialTokens,
      maxOngoingTokensPerSecond: decoded.rca.maxOngoingTokensPerSecond,
      minSecondsPerCollection: decoded.rca.minSecondsPerCollection,
      maxSecondsPerCollection: decoded.rca.maxSecondsPerCollection,
      nonce: decoded.rca.nonce,
      metadata: decoded.rca.metadata,
    },
    signature: decoded.signature,
  }
}

export function decodeAcceptIndexingAgreementMetadata(data: BytesLike): AcceptIndexingAgreementMetadata {
  const [decoded] = ethers.AbiCoder.defaultAbiCoder().decode([ACCEPT_METADATA_TUPLE], data)
  return {
    subgraphDeploymentId: decoded.subgraphDeploymentId,
    version: decoded.version,
    terms: decoded.terms,
  }
}

export function decodeIndexingAgreementTermsV1(data: BytesLike): IndexingAgreementTermsV1 {
  const [decoded] = ethers.AbiCoder.defaultAbiCoder().decode([TERMS_V1_TUPLE], data)
  return {
    tokensPerSecond: decoded.tokensPerSecond,
    tokensPerEntityPerSecond: decoded.tokensPerEntityPerSecond,
  }
}
