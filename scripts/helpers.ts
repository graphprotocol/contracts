import * as fs from "fs";
import * as path from "path";

import { ContractTransaction, ethers, utils, Wallet } from "ethers";
import { ContractReceipt } from "ethers/contract";
import * as ipfsHttpClient from "ipfs-http-client";
import * as bs58 from "bs58";

import { GnsFactory } from "../build/typechain/contracts/GnsFactory";
import { StakingFactory } from "../build/typechain/contracts/StakingFactory";
import { ServiceRegistryFactory } from "../build/typechain/contracts/ServiceRegistryFactory";
import { GraphTokenFactory } from "../build/typechain/contracts/GraphTokenFactory";
import { CurationFactory } from "../build/typechain/contracts/CurationFactory";

// TODO - make addresses depend on our npm package
let addresses = (JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "addresses.json"), "utf-8")
) as any).kovan;
let privateKey = fs.readFileSync(path.join(__dirname, "..", ".privkey.txt"), "utf-8").trim();
let infuraKey = fs.readFileSync(path.join(__dirname, "..", ".infurakey.txt"), "utf-8").trim();

let ethereum = `https://kovan.infura.io/v3/${infuraKey}`;
let eth = new ethers.providers.JsonRpcProvider(ethereum);
let wallet = Wallet.fromMnemonic(privateKey);
wallet = wallet.connect(eth);

export const contracts = {
  gns: GnsFactory.connect(addresses.gns, wallet),
  staking: StakingFactory.connect(addresses.staking, wallet),
  serviceRegistry: ServiceRegistryFactory.connect(addresses.serviceRegistry, wallet),
  graphToken: GraphTokenFactory.connect(addresses.graphToken, wallet),
  curation: CurationFactory.connect(addresses.curation, wallet)
};

export const executeTransaction = async (
  transaction: Promise<ContractTransaction>
): Promise<ContractReceipt> => {
  try {
    let tx = await transaction;
    console.log(`  Transaction pending: 'https://kovan.etherscan.io/tx/${tx.hash}'`);
    let receipt = await tx.wait(1);
    console.log(`  Transaction successfully included in block #${receipt.blockNumber}`);
    return receipt;
  } catch (e) {
    console.log(`  ..executeTransaction failed: ${e.message}`);
    process.exit(1);
  }
};

export const overrides = async (contract: string, func: string) => {
  const gasPrice = utils.parseUnits("25", "gwei");
  const gasLimit = 1000000;
  // console.log(`\ntx gas price: '${gasPrice}'`);
  // console.log(`tx gas limit: ${gasLimit}`);

  return {
    gasPrice: gasPrice,
    gasLimit: gasLimit
  };

  // TODO - make this unique to each function, but for now just passing 1,000,000
  // const multiplier = utils.bigNumberify(1.5)
  // switch (contract) {
  //   case 'gns':
  //     if (func == 'publish'){
  //       return {
  //         gasLimit: (await contracts.gns.estimate.publish(subgraphName, subgraphIDBytes, metaHashBytes)).mul(
  //           utils.bigNumberify(2))
  //       }
  //     }
  // }
};

export class IPFS {
  static createIpfsClient(node: string): ipfsHttpClient {
    let url: URL;
    try {
      url = new URL(node);
    } catch (e) {
      throw new Error(
        `Invalid IPFS URL: ${node}. ` +
          `The URL must be of the following format: http(s)://host[:port]/[path]`
      );
    }

    return ipfsHttpClient({
      protocol: url.protocol.replace(/[:]+$/, ""),
      host: url.hostname,
      port: url.port,
      "api-path": url.pathname.replace(/\/$/, "") + "/api/v0/"
    });
  }

  static ipfsHashToBytes32(hash: string): Buffer {
    let hashBytes = bs58.decode(hash).slice(2);
    // console.log(`base58 to bytes32: ${hash} -> ${utils.hexlify(hashBytes)}`);
    return hashBytes;
  }
}
