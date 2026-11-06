# Billing Contract

This repository contains a Billing contract. It allows users to add tokens (GRT) into the contract for an agent to pull when a billing period is up.

## Contract Design

The contract is designed with the following requirements:

- The contract is owned by the `governor`.
- There is a privileged role named `collector` that has a special permission to pull user funds (this is, for now, the Gateway that acts as intermediary between Consumers and Indexers in The Graph Network).
- Users add tokens into the contract by calling `add()`. It is important to note that the contract
  is designed so that the users are trusting the Collector. Once the user adds tokens, the Collector can
  pull the funds whenever it wants.
- The trust risk for the User is that the Collector would pull funds before the User spent their funds, which are query fees in The Graph Network.
- The trust risk for the Collector is that the user adds funds, spends them on queries, and then
  removes their tokens before the Collector pulled the tokens.
- These combined trust risks make for a situation that we expect both parties to act responsibly.
  It will always be recommended to keep the amount of GRT in the contract low for each user, and for
  the Collector to pull regularly. This way, if one side does not play nice, the funds lost won't be
  that large.

## L1-L2 communication

The Billing contract is designed to be deployed to an L2 (Arbitrum). A BillingConnector contract can be deployed to L1 (mainnet), and allows users to add funds to the Billing contract using a token gateway that allows callhooks as described in [GIP-0031](https://forum.thegraph.com/t/gip-0031-arbitrum-grt-bridge/3305)

To add tokens from L1 to L2, there are two options:

a) If the user's address is an EOA, they can use [BillingConnector.addToL2WithPermit](./contracts/IBillingConnector.sol#L59-L81). They first need to sign a permit for the BillingConnector contract to pull the GRT, and then run the tx including that signature, which will send those GRT to the billing balance for that same address in L2.

b) If the user's address is a contract (e.g. a multisig), or they don't want to sign a permit, then they can use [BillingConnector.addToL2](./contracts/IBillingConnector.sol#L24-L39), but they need to run `GraphToken.approve(billingConnector.address, amount)` beforehand.

To estimate the L2 submission and gas parameters (`_maxGas`, `_gasPriceBid`, and `_maxSubmissionCost`), we recommend using the [Arbitrum SDK](https://github.com/OffchainLabs/arbitrum-sdk). An example for this is available in the [graphprotocol/contracts](https://github.com/graphprotocol/contracts/blob/pcv/l2-bridge/cli/commands/bridge/to-l2.ts#L63-L94) repo - just replace the calldata with the [calldata produced by BillingConnector](./test/billingConnector.test.ts#L277-L284)

To remove tokens on L2, users that have an EOA, or whose account exists in L2 with the same address as L1, can call `Billing.remove` directly on L2 to remove funds to an L2 address. Users whose address doesn't exist in L2 (e.g. when using a multisig), can instead use [BillingConnector.removeOnL2](./contracts/IBillingConnector.sol#L41-L57) to send a message from L1 that will tell the Billing contract to move the tokens to the desired address. There is no validation of the amount actually existing on the L2 balance, and guarantee that the message will arrive before funds are pulled by the Collector, so the message might revert on L2 if the balance is insufficient. Note that this call will also require estimating L2 gas parameters. In this case, the retryable ticket is created directly by the BillingConnector (instead of by the L1GraphTokenGateway), so keep this in mind when estimating gas with the Arbitrum SDK.

## Testing

Run the test suite with:

```bash
yarn test
```

## Using the console

Here is how to use hardhat to quickly do some transactions:

```bash
hh console --network polygon

accounts = await ethers.getSigners()
token = await hre.contracts.Token.connect(accounts[0])
await token.approve('0x5DE9A13C486f5aA12F4D8e5E77246F6E24dac274', '1000000000000000000000')

billing = await hre.contracts.Billing.connect(accounts[0])
await billing.add('1000000000000000000')
```

## Deploy instructions

To deploy, see these instructions:

### Billing
Use arbitrum-one (or arbitrum-goerli) to deploy Billing:

```
hh deploy-billing --network arbitrum-one \
    --collector <COLLECTOR_ADDRESS> \
    --token <GRT_ADDRESS> \
    --governor <GOVERNOR_ADDRESS> \
    --tokengateway <L2GRAPHTOKENGATEWAY_ADDRESS>
```

Then run this to verify on Etherscan:

```
hh verify --network arbitrum-one \
    <NEW_DEPLOYED_ADDRESS> \
    <COLLECTOR_ADDRESS> \
    <GRT_ADDRESS> \
    <GOVERNOR_ADDRESS> \
    <L2GRAPHTOKENGATEWAY_ADDRESS>
```

### BillingConnector
Use mainnet (or goerli) to deploy BillingConnector:

```
hh deploy-billing-connector --network mainnet \
    --tokengateway <L1GRAPHTOKENGATEWAY_ADDRESS> \
    --billing <L2_BILLING_ADDRESS> \
    --token <GRT_ADDRESS> \
    --governor <GOVERNOR_ADDRESS> \
    --inbox <ARBITRUM_INBOX_ADDRESS>
```

Then run this to verify on Etherscan:

```
hh verify --network mainnet \
    <NEW_DEPLOYED_ADDRESS> \
    <L1GRAPHTOKENGATEWAY_ADDRESS> \
    <L2_BILLING_ADDRESS> \
    <GRT_ADDRESS> \
    <GOVERNOR_ADDRESS> \
    <ARBITRUM_INBOX_ADDRESS>
```

### BanxaWrapper
Use arbitrum-one (or arbitrum-goerli) to deploy BanxaConnector:

```
hh deploy-banxa --network arbitrum-one \
    --token <GRT_ADDRESS> \
    --billing <BILLING_ADDRESS> \
    --governor <GOVERNOR_ADDRESS>
```

Then run this to verify on Etherscan:

```
hh verify --network arbitrum-one \
    <NEW_DEPLOYED_ADDRESS> \
    <GRT_ADDRESS> \
    <BILLING_ADDRESS> \
    <GOVERNOR_ADDRESS>
```
