// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import "./MinimalProxyFactory.sol";
import "./IGraphTokenLockManager.sol";
import { GraphTokenLockWallet } from "./GraphTokenLockWallet.sol";

/**
 * @title GraphTokenLockManager
 * @notice This contract manages a list of authorized function calls and targets that can be called
 * by any TokenLockWallet contract and it is a factory of TokenLockWallet contracts.
 *
 * This contract receives funds to make the process of creating TokenLockWallet contracts
 * easier by distributing them the initial tokens to be managed.
 *
 * The owner can setup a list of token destinations that will be used by TokenLock contracts to
 * approve the pulling of funds, this way in can be guaranteed that only protocol contracts
 * will manipulate users funds.
 */
contract GraphTokenLockManager is Ownable, MinimalProxyFactory, IGraphTokenLockManager {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // -- State --

    mapping(bytes4 => address) public authFnCalls;
    EnumerableSet.AddressSet private _tokenDestinations;

    address public masterCopy;
    IERC20 internal _token;

    // -- Events --

    event MasterCopyUpdated(address indexed masterCopy);
    event TokenLockCreated(
        address indexed contractAddress,
        bytes32 indexed initHash,
        address indexed beneficiary,
        address token,
        uint256 managedAmount,
        uint256 startTime,
        uint256 endTime,
        uint256 periods,
        uint256 releaseStartTime,
        uint256 vestingCliffTime,
        IGraphTokenLock.Revocability revocable
    );

    event TokensDeposited(address indexed sender, uint256 amount);
    event TokensWithdrawn(address indexed sender, uint256 amount);

    event FunctionCallAuth(address indexed caller, bytes4 indexed sigHash, address indexed target, string signature);
    event TokenDestinationAllowed(address indexed dst, bool allowed);

    /**
     * Constructor.
     * @param _graphToken Token to use for deposits and withdrawals
     * @param _masterCopy Address of the master copy to use to clone proxies
     */
    constructor(IERC20 _graphToken, address _masterCopy) {
        require(address(_graphToken) != address(0), "Token cannot be zero");
        _token = _graphToken;
        setMasterCopy(_masterCopy);
    }

    // -- Factory --

    /**
     * @notice Sets the masterCopy bytecode to use to create clones of TokenLock contracts
     * @param _masterCopy Address of contract bytecode to factory clone
     */
    function setMasterCopy(address _masterCopy) public override onlyOwner {
        require(_masterCopy != address(0), "MasterCopy cannot be zero");
        masterCopy = _masterCopy;
        emit MasterCopyUpdated(_masterCopy);
    }

    /**
     * @notice Creates and fund a new token lock wallet using a minimum proxy
     * @param _owner Address of the contract owner
     * @param _beneficiary Address of the beneficiary of locked tokens
     * @param _managedAmount Amount of tokens to be managed by the lock contract
     * @param _startTime Start time of the release schedule
     * @param _endTime End time of the release schedule
     * @param _periods Number of periods between start time and end time
     * @param _releaseStartTime Override time for when the releases start
     * @param _revocable Whether the contract is revocable
     */
    function createTokenLockWallet(
        address _owner,
        address _beneficiary,
        uint256 _managedAmount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _periods,
        uint256 _releaseStartTime,
        uint256 _vestingCliffTime,
        IGraphTokenLock.Revocability _revocable
    ) external override onlyOwner {
        require(_token.balanceOf(address(this)) >= _managedAmount, "Not enough tokens to create lock");

        // Create contract using a minimal proxy and call initializer
        bytes memory initializer = abi.encodeWithSelector(
            GraphTokenLockWallet.initialize.selector,
            address(this),
            _owner,
            _beneficiary,
            address(_token),
            _managedAmount,
            _startTime,
            _endTime,
            _periods,
            _releaseStartTime,
            _vestingCliffTime,
            _revocable
        );
        address contractAddress = _deployProxy2(keccak256(initializer), masterCopy, initializer);

        // Send managed amount to the created contract
        _token.safeTransfer(contractAddress, _managedAmount);

        emit TokenLockCreated(
            contractAddress,
            keccak256(initializer),
            _beneficiary,
            address(_token),
            _managedAmount,
            _startTime,
            _endTime,
            _periods,
            _releaseStartTime,
            _vestingCliffTime,
            _revocable
        );
    }

    // -- Funds Management --

    /**
     * @notice Gets the GRT token address
     * @return Token used for transfers and approvals
     */
    function token() external view override returns (IERC20) {
        return _token;
    }

    /**
     * @notice Deposits tokens into the contract
     * @dev Even if the ERC20 token can be transferred directly to the contract
     * this function provide a safe interface to do the transfer and avoid mistakes
     * @param _amount Amount to deposit
     */
    function deposit(uint256 _amount) external override {
        require(_amount > 0, "Amount cannot be zero");
        _token.safeTransferFrom(msg.sender, address(this), _amount);
        emit TokensDeposited(msg.sender, _amount);
    }

    /**
     * @notice Withdraws tokens from the contract
     * @dev Escape hatch in case of mistakes or to recover remaining funds
     * @param _amount Amount of tokens to withdraw
     */
    function withdraw(uint256 _amount) external override onlyOwner {
        require(_amount > 0, "Amount cannot be zero");
        _token.safeTransfer(msg.sender, _amount);
        emit TokensWithdrawn(msg.sender, _amount);
    }

    // -- Token Destinations --

    /**
     * @notice Adds an address that can be allowed by a token lock to pull funds
     * @param _dst Destination address
     */
    function addTokenDestination(address _dst) external override onlyOwner {
        require(_dst != address(0), "Destination cannot be zero");
        require(_tokenDestinations.add(_dst), "Destination already added");
        emit TokenDestinationAllowed(_dst, true);
    }

    /**
     * @notice Removes an address that can be allowed by a token lock to pull funds
     * @param _dst Destination address
     */
    function removeTokenDestination(address _dst) external override onlyOwner {
        require(_tokenDestinations.remove(_dst), "Destination already removed");
        emit TokenDestinationAllowed(_dst, false);
    }

    /**
     * @notice Returns True if the address is authorized to be a destination of tokens
     * @param _dst Destination address
     * @return True if authorized
     */
    function isTokenDestination(address _dst) external view override returns (bool) {
        return _tokenDestinations.contains(_dst);
    }

    /**
     * @notice Returns an array of authorized destination addresses
     * @return Array of addresses authorized to pull funds from a token lock
     */
    function getTokenDestinations() external view override returns (address[] memory) {
        address[] memory dstList = new address[](_tokenDestinations.length());
        for (uint256 i = 0; i < _tokenDestinations.length(); i++) {
            dstList[i] = _tokenDestinations.at(i);
        }
        return dstList;
    }

    // -- Function Call Authorization --

    /**
     * @notice Sets an authorized function call to target
     * @dev Input expected is the function signature as 'transfer(address,uint256)'
     * @param _signature Function signature
     * @param _target Address of the destination contract to call
     */
    function setAuthFunctionCall(string calldata _signature, address _target) external override onlyOwner {
        _setAuthFunctionCall(_signature, _target);
    }

    /**
     * @notice Unsets an authorized function call to target
     * @dev Input expected is the function signature as 'transfer(address,uint256)'
     * @param _signature Function signature
     */
    function unsetAuthFunctionCall(string calldata _signature) external override onlyOwner {
        bytes4 sigHash = _toFunctionSigHash(_signature);
        authFnCalls[sigHash] = address(0);

        emit FunctionCallAuth(msg.sender, sigHash, address(0), _signature);
    }

    /**
     * @notice Sets an authorized function call to target in bulk
     * @dev Input expected is the function signature as 'transfer(address,uint256)'
     * @param _signatures Function signatures
     * @param _targets Address of the destination contract to call
     */
    function setAuthFunctionCallMany(
        string[] calldata _signatures,
        address[] calldata _targets
    ) external override onlyOwner {
        require(_signatures.length == _targets.length, "Array length mismatch");

        for (uint256 i = 0; i < _signatures.length; i++) {
            _setAuthFunctionCall(_signatures[i], _targets[i]);
        }
    }

    /**
     * @notice Sets an authorized function call to target
     * @dev Input expected is the function signature as 'transfer(address,uint256)'
     * @dev Function signatures of Graph Protocol contracts to be used are known ahead of time
     * @param _signature Function signature
     * @param _target Address of the destination contract to call
     */
    function _setAuthFunctionCall(string calldata _signature, address _target) internal {
        require(_target != address(this), "Target must be other contract");
        require(Address.isContract(_target), "Target must be a contract");

        bytes4 sigHash = _toFunctionSigHash(_signature);
        authFnCalls[sigHash] = _target;

        emit FunctionCallAuth(msg.sender, sigHash, _target, _signature);
    }

    /**
     * @notice Gets the target contract to call for a particular function signature
     * @param _sigHash Function signature hash
     * @return Address of the target contract where to send the call
     */
    function getAuthFunctionCallTarget(bytes4 _sigHash) public view override returns (address) {
        return authFnCalls[_sigHash];
    }

    /**
     * @notice Returns true if the function call is authorized
     * @param _sigHash Function signature hash
     * @return True if authorized
     */
    function isAuthFunctionCall(bytes4 _sigHash) external view override returns (bool) {
        return getAuthFunctionCallTarget(_sigHash) != address(0);
    }

    /**
     * @dev Converts a function signature string to 4-bytes hash
     * @param _signature Function signature string
     * @return Function signature hash
     */
    function _toFunctionSigHash(string calldata _signature) internal pure returns (bytes4) {
        return _convertToBytes4(abi.encodeWithSignature(_signature));
    }

    /**
     * @dev Converts function signature bytes to function signature hash (bytes4)
     * @param _signature Function signature
     * @return Function signature in bytes4
     */
    function _convertToBytes4(bytes memory _signature) internal pure returns (bytes4) {
        require(_signature.length == 4, "Invalid method signature");
        bytes4 sigHash;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sigHash := mload(add(_signature, 32))
        }
        return sigHash;
    }
}
