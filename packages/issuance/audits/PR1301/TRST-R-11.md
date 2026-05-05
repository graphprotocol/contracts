# TRST-R-11: Remove or implement unused state flags in IAgreementCollector

- **Severity:** Recommendation

## Description

`IAgreementCollector` defines state flag constants that are not currently used in the RecurringCollector implementation, including `NOTICE_GIVEN`, `SETTLED`, `BY_PAYER`, `BY_PROVIDER`, `BY_DATA_SERVICE`, `AUTO_UPDATE`, and `AUTO_UPDATED`. Unused public interface constants are a source of confusion for integrators, who may code against documented semantics that the implementation does not honor. Either remove the unused flags from the interface, or implement the behaviors they describe in the collector.
