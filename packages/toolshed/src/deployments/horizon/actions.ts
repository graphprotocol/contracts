import type { GraphHorizonContracts, HorizonStakingExtension } from '.'
import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

/**
 * It's important to use JSDoc in the return functions here for good developer experience as
 * intellisense does not expand the args type aliases.
 */
export function loadActions(
  contracts: GraphHorizonContracts,
) {
  return {
    /**
     * Stakes GRT tokens in the Horizon staking contract
     * Note that it will approve HorizonStaking to spend the tokens
     *
     * @param signer - The signer that will execute the transactions
     * @param args Parameters:
     *   - [tokens] - Amount of GRT tokens to stake
     */
    stake: (signer: HardhatEthersSigner, args: Parameters<GraphHorizonContracts['HorizonStaking']['stake']>) => stake(contracts, signer, args),
    /**
     * Stakes GRT tokens in the Horizon staking contract to a service provider
     * Note that it will approve HorizonStaking to spend the tokens
     *
     * @param signer - The signer that will execute the transactions
     * @param args Parameters:
     *   - [serviceProvider, tokens] - The provision parameters
     */
    stakeTo: (signer: HardhatEthersSigner, args: Parameters<GraphHorizonContracts['HorizonStaking']['stakeTo']>) => stakeTo(contracts, signer, args),
    /**
     * Stakes GRT tokens in the Horizon staking contract to a provision
     * Note that it will approve HorizonStaking to spend the tokens
     *
     * @param signer - The signer that will execute the transactions
     * @param args Parameters:
     *   - [serviceProvider, verifier, tokens] - The provision parameters
     */
    stakeToProvision: (signer: HardhatEthersSigner, args: Parameters<GraphHorizonContracts['HorizonStaking']['stakeToProvision']>) => stakeToProvision(contracts, signer, args),
    /**
     * Adds tokens to a provision
     * Note that it will approve HorizonStaking to spend the tokens
     *
     * @param signer - The signer that will execute the transactions
     * @param args Parameters:
     *   - [serviceProvider, verifier, tokens] - The provision parameters
     */
    addToProvision: (signer: HardhatEthersSigner, args: Parameters<GraphHorizonContracts['HorizonStaking']['addToProvision']>) => addToProvision(contracts, signer, args),
    /**
     * Provisions tokens in the Horizon staking contract
     * Note that it will approve HorizonStaking to spend the tokens and stake them
     *
     * @param signer - The signer that will execute the provision transaction
     * @param args Parameters:
     *   - `[serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod]` - The provision parameters
     */
    provision: (signer: HardhatEthersSigner, args: Parameters<GraphHorizonContracts['HorizonStaking']['provision']>) => provision(contracts, signer, args),
    /**
     * [Legacy] Collects query fees from the Horizon staking contract
     * Note that it will approve HorizonStaking to spend the tokens
     * @param signer - The signer that will execute the collect transaction
     * @param args Parameters:
     *   - `[tokens, allocationID]` - The collect parameters
     */
    collect: (signer: HardhatEthersSigner, args: Parameters<GraphHorizonContracts['HorizonStaking']['collect']>) => collect(contracts, signer, args),
    /**
     * Delegates tokens in the Horizon staking contract
     * Note that it will approve HorizonStaking to spend the tokens
     * @param signer - The signer that will execute the delegate transaction
     * @param args Parameters:
     *   - `[serviceProvider, verifier, tokens, minSharesOut]` - The delegate parameters
     */
    delegate: (signer: HardhatEthersSigner, args: Parameters<GraphHorizonContracts['HorizonStaking']['delegate(address,address,uint256,uint256)']>) => delegate(contracts, signer, args),
    /**
     * Adds tokens to a delegation pool
     * Note that it will approve HorizonStaking to spend the tokens
     * @param signer - The signer that will execute the addToDelegationPool transaction
     * @param args Parameters:
     *   - `[serviceProvider, verifier, tokens]` - The addToDelegationPool parameters
     */
    addToDelegationPool: (signer: HardhatEthersSigner, args: Parameters<GraphHorizonContracts['HorizonStaking']['addToDelegationPool']>) => addToDelegationPool(contracts, signer, args),
  }
}

async function stake(
  contracts: GraphHorizonContracts,
  signer: HardhatEthersSigner,
  args: Parameters<GraphHorizonContracts['HorizonStaking']['stake']>,
) {
  const { GraphToken, HorizonStaking } = contracts
  const [tokens] = args

  await GraphToken.connect(signer).approve(HorizonStaking.target, tokens)
  await HorizonStaking.connect(signer).stake(tokens)
}

async function stakeTo(
  contracts: GraphHorizonContracts,
  signer: HardhatEthersSigner,
  args: Parameters<GraphHorizonContracts['HorizonStaking']['stakeTo']>,
) {
  const { GraphToken, HorizonStaking } = contracts
  const [serviceProvider, tokens] = args

  await GraphToken.connect(signer).approve(HorizonStaking.target, tokens)
  await HorizonStaking.connect(signer).stakeTo(serviceProvider, tokens)
}

async function stakeToProvision(
  contracts: GraphHorizonContracts,
  signer: HardhatEthersSigner,
  args: Parameters<GraphHorizonContracts['HorizonStaking']['stakeToProvision']>,
) {
  const { GraphToken, HorizonStaking } = contracts
  const [serviceProvider, verifier, tokens] = args

  await GraphToken.connect(signer).approve(HorizonStaking.target, tokens)
  await HorizonStaking.connect(signer).stakeToProvision(serviceProvider, verifier, tokens)
}

async function addToProvision(
  contracts: GraphHorizonContracts,
  signer: HardhatEthersSigner,
  args: Parameters<GraphHorizonContracts['HorizonStaking']['addToProvision']>,
) {
  const { GraphToken, HorizonStaking } = contracts
  const [serviceProvider, verifier, tokens] = args

  await GraphToken.connect(signer).approve(HorizonStaking.target, tokens)
  await HorizonStaking.connect(signer).addToProvision(serviceProvider, verifier, tokens)
}

async function provision(
  contracts: GraphHorizonContracts,
  signer: HardhatEthersSigner,
  args: Parameters<GraphHorizonContracts['HorizonStaking']['provision']>,
) {
  const { GraphToken, HorizonStaking } = contracts
  const [serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod] = args

  await GraphToken.connect(signer).approve(HorizonStaking.target, tokens)
  await HorizonStaking.connect(signer).stake(tokens)
  await HorizonStaking.connect(signer).provision(serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod)
}

async function collect(
  contracts: GraphHorizonContracts,
  signer: HardhatEthersSigner,
  args: Parameters<GraphHorizonContracts['HorizonStaking']['collect']>,
) {
  const { GraphToken, HorizonStaking } = contracts
  const [tokens, allocationID] = args

  await GraphToken.connect(signer).approve(HorizonStaking.target, tokens)
  await (HorizonStaking as HorizonStakingExtension).connect(signer).collect(tokens, allocationID)
}

async function delegate(
  contracts: GraphHorizonContracts,
  signer: HardhatEthersSigner,
  args: Parameters<GraphHorizonContracts['HorizonStaking']['delegate(address,address,uint256,uint256)']>,
) {
  const { GraphToken, HorizonStaking } = contracts
  const [serviceProvider, verifier, tokens, minSharesOut] = args

  await GraphToken.connect(signer).approve(HorizonStaking.target, tokens)
  await HorizonStaking.connect(signer)['delegate(address,address,uint256,uint256)'](serviceProvider, verifier, tokens, minSharesOut)
}

async function addToDelegationPool(
  contracts: GraphHorizonContracts,
  signer: HardhatEthersSigner,
  args: Parameters<GraphHorizonContracts['HorizonStaking']['addToDelegationPool']>,
) {
  const { GraphToken, HorizonStaking } = contracts
  const [serviceProvider, verifier, tokens] = args

  await GraphToken.connect(signer).approve(HorizonStaking.target, tokens)
  await HorizonStaking.connect(signer).addToDelegationPool(serviceProvider, verifier, tokens)
}
