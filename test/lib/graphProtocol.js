/*
 * @title Graph Protocol JavaScript Library
 *
 * Requirements
 * @req 01 Encode transaction data for use with the MultiSig
 *
 */

module.exports = (options) => {

  // Destructure the options properties to vars
  let {
    DisputeManager,
    GNS,
    GraphToken,
    MultiSigWallet,
    RewardsManager,
    ServiceRegistry,
    Staking
  } = options || {}

  /**
   * @title Staking contract upgradable parameters 
   */
  class governance {

    /**
     * @dev Set the Minimum Staking Amount for Market Curators
     * @param minimumCurationStakingAmount <uint256> - Minimum amount allowed to be staked for Curation
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
   * @param {Function} method 
   * @param {Array(*)} args 
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
