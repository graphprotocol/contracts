# TRST-R-5: Ambiguous return value in getAgreementOfferAt()

- **Severity:** Recommendation

## Description

`getAgreementOfferAt()` returns `(uint8 offerType, bytes memory offerData)`. The offer type constant `OFFER_TYPE_NEW` is defined as 0, which is also the default Solidity return value when no stored offer exists for the given `agreementId` and index. A caller receiving `offerType == 0` cannot distinguish between a stored new-type offer existing and no offer existing. Consider redefining offer type constants with 1-indexed values, or adding an explicit `bool found` return parameter.

---

Using non-zero offer type constants as suggested: `OFFER_TYPE_NEW = 1`, `OFFER_TYPE_UPDATE = 2`. The zero value is declared explicitly as `OFFER_TYPE_NONE` so the "no stored offer" sentinel is part of the interface rather than a NatSpec-only convention.
