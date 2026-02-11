# Query a subgraph for an open allocation

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: In progress
Man4ela: Done
p2p: Not started

We want to test the indexer’s ability to serve queries. Pick a subgraph that you are indexing and use the script/commands below to serve queries. With a subgraph deployment id you can get the subgraph id via explorer: [https://testnet.thegraph.com/explorer](https://testnet.thegraph.com/explorer)

Note that depending on how many other indexers are indexing the subgraph you’ll get only some of the queries.

**Script to query a subgraph through the gateway**

```bash
#!/bin/bash

subgraph_id=${1}
count=${2:-25}
api_key=${3:-"c6ee2f3c1bcf1e0364b83e6470264dce"}

for ((i=0; i<count; i++))
do
    curl "https://gateway.testnet.thegraph.com/api/subgraphs/id/${subgraph_id}" \
        -H 'content-type: application/json' \
        -H "Authorization: Bearer ${api_key}" \
        -d '{"query": "{ _meta { block { number } } }"}'
    echo
done
```

Run `./query.sh <subgraph_id>` 

### Pass criteria

- Query should return a valid result
- Inspecting indexer components database you should see tap receipts being generated. Table for horizon is `tap_horizon_receipts`
- Repeat this a few times so there are multiple receipts for aggregation into RAVs later.