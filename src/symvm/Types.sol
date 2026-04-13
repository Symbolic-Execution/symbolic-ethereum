// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Private handle to an encrypted uint256 value.
type suint256 is bytes32;

/// @dev Private handle to an encrypted boolean value.
type sbool is bytes32;

/// @dev Handle type discriminants matching the symVM event surface.
uint8 constant SUINT256 = 1;
uint8 constant SBOOL = 2;
