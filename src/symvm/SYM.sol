// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {suint256, sbool, SUINT256, SBOOL} from "./Types.sol";
import {ISymVM} from "./ISymVM.sol";

/// @title SYM
/// @notice Typed Solidity library for symVM operations.
/// @dev Wraps ISymVM calls with typed handle arguments and return values.
///      Contracts should use this library for all symVM interactions.
library SYM {
    /// @dev Storage slot for the SymVM configuration.
    ///      keccak256("symbolic.symvm.config.v1")
    bytes32 private constant _CONFIG_SLOT =
        0x7e4c74e7ac1906d57e4e7c1a5b3a21d73e68da8e9c7b5f0a3d2c1b0e9f8a7b6c;

    // ── Configuration ───────────────────────────────────────────────────

    /// @notice Store the symVM contract address. Call once during
    ///         initialization (constructor or initializer).
    function setSymVM(address symvm) internal {
        bytes32 slot = _CONFIG_SLOT;
        assembly {
            sstore(slot, symvm)
        }
    }

    function _symvm() private view returns (ISymVM) {
        address addr;
        bytes32 slot = _CONFIG_SLOT;
        assembly {
            addr := sload(slot)
        }
        return ISymVM(addr);
    }

    // ── Handle creation ─────────────────────────────────────────────────

    function importCiphertext(
        bytes calldata systemCiphertext
    ) internal returns (suint256) {
        return suint256.wrap(
            _symvm().importCiphertext(SUINT256, systemCiphertext)
        );
    }

    function importCiphertextBool(
        bytes calldata systemCiphertext
    ) internal returns (sbool) {
        return sbool.wrap(
            _symvm().importCiphertext(SBOOL, systemCiphertext)
        );
    }

    function fromPlaintext(uint256 value) internal returns (suint256) {
        return suint256.wrap(
            _symvm().fromPlaintext(SUINT256, bytes32(value))
        );
    }

    function fromPlaintext(bool value) internal returns (sbool) {
        return sbool.wrap(
            _symvm().fromPlaintext(SBOOL, bytes32(value ? uint256(1) : uint256(0)))
        );
    }

    // ── Arithmetic ──────────────────────────────────────────────────────

    function add(suint256 a, suint256 b) internal returns (suint256) {
        return suint256.wrap(
            _symvm().add(suint256.unwrap(a), suint256.unwrap(b))
        );
    }

    function sub(suint256 a, suint256 b) internal returns (suint256) {
        return suint256.wrap(
            _symvm().sub(suint256.unwrap(a), suint256.unwrap(b))
        );
    }

    // ── Comparisons ─────────────────────────────────────────────────────

    function eq(suint256 a, suint256 b) internal returns (sbool) {
        return sbool.wrap(
            _symvm().eq(suint256.unwrap(a), suint256.unwrap(b))
        );
    }

    function lt(suint256 a, suint256 b) internal returns (sbool) {
        return sbool.wrap(
            _symvm().lt(suint256.unwrap(a), suint256.unwrap(b))
        );
    }

    function lte(suint256 a, suint256 b) internal returns (sbool) {
        return sbool.wrap(
            _symvm().lte(suint256.unwrap(a), suint256.unwrap(b))
        );
    }

    function gt(suint256 a, suint256 b) internal returns (sbool) {
        return sbool.wrap(
            _symvm().gt(suint256.unwrap(a), suint256.unwrap(b))
        );
    }

    function gte(suint256 a, suint256 b) internal returns (sbool) {
        return sbool.wrap(
            _symvm().gte(suint256.unwrap(a), suint256.unwrap(b))
        );
    }

    // ── Boolean operations ──────────────────────────────────────────────

    function and_(sbool a, sbool b) internal returns (sbool) {
        return sbool.wrap(
            _symvm().and_(sbool.unwrap(a), sbool.unwrap(b))
        );
    }

    function or_(sbool a, sbool b) internal returns (sbool) {
        return sbool.wrap(
            _symvm().or_(sbool.unwrap(a), sbool.unwrap(b))
        );
    }

    function not_(sbool a) internal returns (sbool) {
        return sbool.wrap(
            _symvm().not_(sbool.unwrap(a))
        );
    }

    // ── Selection ───────────────────────────────────────────────────────

    function select(
        sbool pred,
        suint256 whenTrue,
        suint256 whenFalse
    ) internal returns (suint256) {
        return suint256.wrap(
            _symvm().select(
                sbool.unwrap(pred),
                suint256.unwrap(whenTrue),
                suint256.unwrap(whenFalse)
            )
        );
    }

    function select(
        sbool pred,
        sbool whenTrue,
        sbool whenFalse
    ) internal returns (sbool) {
        return sbool.wrap(
            _symvm().select(
                sbool.unwrap(pred),
                sbool.unwrap(whenTrue),
                sbool.unwrap(whenFalse)
            )
        );
    }

    // ── Authorization ───────────────────────────────────────────────────

    function allow(suint256 handle, address target) internal {
        _symvm().allow(suint256.unwrap(handle), target);
    }

    function allow(sbool handle, address target) internal {
        _symvm().allow(sbool.unwrap(handle), target);
    }

    function revoke(suint256 handle, address target) internal {
        _symvm().revoke(suint256.unwrap(handle), target);
    }

    function revoke(sbool handle, address target) internal {
        _symvm().revoke(sbool.unwrap(handle), target);
    }

    function allowTransient(suint256 handle, address target) internal {
        _symvm().allowTransient(suint256.unwrap(handle), target);
    }

    function allowTransient(sbool handle, address target) internal {
        _symvm().allowTransient(sbool.unwrap(handle), target);
    }

    function isAllowed(
        suint256 handle,
        address account
    ) internal view returns (bool) {
        return _symvm().isAllowed(suint256.unwrap(handle), account);
    }

    function isAllowed(
        sbool handle,
        address account
    ) internal view returns (bool) {
        return _symvm().isAllowed(sbool.unwrap(handle), account);
    }

    // ── Utilities ───────────────────────────────────────────────────────

    function isInitialized(suint256 handle) internal pure returns (bool) {
        return suint256.unwrap(handle) != bytes32(0);
    }

    function isInitialized(sbool handle) internal pure returns (bool) {
        return sbool.unwrap(handle) != bytes32(0);
    }
}
