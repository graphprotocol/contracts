pragma solidity ^0.6.4;

/**
 * @title Graph Governance contract
 * @dev All contracts that will be owned by a Governor entity should extend this contract.
 */
contract Governed {
    // -- State --

    address public governor;
    address public pendingGovernor;

    // -- Events --

    event NewPendingOwnership(address indexed from, address indexed to);
    event NewOwnership(address indexed from, address indexed to);
    event ParameterUpdated(string param);

    /**
     * @dev Check if the caller is the governor.
     */
    modifier onlyGovernor {
        require(msg.sender == governor, "Only Governor can call");
        _;
    }

    /**
     * @dev Initialize the governor to the contract caller.
     */
    function _initialize(address _governor) internal {
        governor = _governor;
    }

    /**
     * @dev Admin function to begin change of governor. The `_newGovernor` must call
     * `acceptOwnership` to finalize the transfer.
     * @param _newGovernor Address of new `governor`
     */
    function transferOwnership(address _newGovernor) external onlyGovernor {
        address oldPendingGovernor = pendingGovernor;
        pendingGovernor = _newGovernor;

        emit NewPendingOwnership(oldPendingGovernor, pendingGovernor);
    }

    /**
     * @dev Admin function for pending governor to accept role and update governor.
     * This function must called by the pending governor.
     */
    function acceptOwnership() external {
        require(
            pendingGovernor != address(0) && msg.sender == pendingGovernor,
            "Caller must be pending governor"
        );

        address oldGovernor = governor;
        address oldPendingGovernor = pendingGovernor;

        governor = pendingGovernor;
        pendingGovernor = address(0);

        emit NewOwnership(oldGovernor, governor);
        emit NewPendingOwnership(oldPendingGovernor, pendingGovernor);
    }
}
