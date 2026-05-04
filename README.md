# Symbolic Ethereum

Solidity reference contracts for the Symbolic confidential execution model.
See the [Symbolic specifications](../symbolic-specs/README.md) for the full
system design.

This package contains:

- `SymVM`: an on-chain symbolic handle registry and operation event surface
- `SYM`: a typed Solidity library for calling `SymVM`
- `ERC7984`: a draft confidential fungible token built on `SYM`

## Contracts

### `SymVM`

`SymVM` is the low-level on-chain contract.

It creates handles from:

- encrypted ciphertext imports
- public plaintext constants
- symbolic operations

Supported symbolic operations:

- `add`, `sub`
- `eq`, `lt`, `lte`, `gt`, `gte`
- `and_`, `or_`, `not_`
- `select`

Each operation returns a fresh `bytes32` handle and emits `OperationRequestedV1`.

### `ERC7984`

`ERC7984` is a draft confidential fungible token implementation.

Balances and transfer amounts are private handles. Transfers express symbolic
intent rather than revealing plaintext values.

## Testing

Install Foundry, then run:

```sh
forge test
```
