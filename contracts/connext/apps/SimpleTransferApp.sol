pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../adjudicator/interfaces/CounterfactualApp.sol";
import "../funding/libs/LibOutcome.sol";


/// @title SimpleTwoPartySwapApp
/// @notice This contract lets Alice transfer assets to Bob
contract SimpleTransferApp is CounterfactualApp {

    using SafeMath for uint256;

    struct AppState {
        LibOutcome.CoinTransfer[2] coinTransfers;
    }

    function computeOutcome(bytes calldata encodedState)
        override
        external
        view
        returns (bytes memory)
    {
        AppState memory state = abi.decode(encodedState, (AppState));

        uint256 transferAmount = state.coinTransfers[0].amount;

        state.coinTransfers[0].amount = 0;
        state.coinTransfers[1].amount = transferAmount;

        return abi.encode(state.coinTransfers);
    }
}
