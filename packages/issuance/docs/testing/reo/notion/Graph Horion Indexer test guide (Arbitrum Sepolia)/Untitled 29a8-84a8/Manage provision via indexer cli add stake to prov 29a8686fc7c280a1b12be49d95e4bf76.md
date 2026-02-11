# Manage provision via indexer cli: add stake to provision

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: Done
Man4ela: Done
p2p: Not started

See [How to manage the Subgraph Service Provision](https://www.notion.so/How-to-manage-the-Subgraph-Service-Provision-2728686fc7c280dda377c17a4997df9d?pvs=21) 

Here we want to test basically the `provision add` command

### Pass criteria

The provisions entity in the network subgraph should now show the added stake on tokensProvisioned. The indexer cli `provisions get` command can also be used to display a summary of the provision.

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