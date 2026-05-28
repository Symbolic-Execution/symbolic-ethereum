// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IERC165
/// @notice Standard interface detection (ERC-165).
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @title IERC7984
/// @notice Interface for ERC-7984 Confidential Fungible Token.
/// @dev Amounts are opaque bytes32 handles to private values.
interface IERC7984 is IERC165 {
    // ── Events ──────────────────────────────────────────────────────────

    /// @notice Emitted on every confidential transfer, mint, or burn.
    /// @param from The sender (address(0) for mint).
    /// @param to The receiver (address(0) for burn).
    /// @param amount Opaque handle to the transferred amount.
    event ConfidentialTransfer(
        address indexed from,
        address indexed to,
        bytes32 indexed amount
    );

    /// @notice Emitted when an operator is set or updated.
    event OperatorSet(
        address indexed holder,
        address indexed operator,
        uint48 until
    );

    // ── Metadata ────────────────────────────────────────────────────────

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    /// @notice Returns a URI for contract-level metadata.
    function contractURI() external view returns (string memory);

    // ── Balances ────────────────────────────────────────────────────────

    /// @notice Returns the handle to the confidential balance of `account`.
    function confidentialBalanceOf(
        address account
    ) external view returns (bytes32);

    /// @notice Returns the handle to the confidential total supply.
    function confidentialTotalSupply() external view returns (bytes32);

    // ── Transfers ───────────────────────────────────────────────────────

    /// @notice Transfer a private amount to `to`.
    /// @return transferred Handle to the actually-transferred amount.
    function confidentialTransfer(
        address to,
        bytes32 amount
    ) external returns (bytes32 transferred);

    /// @notice Transfer a private amount to `to` with implementation-specific
    ///         `data`.
    /// @return transferred Handle to the actually-transferred amount.
    function confidentialTransfer(
        address to,
        bytes32 amount,
        bytes calldata data
    ) external returns (bytes32 transferred);

    /// @notice Transfer a private amount from `from` to `to` as an operator.
    /// @return transferred Handle to the actually-transferred amount.
    function confidentialTransferFrom(
        address from,
        address to,
        bytes32 amount
    ) external returns (bytes32 transferred);

    /// @notice Transfer a private amount from `from` to `to` as an operator
    ///         with implementation-specific `data`.
    /// @return transferred Handle to the actually-transferred amount.
    function confidentialTransferFrom(
        address from,
        address to,
        bytes32 amount,
        bytes calldata data
    ) external returns (bytes32 transferred);

    // ── Operators ───────────────────────────────────────────────────────

    /// @notice Grant `operator` spending power until `until` timestamp.
    function setOperator(address operator, uint48 until) external;

    /// @notice Check whether `spender` is an operator for `holder`.
    function isOperator(
        address holder,
        address spender
    ) external view returns (bool);
}
