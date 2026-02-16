# Integration Guide

This guide provides practical examples for integrating with the indexing payments system.

## For Payers (Data Consumers)

### Creating and Signing an RCA

```typescript
import { ethers } from 'ethers'

// Define EIP-712 domain
const domain = {
  name: 'RecurringCollector',
  version: '1.0',
  chainId: 1, // Mainnet
  verifyingContract: RECURRING_COLLECTOR_ADDRESS,
}

// Define RCA type
const types = {
  RecurringCollectionAgreement: [
    { name: 'deadline', type: 'uint64' },
    { name: 'endsAt', type: 'uint64' },
    { name: 'payer', type: 'address' },
    { name: 'dataService', type: 'address' },
    { name: 'serviceProvider', type: 'address' },
    { name: 'maxInitialTokens', type: 'uint256' },
    { name: 'maxOngoingTokensPerSecond', type: 'uint256' },
    { name: 'minSecondsPerCollection', type: 'uint32' },
    { name: 'maxSecondsPerCollection', type: 'uint32' },
    { name: 'nonce', type: 'uint256' },
    { name: 'metadata', type: 'bytes' },
  ],
}

// Encode indexing agreement terms V1
function encodeTermsV1(tokensPerSecond: bigint, tokensPerEntityPerSecond: bigint): string {
  return ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256'], [tokensPerSecond, tokensPerEntityPerSecond])
}

// Encode accept metadata
function encodeAcceptMetadata(subgraphDeploymentId: string, version: number, terms: string): string {
  return ethers.AbiCoder.defaultAbiCoder().encode(['bytes32', 'uint8', 'bytes'], [subgraphDeploymentId, version, terms])
}

// Create and sign RCA
async function createAndSignRCA(signer: ethers.Signer) {
  const now = Math.floor(Date.now() / 1000)

  // Indexing agreement terms
  const tokensPerSecond = ethers.parseEther('0.01') // 0.01 GRT/second
  const tokensPerEntityPerSecond = ethers.parseEther('0.001') // 0.001 GRT/entity/second
  const terms = encodeTermsV1(tokensPerSecond, tokensPerEntityPerSecond)

  const metadata = encodeAcceptMetadata(
    SUBGRAPH_DEPLOYMENT_ID,
    0, // Version 0 = V1
    terms,
  )

  const rca = {
    deadline: now + 86400, // 24 hours to accept
    endsAt: now + 30 * 86400, // 30 days duration
    payer: await signer.getAddress(),
    dataService: SUBGRAPH_SERVICE_ADDRESS,
    serviceProvider: INDEXER_ADDRESS,
    maxInitialTokens: ethers.parseEther('100'), // 100 GRT first collection bonus
    maxOngoingTokensPerSecond: ethers.parseEther('1'), // 1 GRT/second rate limit
    minSecondsPerCollection: 3600, // Min 1 hour between collections
    maxSecondsPerCollection: 7200, // Max 2 hours between collections
    nonce: generateNonce(), // Random nonce to prevent collisions
    metadata: metadata,
  }

  const signature = await signer.signTypedData(domain, types, rca)

  return { rca, signature }
}

function generateNonce(): bigint {
  return BigInt('0x' + ethers.randomBytes(32).toString('hex'))
}

// Usage
const { rca, signature } = await createAndSignRCA(payerSigner)
// Send { rca, signature } to indexer
```

### Updating an RCA

```typescript
// Define RCAU type
const rcauTypes = {
  RecurringCollectionAgreementUpdate: [
    { name: 'agreementId', type: 'bytes16' },
    { name: 'deadline', type: 'uint64' },
    { name: 'endsAt', type: 'uint64' },
    { name: 'maxInitialTokens', type: 'uint256' },
    { name: 'maxOngoingTokensPerSecond', type: 'uint256' },
    { name: 'minSecondsPerCollection', type: 'uint32' },
    { name: 'maxSecondsPerCollection', type: 'uint32' },
    { name: 'nonce', type: 'uint32' },
    { name: 'metadata', type: 'bytes' },
  ],
}

// Encode update metadata
function encodeUpdateMetadata(version: number, terms: string): string {
  return ethers.AbiCoder.defaultAbiCoder().encode(['uint8', 'bytes'], [version, terms])
}

async function createAndSignRCAU(signer: ethers.Signer, agreementId: string, currentNonce: number) {
  const now = Math.floor(Date.now() / 1000)

  // New terms (e.g., increase rates)
  const newTokensPerSecond = ethers.parseEther('0.02') // Double the rate
  const newTokensPerEntityPerSecond = ethers.parseEther('0.002')
  const newTerms = encodeTermsV1(newTokensPerSecond, newTokensPerEntityPerSecond)

  const metadata = encodeUpdateMetadata(0, newTerms)

  const rcau = {
    agreementId: agreementId,
    deadline: now + 86400,
    endsAt: now + 30 * 86400, // Can extend duration
    maxInitialTokens: ethers.parseEther('0'), // No bonus on updates
    maxOngoingTokensPerSecond: ethers.parseEther('2'), // Increase rate limit
    minSecondsPerCollection: 3600,
    maxSecondsPerCollection: 7200,
    nonce: currentNonce + 1, // Must be exactly currentNonce + 1
    metadata: metadata,
  }

  const signature = await signer.signTypedData(domain, rcauTypes, rcau)

  return { rcau, signature }
}
```

### Authorizing a Signer

If you want to use a different account to sign RCAs:

```typescript
// In RecurringCollector, authorize a signer
const recurringCollector = new ethers.Contract(RECURRING_COLLECTOR_ADDRESS, RECURRING_COLLECTOR_ABI, payerSigner)

// Authorize signer
await recurringCollector.authorizeSigner(signerAddress, proof)

// Now signerAddress can sign RCAs on behalf of payerSigner
```

### Canceling an Agreement

```typescript
const subgraphService = new ethers.Contract(SUBGRAPH_SERVICE_ADDRESS, SUBGRAPH_SERVICE_ABI, payerSigner)

// Cancel by payer (allows final collection)
await subgraphService.cancelIndexingAgreementByPayer(agreementId)
```

## For Indexers (Service Providers)

### Accepting an RCA

```typescript
const subgraphService = new ethers.Contract(SUBGRAPH_SERVICE_ADDRESS, SUBGRAPH_SERVICE_ABI, indexerSigner)

// Received { rca, signature } from payer
const signedRCA = {
  rca: rca,
  signature: signature,
}

// Accept for a specific allocation
const tx = await subgraphService.acceptIndexingAgreement(allocationId, signedRCA)

const receipt = await tx.wait()

// Parse agreementId from events
const acceptedEvent = receipt.logs.find((log) => log.topics[0] === ethers.id('IndexingAgreementAccepted(...)'))
const agreementId = acceptedEvent.topics[3] // Indexed agreementId
```

### Collecting Payment

```typescript
// Prepare collection data
function encodeCollectionDataV1(
  entities: bigint,
  poi: string,
  poiBlockNumber: bigint,
  metadata: string,
  maxSlippage: bigint,
): string {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    ['uint256', 'bytes32', 'uint256', 'bytes', 'uint256'],
    [entities, poi, poiBlockNumber, metadata, maxSlippage],
  )
}

async function collectPayment(
  indexerSigner: ethers.Signer,
  agreementId: string,
  entities: bigint,
  poi: string,
  poiBlockNumber: bigint,
) {
  const subgraphService = new ethers.Contract(SUBGRAPH_SERVICE_ADDRESS, SUBGRAPH_SERVICE_ABI, indexerSigner)

  // Calculate expected tokens
  const agreement = await subgraphService.getIndexingAgreement(agreementId)
  const collectionInfo = await recurringCollector.getCollectionInfo(agreement.collectorAgreement)

  const expectedTokens = calculateExpectedTokens(
    collectionInfo.collectionSeconds,
    agreement.collectorAgreement, // Contains terms
    entities,
  )

  // Set slippage tolerance (5%)
  const maxSlippage = (expectedTokens * 5n) / 100n

  const data = encodeCollectionDataV1(
    entities,
    poi,
    poiBlockNumber,
    '0x', // Optional metadata
    maxSlippage,
  )

  // Collect via SubgraphService
  const indexerAddress = await indexerSigner.getAddress()
  const paymentsDestination = await subgraphService.paymentsDestination(indexerAddress)

  const tx = await subgraphService.collect(indexerAddress, agreementId, paymentsDestination || indexerAddress, data)

  const receipt = await tx.wait()

  // Parse collected amount from events
  const collectedEvent = receipt.logs.find((log) => log.topics[0] === ethers.id('IndexingFeesCollectedV1(...)'))

  return receipt
}

function calculateExpectedTokens(collectionSeconds: bigint, agreement: any, entities: bigint): bigint {
  const termsV1 = agreement.termsV1 // From IndexingAgreement
  return collectionSeconds * (termsV1.tokensPerSecond + termsV1.tokensPerEntityPerSecond * entities)
}
```

### Updating an Agreement

```typescript
// Received { rcau, signature } from payer
const signedRCAU = {
  rcau: rcau,
  signature: signature,
}

const indexerAddress = await indexerSigner.getAddress()

const tx = await subgraphService.updateIndexingAgreement(indexerAddress, signedRCAU)

await tx.wait()
```

### Canceling an Agreement

```typescript
const indexerAddress = await indexerSigner.getAddress()

const tx = await subgraphService.cancelIndexingAgreement(indexerAddress, agreementId)

await tx.wait()
// No further collections possible
```

### Monitoring Agreement Status

```typescript
// Get full agreement details
const agreement = await subgraphService.getIndexingAgreement(agreementId)

console.log('Allocation:', agreement.agreement.allocationId)
console.log('Version:', agreement.agreement.version)
console.log('State:', agreement.collectorAgreement.state)
console.log('Payer:', agreement.collectorAgreement.payer)
console.log('Service Provider:', agreement.collectorAgreement.serviceProvider)

// Check if collectable
const recurringCollector = new ethers.Contract(RECURRING_COLLECTOR_ADDRESS, RECURRING_COLLECTOR_ABI, provider)

const [isCollectable, collectionSeconds, reason] = await recurringCollector.getCollectionInfo(
  agreement.collectorAgreement,
)

if (isCollectable) {
  console.log(`Can collect for ${collectionSeconds} seconds`)
} else {
  console.log(`Not collectable: ${reason}`)
}
```

## Automated Collection Bot

Example bot that automatically collects payments:

```typescript
import { ethers } from 'ethers'

class IndexingPaymentCollector {
  constructor(
    private provider: ethers.Provider,
    private indexerSigner: ethers.Signer,
    private subgraphService: ethers.Contract,
    private recurringCollector: ethers.Contract,
  ) {}

  async monitorAgreement(agreementId: string) {
    console.log(`Monitoring agreement ${agreementId}`)

    while (true) {
      try {
        const agreement = await this.subgraphService.getIndexingAgreement(agreementId)

        // Check if collectable
        const [isCollectable, collectionSeconds, reason] = await this.recurringCollector.getCollectionInfo(
          agreement.collectorAgreement,
        )

        if (!isCollectable) {
          console.log(`Not collectable: ${reason}`)
          await this.sleep(60000) // Wait 1 minute
          continue
        }

        const minSeconds = agreement.collectorAgreement.minSecondsPerCollection

        if (collectionSeconds < minSeconds) {
          const waitTime = (minSeconds - Number(collectionSeconds)) * 1000
          console.log(`Waiting ${waitTime}ms until min collection window`)
          await this.sleep(waitTime + 10000) // Add 10s buffer
          continue
        }

        // Attempt collection
        console.log(`Collecting for ${collectionSeconds} seconds...`)
        await this.collect(agreementId, agreement)
      } catch (error) {
        console.error('Error:', error)
        await this.sleep(60000) // Wait 1 minute on error
      }
    }
  }

  async collect(agreementId: string, agreement: any) {
    // Get indexing data from your indexer
    const { entities, poi, blockNumber } = await this.getIndexingData(agreement.agreement.allocationId)

    // Calculate expected tokens
    const collectionInfo = await this.recurringCollector.getCollectionInfo(agreement.collectorAgreement)

    const expectedTokens = this.calculateExpectedTokens(collectionInfo.collectionSeconds, agreement, entities)

    // 10% slippage tolerance
    const maxSlippage = (expectedTokens * 10n) / 100n

    const data = this.encodeCollectionDataV1(entities, poi, blockNumber, '0x', maxSlippage)

    const indexerAddress = await this.indexerSigner.getAddress()
    const paymentsDestination = await this.subgraphService.paymentsDestination(indexerAddress)

    const tx = await this.subgraphService.collect(
      indexerAddress,
      agreementId,
      paymentsDestination || indexerAddress,
      data,
    )

    const receipt = await tx.wait()
    console.log(`Collected! Tx: ${receipt.hash}`)
  }

  async getIndexingData(allocationId: string) {
    // Query your indexer for POI and entity count
    // This is implementation-specific
    return {
      entities: 1000n,
      poi: '0x1234...', // 32 bytes
      blockNumber: 12345678n,
    }
  }

  calculateExpectedTokens(collectionSeconds: bigint, agreement: any, entities: bigint): bigint {
    // Access terms from the agreement
    const tokensPerSecond = agreement.collectorAgreement.tokensPerSecond
    const tokensPerEntityPerSecond = agreement.collectorAgreement.tokensPerEntityPerSecond

    return collectionSeconds * (tokensPerSecond + tokensPerEntityPerSecond * entities)
  }

  encodeCollectionDataV1(
    entities: bigint,
    poi: string,
    poiBlockNumber: bigint,
    metadata: string,
    maxSlippage: bigint,
  ): string {
    return ethers.AbiCoder.defaultAbiCoder().encode(
      ['uint256', 'bytes32', 'uint256', 'bytes', 'uint256'],
      [entities, poi, poiBlockNumber, metadata, maxSlippage],
    )
  }

  sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms))
  }
}

// Usage
const collector = new IndexingPaymentCollector(
  provider,
  indexerSigner,
  subgraphServiceContract,
  recurringCollectorContract,
)

// Start monitoring (runs forever)
collector.monitorAgreement(AGREEMENT_ID)
```

## Event Listening

Monitor events to track agreement activity:

```typescript
// Listen for agreements accepted
subgraphService.on(
  'IndexingAgreementAccepted',
  (indexer, payer, agreementId, allocationId, subgraphDeploymentId, version, terms) => {
    console.log(`Agreement accepted: ${agreementId}`)
    console.log(`Indexer: ${indexer}`)
    console.log(`Payer: ${payer}`)
    console.log(`Allocation: ${allocationId}`)
  },
)

// Listen for collections
subgraphService.on(
  'IndexingFeesCollectedV1',
  (
    indexer,
    payer,
    agreementId,
    allocationId,
    subgraphDeploymentId,
    currentEpoch,
    tokensCollected,
    entities,
    poi,
    poiBlockNumber,
    metadata,
  ) => {
    console.log(`Payment collected: ${ethers.formatEther(tokensCollected)} GRT`)
    console.log(`Entities: ${entities}`)
    console.log(`POI: ${poi}`)
  },
)

// Listen for cancellations
subgraphService.on('IndexingAgreementCanceled', (indexer, payer, agreementId, canceledOnBehalfOf) => {
  console.log(`Agreement canceled: ${agreementId}`)
  console.log(`Canceled by: ${canceledOnBehalfOf}`)
})
```

## Best Practices

### For Payers

1. **Set reasonable rate limits**: `maxOngoingTokensPerSecond` should be high enough to cover expected usage but low enough to prevent unexpected charges
2. **Choose appropriate collection windows**: Balance between frequent updates and transaction costs
3. **Use maxInitialTokens**: Provide upfront payment to cover initial setup costs
4. **Monitor escrow balance**: Ensure sufficient funds for ongoing payments
5. **Consider authorized signers**: Use a hot wallet for signing RCAs while keeping funds in cold storage

### For Indexers

1. **Validate RCAs before accepting**: Check terms, duration, and rate limits
2. **Monitor collection windows**: Collect regularly to avoid hitting `maxSecondsPerCollection`
3. **Set appropriate maxSlippage**: Account for potential rate limiting
4. **Automate collections**: Use a bot to ensure timely collections
5. **Monitor agreement state**: Track cancellations and expirations
6. **Keep accurate POI**: Essential for disputes and validation

### Security Considerations

1. **Validate all signatures**: Never trust unsigned agreements
2. **Check agreement state**: Before operations, verify state is appropriate
3. **Handle slippage**: Always set `maxSlippage` to prevent unexpected behavior
4. **Monitor events**: Track all state changes for auditing
5. **Test thoroughly**: Use testnets before mainnet deployment

## Related Documentation

- [Architecture](./Architecture.md) - System components and relationships
- [Agreement Lifecycle](./AgreementLifecycle.md) - State transitions and flows
- [Payment Calculation](./PaymentCalculation.md) - Fee computation details
