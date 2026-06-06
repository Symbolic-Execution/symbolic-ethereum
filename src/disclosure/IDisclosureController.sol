// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IDisclosureController
/// @notice Higher-level disclosure policy surface for symbolic handles.
interface IDisclosureController {
    /// @notice Returns the account currently authorized to approve off-chain
    ///         disclosure of `handleId`.
    /// @dev Returns `address(0)` when the handle is unknown or currently has no
    ///      disclosure controller.
    function disclosureController(
        bytes32 handleId
    ) external view returns (address controller);
}
