// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SymVM} from "../src/symvm/SymVM.sol";
import {SBOOL, SUINT256} from "../src/symvm/Types.sol";

contract SymVMOwnerHarness {
    SymVM private immutable _symvm;

    constructor(SymVM symvm_) {
        _symvm = symvm_;
    }

    function createUint(uint256 value) external returns (bytes32) {
        return _symvm.fromPlaintext(SUINT256, bytes32(value));
    }

    function createBool(bool value) external returns (bytes32) {
        return _symvm.fromPlaintext(
            SBOOL, bytes32(value ? uint256(1) : uint256(0))
        );
    }

    function allow(bytes32 handleId, address target) external {
        _symvm.allow(handleId, target);
    }

    function revoke(bytes32 handleId, address target) external {
        _symvm.revoke(handleId, target);
    }

    function allowTransient(bytes32 handleId, address target) external {
        _symvm.allowTransient(handleId, target);
    }
}

contract SymVMUserHarness {
    SymVM private immutable _symvm;

    constructor(SymVM symvm_) {
        _symvm = symvm_;
    }

    function add(bytes32 a, bytes32 b) external returns (bytes32) {
        return _symvm.add(a, b);
    }
}

contract SymVMTest is Test {
    bytes32 private constant DOMAIN = keccak256("symbolic.test.domain");

    SymVM private symvm;

    event HandleImportedV1(
        bytes32 indexed domainId,
        address indexed contractAddr,
        bytes32 indexed handleId,
        uint8 handleType,
        bytes systemCiphertext
    );

    event HandleFromPlaintextV1(
        bytes32 indexed domainId,
        address indexed contractAddr,
        bytes32 indexed handleId,
        uint8 handleType,
        bytes32 plaintext
    );

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

    function testSourceHandleCreationEmitsDeterministicIds() public {
        bytes memory ciphertext = hex"010203";
        bytes32 expectedPlain = _expectedHandle(address(this), 0);
        bytes32 expectedImport = _expectedHandle(address(this), 1);

        vm.expectEmit(true, true, true, true, address(symvm));
        emit HandleFromPlaintextV1(
            DOMAIN,
            address(this),
            expectedPlain,
            SUINT256,
            bytes32(uint256(42))
        );
        bytes32 plain = symvm.fromPlaintext(SUINT256, bytes32(uint256(42)));
        assertEq(plain, expectedPlain);

        vm.expectEmit(true, true, true, true, address(symvm));
        emit HandleImportedV1(
            DOMAIN, address(this), expectedImport, SBOOL, ciphertext
        );
        bytes32 imported = symvm.importCiphertext(SBOOL, ciphertext);
        assertEq(imported, expectedImport);
    }

    function testSourceHandleValidation() public {
        vm.expectRevert("invalid type");
        symvm.fromPlaintext(0, bytes32(0));

        vm.expectRevert("invalid type");
        symvm.importCiphertext(3, hex"");

        vm.expectRevert("invalid bool");
        symvm.fromPlaintext(SBOOL, bytes32(uint256(2)));
    }

    function testAllOperationsEmitCanonicalOutputTypesAndInputs() public {
        bytes32 a = symvm.fromPlaintext(SUINT256, bytes32(uint256(1)));
        bytes32 b = symvm.fromPlaintext(SUINT256, bytes32(uint256(2)));
        bytes32 t = symvm.fromPlaintext(SBOOL, bytes32(uint256(1)));
        bytes32 f = symvm.fromPlaintext(SBOOL, bytes32(0));

        _expectOperation(address(this), 4, SUINT256, 1, _inputs2(a, b));
        assertEq(symvm.add(a, b), _expectedHandle(address(this), 4));

        _expectOperation(address(this), 5, SUINT256, 2, _inputs2(a, b));
        assertEq(symvm.sub(a, b), _expectedHandle(address(this), 5));

        _expectOperation(address(this), 6, SBOOL, 3, _inputs2(a, b));
        assertEq(symvm.eq(a, b), _expectedHandle(address(this), 6));

        _expectOperation(address(this), 7, SBOOL, 4, _inputs2(a, b));
        assertEq(symvm.lt(a, b), _expectedHandle(address(this), 7));

        _expectOperation(address(this), 8, SBOOL, 5, _inputs2(a, b));
        assertEq(symvm.lte(a, b), _expectedHandle(address(this), 8));

        _expectOperation(address(this), 9, SBOOL, 6, _inputs2(a, b));
        assertEq(symvm.gt(a, b), _expectedHandle(address(this), 9));

        _expectOperation(address(this), 10, SBOOL, 7, _inputs2(a, b));
        assertEq(symvm.gte(a, b), _expectedHandle(address(this), 10));

        _expectOperation(address(this), 11, SBOOL, 8, _inputs2(t, f));
        assertEq(symvm.and_(t, f), _expectedHandle(address(this), 11));

        _expectOperation(address(this), 12, SBOOL, 9, _inputs2(t, f));
        assertEq(symvm.or_(t, f), _expectedHandle(address(this), 12));

        _expectOperation(address(this), 13, SBOOL, 10, _inputs1(t));
        assertEq(symvm.not_(t), _expectedHandle(address(this), 13));

        _expectOperation(address(this), 14, SUINT256, 11, _inputs3(t, a, b));
        assertEq(symvm.select(t, a, b), _expectedHandle(address(this), 14));

        _expectOperation(address(this), 15, SBOOL, 11, _inputs3(t, t, f));
        assertEq(symvm.select(t, t, f), _expectedHandle(address(this), 15));
    }

    function testOperationTypeRejections() public {
        bytes32 value = symvm.fromPlaintext(SUINT256, bytes32(uint256(1)));
        bytes32 otherValue = symvm.fromPlaintext(SUINT256, bytes32(uint256(2)));
        bytes32 flag = symvm.fromPlaintext(SBOOL, bytes32(uint256(1)));
        bytes32 otherFlag = symvm.fromPlaintext(SBOOL, bytes32(0));

        vm.expectRevert("invalid input type");
        symvm.add(flag, otherFlag);

        vm.expectRevert("invalid input type");
        symvm.and_(flag, value);

        vm.expectRevert("invalid input type");
        symvm.not_(value);

        vm.expectRevert("invalid input type");
        symvm.select(value, otherValue, value);

        vm.expectRevert("type mismatch");
        symvm.select(flag, value, otherFlag);
    }

    function testUninitializedAndUnknownHandlesRevertAsInputs() public {
        bytes32 value = symvm.fromPlaintext(SUINT256, bytes32(uint256(1)));
        bytes32 unknown = bytes32(uint256(0x1234));

        vm.expectRevert("uninitialized handle");
        symvm.add(bytes32(0), value);

        vm.expectRevert("unknown handle");
        symvm.add(unknown, value);
    }

    function testUnknownHandleIsNotAllowed() public view {
        assertFalse(symvm.isAllowed(bytes32(uint256(1)), address(0)));
    }

    function testPersistentGrantAndRevokeAcrossContracts() public {
        SymVMOwnerHarness owner = new SymVMOwnerHarness(symvm);
        SymVMUserHarness user = new SymVMUserHarness(symvm);

        bytes32 a = owner.createUint(1);
        bytes32 b = owner.createUint(2);

        vm.expectRevert("not authorized");
        user.add(a, b);

        owner.allow(a, address(user));

        vm.expectRevert("not authorized");
        user.add(a, b);

        owner.allow(b, address(user));

        _expectOperation(address(user), 0, SUINT256, 1, _inputs2(a, b));
        bytes32 output = user.add(a, b);
        assertEq(output, _expectedHandle(address(user), 0));

        owner.revoke(a, address(user));

        vm.expectRevert("not authorized");
        user.add(a, b);
    }

    function testTransientGrantAllowsUseInCurrentTransaction() public {
        SymVMOwnerHarness owner = new SymVMOwnerHarness(symvm);
        SymVMUserHarness user = new SymVMUserHarness(symvm);

        bytes32 a = owner.createUint(1);
        bytes32 b = owner.createUint(2);

        owner.allowTransient(a, address(user));
        owner.allowTransient(b, address(user));

        _expectOperation(address(user), 0, SUINT256, 1, _inputs2(a, b));
        bytes32 output = user.add(a, b);
        assertEq(output, _expectedHandle(address(user), 0));
    }

    function _expectOperation(
        address contractAddr,
        uint64 outputNonce,
        uint8 outputType,
        uint8 operation,
        bytes32[] memory inputs
    ) private {
        bytes32 output = _expectedHandle(contractAddr, outputNonce);

        vm.expectEmit(true, true, true, true, address(symvm));
        emit OperationRequestedV1(
            DOMAIN, contractAddr, output, outputType, operation, inputs
        );
    }

    function _inputs1(bytes32 a) private pure returns (bytes32[] memory inputs) {
        inputs = new bytes32[](1);
        inputs[0] = a;
    }

    function _inputs2(
        bytes32 a,
        bytes32 b
    ) private pure returns (bytes32[] memory inputs) {
        inputs = new bytes32[](2);
        inputs[0] = a;
        inputs[1] = b;
    }

    function _inputs3(
        bytes32 a,
        bytes32 b,
        bytes32 c
    ) private pure returns (bytes32[] memory inputs) {
        inputs = new bytes32[](3);
        inputs[0] = a;
        inputs[1] = b;
        inputs[2] = c;
    }

    function _expectedHandle(
        address contractAddr,
        uint64 nonce
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(DOMAIN, contractAddr, nonce));
    }
}
