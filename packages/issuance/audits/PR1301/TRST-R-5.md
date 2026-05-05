# TRST-R-5: Ambiguous return value in getAgreementOfferAt()

- **Severity:** Recommendation

## Description

`getAgreementOfferAt()` returns `(uint8 offerType, bytes memory offerData)`. The offer type constant `OFFER_TYPE_NEW` is defined as 0, which is also the default Solidity return value when no stored offer exists for the given `agreementId` and index. A caller receiving `offerType == 0` cannot distinguish between a stored new-type offer existing and no offer existing. Consider redefining offer type constants with 1-indexed values, or adding an explicit `bool found` return parameter.
