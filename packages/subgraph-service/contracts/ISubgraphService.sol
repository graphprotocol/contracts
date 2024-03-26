// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

interface ISubgraphService {
    // register as a provider in the data service
    function register(address provisionId, string calldata url, string calldata geohash, uint256 delegatorQueryFeeCut)
        external;

    // register as a provider in the data service, create the required provision first
    // function provisionAndRegister(
    //     uint256 tokens,
    //     string calldata url,
    //     string calldata geohash,
    //     uint256 delegatorQueryFeeCut
    // ) external;
}
