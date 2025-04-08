// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27 ;

// We import these here to force Hardhat to compile them.
// This ensures that their artifacts are available for Hardhat Ignition to use.
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";


// These are needed to get artifacts for toolshed
import "@graphprotocol/contracts/contracts/governance/Controller.sol";
import "@graphprotocol/contracts/contracts/upgrades/GraphProxyAdmin.sol";
import "@graphprotocol/contracts/contracts/l2/curation/IL2Curation.sol";