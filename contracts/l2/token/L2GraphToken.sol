// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { GraphTokenUpgradeable } from "./GraphTokenUpgradeable.sol";
import { IArbToken } from "../../arbitrum/IArbToken.sol";

/**
 * @title L2 Graph Token Contract
 * @dev Provides the L2 version of the GRT token, meant to be minted/burned
 * through the L2GraphTokenGateway.
 */
contract L2GraphToken is GraphTokenUpgradeable, IArbToken {
    /// Address of the gateway (on L2) that is allowed to mint tokens
    address public gateway;
    /// Address of the corresponding Graph Token contract on L1
    address public override l1Address;

    /// Emitted when the bridge / gateway has minted new tokens, i.e. tokens were transferred to L2
    event BridgeMinted(address indexed account, uint256 amount);
    /// Emitted when the bridge / gateway has burned tokens, i.e. tokens were transferred back to L1
    event BridgeBurned(address indexed account, uint256 amount);
    /// Emitted when the address of the gateway has been updated
    event GatewaySet(address gateway);
    /// Emitted when the address of the Graph Token contract on L1 has been updated
    event L1AddressSet(address l1Address);

    /**
     * @dev Checks that the sender is the L2 gateway from the L1/L2 token bridge
     */
    modifier onlyGateway() {
        require(msg.sender == gateway, "NOT_GATEWAY");
        _;
    }

    /**
     * @notice L2 Graph Token Contract initializer.
     * @dev Note some parameters have to be set separately as they are generally
     * not expected to be available at initialization time:
     * - gateway using setGateway
     * - l1Address using setL1Address
     * @param _owner Governance address that owns this contract
     */
    function initialize(address _owner) external onlyImpl initializer {
        require(_owner != address(0), "Owner must be set");
        // Initial supply hard coded to 0 as tokens are only supposed
        // to be minted through the bridge.
        GraphTokenUpgradeable._initialize(_owner, 0);
    }

    /**
     * @notice Sets the address of the L2 gateway allowed to mint tokens
     * @param _gw Address for the L2GraphTokenGateway that will be allowed to mint tokens
     */
    function setGateway(address _gw) external onlyGovernor {
        require(_gw != address(0), "INVALID_GATEWAY");
        gateway = _gw;
        emit GatewaySet(_gw);
    }

    /**
     * @notice Sets the address of the counterpart token on L1
     * @param _addr Address for the GraphToken contract on L1
     */
    function setL1Address(address _addr) external onlyGovernor {
        require(_addr != address(0), "INVALID_L1_ADDRESS");
        l1Address = _addr;
        emit L1AddressSet(_addr);
    }

    /**
     * @notice Increases token supply, only callable by the L1/L2 bridge (when tokens are transferred to L2)
     * @param _account Address to credit with the new tokens
     * @param _amount Number of tokens to mint
     */
    function bridgeMint(address _account, uint256 _amount) external override onlyGateway {
        _mint(_account, _amount);
        emit BridgeMinted(_account, _amount);
    }

    /**
     * @notice Decreases token supply, only callable by the L1/L2 bridge (when tokens are transferred to L1).
     * @param _account Address from which to extract the tokens
     * @param _amount Number of tokens to burn
     */
    function bridgeBurn(address _account, uint256 _amount) external override onlyGateway {
        burnFrom(_account, _amount);
        emit BridgeBurned(_account, _amount);
    }
}
