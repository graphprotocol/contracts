# Issuance Deployment Scripts

This directory contains scripts for managing the IssuanceAllocator deployment and upgrade workflow with **pending implementation tracking**.

## 🎯 **Overview**

The scripts implement a three-phase upgrade workflow:

1. **Upgrade Preparation**: Deploy new implementation → Set as pending
2. **Governance Execution**: Execute upgrade on-chain → Implementation updated
3. **Address Book Sync**: Update records → Move pending to active

This approach provides clear interim state tracking and supports both local testing and governance-controlled upgrades.

## 📁 **Scripts**

### **`deploy-upgrade-prep.js`**

Deploys a new IssuanceAllocator implementation and sets it as pending in the address book.

**Usage:**

```bash
node scripts/deploy-upgrade-prep.js <network>
pnpm upgrade-prep:hardhat
pnpm upgrade-prep:mainnet
```

**What it does:**

1. Deploys new implementation using Ignition
2. Updates address book with `pendingImplementation`
3. Shows deployment status with pending implementation

### **`deploy-governance-upgrade.js`**

Executes the governance upgrade on-chain and syncs the address book.

**Usage:**

```bash
node scripts/deploy-governance-upgrade.js <network>
pnpm governance-upgrade:hardhat
pnpm governance-upgrade:mainnet
```

**What it does:**

1. Checks for pending implementation
2. Executes governance upgrade via Ignition (on-chain)
3. Syncs address book with completed upgrade
4. Shows updated deployment status

### **`update-address-book.js`**

Utility functions for managing the address book with pending implementation support.

**Usage:**

```bash
# Show deployment status
node scripts/update-address-book.js status <network>
pnpm status:hardhat

# Manually activate pending implementation
node scripts/update-address-book.js activate <network> <contractName>
```

**Functions:**

- `updateAddressBookInitialDeployment()` - Set up initial deployment
- `updateAddressBookPendingImplementation()` - Add pending implementation
- `activatePendingImplementation()` - Sync address book with completed upgrade
- `printDeploymentStatus()` - Show current status

## 🔄 **Workflow Example**

### **1. Prepare Upgrade**

```bash
$ pnpm upgrade-prep:mainnet

🚀 Starting upgrade preparation deployment on mainnet
📦 Step 1: Deploying new IssuanceAllocator implementation...
📋 Step 2: Updating address book with pending implementation...
✅ Pending implementation set: 0x5FbDB...

📊 Step 3: Current deployment status:
IssuanceAllocator:
  Implementation: 0xe7f17... (active)
  🟡 Pending Implementation: 0x5FbDB... (ready for upgrade)
```

### **2. Execute Governance Upgrade**

```bash
$ pnpm governance-upgrade:mainnet

🏛️ Starting governance upgrade on mainnet
⚡ Step 2: Executing governance upgrade...
📋 Step 3: Activating pending implementation in address book...
✅ Pending implementation activated: 0x5FbDB...

📊 Step 4: Updated deployment status:
IssuanceAllocator:
  Implementation: 0x5FbDB... (active)
```

### **3. Verify Status**

```bash
$ pnpm status:mainnet

📋 Deployment Status for mainnet
IssuanceAllocator:
  Address: 0x9fE46...
  Proxy: Yes
  Implementation: 0x5FbDB... (active)
```

## 🎯 **Benefits**

- **Clear State Tracking**: Always know what's deployed vs active
- **Governance Support**: Same workflow for local testing and mainnet
- **Audit Trail**: Complete history of upgrade states
- **Safety**: Pending implementations can be discarded if needed
- **Coordination**: Multiple stakeholders can see upgrade status

## 🔧 **Integration**

These scripts integrate with:

- **Hardhat Ignition**: For declarative deployments
- **Address Book**: For state tracking (toolshed pattern)
- **Package Scripts**: Via `pnpm` commands
- **CI/CD**: Can be automated for different networks

## 📋 **Supported Networks**

- `hardhat` - Local testing
- `sepolia` - Ethereum testnet
- `mainnet` - Ethereum mainnet
- `arbitrumOne` - Arbitrum mainnet
- `arbitrumSepolia` - Arbitrum testnet

## 🚨 **Important Notes**

1. **Always run upgrade-prep first** before governance-upgrade
2. **Check status** between phases to verify pending implementation
3. **Governance upgrades are irreversible** - test thoroughly on testnets
4. **Address book tracks state** regardless of who performs the upgrade
5. **Scripts handle both local testing and production** workflows
6. **Local address files** (`addresses-hardhat.json`, `addresses-localhost.json`) are **not tracked in git** - they contain ephemeral addresses that reset between sessions
