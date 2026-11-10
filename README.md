# Utility contracts

Utility smart contracts for DMD Diamond network.

## Contracts

| Contract name | Address | Upgrade authority (proxy admin owner) | Description |
| --- | --- | --- | --- |
| [ScintillaRecovery](src/ScintillaRecovery.sol) | [0x9E1268542561fa401615388CDe5Fca165E06F81d](https://explorer.bit.diamonds/address/0x9E1268542561fa401615388CDe5Fca165E06F81d) | [DMD DAO](https://explorer.bit.diamonds/address/0xDA0da0da0Da0Da0Da0DA00DA0da0da0DA0DA0dA0) | Holds native DMD recovered through the Scintilla hard fork. Only the DMD DAO can distribute these funds through batch payouts to specified recipients. |
| [DexFeeCollector](src/DexFeeCollector.sol) | [0xF940733904E16A8961982c8dFEd065d43Dbb9f7E](https://explorer.bit.diamonds/address/0xF940733904E16A8961982c8dFEd065d43Dbb9f7E) | [DMD DAO](https://explorer.bit.diamonds/address/0xDA0da0da0Da0Da0Da0DA00DA0da0da0DA0DA0dA0) | Collects ERC-20 DEX protocol fees and converts entire token balances into native DMD for the reinsert pot. Anyone can trigger conversion using governance-configured paths or a direct WDMD pair. WDMD is unwrapped directly, and native deposits can also be forwarded to the pot. |
