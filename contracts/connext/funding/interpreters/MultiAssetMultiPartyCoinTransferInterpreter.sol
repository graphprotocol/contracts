pragma solidity 0.5.11;
pragma experimental "ABIEncoderV2";

import "../state-deposit-holders/MultisigTransfer.sol";
import "../libs/LibOutcome.sol";
import "../Interpreter.sol";


contract MultiAssetMultiPartyCoinTransferInterpreter is MultisigTransfer, Interpreter {

    uint256 constant MAX_UINT256 = 2 ** 256 - 1;

    struct MultiAssetMultiPartyCoinTransferInterpreterParams {
        uint256[] limit;
        address[] tokenAddresses;
    }

    // NOTE: This is useful for writing tests, but is bad practice
    // to have in the contract when deploying it. We do not want people
    // to send funds to this contract in any scenario.
    function () external payable { }

    function interpretOutcomeAndExecuteEffect(
        bytes calldata encodedOutcome,
        bytes calldata encodedParams
    )
        external
    {
        MultiAssetMultiPartyCoinTransferInterpreterParams memory params = abi.decode(
            encodedParams,
            (MultiAssetMultiPartyCoinTransferInterpreterParams)
        );

        LibOutcome.CoinTransfer[][] memory coinTransferListOfLists = abi.decode(
            encodedOutcome,
            (LibOutcome.CoinTransfer[][])
        );

        for (uint256 i = 0; i < coinTransferListOfLists.length; i++) {

            address tokenAddress = params.tokenAddresses[i];
            uint256 limitRemaining = params.limit[i];
            LibOutcome.CoinTransfer[] memory coinTransferList = coinTransferListOfLists[i];

            for (uint256 j = 0; j < coinTransferList.length; j++) {

                LibOutcome.CoinTransfer memory coinTransfer = coinTransferList[j];

                address payable to = address(uint160(coinTransfer.to));

                if (coinTransfer.amount > 0) {
                    limitRemaining -= coinTransfer.amount;
                    multisigTransfer(to, tokenAddress, coinTransfer.amount);
                }

            }

            // NOTE: If the limit is MAX_UINT256 it can bypass this check.
            // We do this for the FreeBalanceApp since its values change.
            if (params.limit[i] != MAX_UINT256) {
                require(
                    limitRemaining == 0,
                    "Sum of total amounts received from outcome did not equate to limits."
                );
            }

        }
    }

}
