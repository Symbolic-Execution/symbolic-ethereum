// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDisclosureController} from "./IDisclosureController.sol";

/// @title DisclosureController
/// @notice Reference storage helper for higher-level contracts that own
///         symbolic handles and need to expose disclosure policy.
abstract contract DisclosureController is IDisclosureController {
    mapping(bytes32 handleId => address controller) private _controllers;

    event DisclosureControllerUpdated(
        bytes32 indexed handleId,
        address indexed controller
    );

    function disclosureController(
        bytes32 handleId
    ) public view virtual returns (address controller) {
        return _controllers[handleId];
    }

    function _setDisclosureController(
        bytes32 handleId,
        address controller
    ) internal virtual {
        _controllers[handleId] = controller;
        emit DisclosureControllerUpdated(handleId, controller);
    }

    function _clearDisclosureController(bytes32 handleId) internal virtual {
        delete _controllers[handleId];
        emit DisclosureControllerUpdated(handleId, address(0));
    }
}
