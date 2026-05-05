/**
 * Constants for constructing RCA / RCAU offers against `RecurringCollector`.
 *
 * Source of truth for off-chain agents — the on-chain values are declared as
 * `internal constant` in RecurringCollector.sol (no ABI getters), so consumers
 * import these instead of querying the contract.
 *
 * EIP-712 typehashes are derived: `keccak256(toUtf8Bytes(typestring))`. Typed-data
 * signing helpers (e.g. ethers `signTypedData`) take the field tuples directly —
 * derive those from the typestring at the call site.
 */

/** Minimum seconds between collections enforced by the collector window check. */
export const RC_MIN_SECONDS_COLLECTION_WINDOW = 600

/** Conditions bitmask: agreement requires payer eligibility check (IProviderEligibility). */
export const RC_CONDITION_ELIGIBILITY_CHECK = 1 << 0

/**
 * Conditions bitmask: agreement uses IAgreementOwner callbacks
 * (beforeCollection / afterCollection). Validated via ERC-165 at acceptance,
 * so callback dispatch is locked to acceptance time and unaffected by
 * post-acceptance payer code changes (e.g. EIP-7702 delegation swaps).
 *
 * Off-chain agents constructing RCAs against a contract payer that relies on
 * these callbacks (such as RecurringAgreementManager for JIT escrow top-up)
 * must set this bit; otherwise the callbacks are skipped silently.
 */
export const RC_CONDITION_AGREEMENT_OWNER = 1 << 1

/** EIP-712 typestring for a RecurringCollectionAgreement (RCA). */
export const RC_EIP712_RCA_TYPESTRING =
  'RecurringCollectionAgreement(uint64 deadline,uint64 endsAt,address payer,address dataService,address serviceProvider,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,uint16 conditions,uint256 nonce,bytes metadata)'

/** EIP-712 typestring for a RecurringCollectionAgreementUpdate (RCAU). */
export const RC_EIP712_RCAU_TYPESTRING =
  'RecurringCollectionAgreementUpdate(bytes16 agreementId,uint64 deadline,uint64 endsAt,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,uint16 conditions,uint32 nonce,bytes metadata)'
