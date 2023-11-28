# Usage

1) Upgrade the GNS contract, add a `uint256 public test;` storage variable
2) Run the upgrade script:
    ```
    CHAIN_ID=1 FORK_URL=<RPC_URL> CONTRACT_NAME=GNS UPGRADE_NAME=example yarn test:upgrade
    ```