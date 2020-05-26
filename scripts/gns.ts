#!/usr/bin/env ts-node

import { utils } from "ethers";
import * as path from "path";
import * as minimist from "minimist";

import { contracts, executeTransaction, overrides, IPFS } from "./helpers";

///////////////////////
// Set up the script //
///////////////////////

let { func, subgraphName, ipfs, subgraphID, metadataPath, newOwner } = minimist(
  process.argv.slice(2),
  {
    string: ["func", "subgraphName", "ipfs", "subgraphID", "metadataPath", "newOwner"]
  }
);

if (!func || !subgraphName) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
    --func <text> - options: publish, unpublish, transfer

Function arguments:
    publish
      --ipfs <url>            - ex. https://api.thegraph.com/ipfs/
      --subgraphName <text>   - name of the subgraph
      --subgraphID <base58>   - subgraphID in bas358
      --metadata <path>       - filepath to metadata. JSON format:
                                  {
                                    "displayName": "",
                                    "image": "",
                                    "description": "",
                                    "codeRepository": "",
                                    "websiteURL": ""
                                  }
    
    unpublish
      --subgraphName <text>  - name of the subgraph

    transfer
      --subgraphName <text>  - name of the subgraph
      --new-owner <address>   - address of the new owner
`
  );
  process.exit(1);
}

///////////////////////
// functions //////////
///////////////////////

const publish = async () => {
  if (!ipfs || !subgraphID || !metadataPath) {
    console.error(`ERROR: publish must be provided an ipfs endpoint and a subgraphID`);
    process.exit(1);
  }
  console.log("Subgraph:      ", subgraphName);
  console.log("Subgraph ID:   ", subgraphID);
  console.log("IPFS:          ", ipfs);
  console.log("Metadata path: ", metadataPath);

  const metadata = require(metadataPath);
  console.log("Meta data:");
  console.log("  Display name:     ", metadata.displayName || "");
  console.log("  Image:            ", metadata.image || "");
  console.log("  Subtitle:         ", metadata.subtitle || "");
  console.log("  Description:      ", metadata.description || "");
  console.log("  Code Repository:  ", metadata.codeRepository || "");
  console.log("  Website:          ", metadata.websiteURL || "");

  let ipfsClient = IPFS.createIpfsClient(ipfs);

  console.log("\nUpload JSON meta data to IPFS...");
  let result = await ipfsClient.add(Buffer.from(JSON.stringify(metadata)));
  let metaHash = result[0].hash;
  let metaHashBytes = IPFS.ipfsHashToBytes32(metaHash);
  try {
    let data = JSON.parse(await ipfsClient.cat(metaHash));
    if (JSON.stringify(data) !== JSON.stringify(metadata)) {
      throw new Error(`Original meta data and uploaded data are not identical`);
    }
  } catch (e) {
    throw new Error(`Failed to retrieve and parse JSON meta data after uploading: ${e.message}`);
  }
  console.log("Upload metadata successful!\n");

  let subgraphIDBytes = IPFS.ipfsHashToBytes32(subgraphID);
  const gnsOverrides = await overrides("gns", "publish");
  try {
    await executeTransaction(
      contracts.gns.functions.publish(subgraphName, subgraphIDBytes, metaHashBytes, gnsOverrides)
    );
  } catch (e) {
    console.log(`  ..failed: ${e.message}`);
    process.exit(1);
  }
};

const unpublish = async () => {
  console.log("Subgraph:           ", subgraphName);
  let nameHash = utils.id(subgraphName);
  console.log("Subgraph name hash: ", nameHash);
  console.log("\n");
  const gnsOverrides = await overrides("gns", "unpublish");
  try {
    await executeTransaction(contracts.gns.functions.unpublish(nameHash, gnsOverrides));
  } catch (e) {
    console.log(`  ..failed: ${e.message}`);
    process.exit(1);
  }
};

const transfer = async () => {
  if (!newOwner) {
    console.error(`ERROR: transfer must be provided a new owner`);
    process.exit(1);
  }
  console.log("Subgraph:           ", subgraphName);
  let nameHash = utils.id(subgraphName);
  console.log("Subgraph name hash: ", nameHash);
  console.log("New owner:          ", newOwner);
  console.log("\n");
  const gnsOverrides = await overrides("gns", "unpublish");
  try {
    await executeTransaction(contracts.gns.functions.transfer(nameHash, newOwner, gnsOverrides));
  } catch (e) {
    console.log(`  ..failed: ${e.message}`);
    process.exit(1);
  }
};

///////////////////////
// main ///////////////
///////////////////////

const main = async () => {
  try {
    if (func == "publish") {
      console.log(`Publishing subgraph ${subgraphName} ...`);
      publish();
    } else if (func == "unpublish") {
      console.log(`Unpublishing subgraph ${subgraphName} ...`);
      unpublish();
    } else if (func == "transfer") {
      console.log(`Transferring ownership of subgraph ${subgraphName} to ${newOwner}`);
      transfer();
    }
  } catch (e) {
    console.log(`  ..failed: ${e.message}`);
    process.exit(1);
  }
};

main();
