import assert from 'node:assert/strict'
import { ethers } from 'ethers'

import {
  decodeSignedRCA,
  decodeAcceptIndexingAgreementMetadata,
  decodeIndexingAgreementTermsV1,
  encodeCollectIndexingFeesData,
} from '../dist/core/index.js'

const coder = ethers.AbiCoder.defaultAbiCoder()

// -- decodeSignedRCA round-trip --

{
  const rca = {
    deadline: 1000000n,
    endsAt: 2000000n,
    payer: '0x1111111111111111111111111111111111111111',
    dataService: '0x2222222222222222222222222222222222222222',
    serviceProvider: '0x3333333333333333333333333333333333333333',
    maxInitialTokens: 500n * 10n ** 18n,
    maxOngoingTokensPerSecond: 1n * 10n ** 15n,
    minSecondsPerCollection: 3600n,
    maxSecondsPerCollection: 86400n,
    nonce: 42n,
    metadata: '0xdeadbeef',
  }
  const signature = '0x' + 'ab'.repeat(65)

  const encoded = coder.encode(
    [
      'tuple(tuple(uint64 deadline, uint64 endsAt, address payer, address dataService, address serviceProvider, uint256 maxInitialTokens, uint256 maxOngoingTokensPerSecond, uint32 minSecondsPerCollection, uint32 maxSecondsPerCollection, uint256 nonce, bytes metadata) rca, bytes signature)',
    ],
    [{ rca, signature }],
  )

  const decoded = decodeSignedRCA(encoded)

  assert.equal(decoded.rca.deadline, rca.deadline)
  assert.equal(decoded.rca.endsAt, rca.endsAt)
  assert.equal(decoded.rca.payer, rca.payer)
  assert.equal(decoded.rca.dataService, rca.dataService)
  assert.equal(decoded.rca.serviceProvider, rca.serviceProvider)
  assert.equal(decoded.rca.maxInitialTokens, rca.maxInitialTokens)
  assert.equal(decoded.rca.maxOngoingTokensPerSecond, rca.maxOngoingTokensPerSecond)
  assert.equal(decoded.rca.minSecondsPerCollection, rca.minSecondsPerCollection)
  assert.equal(decoded.rca.maxSecondsPerCollection, rca.maxSecondsPerCollection)
  assert.equal(decoded.rca.nonce, rca.nonce)
  assert.equal(decoded.rca.metadata, rca.metadata)
  assert.equal(decoded.signature, signature)
  console.log('PASS: decodeSignedRCA round-trip')
}

// -- decodeSignedRCA with empty metadata --

{
  const rca = {
    deadline: 100n,
    endsAt: 200n,
    payer: '0x' + '00'.repeat(20),
    dataService: '0x' + '00'.repeat(20),
    serviceProvider: '0x' + '00'.repeat(20),
    maxInitialTokens: 0n,
    maxOngoingTokensPerSecond: 0n,
    minSecondsPerCollection: 0n,
    maxSecondsPerCollection: 0n,
    nonce: 0n,
    metadata: '0x',
  }
  const signature = '0x'

  const encoded = coder.encode(
    [
      'tuple(tuple(uint64 deadline, uint64 endsAt, address payer, address dataService, address serviceProvider, uint256 maxInitialTokens, uint256 maxOngoingTokensPerSecond, uint32 minSecondsPerCollection, uint32 maxSecondsPerCollection, uint256 nonce, bytes metadata) rca, bytes signature)',
    ],
    [{ rca, signature }],
  )

  const decoded = decodeSignedRCA(encoded)
  assert.equal(decoded.rca.metadata, '0x')
  assert.equal(decoded.signature, '0x')
  console.log('PASS: decodeSignedRCA with empty metadata')
}

// -- decodeAcceptIndexingAgreementMetadata round-trip --

{
  const subgraphDeploymentId = ethers.id('my-subgraph')
  const version = 0n // V1 = 0 in the enum
  const terms = coder.encode(['uint256', 'uint256'], [1000n, 2000n])

  const encoded = coder.encode(
    ['tuple(bytes32 subgraphDeploymentId, uint8 version, bytes terms)'],
    [{ subgraphDeploymentId, version, terms }],
  )

  const decoded = decodeAcceptIndexingAgreementMetadata(encoded)

  assert.equal(decoded.subgraphDeploymentId, subgraphDeploymentId)
  assert.equal(decoded.version, version)
  assert.equal(decoded.terms, terms)
  console.log('PASS: decodeAcceptIndexingAgreementMetadata round-trip')
}

// -- decodeAcceptIndexingAgreementMetadata with empty terms --

{
  const encoded = coder.encode(
    ['tuple(bytes32 subgraphDeploymentId, uint8 version, bytes terms)'],
    [{ subgraphDeploymentId: ethers.ZeroHash, version: 0, terms: '0x' }],
  )

  const decoded = decodeAcceptIndexingAgreementMetadata(encoded)
  assert.equal(decoded.terms, '0x')
  console.log('PASS: decodeAcceptIndexingAgreementMetadata with empty terms')
}

// -- decodeAcceptIndexingAgreementMetadata with unknown version --

{
  const encoded = coder.encode(
    ['tuple(bytes32 subgraphDeploymentId, uint8 version, bytes terms)'],
    [{ subgraphDeploymentId: ethers.ZeroHash, version: 255, terms: '0x' }],
  )

  const decoded = decodeAcceptIndexingAgreementMetadata(encoded)
  assert.equal(decoded.version, 255n)
  console.log('PASS: decodeAcceptIndexingAgreementMetadata with unknown version')
}

// -- decodeIndexingAgreementTermsV1 round-trip --

{
  const tokensPerSecond = 1000n * 10n ** 18n
  const tokensPerEntityPerSecond = 5n * 10n ** 15n

  const encoded = coder.encode(['tuple(uint256 tokensPerSecond, uint256 tokensPerEntityPerSecond)'], [{ tokensPerSecond, tokensPerEntityPerSecond }])

  const decoded = decodeIndexingAgreementTermsV1(encoded)

  assert.equal(decoded.tokensPerSecond, tokensPerSecond)
  assert.equal(decoded.tokensPerEntityPerSecond, tokensPerEntityPerSecond)
  console.log('PASS: decodeIndexingAgreementTermsV1 round-trip')
}

// -- encodeCollectIndexingFeesData round-trip --

{
  const agreementId = '0x' + 'ab'.repeat(16)
  const entities = 1000n
  const poi = ethers.id('test-poi')
  const poiBlockNumber = 12345n
  const metadata = '0xdeadbeef'
  const maxSlippage = 100n

  const encoded = encodeCollectIndexingFeesData(agreementId, entities, poi, poiBlockNumber, metadata, maxSlippage)

  // Decode outer: (bytes16, bytes)
  const [decodedAgreementId, innerData] = coder.decode(['bytes16', 'bytes'], encoded)
  assert.equal(decodedAgreementId, agreementId)

  // Decode inner: CollectIndexingFeeDataV1
  const [decodedEntities, decodedPoi, decodedPoiBlockNumber, decodedMetadata, decodedMaxSlippage] = coder.decode(
    ['uint256', 'bytes32', 'uint256', 'bytes', 'uint256'],
    innerData,
  )
  assert.equal(decodedEntities, entities)
  assert.equal(decodedPoi, poi)
  assert.equal(decodedPoiBlockNumber, poiBlockNumber)
  assert.equal(decodedMetadata, metadata)
  assert.equal(decodedMaxSlippage, maxSlippage)
  console.log('PASS: encodeCollectIndexingFeesData round-trip')
}

console.log('\nAll tests passed.')
