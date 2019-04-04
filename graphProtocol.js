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
  module.exports = (options = {}) => {

    // Destructure the options properties for our contract ABIs
    const {
      DisputeManager,
      GNS,
      GraphToken,
      MultiSigWallet,
      RewardsManager,
      ServiceRegistry,
      Staking
    } = options
  
    /**
     * @title Governance of upgradable contract parameters 
     */
    class governance {
  
      /**
       * @dev Set the Minimum Staking Amount for Market Curators
       * @param {Number} minimumCurationStakingAmount Minimum amount allowed to be staked for Curation
       */
      static setMinimumCurationStakingAmount(minimumCurationStakingAmount, from) {
        // encode the transaction data to be sent to the multisig
        const txData = abiEncode(
          Staking.contract.methods.setMinimumCurationStakingAmount,
          [ minimumCurationStakingAmount ]
        )
        
        // submit the transaction to the multisig (where it is confirmed and executed)
        return MultiSigWallet.submitTransaction(Staking.address, 0, txData, { from })
      }
  
    }

    /**
     * @title Public Staking methods 
     */
    class staking {

      /**
       * @dev Getter for `governor` address
       * @returns {Address} Address of the `governor`
       */
      static governor() {
        return Staking.governor()
      }

      /**
       * @dev Getter for `maximumIndexers`
       * @returns {Number} Maximum number of Indexing Nodes allowed
       */
      static maximumIndexers() {
        return Staking.maximumIndexers()
      }

      /**
       * @dev Getter for `minimumCurationStakingAmount`
       * @returns {Number} Minimum curation staking amount
       */
      static minimumCurationStakingAmount() {
        return Staking.minimumCurationStakingAmount()
      }

      /**
       * @dev Getter for `minimumIndexingStakingAmount`
       * @returns {Number} Minimum indexing staking amount
       */
      static minimumIndexingStakingAmount() {
        return Staking.minimumIndexingStakingAmount()
      }

      /**
       * @dev Getter for `token` (deployed GraphToken contract address)
       * @returns {Address} Deployed Graph Token contract address
       */
      static token() {
        return Staking.token()
      }

      /**
       * @dev Getter for `curators` mapping
       * @param {Address} curationStaker Address of `curators` staking tokens
       * @param {Bytes32} subgraphId Subgraph ID `Curator` is staking for
       * @returns {Object} Curator
       */
      static curators(curationStaker, subgraphId) {
        return Staking.curators.call(curationStaker, subgraphId)
      }

      /**
       * @dev Getter for `indexingNodes` mapping
       * @param {Address} indexingStaker Address of `indexingNodes` staking tokens
       * @param {Bytes32} subgraphId Subgraph ID `IndexingNode` is staking for
       * @returns {Object} IndexingNode
       */
      static indexingNodes(indexingStaker, subgraphId) {
        return Staking.indexingNodes.call(indexingStaker, subgraphId)
      }

      /**
       * @dev Getter for `arbitrator` address
       * @returns {Address} arbitrator
       */
      static arbitrator() {
        return Staking.arbitrator()
      }

      /**
       * @dev Calculate number of shares that should be issued for the proportion
       *  of addedStake to totalStake based on a bonding curve 
       * @param {uint256} purchaseTokens Amount of tokens being staked (purchase amount)
       * @param {uint256} currentTokens Total amount of tokens currently in reserves
       * @param {uint256} currentShares Total amount of current shares issued
       * @param {uint256} reserveRatio Reserve ratio
       * @returns {uint256} issuedShares Amount of shares issued given the above input
       */
      static stakeToShares(
        purchaseTokens,
        currentTokens,
        currentShares,
        reserveRatio
      ) {
        return Staking.stakeToShares(
          purchaseTokens,
          currentTokens,
          currentShares,
          reserveRatio
        )
      }

      /**
       * @dev Stake Graph Tokens for curation
       * @param {Hexadecimal} subgraphId Id of the subgraph curator is staking for
       * @param {Address} from Account of curator staking tokens
       * @param {Number} value Amount of Graph Tokens to be staked for curation
       * @returns {Boolean} success
       */
      static stakeForCuration(subgraphId, from, value) {
        // encode data to be used in staking for curation
        const data = web3.utils.hexToBytes('0x01' + subgraphId)
        return GraphToken.transferWithData(
          Staking.address, // to
          value, // value
          data, // data
          { from } // from/curator
        )
      }

      /**
       * @dev Stake Graph Tokens for indexing
       * @param {Hexadecimal} subgraphId Id of the subgraph Indexing Node is staking for
       * @param {Address} from Account of Indexing Node staking tokens
       * @param {Number} value Amount of Graph Tokens to be staked for indexing
       * @param {Data} indexingRecords Data containing indexing records for this subgraphId
       * @returns {Boolean} success
       */
      static stakeForIndexing(subgraphId, from, value, indexingRecords) {
        // encode data to be used in staking for indexing
        let hex = '0x00' + subgraphId
        if (indexingRecords) hex += indexingRecords
        const data = web3.utils.hexToBytes(hex)
        return GraphToken.transferWithData(
          Staking.address, // to
          value, // value
          data, // data
          { from } // from/curator
        )
      }
      
      /**
       * @dev Indexing node can start logout process
       * @param subgraphId <bytes32> - Subgraph ID the Indexing Node has staked Graph Tokens for
       * @param from <address> - Address of staking indexing node
       */
      static beginLogout(subgraphId, from) {
        return Staking.beginLogout(
          subgraphId,
          { from }
        )
      }

      /**
       * @dev Indexing node can finalize logout process
       * @param subgraphId <bytes32> - Subgraph ID the Indexing Node has staked Graph Tokens for
       * @param from <address> - Address of staking indexing node
       */
      static finalizeLogout(subgraphId, from) {
        return Staking.finalizeLogout(
          subgraphId, 
          { from }
        )
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
      staking,
    }
  
  }