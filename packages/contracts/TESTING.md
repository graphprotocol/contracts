# Testing

Testing is done with the following stack:

- [Hardhat](https://hardhat.org/)
- [Typescript](https://www.typescriptlang.org/)
- [Ethers](https://docs.ethers.io/v5/)

## Unit testing

To test all the smart contracts, use `yarn test`.
To test a single file run: `npx hardhat test test/<FILE_NAME>.ts`

## E2E Testing

End to end tests are also available and can be run against a local network or a live network. These can be useful to validate that a protocol deployment is configured and working as expected. 

There are several types of e2e tests which can be run separately:
- **deployment/config**
  - Test the configuration of deployed contracts (parameters that don't change over time).
  - Can be run against any network at any time and the tests should pass.
  - Only read only interactions with the blockchain.
  - Example: a test validating the curation default reserve ratio matches the value in the graph config file.
- **deployment/init** 
  - Test the initialization of deployed contracts (parameters that change with protocol usage).
  - Can be run against a "fresh" protocol deployment. Running these tests against a protocol with pre-existing state will probably fail.
  - Only read only interactions with the blockchain.
  - Example: a test validating that the GRT total supply equals 10B, this is only true on a freshly deployed protocol until the first allocation is closed and protocol issuance kicks in.
- **scenarios**
  - Test the execution of common protocol actions.
  - Can be run against any network at any time and the tests should pass.
  - Read and write interactions with the blockchain. _Requires an account with sufficient balance!_
  - Example: a test validating that a user can add signal to a subgraph.

### Hardhat local node (L1)

It can be useful to run E2E tests against a fresh protocol deployment on L1, this can be done with the following:

```bash
L1_NETWORK=localhost yarn test:e2e
```

The command will:
- start a hardhat local node
- deploy the L1 protocol
- configure the new L1 deployment
- Run all L1 e2e tests

### Arbitrum Nitro testnodes (L1/L2)

If you want to test the protocol on an L1/L2 setup, you can run:

```bash
L1_NETWORK=localnitrol1 L2_NETWORK=localnitrol2 yarn test:e2e
```

In this case the command will:
- deploy the L1 protocol
- configure the new L1 deployment
- deploy the L2 protocol
- configure the new L2 deployment
- configure the L1/L2 bridge
- Run all L1 e2e tests
- Run all L2 e2e tests

Note that you'll need to setup the testnodes before running the tests. See [Quick Setup](https://github.com/edgeandnode/nitro#quick-setup) for details on how to do this.

### Other networks

To run tests against a live testnet or even mainnet run:

```bash
# All e2e tests
ARBITRUM_ADDRESS_BOOK=<arbitrum-address-book> npx hardhat e2e --network <network> --l1-graph-config config/graph.<l1-network>.yml --l2-graph-config config/graph.<l2-network>.yml

# Only deployment config tests
ARBITRUM_ADDRESS_BOOK=<arbitrum-address-book> npx hardhat e2e:config --network <network> --l1-graph-config config/graph.<l1-network>.yml --l2-graph-config config/graph.<l2-network>.yml

# Only deployment init tests
ARBITRUM_ADDRESS_BOOK=<arbitrum-address-book> npx hardhat e2e:init --network <network> --l1-graph-config config/graph.<l1-network>.yml --l2-graph-config config/graph.<l2-network>.yml

# Only a specific scenario
npx hardhat e2e:scenario <scenario> --network <network> --graph-config config/graph.<network>.yml
```

Note that this command will only run the tests so you need to be sure the protocol is already deployed and the graph config file and address book files are up to date.

### How to add scenarios

Scenarios are defined by an optional script and a test file:

- Optional ts script
   - The objective of this script is to perform actions on the protocol to advance it's state to the desired one.
   - Should follow hardhat script convention.
   - Should be named test/e2e/scenarios/{scenario-name}.ts.
   - They run before the test file.
- Test file
   - Should be named test/e2e/scenarios/{scenario-name}.test.ts.
   - Standard chai/mocha/hardhat/ethers test file.