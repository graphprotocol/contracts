/**
 * @title Graph Protocol JavaScript Library
 *
 * @dev This library can be used in tests, dapps or any JavaScript client to simplify upgrading contracts
 * @todo Publish this as an NPM package for use with any web3/dapp/other project
 * 
 * Requirements
 * @req 01 Encode transaction data for use with the MultiSig
 * @req 02 Write functions to upgrade contracts via the multisig
 * @req 03 Include upgradable contract functions in an exported `governance` class
 * @req 04 Include functions to check on multisig transactions and their statuses
 *
 */

  /**
   * @dev Contract ABIs are sent as properties in an `options` object
   * 
   * @param {Object} options JSON object containing contract ABIs
   * @example `{ GNS: deployedGnsContract, Staking: deployedStakingContract }`
   * @see line26 For the property names used in this module
   * 
   */
  module.exports = (options) => {

  // Destructure the options properties for our contract ABIs
  const {
    DisputeManager,
    GNS,
    GraphToken,
    MultiSigWallet,
    RewardsManager,
    ServiceRegistry,
    Staking
  } = options || {}

  /**
   * @title Governance of upgradable contract parameters 
   */
  class governance {

    /**
     * @dev Set the Minimum Staking Amount for Market Curators
     * @param {Number} minimumCurationStakingAmount Minimum amount allowed to be staked for Curation
     */
    static setMinimumCurationStakingAmount(minimumCurationStakingAmount) {
      // encode the transaction data to be sent to the multisig
      const txData = abiEncode(
        Staking.contract.methods.setMinimumCurationStakingAmount,
        [ minimumCurationStakingAmount ]
      )
      
      // submit the transaction to the multisig (where it is confirmed and executed)
      return MultiSigWallet.submitTransaction(Staking.address, 0, txData)
    }

  }

  /**
   * @dev Use the ABI encoding method to encode transaction data
   * @dev This approach requires the contract ABI method to be passed as an arguement.
   * @dev This method does not present any advantage over using `encodeABI()` directly.
   * 
   * @param {Function} method ABI for target method
   * @param {Array(*)} args Arguments to be passed
   */
  function abiEncode(method, args) {
    return method(...args).encodeABI()
  }

  /**
   * Exports
   */
  return {
    abiEncode,
    governance,
  }

}
