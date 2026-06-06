// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DisclosureController} from "../src/disclosure/DisclosureController.sol";

contract DisclosureControllerHarness is DisclosureController {
    function setController(bytes32 handleId, address controller) external {
        _setDisclosureController(handleId, controller);
    }

    function clearController(bytes32 handleId) external {
        _clearDisclosureController(handleId);
    }
}

contract DisclosureControllerTest is Test {
    DisclosureControllerHarness private harness;

    event DisclosureControllerUpdated(
        bytes32 indexed handleId,
        address indexed controller
    );

    function setUp() public {
        harness = new DisclosureControllerHarness();
    }

    function testReturnsZeroAddressForUnknownHandle() public view {
        assertEq(harness.disclosureController(bytes32(uint256(1))), address(0));
    }

    function testStoresAndReturnsController() public {
        bytes32 handleId = keccak256("handle");
        address controller = address(0xBEEF);

        vm.expectEmit(true, true, false, false, address(harness));
        emit DisclosureControllerUpdated(handleId, controller);
        harness.setController(handleId, controller);

        assertEq(harness.disclosureController(handleId), controller);
    }

    function testClearingControllerRestoresZeroAddress() public {
        bytes32 handleId = keccak256("handle");
        harness.setController(handleId, address(0xBEEF));

        vm.expectEmit(true, true, false, false, address(harness));
        emit DisclosureControllerUpdated(handleId, address(0));
        harness.clearController(handleId);

        assertEq(harness.disclosureController(handleId), address(0));
    }
}
