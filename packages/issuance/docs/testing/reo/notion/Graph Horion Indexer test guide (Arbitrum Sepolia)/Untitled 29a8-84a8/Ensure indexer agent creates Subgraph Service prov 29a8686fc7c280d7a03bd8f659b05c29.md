# Ensure indexer agent creates Subgraph Service provision and registers

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: Done
Man4ela: Done
p2p: Not started

On phase 4, and assuming the conditions described here ([Phase 4](https://www.notion.so/Phase-4-26c8686fc7c28007adfdf48cbc7a57e1?pvs=21)) are met the indexer agent should automatically create the Subgraph Service provision for the indexer.

### Pass criteria

The provisions entity in the network subgraph should show:

- indexer registration data: url and geoHash
- tokensProvisioned should be at most `INDEXER_AGENT_MAX_PROVISION_INITIAL_SIZE`

```bash
{
	provisions(where:{ indexer_: { id: "INDEXER_ADDRESS_LOWERCASE" } }) {
    id
    url
    geoHash
    indexer {
      id
    }
    tokensProvisioned
  }
}
```

- Example of indexer agent logs for a successful provision creation and registration
    
    ```bash
    [11:13:27.586] INFO (IndexerAgent/1): Creating provision
        component: "Network"
        indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        protocolNetwork: "eip155:421614"
        operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        address: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        tokens: "500000.0"
        thawingPeriod: 28800
        maxVerifierCut: 500000
    [11:13:28.896] INFO (IndexerAgent/1): Sending transaction
        component: "Network"
        indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        protocolNetwork: "eip155:421614"
        operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        address: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        function: "horizonStaking.provision"
        txConfig: {
          "attempt": 1,
          "gasBump": 1200,
          "gasLimit": 190988,
          "maxFeePerGas": 200000000,
          "maxPriorityFeePerGas": 0,
          "nonce": 7,
          "type": 0
        }
    [11:13:28.896] INFO (IndexerAgent/1): Transaction pending
        component: "Network"
        indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        protocolNetwork: "eip155:421614"
        operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        address: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        function: "horizonStaking.provision"
        tx: {
          "_type": "TransactionResponse",
          "accessList": [],
          "blockNumber": null,
          "blockHash": null,
          "blobVersionedHashes": null,
          "chainId": "421614",
          "data": "0x010167e5000000000000000000000000b0188c4d02eab4d444c1678f1ede9f790ffc838e000000000000000000000000c24a3dac5d06d771f657a48b20ce1a671b78f26b0000000000000000000000000000000000000000000069e10de76676d0800000000000000000000000000000000000000000000000000000000000000007a1200000000000000000000000000000000000000000000000000000000000007080",
          "from": "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e",
          "gasLimit": "190988",
          "gasPrice": null,
          "hash": "0x2a732e4ec63b3c5324341634527b33c18554138b8c9450b57ab97cc85fb72f73",
          "maxFeePerGas": "200000000",
          "maxPriorityFeePerGas": "0",
          "maxFeePerBlobGas": null,
          "nonce": 7,
          "signature": {
            "_type": "signature",
            "networkV": null,
            "r": "0x87890f49214698e823e188502f60f543493c3c331c1111f62cf4ff31c869173a",
            "s": "0x644a5a768276ad7044aa5f4b37dd27c488068b29297d5910e566255f7a507cfb",
            "v": 28
          },
          "to": "0x865365C425f3A593Ffe698D9c4E6707D14d51e08",
          "type": 2,
          "value": "0"
        }
        confirmationBlocks: 3
    [11:13:37.686] INFO (IndexerAgent/1): Transaction successfully included in block
        component: "Network"
        indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        protocolNetwork: "eip155:421614"
        operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        address: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        function: "horizonStaking.provision"
        tx: "0x2a732e4ec63b3c5324341634527b33c18554138b8c9450b57ab97cc85fb72f73"
        receipt: {
          "_type": "TransactionReceipt",
          "blockHash": "0x7636a6d0e61612f3670394f7562f404a16a48db4697503662e32bbf00b231ebd",
          "blockNumber": 209363603,
          "contractAddress": null,
          "cumulativeGasUsed": "125164",
          "from": "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e",
          "gasPrice": "100000000",
          "blobGasUsed": null,
          "blobGasPrice": null,
          "gasUsed": "125164",
          "hash": "0x2a732e4ec63b3c5324341634527b33c18554138b8c9450b57ab97cc85fb72f73",
          "index": 1,
          "logs": [
            {
              "_type": "log",
              "address": "0x865365C425f3A593Ffe698D9c4E6707D14d51e08",
              "blockHash": "0x7636a6d0e61612f3670394f7562f404a16a48db4697503662e32bbf00b231ebd",
              "blockNumber": 209363603,
              "data": "0x0000000000000000000000000000000000000000000069e10de76676d0800000000000000000000000000000000000000000000000000000000000000007a1200000000000000000000000000000000000000000000000000000000000007080",
              "index": 0,
              "topics": [
                "0x88b4c2d08cea0f01a24841ff5d14814ddb5b14ac44b05e0835fcc0dcd8c7bc25",
                "0x000000000000000000000000b0188c4d02eab4d444c1678f1ede9f790ffc838e",
                "0x000000000000000000000000c24a3dac5d06d771f657a48b20ce1a671b78f26b"
              ],
              "transactionHash": "0x2a732e4ec63b3c5324341634527b33c18554138b8c9450b57ab97cc85fb72f73",
              "transactionIndex": 1
            }
          ],
          "logsBloom": "0x00008000000000000400000000000100000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000010000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000100",
          "status": 1,
          "to": "0x865365C425f3A593Ffe698D9c4E6707D14d51e08"
        }
    [11:13:37.687] INFO (IndexerAgent/1): Successfully provisioned to the Subgraph Service
        component: "Network"
        indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        protocolNetwork: "eip155:421614"
        operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        address: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
    [11:13:37.844] INFO (IndexerAgent/1): Register indexer
        component: "Network"
        indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        protocolNetwork: "eip155:421614"
        operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        address: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        url: "https://capitanbeto.xyz"
        geoCoordinates: [
          -34.545272407633256,
          -58.449759085768086
        ]
        geoHash: "69y7mznpj"
        paymentsDestination: "0xF671c6B83f44eAd14cA1c5F4A629F1b9B18C8f29"
    [11:13:38.160] DEBUG (IndexerAgent/1): Indexer registration data
        component: "Network"
        indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        protocolNetwork: "eip155:421614"
        operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        address: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        indexerRegistrationData: {
          "url": "",
          "geoHash": "",
          "paymentsDestination": "0x0000000000000000000000000000000000000000"
        }
    [11:13:39.629] INFO (IndexerAgent/1): Sending transaction
        component: "Network"
        indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        protocolNetwork: "eip155:421614"
        operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        address: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        function: "subgraphService.register"
        txConfig: {
          "attempt": 1,
          "gasBump": 1200,
          "gasLimit": 232790,
          "maxFeePerGas": 200000000,
          "maxPriorityFeePerGas": 0,
          "nonce": 8,
          "type": 0
        }
    [11:13:39.629] INFO (IndexerAgent/1): Transaction pending
        component: "Network"
        indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        protocolNetwork: "eip155:421614"
        operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        address: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        function: "subgraphService.register"
        tx: {
          "_type": "TransactionResponse",
          "accessList": [],
          "blockNumber": null,
          "blockHash": null,
          "blobVersionedHashes": null,
          "chainId": "421614",
          "data": "0x24b8fbf6000000000000000000000000b0188c4d02eab4d444c1678f1ede9f790ffc838e000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000f671c6b83f44ead14ca1c5f4a629f1b9b18c8f29000000000000000000000000000000000000000000000000000000000000001768747470733a2f2f6361706974616e6265746f2e78797a0000000000000000000000000000000000000000000000000000000000000000000000000000000009363979376d7a6e706a0000000000000000000000000000000000000000000000",
          "from": "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e",
          "gasLimit": "232790",
          "gasPrice": null,
          "hash": "0x2602f5149dc1f48e196fd9387251269ae8e2d9d2dbca9072d43b12b8ea8dccb0",
          "maxFeePerGas": "200000000",
          "maxPriorityFeePerGas": "0",
          "maxFeePerBlobGas": null,
          "nonce": 8,
          "signature": {
            "_type": "signature",
            "networkV": null,
            "r": "0x65a90892de862c8f3f1b7a0b31e16acde56e4ec97723384875b5a07fd74e6973",
            "s": "0x71b0417eaf291ed9aa089c83100f2f5c8c66e2e3592b685d14c963aafdc40277",
            "v": 28
          },
          "to": "0xc24A3dAC5d06d771f657A48B20cE1a671B78f26b",
          "type": 2,
          "value": "0"
        }
        confirmationBlocks: 3
    [11:13:48.707] INFO (IndexerAgent/1): Transaction successfully included in block
        component: "Network"
        indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        protocolNetwork: "eip155:421614"
        operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        address: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        function: "subgraphService.register"
        tx: "0x2602f5149dc1f48e196fd9387251269ae8e2d9d2dbca9072d43b12b8ea8dccb0"
        receipt: {
          "_type": "TransactionReceipt",
          "blockHash": "0xb78cdc9cfdb5757aa17707b1c144c6c263ef705abf68afaa705c8844cbf213d9",
          "blockNumber": 209363646,
          "contractAddress": null,
          "cumulativeGasUsed": "1801454",
          "from": "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e",
          "gasPrice": "100000000",
          "blobGasUsed": null,
          "blobGasPrice": null,
          "gasUsed": "152813",
          "hash": "0x2602f5149dc1f48e196fd9387251269ae8e2d9d2dbca9072d43b12b8ea8dccb0",
          "index": 2,
          "logs": [
            {
              "_type": "log",
              "address": "0xc24A3dAC5d06d771f657A48B20cE1a671B78f26b",
              "blockHash": "0xb78cdc9cfdb5757aa17707b1c144c6c263ef705abf68afaa705c8844cbf213d9",
              "blockNumber": 209363646,
              "data": "0x",
              "index": 2,
              "topics": [
                "0x003215dc05a2fc4e6a1e2c2776311d207c730ee51085aae221acc5cbe6fb55c1",
                "0x000000000000000000000000b0188c4d02eab4d444c1678f1ede9f790ffc838e",
                "0x000000000000000000000000f671c6b83f44ead14ca1c5f4a629f1b9b18c8f29"
              ],
              "transactionHash": "0x2602f5149dc1f48e196fd9387251269ae8e2d9d2dbca9072d43b12b8ea8dccb0",
              "transactionIndex": 2
            },
            {
              "_type": "log",
              "address": "0xc24A3dAC5d06d771f657A48B20cE1a671B78f26b",
              "blockHash": "0xb78cdc9cfdb5757aa17707b1c144c6c263ef705abf68afaa705c8844cbf213d9",
              "blockNumber": 209363646,
              "data": "0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000f671c6b83f44ead14ca1c5f4a629f1b9b18c8f29000000000000000000000000000000000000000000000000000000000000001768747470733a2f2f6361706974616e6265746f2e78797a0000000000000000000000000000000000000000000000000000000000000000000000000000000009363979376d7a6e706a0000000000000000000000000000000000000000000000",
              "index": 3,
              "topics": [
                "0x159567bea25499a91f60e1fbb349ff2a1f8c1b2883198f25c1e12c99eddb44fa",
                "0x000000000000000000000000b0188c4d02eab4d444c1678f1ede9f790ffc838e"
              ],
              "transactionHash": "0x2602f5149dc1f48e196fd9387251269ae8e2d9d2dbca9072d43b12b8ea8dccb0",
              "transactionIndex": 2
            }
          ],
          "logsBloom": "0x00008000000000000000000080000000000000400000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000002000000000000000000000004000000000000000000001000000000000000000000000010000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000100000000000400000000000000000000000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000002000000000",
          "status": 1,
          "to": "0xc24A3dAC5d06d771f657A48B20cE1a671B78f26b"
        }
    [11:13:48.707] INFO (IndexerAgent/1): Successfully registered indexer
        component: "Network"
        indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        protocolNetwork: "eip155:421614"
        operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
        address: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
    ```