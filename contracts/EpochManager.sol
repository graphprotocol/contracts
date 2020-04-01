pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

/*
 * @title EpochManager contract
 * @notice
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

    event NewEpoch(uint256 indexed epoch, uint256 blockNumber, address caller);

    /**
     * @dev Contract Constructor
     * @param _governor <address> - Owner address of this contract
     * @param _epochLength <> -
     */
    constructor(address _governor, uint256 _epochLength)
        public
        Governed(_governor)
    {
        require(_epochLength > 0, "Epoch length cannot be 0");

        epochLength = _epochLength;
        lastLengthUpdateEpoch = currentEpoch();
        lastLengthUpdateBlock = currentEpochBlock();
    }

    /**
     * @notice Set epoch length
     * @param _epochLength Epoch length in blocks
     */
    function setEpochLength(uint256 _epochLength) external onlyGovernance {
        require(_epochLength > 0, "Epoch length cannot be 0");

        lastLengthUpdateEpoch = currentEpoch();
        lastLengthUpdateBlock = currentEpochBlock();
        epochLength = _epochLength;
    }

    /**
     * @dev Run a new epoch, should be called once at the start of any epoch
     */
    function runEpoch() external {
        // Check if already called for the current epoch
        require(!isCurrentEpochRun(), "Current epoch already run");

        lastRunEpoch = currentEpoch();

        // Hook for protocol general state updates

        emit NewEpoch(lastRunEpoch, blockNum(), msg.sender);
    }

    /**
     * @dev Return true if the current epoch has already run
     * @return <bool> Return true if epoch has run
     */
    function isCurrentEpochRun() public view returns (bool) {
        return lastRunEpoch == currentEpoch();
    }

    /**
     * @dev Return current block number
     * @return <uint256> Block number
     */
    function blockNum() public view returns (uint256) {
        return block.number;
    }

    /**
     * @dev Return blockhash for a block
     * @return <bytes32> BlockHash for `_block` number
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
     * @return <uint256> The current epoch based on epoch length
     */
    function currentEpoch() public view returns (uint256) {
        return lastLengthUpdateEpoch.add(epochsSinceUpdate());
    }

    /**
     * @dev Return block where the current epoch started
     * @return <uint256> The block number when the current epoch started
     */
    function currentEpochBlock() public view returns (uint256) {
        return lastLengthUpdateBlock.add(epochsSinceUpdate().mul(epochLength));
    }

    /**
     * @dev Return number of epochs passed since last epoch length update
     * @return <uint256> The number of epoch that passed since last epoch length update
     */
    function epochsSinceUpdate() private view returns (uint256) {
        return blockNum().sub(lastLengthUpdateBlock).div(epochLength);
    }
}
