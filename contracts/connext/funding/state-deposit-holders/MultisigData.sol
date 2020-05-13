pragma solidity 0.6.7;
pragma experimental ABIEncoderV2;


/// @title MultisigData - data that is kept in the multisig
/// and needs to be made available to contracts that the
/// multisig delegatecalls to, e.g. interpreters.
contract MultisigData {

    // The masterCopy address must occupy the first slot,
    // because we're using the multisig as a proxy.
    // Don't move or remove the following line!
    address masterCopy;

    mapping (address => uint256) public totalAmountWithdrawn;

}
