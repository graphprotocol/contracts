#!/usr/bin/env ts-node
import { utils } from "ethers";
import * as path from "path";
import * as minimist from "minimist";

import { contracts, executeTransaction, overrides } from "./helpers";
///////////////////////
// Set up the script //
///////////////////////

let { func, id, amount } = minimist(process.argv.slice(2), {
  string: ["id", "amount"]
});

if (!func || !id || !amount) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --func <text> - options: stake, redeem

Function arguments:
  stake
    --id <bytes32>      - The subgraph deployment ID being curated on
    --amount <number>   - Amount of tokens being signaled

  redeem
    --id <bytes32>      - The subgraph deployment ID being curated on
    --amount <number>   - Amount of shares being redeemed
    `
  );
  process.exit(1);
}
///////////////////////
// functions //////////
///////////////////////

const amountBN = utils.parseUnits(amount, 18);

const stake = async () => {
  console.log("  First calling approve() to ensure curation contract can call transferFrom()...");
  const approveOverrides = await overrides("graphToken", "approve");
  await executeTransaction(
    contracts.graphToken.functions.approve(contracts.curation.address, amountBN, approveOverrides)
  );
  console.log("\n");

  console.log("  Now calling stake() on curation...");
  const stakeOverrides = await overrides("curation", "stake");
  await executeTransaction(contracts.curation.functions.stake(id, amountBN, stakeOverrides));
};

const redeem = async () => {
  const redeemOverrides = await overrides("curation", "redeem");
  // Redeeming does not need Big Number
  await executeTransaction(contracts.curation.functions.redeem(id, amount, redeemOverrides));
};

///////////////////////
// main ///////////////
///////////////////////

const main = async () => {
  try {
    if (func == "stake") {
      console.log(`Signaling on ${id} with ${amount} tokens...`);
      stake();
    } else if (func == "redeem") {
      console.log(`Redeeming ${amount} shares on ${id}...`);
      redeem();
    }
  } catch (e) {
    console.log(`  ..failed within main: ${e.message}`);
    process.exit(1);
  }
};

main();
