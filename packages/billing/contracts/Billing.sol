// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IBilling } from "./IBilling.sol";
import { Governed } from "./Governed.sol";
import { Rescuable } from "./Rescuable.sol";
import { AddressAliasHelper } from "./arbitrum/AddressAliasHelper.sol";

/**
 * @title Billing Contract
 * @dev The billing contract allows for Graph Tokens to be added by a user. The token can then
 * be pulled by a permissioned set of users named 'collectors'. It is owned and controlled by the 'governor'.
 */
contract Billing is IBilling, Governed, Rescuable {
    // -- State --

    // The contract for interacting with The Graph Token
    IERC20 private immutable graphToken;
    // True for addresses that are Collectors
    mapping(address => bool) public isCollector;

    // maps user address --> user billing balance
    mapping(address => uint256) public userBalances;

    // The L2 token gateway address
    address public l2TokenGateway;

    // The L1 BillingConnector address
    address public l1BillingConnector;

    // -- Events --

    /**
     * @dev User adds tokens
     */
    event TokensAdded(address indexed user, uint256 amount);

    /**
     * @dev User removes tokens
     */
    event TokensRemoved(address indexed from, address indexed to, uint256 amount);

    /**
     * @dev User tried to remove tokens from L1,
     * but they did not have enough balance
     */
    event InsufficientBalanceForRemoval(address indexed from, address indexed to, uint256 amount);

    /**
     * @dev Gateway pulled tokens from a user
     */
    event TokensPulled(address indexed user, uint256 amount);

    /**
     * @dev Collector added or removed
     */
    event CollectorUpdated(address indexed collector, bool enabled);

    /**
     * @dev L2 Token Gateway address updated
     */
    event L2TokenGatewayUpdated(address l2TokenGateway);

    /**
     * @dev L1 BillingConnector address updated
     */
    event L1BillingConnectorUpdated(address l1BillingConnector);

    /**
     * @notice Constructor function for the Billing contract
     * @dev Note that the l1BillingConnector address must be provided
     * afterwards through setL1BillingConnector, since it's expected
     * to be deployed after this one.
     * @param _collector   Initial collector address
     * @param _token     Graph Token address
     * @param _governor  Governor address
     */
    constructor(
        address _collector,
        IERC20 _token,
        address _governor,
        address _l2TokenGateway
    ) Governed(_governor) {
        _setCollector(_collector, true);
        _setL2TokenGateway(_l2TokenGateway);
        graphToken = _token;
    }

    /**
     * @dev Check if the caller is a Collector.
     */
    modifier onlyCollector() {
        require(isCollector[msg.sender], "Caller must be Collector");
        _;
    }

    /**
     * @dev Check if the caller is the L2 token gateway.
     */
    modifier onlyL2TokenGateway() {
        require(msg.sender == l2TokenGateway, "Caller must be L2 token gateway");
        _;
    }

    /**
     * @dev Check if the caller is the L2 alias of the L1 BillingConnector
     */
    modifier onlyL1BillingConnector() {
        require(l1BillingConnector != address(0), "BillingConnector not set");
        require(
            msg.sender == AddressAliasHelper.applyL1ToL2Alias(l1BillingConnector),
            "Caller must be L1 BillingConnector"
        );
        _;
    }

    /**
     * @notice Set or unset an address as an allowed Collector
     * @param _collector  Collector address
     * @param _enabled True to set the _collector address as a Collector, false to remove it
     */
    function setCollector(address _collector, bool _enabled) external override onlyGovernor {
        _setCollector(_collector, _enabled);
    }

    /**
     * @notice Sets the L2 token gateway address
     * @param _l2TokenGateway New address for the L2 token gateway
     */
    function setL2TokenGateway(address _l2TokenGateway) external override onlyGovernor {
        _setL2TokenGateway(_l2TokenGateway);
    }

    /**
     * @notice Sets the L1 Billing Connector address
     * @param _l1BillingConnector New address for the L1 BillingConnector (without any aliasing!)
     */
    function setL1BillingConnector(address _l1BillingConnector) external override onlyGovernor {
        require(_l1BillingConnector != address(0), "L1 Billing Connector cannot be 0");
        l1BillingConnector = _l1BillingConnector;
        emit L1BillingConnectorUpdated(_l1BillingConnector);
    }

    /**
     * @notice Add tokens into the billing contract
     * @dev Ensure graphToken.approve() is called on the billing contract first
     * @param _amount  Amount of tokens to add
     */
    function add(uint256 _amount) external override {
        _pullAndAdd(msg.sender, msg.sender, _amount);
    }

    /**
     * @notice Add tokens into the billing contract for any user
     * @dev Ensure graphToken.approve() is called on the billing contract first
     * @param _to  Address that tokens are being added to
     * @param _amount  Amount of tokens to add
     */
    function addTo(address _to, uint256 _amount) external override {
        _pullAndAdd(msg.sender, _to, _amount);
    }

    /**
     * @notice Receive tokens with a callhook from the Arbitrum GRT bridge
     * @dev Expects an `address user` in the encoded _data.
     * @param _from Token sender in L1
     * @param _amount Amount of tokens that were transferred
     * @param _data ABI-encoded callhook data: contains address that tokens are being added to
     */
    function onTokenTransfer(
        address _from,
        uint256 _amount,
        bytes calldata _data
    ) external override onlyL2TokenGateway {
        require(l1BillingConnector != address(0), "BillingConnector not set");
        require(_from == l1BillingConnector, "Invalid L1 sender!");
        address user = abi.decode(_data, (address));
        _add(user, _amount);
    }

    /**
     * @notice Remove tokens from the billing contract, from L1
     * @dev This can only be called from the BillingConnector on L1.
     * If the user does not have enough balance, rather than reverting,
     * this function will succeed and emit InsufficientBalanceForRemoval.
     * @param _from  Address from which the tokens are removed
     * @param _to Address to send the tokens
     * @param _amount  Amount of tokens to remove
     */
    function removeFromL1(
        address _from,
        address _to,
        uint256 _amount
    ) external override onlyL1BillingConnector {
        require(_to != address(0), "destination != 0");
        require(_amount != 0, "Must remove more than 0");
        if (userBalances[_from] >= _amount) {
            userBalances[_from] = userBalances[_from] - _amount;
            graphToken.transfer(_to, _amount);
            emit TokensRemoved(_from, _to, _amount);
        } else {
            emit InsufficientBalanceForRemoval(_from, _to, _amount);
        }
    }

    /**
     * @notice Add tokens into the billing contract in bulk
     * @dev Ensure graphToken.approve() is called on the billing contract first
     * @param _to  Array of addresses where to add tokens
     * @param _amount  Array of amount of tokens to add to each account
     */
    function addToMany(address[] calldata _to, uint256[] calldata _amount) external override {
        require(_to.length == _amount.length, "Lengths not equal");

        // Get total amount to add
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _amount.length; i++) {
            require(_amount[i] > 0, "Must add more than 0");
            totalAmount += _amount[i];
        }
        graphToken.transferFrom(msg.sender, address(this), totalAmount);

        // Add each amount
        for (uint256 i = 0; i < _to.length; i++) {
            address user = _to[i];
            require(user != address(0), "user != 0");
            userBalances[user] += _amount[i];
            emit TokensAdded(user, _amount[i]);
        }
    }

    /**
     * @notice Remove tokens from the billing contract
     * @dev Tokens will be removed from the sender's balance
     * @param _to  Address that tokens will be sent to
     * @param _amount  Amount of tokens to remove
     */
    function remove(address _to, uint256 _amount) external override {
        require(_to != address(0), "destination != 0");
        require(_amount != 0, "Must remove more than 0");
        require(userBalances[msg.sender] >= _amount, "Too much removed");
        userBalances[msg.sender] = userBalances[msg.sender] - _amount;
        graphToken.transfer(_to, _amount);
        emit TokensRemoved(msg.sender, _to, _amount);
    }

    /**
     * @notice Collector pulls tokens from the billing contract
     * @param _user  Address that tokens are being pulled from
     * @param _amount  Amount of tokens to pull
     * @param _to Destination to send pulled tokens
     */
    function pull(
        address _user,
        uint256 _amount,
        address _to
    ) external override onlyCollector {
        uint256 maxAmount = _pull(_user, _amount);
        _sendTokens(_to, maxAmount);
    }

    /**
     * @notice Collector pulls tokens from many users in the billing contract
     * @param _users  Addresses that tokens are being pulled from
     * @param _amounts  Amounts of tokens to pull from each user
     * @param _to Destination to send pulled tokens
     */
    function pullMany(
        address[] calldata _users,
        uint256[] calldata _amounts,
        address _to
    ) external override onlyCollector {
        require(_users.length == _amounts.length, "Lengths not equal");
        uint256 totalPulled;
        for (uint256 i = 0; i < _users.length; i++) {
            uint256 userMax = _pull(_users[i], _amounts[i]);
            totalPulled = totalPulled + userMax;
        }
        _sendTokens(_to, totalPulled);
    }

    /**
     * @notice Allows the Governor to rescue any ERC20 tokens sent to this contract by accident
     * @param _to  Destination address to send the tokens
     * @param _token  Token address of the token that was accidentally sent to the contract
     * @param _amount  Amount of tokens to pull
     */
    function rescueTokens(
        address _to,
        address _token,
        uint256 _amount
    ) external onlyGovernor {
        _rescueTokens(_to, _token, _amount);
    }

    /**
     * @dev Collector pulls tokens from the billing contract. Uses Math.min() so that it won't fail
     * in the event that a user removes in front of the Collector pulling
     * @param _user  Address that tokens are being pulled from
     * @param _amount  Amount of tokens to pull
     */
    function _pull(address _user, uint256 _amount) internal returns (uint256) {
        uint256 maxAmount = Math.min(_amount, userBalances[_user]);
        if (maxAmount > 0) {
            userBalances[_user] = userBalances[_user] - maxAmount;
            emit TokensPulled(_user, maxAmount);
        }
        return maxAmount;
    }

    /**
     * @dev Send tokens to a destination account
     * @param _to Address where to send tokens
     * @param _amount Amount of tokens to send
     */
    function _sendTokens(address _to, uint256 _amount) internal {
        if (_amount > 0) {
            require(_to != address(0), "Cannot transfer to empty address");
            graphToken.transfer(_to, _amount);
        }
    }

    /**
     * @dev Set or unset an address as an allowed Collector
     * @param _collector  Collector address
     * @param _enabled True to set the _collector address as a Collector, false to remove it
     */
    function _setCollector(address _collector, bool _enabled) internal {
        require(_collector != address(0), "Collector cannot be 0");
        isCollector[_collector] = _enabled;
        emit CollectorUpdated(_collector, _enabled);
    }

    /**
     * @dev Set the new L2 token gateway address
     * @param _l2TokenGateway  New L2 token gateway address
     */
    function _setL2TokenGateway(address _l2TokenGateway) internal {
        require(_l2TokenGateway != address(0), "L2 Token Gateway cannot be 0");
        l2TokenGateway = _l2TokenGateway;
        emit L2TokenGatewayUpdated(_l2TokenGateway);
    }

    /**
     * @dev Pull, then add tokens into the billing contract
     * Ensure graphToken.approve() is called on the billing contract first
     * @param _from  Address that is sending tokens
     * @param _user  User that is adding tokens
     * @param _amount  Amount of tokens to add
     */
    function _pullAndAdd(
        address _from,
        address _user,
        uint256 _amount
    ) private {
        require(_amount != 0, "Must add more than 0");
        require(_user != address(0), "user != 0");
        graphToken.transferFrom(_from, address(this), _amount);
        _add(_user, _amount);
    }

    /**
     * @dev Add tokens into the billing account balance for a user
     * Tokens must already be in this contract's balance
     * @param _user  User that is adding tokens
     * @param _amount  Amount of tokens to add
     */
    function _add(address _user, uint256 _amount) private {
        userBalances[_user] = userBalances[_user] + _amount;
        emit TokensAdded(_user, _amount);
    }
}
