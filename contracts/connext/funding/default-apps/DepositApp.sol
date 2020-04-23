pragma solidity 0.5.11;
pragma experimental "ABIEncoderV2";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../adjudicator/interfaces/CounterfactualApp.sol";
import "../state-deposit-holders/MinimumViableMultisig.sol";
import "../libs/LibOutcome.sol";


/// @title Deposit App
/// @notice This contract allows a user to trustlessly deposit into a channel
///         by attributing the difference in value of multisig to the depositor

///         THIS CONTRACT WILL ONLY WORK FOR 2-PARTY CHANNELS!
contract DepositApp is CounterfactualApp {

    address constant CONVENTION_FOR_ETH_TOKEN_ADDRESS = address(0x0);

    struct AppState {
        LibOutcome.CoinTransfer[2] transfers; // both amounts should be 0 in initial state
        address payable multisigAddress;
        address assetId;
        uint256 startingTotalAmountWithdrawn;
        uint256 startingMultisigBalance;
    }

    function computeOutcome(bytes calldata encodedState)
        external
        view
        returns (bytes memory)
    {
        AppState memory state = abi.decode(encodedState, (AppState));

        uint256 endingTotalAmountWithdrawn;
        uint256 endingMultisigBalance;

        if (isDeployed(state.multisigAddress)) {
            endingTotalAmountWithdrawn = MinimumViableMultisig(state.multisigAddress).totalAmountWithdrawn(state.assetId);
        } else {
            endingTotalAmountWithdrawn = 0;
        }

        if (state.assetId == CONVENTION_FOR_ETH_TOKEN_ADDRESS) {
            endingMultisigBalance = state.multisigAddress.balance;
        } else {
            endingMultisigBalance = ERC20(state.assetId).balanceOf(state.multisigAddress);
        }

        return abi.encode(LibOutcome.CoinTransfer[2]([
            LibOutcome.CoinTransfer(
                state.transfers[0].to,
                // NOTE: deliberately do NOT use safemath here. For more info, see: TODO
                (endingMultisigBalance - state.startingMultisigBalance) +
                        (endingTotalAmountWithdrawn - state.startingTotalAmountWithdrawn)
            ),
            LibOutcome.CoinTransfer(
                state.transfers[1].to,
                /* should always be 0 */
                0
            )
        ]));
    }

    function isDeployed(address _addr)
        internal
        view
    returns (bool)
    {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }
}
