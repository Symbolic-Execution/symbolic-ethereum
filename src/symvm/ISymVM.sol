// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ISymVM
/// @notice Low-level interface to the symVM on-chain contract.
/// @dev Contracts should use the typed SYM library instead of calling this
///      interface directly.
interface ISymVM {
    // ── Handle creation ─────────────────────────────────────────────────

    /// @notice Import a client-encrypted ciphertext and create a new handle.
    function importCiphertext(
        uint8 handleType,
        bytes calldata systemCiphertext
    ) external returns (bytes32 handleId);

    /// @notice Create a handle from a public plaintext constant.
    function fromPlaintext(
        uint8 handleType,
        bytes32 value
    ) external returns (bytes32 handleId);

    // ── Arithmetic ──────────────────────────────────────────────────────

    function add(bytes32 a, bytes32 b) external returns (bytes32);
    function sub(bytes32 a, bytes32 b) external returns (bytes32);

    // ── Comparisons ─────────────────────────────────────────────────────

    function eq(bytes32 a, bytes32 b) external returns (bytes32);
    function lt(bytes32 a, bytes32 b) external returns (bytes32);
    function lte(bytes32 a, bytes32 b) external returns (bytes32);
    function gt(bytes32 a, bytes32 b) external returns (bytes32);
    function gte(bytes32 a, bytes32 b) external returns (bytes32);

    // ── Boolean operations ──────────────────────────────────────────────

    function and_(bytes32 a, bytes32 b) external returns (bytes32);
    function or_(bytes32 a, bytes32 b) external returns (bytes32);
    function not_(bytes32 a) external returns (bytes32);

    // ── Selection ───────────────────────────────────────────────────────

    function select(
        bytes32 pred,
        bytes32 whenTrue,
        bytes32 whenFalse
    ) external returns (bytes32);

    // ── Authorization ───────────────────────────────────────────────────

    /// @notice Grant persistent operation-use permission to `target`.
    function allow(bytes32 handleId, address target) external;

    /// @notice Revoke a previously granted persistent permission.
    function revoke(bytes32 handleId, address target) external;

    /// @notice Grant operation-use permission for the current transaction only.
    function allowTransient(bytes32 handleId, address target) external;

    /// @notice Check whether `account` is authorized to use `handleId`.
    function isAllowed(
        bytes32 handleId,
        address account
    ) external view returns (bool);
}
