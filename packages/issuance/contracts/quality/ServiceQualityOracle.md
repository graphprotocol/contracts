# ServiceQualityOracle

The ServiceQualityOracle is a smart contract that manages indexer eligibility for receiving rewards based on service quality assessments. It implements a time-based allowlist system where indexers must be explicitly approved by authorized oracles to receive rewards.

## Overview

The contract operates on a "deny by default" principle - all indexers are initially ineligible for rewards until they are explicitly allowed by an authorized oracle. Once allowed, indexers remain eligible for a configurable period before their eligibility expires and they need to be re-approved.

## Key Features

- **Time-based Eligibility**: Indexers are allowed for a configurable period (default: 14 days)
- **Oracle-based Approval**: Only authorized oracles can approve indexers
- **Global Toggle**: Quality checking can be globally enabled/disabled
- **Timeout Mechanism**: If oracles don't update for too long, all indexers are automatically allowed
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

- `allowedIndexerTimestamps`: Maps indexer addresses to their last approval timestamp
- `allowedPeriod`: Duration (in seconds) for which approval lasts (default: 14 days)
- `checkingActive`: Global flag to enable/disable quality checking (default: false, to be enabled by operator when ready)
- `oracleUpdateTimeout`: Timeout after which all indexers are automatically allowed (default: 7 days)
- `lastOracleUpdateTime`: Timestamp of the last oracle update

## Core Functions

### Oracle Management

Oracle roles are managed through the standard AccessControl functions inherited from BaseUpgradeable:

- **`grantRole(bytes32 role, address account)`**: Grant oracle privileges to an account (OPERATOR_ROLE only)
- **`revokeRole(bytes32 role, address account)`**: Revoke oracle privileges from an account (OPERATOR_ROLE only)
- **`hasRole(bytes32 role, address account)`**: Check if an account has oracle privileges

The `ORACLE_ROLE` constant can be used as the role parameter for these functions.

### Configuration

#### `setAllowedPeriod(uint256 allowedPeriod) → bool`

- **Access**: OPERATOR_ROLE only
- **Purpose**: Set how long indexer approvals last
- **Parameters**: `allowedPeriod` - Duration in seconds
- **Returns**: Always true for current implementation
- **Events**: Emits `AllowedPeriodUpdated` if value changes

#### `setOracleUpdateTimeout(uint256 oracleUpdateTimeout) → bool`

- **Access**: OPERATOR_ROLE only
- **Purpose**: Set timeout after which all indexers are automatically allowed
- **Parameters**: `oracleUpdateTimeout` - Timeout duration in seconds
- **Returns**: Always true for current implementation
- **Events**: Emits `OracleUpdateTimeoutUpdated` if value changes

#### `setQualityChecking(bool enabled) → bool`

- **Access**: OPERATOR_ROLE only
- **Purpose**: Enable or disable quality checking globally
- **Parameters**: `enabled` - True to enable, false to disable
- **Returns**: Always true for current implementation
- **Events**: Emits `QualityCheckingUpdated` if state changes

### Indexer Management

#### `allowIndexers(address[] calldata indexers, bytes calldata data) → uint256`

- **Access**: ORACLE_ROLE only
- **Purpose**: Approve indexers for rewards
- **Parameters**:
  - `indexers` - Array of indexer addresses (zero addresses ignored)
  - `data` - Arbitrary calldata for future extensions
- **Returns**: Number of indexers whose timestamp was updated
- **Events**:
  - Emits `IndexerQualityData` with oracle and data
  - Emits `IndexerAllowed` for each newly allowed indexer
- **Notes**:
  - Updates `lastOracleUpdateTime` to current block timestamp
  - Only updates timestamp if less than current block timestamp
  - Ignores zero addresses and duplicate updates within same block

### View Functions

#### `isAllowed(address indexer) → bool`

- **Purpose**: Check if an indexer is eligible for rewards
- **Logic**:
  1. If quality checking is disabled → return true
  2. If oracle timeout exceeded → return true
  3. Otherwise → check if indexer's approval is still valid
- **Returns**: True if indexer is allowed, false otherwise

#### `isAuthorizedOracle(address oracle) → bool`

- **Purpose**: Check if an address has oracle privileges
- **Returns**: True if address has ORACLE_ROLE

#### `getLastAllowedTime(address indexer) → uint256`

- **Purpose**: Get the timestamp when indexer was last approved
- **Returns**: Timestamp or 0 if never approved

#### `getAllowedPeriod() → uint256`

- **Purpose**: Get the current allowed period
- **Returns**: Duration in seconds

#### `getOracleUpdateTimeout() → uint256`

- **Purpose**: Get the current oracle update timeout
- **Returns**: Duration in seconds

#### `getLastOracleUpdateTime() → uint256`

- **Purpose**: Get when oracles last updated
- **Returns**: Timestamp of last oracle update

#### `isQualityCheckingActive() → bool`

- **Purpose**: Check if quality checking is enabled
- **Returns**: True if active, false if disabled

## Eligibility Logic

An indexer is considered allowed if ANY of the following conditions are met:

1. **Valid approval** (`block.timestamp <= allowedIndexerTimestamps[indexer] + allowedPeriod`)
2. **Oracle timeout exceeded** (`lastOracleUpdateTime + oracleUpdateTimeout < block.timestamp`)
3. **Quality checking is disabled** (`checkingActive = false`)

This design ensures that:

- The system fails open if oracles stop updating
- Operators can disable quality checking entirely if needed
- Individual indexer approvals have time limits

In normal operation, the first condition is expected to be the only one that applies. The other two conditions provide fail-safes for oracle failures, or in extreme cases an operator override. For normal operational failure of oracles, the system gracefully degrades into a "allow all" mode. This mechanism is not perfect in that oracles could still be updating but allowing far fewer indexers than they should. However this is regarded as simple mechanism that is good enough to start with and provide a foundation for future improvements and decentralization.

While this simple model allows the criteria for providing good service to evolve over time (which is essential for the long-term health of the network), it captures sufficient information on-chain for indexers to be able to monitor their eligibility. This is important to ensure that even in the absence of other sources of information regarding observed indexer service, indexers have a good transparency about if they are being observed to be providing good service, and for how long their current approval is valid.

It might initially seem safer to allow indexers by default unless an oracle explicitly denies an indexer. While that might seem safer from the perspective of the ServiceQualityOracle in isolation, in the absence of a more sophisticated voting system it would make the system vulnerable to a single bad oracle denying many indexers. The design of deny by default is better suited to allowing redundant oracles to be working in parallel, where only one needs to be successfully detecting indexers that are providing quality service, as well as eventually allowing different oracles to have different approval criteria and/or inputs. Therefore deny by default facilitates a more resilient and open oracle system that is less vulnerable to a single points of failure, and more open to increasing decentralization over time.

In general to be rewarded for providing service on The Graph, there is expected to be proof provided of good operation (such as for proof of indexing). While proof should be required to receive rewards, the system is designed for participants to have confidence is being able to adequately prove good operation (and in the case of oracles, be seen by at least one observer) that is sufficient to allow the indexer to receive rewards. The oracle model is in general far more suited to collecting evidence of good operation, from multiple independent observers, rather than any observer being able to establish that an indexer is not providing good service.

## Events

```solidity
event IndexerQualityData(address indexed oracle, bytes data);
event IndexerAllowed(address indexed indexer, address indexed oracle);
event AllowedPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
event QualityCheckingUpdated(bool active);
event OracleUpdateTimeoutUpdated(uint256 oldTimeout, uint256 newTimeout);
```

## Default Configuration

- **Allowed Period**: 14 days (1,209,600 seconds)
- **Oracle Update Timeout**: 7 days (604,800 seconds)
- **Quality Checking**: Disabled (false)
- **Last Oracle Update Time**: 0 (never updated)

The system is deployed with reasonable defaults but can be adjusted as required. Quality checking is disabled by default as the expectation is to first see oracles successfully allowing indexers and having suitably established allowed indexers before enabling.

## Usage Patterns

### Initial Setup

1. Deploy contract with Graph Token address
2. Initialize with governor address
3. Governor grants OPERATOR_ROLE to operational accounts
4. Operators grant ORACLE_ROLE to oracle services using `grantRole(ORACLE_ROLE, oracleAddress)`
5. Configure allowed period and timeout as needed
6. After demonstration of successful oracle operation and having established a set of allowed indexers, quality checking is enabled

### Normal Operation

1. Oracles periodically call `allowIndexers()` with quality-approved indexers
2. Reward systems call `isAllowed()` to check indexer eligibility
3. Operators adjust parameters as needed via configuration functions
4. The operation of the system is monitored and adjusted as needed

### Emergency Scenarios

- **Oracle failure**: System automatically allows all indexers after timeout
- **Quality issues**: Operators can disable quality checking globally
- **Parameter changes**: Operators can adjust periods and timeouts

## Integration

The contract implements the `IServiceQualityOracle` interface and can be integrated with any system that needs to verify indexer quality status. The primary integration point is the `isAllowed(address)` function which returns a simple boolean indicating eligibility.
