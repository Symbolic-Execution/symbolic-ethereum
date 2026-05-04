// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SymVM} from "../src/symvm/SymVM.sol";
import {SBOOL, SUINT256} from "../src/symvm/Types.sol";

contract SymVMTest is Test {
    bytes32 private constant DOMAIN = keccak256("symbolic.test.domain");

    SymVM private symvm;

    event OperationRequestedV1(
        bytes32 indexed domainId,
        address indexed contractAddr,
        bytes32 indexed outputHandleId,
        uint8 outputType,
        uint8 operation,
        bytes32[] inputHandles
    );

    function setUp() public {
        symvm = new SymVM(DOMAIN);
    }

    function testSourceHandleValidation() public {
        vm.expectRevert("invalid type");
        symvm.fromPlaintext(0, bytes32(0));

        vm.expectRevert("invalid type");
        symvm.importCiphertext(3, hex"");

        vm.expectRevert("invalid bool");
        symvm.fromPlaintext(SBOOL, bytes32(uint256(2)));
    }

    function testAddEmitsSuint256OutputType() public {
        bytes32 a = symvm.fromPlaintext(SUINT256, bytes32(uint256(1)));
        bytes32 b = symvm.fromPlaintext(SUINT256, bytes32(uint256(2)));
        bytes32 expectedOutput = _expectedHandle(2);

        bytes32[] memory inputs = new bytes32[](2);
        inputs[0] = a;
        inputs[1] = b;

        vm.expectEmit(true, true, true, true, address(symvm));
        emit OperationRequestedV1(
            DOMAIN, address(this), expectedOutput, SUINT256, 1, inputs
        );

        bytes32 output = symvm.add(a, b);
        assertEq(output, expectedOutput);
    }

    function testComparisonEmitsSboolOutputType() public {
        bytes32 a = symvm.fromPlaintext(SUINT256, bytes32(uint256(1)));
        bytes32 b = symvm.fromPlaintext(SUINT256, bytes32(uint256(2)));
        bytes32 expectedOutput = _expectedHandle(2);

        bytes32[] memory inputs = new bytes32[](2);
        inputs[0] = a;
        inputs[1] = b;

        vm.expectEmit(true, true, true, true, address(symvm));
        emit OperationRequestedV1(
            DOMAIN, address(this), expectedOutput, SBOOL, 5, inputs
        );

        bytes32 output = symvm.lte(a, b);
        assertEq(output, expectedOutput);
    }

    function testBooleanOpsRequireSboolInputs() public {
        bytes32 value = symvm.fromPlaintext(SUINT256, bytes32(uint256(1)));
        bytes32 flag = symvm.fromPlaintext(SBOOL, bytes32(uint256(1)));

        vm.expectRevert("invalid input type");
        symvm.not_(value);

        vm.expectRevert("invalid input type");
        symvm.and_(flag, value);
    }

    function testArithmeticRejectsSboolInputs() public {
        bytes32 a = symvm.fromPlaintext(SBOOL, bytes32(uint256(1)));
        bytes32 b = symvm.fromPlaintext(SBOOL, bytes32(0));

        vm.expectRevert("invalid input type");
        symvm.add(a, b);
    }

    function testSelectRequiresSboolPredicateAndMatchingBranches() public {
        bytes32 pred = symvm.fromPlaintext(SBOOL, bytes32(uint256(1)));
        bytes32 whenTrue = symvm.fromPlaintext(SUINT256, bytes32(uint256(1)));
        bytes32 whenFalse = symvm.fromPlaintext(SUINT256, bytes32(uint256(2)));
        bytes32 expectedOutput = _expectedHandle(3);

        bytes32[] memory inputs = new bytes32[](3);
        inputs[0] = pred;
        inputs[1] = whenTrue;
        inputs[2] = whenFalse;

        vm.expectEmit(true, true, true, true, address(symvm));
        emit OperationRequestedV1(
            DOMAIN, address(this), expectedOutput, SUINT256, 11, inputs
        );

        bytes32 output = symvm.select(pred, whenTrue, whenFalse);
        assertEq(output, expectedOutput);

        bytes32 notPred = symvm.fromPlaintext(SUINT256, bytes32(uint256(3)));

        vm.expectRevert("invalid input type");
        symvm.select(notPred, whenTrue, whenFalse);

        bytes32 boolBranch = symvm.fromPlaintext(SBOOL, bytes32(0));

        vm.expectRevert("type mismatch");
        symvm.select(pred, whenTrue, boolBranch);
    }

    function testUnknownHandleIsNotAllowed() public view {
        assertFalse(symvm.isAllowed(bytes32(uint256(1)), address(0)));
    }

    function _expectedHandle(uint64 nonce) private view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN, address(this), nonce));
    }
}
