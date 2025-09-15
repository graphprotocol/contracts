/**
 * @title natspec-smells configuration for The Graph Protocol contracts
 * @notice Configuration for natspec-smells linter to ensure consistent and complete
 * documentation across all Solidity contracts in the monorepo.
 *
 * This configuration is based on the horizon config from the main contracts repository
 * for consistency across The Graph Protocol ecosystem.
 *
 * List of supported options: https://github.com/defi-wonderland/natspec-smells?tab=readme-ov-file#options
 */

/** @type {import('@defi-wonderland/natspec-smells').Config} */
module.exports = {
  include: [
    'packages/issuance/contracts/**/*.sol', 
    'packages/interfaces/contracts/**/*.sol',
    'packages/horizon/contracts/**/*.sol',
    'packages/subgraph-service/contracts/**/*.sol'
  ],

  root: './',

  // Disable @inheritdoc enforcement to avoid issues with storage getters and non-interface functions
  enforceInheritdoc: false,

  constructorNatspec: true,
}
