# Still pending

* Remove extension if I can fit everything in one service?
* One Interface for all subgraph
* `require(provision.tokens != 0, DisputeManagerZeroTokens());` - Document or fix?
* Check code coverage
* Don't love cancel agreement on stop service / close stale allocation.
* Arbitration Charter: Update to support disputing IndexingFee.

# Done

* DONE: ~~* Missing Upgrade event for subgraph service~~
* DONE: ~~* Check contract size~~
* DONE: ~~Switch cancel event in recurring collector to use Enum~~
* DONE: ~~Switch timestamps to uint64~~
* DONE: ~~Check that UUID-v4 fits in `bytes16`~~
* DONE: ~~Double check cancelation policy. Who can cancel when? Right now is either party at any time. Answer: If gateway cancels allow collection till that point.~~
* DONE: ~~If an indexer closes an allocation, what should happen to the accepeted agreement? Answer: Look into canceling agreement as part of stop service.~~
* DONE: ~~Switch `duration` for `endsAt`? Answer: Do it.~~
* DONE: ~~Support a way for gateway to shop an agreement around? Deadline + dedup key? So only one agreement with the dedupe key can be accepted? Answer: No. Agreements will be "signaled" as approved or rejected on the API call that sends the agreement. We'll trust (and verify) that that's the case.~~
* DONE: ~~Test `upgrade` paths~~
* DONE: ~~Fix upgrade.t.sol, lots of comments~~
* DONE: ~~How do we solve for the case where an indexer has reached their max expected payout for the initial sync but haven't reached the current epoch (thus their POI is incorrect)? Answer: Signal in the event that the max amount was collected, so that fisherman understand the case.~~
* DONE: ~~Debate epoch check protocol team. Maybe don't revert but store it in event. Pablo suggest block number instead of epoch.~~
* DONE: ~~Should we set a different param for initial collection time max? Some subgraphs take a lot to catch up. Answer: Do nothing. Make sure that zero POIs allow to eventually sync~~
* DONE: ~~Since an allocation is required for collecting, do we want to expect that the allocation is not stale? Do we want to add code to collect rewards as part of the collection of fees? Make sure allocation is more than one epoch old if we attempt this. Answer: Ignore stale allocation~~
* DONE: ~~If service wants to collect more than collector allows. Collector limits but doesn't tell the service? Currently reverts. Answer: Allow for max allowed~~
* DONE: ~~What should happen if the escrow doesn't have enough funds? Answer: Reverts~~
* DONE: ~~Don't pay for entities on initial collection? Where did we land in terms of payment terms? Answer: pay initial~~
* DONE: ~~Test lock stake~~
* DONE: ~~Reduce the number of errors declared and returned~~
* DONE: ~~Support `DisputeManager`~~
* DONE: ~~Check upgrade conditions. Support indexing agreement upgradability, so that there is a mechanism to adjust the rates without having to cancel and start over.~~
* DONE: ~~Maybe check that the epoch the indexer is sending is the one the transaction will be run in?~~
* DONE: ~~Should we deal with zero entities declared as a special case?~~
* DONE: ~~Support for agreements that end up in `RecurringCollectorCollectionTooLate` or ways to avoid getting to that state.~~
* DONE: ~~Make `agreementId` unique globally so that we don't need the full tuple (`payer`+`indexer`+`agreementId`) as key?~~
* DONE: ~~Maybe IRecurringCollector.cancel(address payer, address serviceProvider, bytes16 agreementId) should only take in agreementId?~~
* DONE: ~~Unify to one error in Decoder.sol~~
* DONE: ~~Built-in upgrade path to indexing agreements v2~~
* DONE: ~~Missing events for accept, cancel, upgrade RCAs.~~

# Won't Fix

* Add upgrade path to v2 collector terms
* Expose a function that indexers can use to calculate the tokens to be collected and other collection params?
* Place all agreement terms into one struct
* It's more like a collect + cancel since the indexer is expected to stop work then and there. When posting a POI that's < N-1 epoch. Answer: Emit signal that the collection is meant to be final. Counter: Won't do since collector can't signal back to data service that payment is maxed out. Could emit an event from the collector, but is it really worth it? Right now any collection where epoch POI < current POI is suspect.
