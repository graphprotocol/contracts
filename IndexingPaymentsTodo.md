# Still pending

* Arbitration Charter: Update to support disputing IndexingFee.
* Economics
  * If service wants to collect more than collector allows. Collector limits but doesn't tell the service?
  * Since an allocation is required for collecting, do we want to expect that the allocation is not stale? Do we want to add code to collect rewards as part of the collection of fees? Make sure allocation is more than one epoch old if we attempt this.
  * What should happen if the escrow doesn't have enough funds?
  * Don't pay for entities on initial collection? Where did we land in terms of payment terms?
  * Should we set a different param for initial collection time max? Some subgraphs take a lot to catch up.
  * How do we solve for the case where an indexer has reached their max expected payout for the initial sync but haven't reached the current epoch (thus their POI is incorrect)?
* Double check cancelation policy. Who can cancel when? Right now is either party at any time.
* Expose a function that indexers can use to calculate the tokens to be collected and other collection params?
* Support a way for gateway to shop an agreement around? Deadline + dedup key? So only one agreement with the dedupe key can be accepted?
* If an indexer closes an allocation, what should happen to the accepeted agreement?
* test_SubgraphService_CollectIndexingFee_Integration fails with PaymentsEscrowInconsistentCollection
* Switch `duration` for `endsAt`?
* Check that UUID-v4 fits in `bytes16`
* Test `upgrade` paths
* Test lock stake

# Done

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
