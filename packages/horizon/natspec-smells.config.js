/**
 * List of supported options: https://github.com/defi-wonderland/natspec-smells?tab=readme-ov-file#options
 */

/** @type {import('@defi-wonderland/natspec-smells').Config} */
module.exports = {
  include: 'contracts/**/*.sol',
  exclude: ['test/**/*.sol', 'contracts/mocks/**/*.sol', 'contracts/**/LibFixedMath.sol'],
  constructorNatspec: true,
}
