# RewardsEligibilityOracle

The RewardsEligibilityOracle is a smart contract that manages indexer eligibility for receiving rewards. It implements a time-based eligibility system where indexers must be explicitly marked as eligible by authorized oracles to receive rewards.

## Overview

The contract operates on a "deny by default" principle - indexers are not eligible for rewards until their eligibility is explicitly validated by an authorized oracle. (See edge case below for extremely large eligibility periods.) After eligibility is initially validated or renewed, indexers remain eligible for a configurable period before their eligibility expires and needs to be renewed again. We generally refer to all validation as "renewal" for simplicity.

**Very large eligibility period edge case**: If the eligibility period is set to an extremely large value that exceeds the current block timestamp relative to the genesis block, all indexers (including those who have never been registered) will be considered eligible. This is an edge case; if configured with an eligibility period that includes the genesis block, all indexers are eligible.

## Key Features

- **Time-based Eligibility**: Indexers are eligible for a configurable period (default: 14 days)
- **Oracle-based Renewal**: Only authorized oracles can renew indexer eligibility
- **Global Toggle**: Eligibility validation can be globally enabled/disabled
- **Timeout Mechanism**: If oracles don't update for too long, all indexers are automatically eligible
- **Role-based Access Control**: Uses hierarchical roles for governance and operations

## Architecture

### Roles

The contract uses four main roles:

- **GOVERNOR_ROLE**: Can grant/revoke operator roles and perform governance actions
- **OPERATOR_ROLE**: Can configure contract parameters and manage oracle roles
- **ORACLE_ROLE**: Can approve indexers for rewards
- **PAUSE_ROLE**: Can pause contract operations (inherited from BaseUpgradeable)

### Storage

The contract uses ERC-7201 namespaced storage to prevent storage collisions in upgradeable contracts:

- `indexerEligibilityTimestamps`: Maps indexer addresses to their last eligibility timestamp
- `eligibilityPeriod`: Duration (in seconds) for which eligibility lasts (default: 14 days)
- `eligibilityValidationEnabled`: Global flag to enable/disable eligibility validation (default: false, to be enabled by operator when ready)
- `oracleUpdateTimeout`: Timeout after which all indexers are automatically eligible (default: 7 days)
- `lastOracleUpdateTime`: Timestamp of the last oracle update

## Core Functions

### Oracle Management

Oracle roles are managed through the standard AccessControl functions inherited from BaseUpgradeable:

- **`grantRole(bytes32 role, address account)`**: Grant oracle privileges to an account (OPERATOR_ROLE only)
- **`revokeRole(bytes32 role, address account)`**: Revoke oracle privileges from an account (OPERATOR_ROLE only)
- **`hasRole(bytes32 role, address account)`**: Check if an account has oracle privileges

The `ORACLE_ROLE` constant can be used as the role parameter for these functions.

### Configuration

#### `setEligibilityPeriod(uint256 eligibilityPeriod) → bool`

- **Access**: OPERATOR_ROLE only
- **Purpose**: Set how long indexer eligibility lasts
- **Parameters**: `eligibilityPeriod` - Duration in seconds
- **Returns**: Always true for current implementation
- **Events**: Emits `EligibilityPeriodUpdated` if value changes

#### `setOracleUpdateTimeout(uint256 oracleUpdateTimeout) → bool`

- **Access**: OPERATOR_ROLE only
- **Purpose**: Set timeout after which all indexers are automatically eligible
- **Parameters**: `oracleUpdateTimeout` - Timeout duration in seconds
- **Returns**: Always true for current implementation
- **Events**: Emits `OracleUpdateTimeoutUpdated` if value changes

#### `setEligibilityValidation(bool enabled) → bool`

- **Access**: OPERATOR_ROLE only
- **Purpose**: Enable or disable eligibility validation globally
- **Parameters**: `enabled` - True to enable, false to disable
- **Returns**: Always true for current implementation
- **Events**: Emits `EligibilityValidationUpdated` if state changes

### Indexer Management

#### `renewIndexerEligibility(address[] calldata indexers, bytes calldata data) → uint256`

- **Access**: ORACLE_ROLE only
- **Purpose**: Renew eligibility for indexers to receive rewards
- **Parameters**:
  - `indexers` - Array of indexer addresses (zero addresses ignored)
  - `data` - Arbitrary calldata for future extensions
- **Returns**: Number of indexers whose eligibility renewal timestamp was updated
- **Events**:
  - Emits `IndexerEligibilityData` with oracle and data
  - Emits `IndexerEligibilityRenewed` for each indexer whose eligibility was renewed
- **Notes**:
  - Updates `lastOracleUpdateTime` to current block timestamp
  - Only updates timestamp if less than current block timestamp
  - Ignores zero addresses and duplicate updates within same block

### View Functions

#### `isEligible(address indexer) → bool`

- **Purpose**: Check if an indexer is eligible for rewards
- **Logic**:
  1. If eligibility validation is disabled → return true
  2. If oracle timeout exceeded → return true
  3. Otherwise → check if indexer's eligibility is still valid
- **Returns**: True if indexer is eligible, false otherwise

#### `getEligibilityRenewalTime(address indexer) → uint256`

- **Purpose**: Get the timestamp when indexer's eligibility was last renewed
- **Returns**: Timestamp or 0 if eligibility was never renewed

#### `getEligibilityPeriod() → uint256`

- **Purpose**: Get the current eligibility period
- **Returns**: Duration in seconds

#### `getOracleUpdateTimeout() → uint256`

- **Purpose**: Get the current oracle update timeout
- **Returns**: Duration in seconds

#### `getLastOracleUpdateTime() → uint256`

- **Purpose**: Get when oracles last updated
- **Returns**: Timestamp of last oracle update

#### `getEligibilityValidation() → bool`

- **Purpose**: Get eligibility validation state
- **Returns**: True if enabled, false if disabled

## Eligibility Logic

An indexer is considered eligible if ANY of the following conditions are met:

1. **Valid eligibility** (`block.timestamp < indexerEligibilityTimestamps[indexer] + eligibilityPeriod`)
2. **Oracle timeout exceeded** (`lastOracleUpdateTime + oracleUpdateTimeout < block.timestamp`)
3. **Eligibility validation is disabled** (`eligibilityValidationEnabled = false`)

This design ensures that:

- The system fails open if oracles stop updating
- Operators can disable eligibility validation entirely if needed
- Individual indexer eligibility has time limits

### Edge Case: Large Eligibility Periods

The eligibility check `block.timestamp < indexerEligibilityTimestamps[indexer] + eligibilityPeriod` has specific behavior when the eligibility period is set to an extremely large value:

- For indexers who have never been registered, `indexerEligibilityTimestamps[indexer]` is 0 (zero-initialized storage)
- If `block.timestamp < eligibilityPeriod`, then `block.timestamp < 0 + eligibilityPeriod`
- This means **all indexers are eligible**, including those who have never been explicitly approved

For normal operations with reasonable eligibility periods (e.g., 14 days), indexers who have never been registered will correctly be ineligible since `block.timestamp < 0 + 14 days` will be false for any realistic block timestamp.

In normal operation, the first condition is expected to be the only one that applies. The other two conditions provide fail-safes for oracle failures, or in extreme cases an operator override. For normal operational failure of oracles, the system gracefully degrades into a "allow all" mode. This mechanism is not perfect in that oracles could still be updating but allowing far fewer indexers than they should. However this is regarded as simple mechanism that is good enough to start with and provide a foundation for future improvements and decentralization.

While this simple model allows the criteria for providing good service to evolve over time (which is essential for the long-term health of the network), it captures sufficient information on-chain for indexers to be able to monitor their eligibility. This is important to ensure that even in the absence of other sources of information regarding observed indexer service, indexers have good transparency about if they are being observed to be providing good service, and for how long their current approval is valid.

It might initially seem safer to allow indexers by default unless an oracle explicitly denies an indexer. While that might seem safer from the perspective of the RewardsEligibilityOracle in isolation, in the absence of a more sophisticated voting system it would make the system vulnerable to a single bad oracle denying many indexers. The design of deny by default is better suited to allowing redundant oracles to be working in parallel, where only one needs to be successfully detecting indexers that are providing quality service, as well as eventually allowing different oracles to have different approval criteria and/or inputs. Therefore deny by default facilitates a more resilient and open oracle system that is less vulnerable to a single points of failure, and more open to increasing decentralization over time.

In general to be rewarded for providing service on The Graph, there is expected to be proof provided of good operation (such as for proof of indexing). While proof should be required to receive rewards, the system is designed for participants to have confidence in being able to adequately prove good operation (and in the case of oracles, be seen by at least one observer) that is sufficient to allow the indexer to receive rewards. The oracle model is in general far more suited to collecting evidence of good operation, from multiple independent observers, rather than any observer being able to establish that an indexer is not providing good service.

## Operational Considerations

### Race Conditions with Configuration Changes

Configuration changes can create race conditions with in-flight reward claim transactions, potentially causing indexers to permanently lose rewards.

When an indexer submits a transaction to claim rewards through the RewardsManager:

1. The indexer is eligible at the time of transaction submission
2. The transaction enters the mempool and waits for execution
3. A configuration change occurs (e.g., reducing `eligibilityPeriod` or enabling `eligibilityValidation`)
4. The transaction executes after the indexer is no longer eligible
5. **The indexer is denied rewards** resulting in permanent loss for the indexer

This occurs because the RewardsManager's `takeRewards()` function returns 0 rewards for ineligible indexers, but the calling contract (Staking or SubgraphService) still marks the allocation as processed.

Circumstances potentially leading to this race condition:

1. **Reducing eligibility period** (`setEligibilityPeriod`):
   - Shortening the eligibility window may cause recently-approved indexers to become ineligible
   - Indexers near the end of their eligibility period become ineligible immediately

2. **Enabling eligibility validation** (`setEligibilityValidation`):
   - Switching from disabled (all eligible) to enabled (oracle-based)
   - Indexers without recent oracle renewals become ineligible immediately

3. **Oracle update delays**:
   - If oracles do not renew an indexer's eligibility before it expires
   - Combined with network congestion delaying claim transactions

4. **Network conditions**:
   - High gas prices causing indexers to delay transaction submission
   - Network congestion delaying transaction execution
   - Multiple blocks between submission and execution

#### Mitigation Strategies

Operators and indexers should implement these practices:

**For Operators:**

1. **Announce configuration changes in advance**:
   - Publish planned changes to eligibility period or validation state
   - Provide sufficient notice (e.g., 24-48 hours) before executing changes
   - Use governance forums, Discord, or official communication channels

2. **Implement two-step process for critical changes**:
   - First transaction: Announce the pending change with a delay period
   - Second transaction: Execute the change after the delay
   - This is a governance/operational practice, not enforced by the contract

3. **Avoid sudden reductions in eligibility**:
   - When reducing eligibility period, consider gradual reductions
   - Monitor pending transactions in the mempool before making changes
   - Time changes for periods of low network activity

4. **Coordinate with oracle operations**:
   - Ensure oracles are actively renewing indexer eligibility
   - Verify oracle health before enabling eligibility validation
   - Monitor `lastOracleUpdateTime` to detect oracle failures

**For Indexers:**

1. **Monitor eligibility status closely**:
   - Regularly check `isEligible()` and `getEligibilityRenewalTime()`
   - Calculate when eligibility will expire (`renewalTime + eligibilityPeriod`)
   - Set up alerts for approaching expiration

2. **Claim rewards with sufficient margin**:
   - Don't wait until the last moment of eligibility period
   - Account for network congestion and gas price volatility
   - Consider claiming more frequently rather than in large batches

3. **Watch for configuration change announcements**:
   - Monitor governance communications and proposals
   - Subscribe to operator announcements
   - Plan claim transactions around announced changes

4. **Use appropriate gas pricing**:
   - During announced configuration changes, use higher gas prices
   - Ensure transactions execute quickly during critical windows
   - Monitor transaction status and resubmit if necessary

5. **Understand the risk**:
   - Be aware that rewards can be permanently lost due to race conditions
   - Factor this risk into reward claiming strategies

#### Monitoring and Detection

Operators should monitor:

- `RewardsDeniedDueToEligibility` events
- Time between configuration changes and claim transactions

Indexers should monitor:

- Their own eligibility status via `isEligible()`
- `EligibilityPeriodUpdated` events
- `EligibilityValidationUpdated` events
- `IndexerEligibilityRenewed` events for their address

## Events

```solidity
event IndexerEligibilityData(address indexed oracle, bytes data);
event IndexerEligibilityRenewed(address indexed indexer, address indexed oracle);
event EligibilityPeriodUpdated(uint256 indexed oldPeriod, uint256 indexed newPeriod);
event EligibilityValidationUpdated(bool indexed enabled);
event OracleUpdateTimeoutUpdated(uint256 indexed oldTimeout, uint256 indexed newTimeout);
```

## Default Configuration

- **Eligibility Period**: 14 days (1,209,600 seconds)
- **Oracle Update Timeout**: 7 days (604,800 seconds)
- **Eligibility Validation**: Disabled (false)
- **Last Oracle Update Time**: 0 (never updated)

The system is deployed with reasonable defaults but can be adjusted as required. Eligibility validation is disabled by default as the expectation is to first see oracles successfully marking indexers as eligible and having suitably established eligible indexers before enabling.

## Usage Patterns

### Initial Setup

1. Deploy contract with Graph Token address
2. Initialize with governor address
3. Governor grants OPERATOR_ROLE to operational accounts
4. Operators grant ORACLE_ROLE to oracle services using `grantRole(ORACLE_ROLE, oracleAddress)`
5. Configure eligibility period and timeout as needed
6. After demonstration of successful oracle operation and having established indexers with renewed eligibility, eligibility checking is enabled

### Normal Operation

1. Oracle nodes periodically call `renewIndexerEligibility()` to renew eligibility for indexers
2. RewardsManager calls `isEligible()` to check indexer eligibility
3. Operators adjust parameters as needed via configuration functions
4. The operation of the system is monitored and adjusted as needed

### Emergency Scenarios

- **Oracle failure**: System automatically reports all indexers as eligible after timeout
- **Eligibility issues**: Operators can disable eligibility checking globally
- **Parameter changes**: Operators can adjust periods and timeouts

## Integration

The contract implements four focused interfaces (`IRewardsEligibility`, `IRewardsEligibilityAdministration`, `IRewardsEligibilityReporting`, and `IRewardsEligibilityStatus`) and can be integrated with any system that needs to verify indexer eligibility status. The primary integration point is the `isEligible(address)` function which returns a simple boolean indicating eligibility.
