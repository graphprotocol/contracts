# The Graph Minting Channel Contract

## Requirements
- A variation on the Payment Channel contract
- Payments are always one-way (from End-User to Indexing Node's balance in staking contract).
- Instead of off-chain balance transfers being backed by a deposit of tokens, the Payment Channel Hub has the power to *mint* Graph Tokens.
- Payment Channel Hub commits to minting tokens in a micropayment, proportional to the amount of ETH received for the micropayment they are relaying.
- Gets around gigantic ETH balance requirements of Payment Channel Hub.
- Payment Channel settles channel at least once per inflation round, and deposits ETH into an auction contract which sells ETH for Graph Tokens, and transfers Graph Tokens to Graph DAO (where they are possibly burned).