import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { EventfulDataEdge, EventfulDataEdge__factory } from "../build/types";
import { expect } from "chai";

const { getContractFactory, getSigners } = ethers;
const { id, hexConcat, randomBytes, hexlify, defaultAbiCoder } = ethers.utils;

describe("EventfulDataEdge", () => {
  let edge: EventfulDataEdge;
  let me: SignerWithAddress;

  beforeEach(async () => {
    [me] = await getSigners(); // eslint-disable-line @typescript-eslint/no-extra-semi

    const factory = (await getContractFactory(
      "EventfulDataEdge",
      me
    )) as EventfulDataEdge__factory;
    edge = await factory.deploy();
    await edge.deployed();
  });

  describe("submit data", () => {
    it("post any arbitrary data as selector", async () => {
      // virtual function call
      const txRequest = {
        data: "0x123123",
        to: edge.address,
      };
      // send transaction
      const tx = await me.sendTransaction(txRequest);
      const rx = await tx.wait();
      // transaction must work - it just stores data
      expect(rx.status).eq(1);
      // emit log event
      const event = edge.interface.parseLog(rx.logs[0]).args;
      expect(event.data).eq(txRequest.data);
    });

    it("post long calldata", async () => {
      // virtual function call
      const selector = id("setEpochBlocksPayload(bytes)").slice(0, 10);
      // calldata payload
      const messageBlocks = hexlify(randomBytes(1000));
      const txCalldata = defaultAbiCoder.encode(["bytes"], [messageBlocks]); // we abi encode to allow the subgraph to decode it properly
      const txData = hexConcat([selector, txCalldata]);
      // craft full transaction
      const txRequest = {
        data: txData,
        to: edge.address,
      };
      // send transaction
      const tx = await me.sendTransaction(txRequest);
      const rx = await tx.wait();
      // transaction must work - it just stores data
      expect(rx.status).eq(1);
      // emit log event
      const event = edge.interface.parseLog(rx.logs[0]).args;
      expect(event.data).eq(txRequest.data);
    });
  });
});
