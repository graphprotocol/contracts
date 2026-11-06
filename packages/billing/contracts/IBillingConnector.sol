// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IBillingConnector {
    /**
     * @dev Sets the L1 token gateway address
     * @param _l1TokenGateway New address for the L1 token gateway
     */
    function setL1TokenGateway(address _l1TokenGateway) external;

    /**
     * @dev Sets the L2 Billing address
     * @param _l2Billing New address for the L2 Billing contract
     */
    function setL2Billing(address _l2Billing) external;

    /**
     * @dev Sets the Arbitrum Delayed Inbox address
     * @param _inbox New address for the L2 Billing contract
     */
    function setArbitrumInbox(address _inbox) external;

    /**
     * @dev Add tokens into the billing contract on L2, for any user
     * Ensure graphToken.approve() is called for the BillingConnector contract first
     * @param _to  Address that tokens are being added to
     * @param _amount  Amount of tokens to add
     * @param _maxGas Max gas for the L2 retryable ticket execution
     * @param _gasPriceBid Gas price for the L2 retryable ticket execution
     * @param _maxSubmissionCost Max submission price for the L2 retryable ticket
     */
    function addToL2(
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external payable;

    /**
     * @dev Remove tokens from the billing contract on L2, sending the tokens
     * to an L2 address. Useful when the tokens are in the balance for an address
     * that doesn't exist in L2.
     * @param _to  L2 address to which the tokens will be sent
     * @param _amount  Amount of tokens to remove
     * @param _maxGas Max gas for the L2 retryable ticket execution
     * @param _gasPriceBid Gas price for the L2 retryable ticket execution
     * @param _maxSubmissionCost Max submission price for the L2 retryable ticket
     */
    function removeOnL2(
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external payable;

    /**
     * @dev Add tokens into the billing contract on L2, for any user, using a signed permit
     * @param _user Address of the current owner of the tokens, that will also be the destination in L2
     * @param _amount  Amount of tokens to add
     * @param _maxGas Max gas for the L2 retryable ticket execution
     * @param _gasPriceBid Gas price for the L2 retryable ticket execution
     * @param _maxSubmissionCost Max submission price for the L2 retryable ticket
     * @param _deadline Expiration time of the signed permit
     * @param _v Signature recovery id
     * @param _r Signature r value
     * @param _s Signature s value
     */
    function addToL2WithPermit(
        address _user,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external payable;

    /**
     * @dev Allows the Governor to rescue any ERC20 tokens sent to this contract by accident
     * @param _to  Destination address to send the tokens
     * @param _token  Token address of the token that was accidentally sent to the contract
     * @param _amount  Amount of tokens to pull
     */
    function rescueTokens(
        address _to,
        address _token,
        uint256 _amount
    ) external;
}
