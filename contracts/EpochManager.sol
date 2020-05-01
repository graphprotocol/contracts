pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

/*
 * @title EpochManager contract
 * @notice Tracks epochs based on its block duration to sync contracts in the protocol.
 */

import "./Governed.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";


contract EpochManager is Governed {
    using SafeMath for uint256;

    // -- State --

    // Epoch length in blocks
    uint256 public epochLength;

    // Epoch that was last run
    uint256 public lastRunEpoch;

    // Block and epoch when epoch length was last updated
    uint256 public lastLengthUpdateEpoch;
    uint256 public lastLengthUpdateBlock;

    // -- Events --

    event EpochRun(uint256 indexed epoch, address caller);
    event EpochLengthUpdate(uint256 indexed epoch, uint256 epochLength);

    /**
     * @dev Contract Constructor
     * @param _governor Owner address of this contract
     * @param _epochLength Epoch length in blocks
     */
    constructor(address _governor, uint256 _epochLength) public Governed(_governor) {
        require(_epochLength > 0, "Epoch length cannot be 0");

        lastLengthUpdateEpoch = 0;
        lastLengthUpdateBlock = blockNum();
        epochLength = _epochLength;

        emit EpochLengthUpdate(lastLengthUpdateEpoch, epochLength);
    }

    /**
     * @dev Set the epoch length
     * @notice Set epoch length to `_epochLength` blocks
     * @param _epochLength Epoch length in blocks
     */
    function setEpochLength(uint256 _epochLength) external onlyGovernor {
        require(_epochLength > 0, "Epoch length cannot be 0");
        require(_epochLength != epochLength, "Epoch length must be different to current");

        lastLengthUpdateEpoch = currentEpoch();
        lastLengthUpdateBlock = currentEpochBlock();
        epochLength = _epochLength;

        emit EpochLengthUpdate(lastLengthUpdateEpoch, epochLength);
    }

    /**
     * @dev Run a new epoch, should be called once at the start of any epoch
     * @notice Perform state changes for the current epoch
     */
    function runEpoch() external {
        // Check if already called for the current epoch
        require(!isCurrentEpochRun(), "Current epoch already run");

        lastRunEpoch = currentEpoch();

        // Hook for protocol general state updates

        emit EpochRun(lastRunEpoch, msg.sender);
    }

    /**
     * @dev Return true if the current epoch has already run
     * @return Return true if epoch has run
     */
    function isCurrentEpochRun() public view returns (bool) {
        return lastRunEpoch == currentEpoch();
    }

    /**
     * @dev Return current block number
     * @return Block number
     */
    function blockNum() public view returns (uint256) {
        return block.number;
    }

    /**
     * @dev Return blockhash for a block
     * @return BlockHash for `_block` number
     */
    function blockHash(uint256 _block) public view returns (bytes32) {
        uint256 currentBlock = blockNum();

        require(_block < currentBlock, "Can only retrieve past block hashes");
        require(
            currentBlock < 256 || _block >= currentBlock - 256,
            "Can only retrieve hashes for last 256 blocks"
        );

        return blockhash(_block);
    }

    /**
     * @dev Return the current epoch, it may have not been run yet
     * @return The current epoch based on epoch length
     */
    function currentEpoch() public view returns (uint256) {
        return lastLengthUpdateEpoch.add(epochsSinceUpdate());
    }

    /**
     * @dev Return block where the current epoch started
     * @return The block number when the current epoch started
     */
    function currentEpochBlock() public view returns (uint256) {
        return lastLengthUpdateBlock.add(epochsSinceUpdate().mul(epochLength));
    }

    /**
     * @dev Return the number of blocks that passed since current epoch started
     * @return Blocks that passed since start of epoch
     */
    function currentEpochBlockSinceStart() public view returns (uint256) {
        return blockNum() - currentEpochBlock();
    }

    /**
     * @dev Return the number of epoch that passed since another epoch
     * @param _epoch Epoch to use as since epoch value
     * @return Number of epochs and current epoch
     */
    function epochsSince(uint256 _epoch) public view returns (uint256, uint256) {
        uint256 epoch = currentEpoch();
        return (epoch.sub(_epoch), epoch);
    }

    /**
     * @dev Return number of epochs passed since last epoch length update
     * @return The number of epoch that passed since last epoch length update
     */
    function epochsSinceUpdate() public view returns (uint256) {
        return blockNum().sub(lastLengthUpdateBlock).div(epochLength);
    }
}
