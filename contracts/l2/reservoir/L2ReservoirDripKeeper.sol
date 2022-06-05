// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "../../reservoir/IReservoir.sol";
import "../../gelato/OpsReady.sol";
import "../../governance/Managed.sol";
import "../../upgrades/GraphUpgradeable.sol";

import "arbos-precompiles/arbos/builtin/ArbRetryableTx.sol";

interface INextDripNonce {
    function nextDripNonce() external returns (uint256);
}

contract L2ReservoirDripKeeper is OpsReady, GraphUpgradeable, Managed {
    address internal constant ARB_TX_ADDRESS = address(0x000000000000000000000000000000000000006E);

    /**
     * @dev Initialize this contract.
     * The contract will be paused.
     * @param _controller Address of the Controller that manages this contract
     */
    function initialize(address _controller) external onlyImpl {
        Managed._initialize(_controller);
    }

    /**
     * @dev Redeem a retryable ticket for the L2Reservoir receiveDrip
     * This currently won't work :( because ArbRetryableTx.redeem reverts
     * when called by a contract.
     * @param txId
     */
    function redeemDripWithReward(bytes32 txId) external onlyOps {
        uint256 fee;
        address feeToken;

        (fee, feeToken) = IOps(ops).getFeeDetails();

        // Transfer the reward to Gelato
        _transfer(fee, feeToken);

        INextDripNonce reservoir = INextDripNonce(_resolveContract(keccak256("Reservoir")));
        uint256 beforeNonce = reservoir.nextDripNonce();
        ArbRetryableTx(ARB_TX_ADDRESS).redeem(txId);
        uint256 afterNonce = reservoir.nextDripNonce();
        // Only pay reward if the ticket caused the nonce to increase, i.e. it called receiveDrip successfully
        require(beforeNonce != afterNonce, "TX_DID_NOT_DRIP");
    }
}
