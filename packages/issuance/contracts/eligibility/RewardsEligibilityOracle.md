# RewardsEligibilityOracle

The RewardsEligibilityOracle is a smart contract that manages indexer eligibility for receiving rewards. It implements a time-based eligibility system where indexers must be explicitly marked as eligible by authorized oracles to receive rewards.

## Overview

The contract operates on a "deny by default" principle - all indexers are initially ineligible for rewards until their eligibility is explicitly renewed by an authorized oracle. Once eligibility is renewed, indexers remain eligible for a configurable period before their eligibility expires and needs to be renewed again.

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

In normal operation, the first condition is expected to be the only one that applies. The other two conditions provide fail-safes for oracle failures, or in extreme cases an operator override. For normal operational failure of oracles, the system gracefully degrades into a "allow all" mode. This mechanism is not perfect in that oracles could still be updating but allowing far fewer indexers than they should. However this is regarded as simple mechanism that is good enough to start with and provide a foundation for future improvements and decentralization.

While this simple model allows the criteria for providing good service to evolve over time (which is essential for the long-term health of the network), it captures sufficient information on-chain for indexers to be able to monitor their eligibility. This is important to ensure that even in the absence of other sources of information regarding observed indexer service, indexers have a good transparency about if they are being observed to be providing good service, and for how long their current approval is valid.

It might initially seem safer to allow indexers by default unless an oracle explicitly denies an indexer. While that might seem safer from the perspective of the RewardsEligibilityOracle in isolation, in the absence of a more sophisticated voting system it would make the system vulnerable to a single bad oracle denying many indexers. The design of deny by default is better suited to allowing redundant oracles to be working in parallel, where only one needs to be successfully detecting indexers that are providing quality service, as well as eventually allowing different oracles to have different approval criteria and/or inputs. Therefore deny by default facilitates a more resilient and open oracle system that is less vulnerable to a single points of failure, and more open to increasing decentralization over time.

In general to be rewarded for providing service on The Graph, there is expected to be proof provided of good operation (such as for proof of indexing). While proof should be required to receive rewards, the system is designed for participants to have confidence is being able to adequately prove good operation (and in the case of oracles, be seen by at least one observer) that is sufficient to allow the indexer to receive rewards. The oracle model is in general far more suited to collecting evidence of good operation, from multiple independent observers, rather than any observer being able to establish that an indexer is not providing good service.

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

1. Oracles periodically call `renewIndexerEligibility()` to renew eligibility for indexers
2. Reward systems call `isEligible()` to check indexer eligibility
3. Operators adjust parameters as needed via configuration functions
4. The operation of the system is monitored and adjusted as needed

### Emergency Scenarios

- **Oracle failure**: System automatically reports all indexers as eligible after timeout
- **Eligibility issues**: Operators can disable eligibility checking globally
- **Parameter changes**: Operators can adjust periods and timeouts

## Integration

The contract implements four focused interfaces (`IRewardsEligibility`, `IRewardsEligibilityAdministration`, `IRewardsEligibilityReporting`, and `IRewardsEligibilityStatus`) and can be integrated with any system that needs to verify indexer eligibility status. The primary integration point is the `isEligible(address)` function which returns a simple boolean indicating eligibility.
