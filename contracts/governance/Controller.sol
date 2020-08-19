pragma solidity ^0.6.4;

import "./IController.sol";
import "./IManager.sol";
import "./Governed.sol";

/**
 * @title Graph Controller contract
 * @dev Controller is a registry of contracts for convience. Inspired by Livepeer:
 * https://github.com/livepeer/protocol/blob/streamflow/contracts/Controller.sol
 */
contract Controller is IController, Governed {
    // Track contract ids to contract proxy address
    mapping(bytes32 => address) private registry;

    // Todo - add in guardian, but in the next PR

    constructor(address _governor) public {
        Governed._initialize(_governor);
    }

    /**
     * @notice Register contract id and mapped address
     * @param _id Contract id (keccak256 hash of contract name)
     * @param _contractAddress Contract address
     */
    function setContract(
        bytes32 _id,
        address _contractAddress,
    ) external onlyOwner {
        registry[_id].contractAddress = _contractAddress;
        emit SetContractInfo(_id, _contractAddress);
    }

    /**
     * @notice Update contract's controller
     * @param _id Contract id (keccak256 hash of contract name)
     * @param _controller Controller address
     */
    function updateController(bytes32 _id, address _controller) external onlyGovernor {
        return IManager(registry[_id]).setController(_controller);
    }

    /**
     * @notice Get contract proxy address by its id
     * @param _id Contract id
     */
    function getContractProxy(bytes32 _id) public view returns (address) {
        return registry[_id];
    }
}
