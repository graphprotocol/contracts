// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockRewardsManager
 * @notice A simplified version of RewardsManager for testing purposes
 */
contract MockRewardsManager {
    // State variables
    address public governor;
    uint256 public issuancePerBlock;
    IERC20 public graphToken;
    
    // Events
    event IssuancePerBlockUpdated(uint256 _old, uint256 _new);
    
    /**
     * @notice Constructor
     * @param _graphToken Address of the Graph Token
     * @param _governor Address of the governor
     * @param _issuancePerBlock Issuance per block
     */
    constructor(address _graphToken, address _governor, uint256 _issuancePerBlock) {
        graphToken = IERC20(_graphToken);
        governor = _governor;
        issuancePerBlock = _issuancePerBlock;
    }
    
    /**
     * @notice Set the issuance per block
     * @param _issuancePerBlock New issuance per block
     */
    function setIssuancePerBlock(uint256 _issuancePerBlock) external {
        require(msg.sender == governor, "Only governor can call");
        uint256 oldIssuancePerBlock = issuancePerBlock;
        issuancePerBlock = _issuancePerBlock;
        emit IssuancePerBlockUpdated(oldIssuancePerBlock, _issuancePerBlock);
    }
    
    /**
     * @notice Set the governor
     * @param _governor New governor
     */
    function setGovernor(address _governor) external {
        require(msg.sender == governor, "Only governor can call");
        governor = _governor;
    }
}
