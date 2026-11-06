---
'@graphprotocol/interfaces': major
---

Use OpenZeppelin 5. The generated `IERC20Upgradeable` types are gone, the `IERC165` types moved to `utils/introspection`, and ABI parameter names follow OpenZeppelin 5 (for example `transfer(to, value)`, `setApprovalForAll(operator, approved)`), which changes the wagmi ABIs.
