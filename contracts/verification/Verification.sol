// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

contract Verification {
  mapping(address => Connector) private connectorMap;
  mapping(string => address[]) private connectorHashes;
  string[] private hashes;

  struct Connector {
    bool approved;
    bool verified;
  }

  // Can only be called by owner or the verifier service.
  function resetVerificationState() external {
    for (uint i = 0; i < hashes.length; i++) {
      address[] memory addresses = connectorHashes[hashes[i]];

      for (uint _i = 0; _i < addresses.length; _i++) {
        Connector storage connector = connectorMap[addresses[i]];
        connector.verified = false;
      }

      delete connectorHashes[hashes[i]];
    }
  }

  // Can only be called by the owner or the verifier service.
  function setConnectorHash(address _connector, string calldata _queryHash) external {
    connectorHashes[_queryHash].push(_connector);
    connectorMap[_connector].verified = true;
  }

  // Should a connector call this or the gateway will check the connector registry instead
  function connectorIsApproved() external view returns (bool) {
    address _connector = msg.sender;
    return connectorMap[_connector].approved;
  }

  // Can only be called by owner/verifier address. Will either updated approvedConnectors
  // or the connectorRegistry
  function updateApprovedConnectors() external {
    uint highestConnectorsCount;
    string[] memory winningHashes;
    uint winningHashesCount; 

    for (uint i = 0; i < hashes.length; i++) {
      string memory _hash = hashes[i];
      uint connectorCount = connectorHashes[_hash].length;

      if (connectorCount > highestConnectorsCount) {
        highestConnectorsCount = connectorCount;
        delete winningHashes;
        winningHashes[winningHashesCount] = _hash;
        winningHashesCount++;
      }

      if (connectorCount == highestConnectorsCount) {
        winningHashes[winningHashesCount] = _hash;
        winningHashesCount++;
      }

      // We also need to set all Connector.approved to `false`
    }

    for (uint i = 0; i < winningHashes.length; i++) {
      address[] memory connectors = connectorHashes[winningHashes[i]];

      for (uint _i = 0; _i < connectors.length; _i++) {
        Connector storage _connector = connectorMap[connectors[i]];
        _connector.approved = true;
      }
    }
  }
}