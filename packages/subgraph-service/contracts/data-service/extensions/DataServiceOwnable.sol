// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { DataService } from "../DataService.sol";

abstract contract DataServiceOwnable is Ownable, DataService {
    constructor(address _owner) Ownable(_owner) {}

    function slash(address serviceProvider, bytes calldata data) external virtual override onlyOwner {
        (uint256 tokens, uint256 reward) = abi.decode(data, (uint256, uint256));
        graphStaking.slash(serviceProvider, tokens, reward, owner());
    }
}
