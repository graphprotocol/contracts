# Testing

Testing is done with the following stack:

- [Waffle](https://getwaffle.io/)
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

### Hardhat local node

To run all e2e tests against a hardhat local node run:

```bash
yarn test:e2e
```

The command will perform the following actions:

- Start a hardhat node (localhost)
- Run `migrate:accounts` hardhat task to create keys for all protocol roles (deployer, governor, arbiter, etc). This currently doesn't support multisig accounts.
- Run `migrate` hardhat task to deploy the protocol
- Run `migrate:ownership` hardhat task to transfer ownership of governed contracts to the governor
- Run `migrate:unpause` to unpause the protocol
- Run `e2e` hardhat task to run all deployment tests (config and init)
- Run `e2e:scenario` hardhat task to run a scenario

### Other networks

To run tests against a live testnet or even mainnet run:

```bash
# All e2e tests
npx hardhat e2e --network <network> --graph-config config/graph.<network>.yml

# Only deployment config tests
npx hardhat e2e:config --network <network> --graph-config config/graph.<network>.yml

# Only deployment init tests
npx hardhat e2e:init --network <network> --graph-config config/graph.<network>.yml

# Only a specific scenario
npx hardhat e2e:scenario <scenario> --network <network> --graph-config config/graph.<network>.yml
```

Note that this command will only run the tests so you need to be sure the protocol is already deployed and the graph config file and address book files are up to date.

### How to add scenarios

Scenarios are defined by an optional script and a test file:

- Optional ts script
   - The objective of this script is to perform actions on the protocol to advance it's state to the desired one.
   - Should follow hardhat script convention.
   - Should be named e2e/scenarios/{scenario-name}.ts.
   - They run before the test file.
- Test file
   - Should be named e2e/scenarios/{scenario-name}.test.ts.
   - Standard chai/mocha/hardhat/ethers test file.