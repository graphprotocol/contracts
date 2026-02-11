# Manage provision via indexer cli: remove stake from provision

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: Done
Man4ela: Done
p2p: Not started

See [How to manage the Subgraph Service Provision](https://www.notion.so/How-to-manage-the-Subgraph-Service-Provision-2728686fc7c280dda377c17a4997df9d?pvs=21) 

Once stake has thawed from the provision it can be removed with `provision remove` command. 

Remember during the transition period, tokens removed from a provision will still require an additional thawing stage.

### Pass criteria

The indexer cli `provisions list-thaw` command can be used to display a summary of the thawings.