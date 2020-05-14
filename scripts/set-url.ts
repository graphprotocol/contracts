#!/usr/bin/env ts-node

import { utils } from "ethers";
import * as path from "path";
import * as minimist from "minimist";

import { contracts } from "./helpers";

let { url } = minimist(process.argv.slice(2), {
  string: ["url"]
});

if (!url) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])} \
--url <url>
`
  );
  process.exit(1);
}

console.log("URL:    ", url);

const main = async () => {
  try {
    console.log("Set indexer URL...");
    let tx = await contracts.serviceRegistry.functions.setUrl(url, {
      gasLimit: 1000000,
      gasPrice: utils.parseUnits("10", "gwei")
    });
    console.log(`  ..pending: https://ropsten.etherscan.io/tx/${tx.hash}`);
    await tx.wait(1);
    console.log(`  ..success`);
  } catch (e) {
    console.log(`  ..failed: ${e.message}`);
    process.exit(1);
  }

  //
};

main();
