pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../adjudicator/interfaces/CounterfactualApp.sol";
import "../funding/libs/LibOutcome.sol";


/// @title SimpleTwoPartySwapApp
/// @notice This contract lets two parties swap one ERC20 or ETH asset for another
contract SimpleTwoPartySwapApp is CounterfactualApp {

    using SafeMath for uint256;

    struct AppState {
        LibOutcome.CoinTransfer[][] coinTransfers;
    }

    function computeOutcome(bytes calldata encodedState)
        override
        external
        view
        returns (bytes memory)
    {
        AppState memory state = abi.decode(encodedState, (AppState));

        uint256 amountsA = state.coinTransfers[0][0].amount;
        uint256 amountsB = state.coinTransfers[1][0].amount;

        state.coinTransfers[0][0].amount = amountsB;
        state.coinTransfers[1][0].amount = amountsA;

        return abi.encode(state.coinTransfers);
    }
}
