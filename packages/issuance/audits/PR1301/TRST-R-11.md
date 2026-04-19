# TRST-R-11: Remove or implement unused state flags in IAgreementCollector

- **Severity:** Recommendation

## Description

`IAgreementCollector` defines state flag constants that are not currently used in the RecurringCollector implementation, including `NOTICE_GIVEN`, `SETTLED`, `BY_PAYER`, `BY_PROVIDER`, `BY_DATA_SERVICE`, `AUTO_UPDATE`, and `AUTO_UPDATED`. Unused public interface constants are a source of confusion for integrators, who may code against documented semantics that the implementation does not honor. Either remove the unused flags from the interface, or implement the behaviors they describe in the collector.

---

Removed usused flags: `AUTO_UPDATE`, `AUTO_UPDATED`, `BY_DATA_SERVICE`, `WITH_NOTICE` and `IF_NOT_ACCEPTED` are dropped from the interface.

NatSpec updated for remaining flags with new semantics.

In RecurringCollector `NOTICE_GIVEN`, `SETTLED`, `BY_PAYER`, `BY_PROVIDER` are now set by `getAgreementDetails` to describe cancel origin and collectability (see TRST-R-12 fix).
