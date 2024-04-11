// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface IDataService {
    function register(address serviceProvider, bytes calldata data) external;
}
