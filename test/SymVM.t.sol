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
    bytes32 private constant KEY_ID = keccak256("symbolic.test.key");

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
        symvm = new SymVM(DOMAIN, KEY_ID);
    }

    function testSourceHandleCreationEmitsDeterministicIds() public {
        bytes memory ciphertext = _validEnvelope(SBOOL, address(this));
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

    function testImportAcceptsWellBoundCiphertextForBothTypes() public {
        bytes32 a = symvm.importCiphertext(
            SUINT256, _validEnvelope(SUINT256, address(this))
        );
        assertEq(a, _expectedHandle(address(this), 0));

        bytes32 b = symvm.importCiphertext(
            SBOOL, _validEnvelope(SBOOL, address(this))
        );
        assertEq(b, _expectedHandle(address(this), 1));
    }

    function testImportRejectsMismatchedCaller() public {
        // AAD bound to a different contract than msg.sender.
        bytes memory env = _validEnvelope(SUINT256, address(0xBEEF));
        vm.expectRevert("caller mismatch");
        symvm.importCiphertext(SUINT256, env);
    }

    function testImportRejectsMismatchedDomain() public {
        SymVM.SystemInputAadV1 memory aad = _baseAad(SUINT256, address(this));
        aad.domainId = keccak256("other.domain");
        vm.expectRevert("domain mismatch");
        symvm.importCiphertext(SUINT256, _encode(aad, KEY_ID));
    }

    function testImportRejectsMismatchedChainId() public {
        SymVM.SystemInputAadV1 memory aad = _baseAad(SUINT256, address(this));
        aad.chainId = block.chainid + 1;
        vm.expectRevert("chain mismatch");
        symvm.importCiphertext(SUINT256, _encode(aad, KEY_ID));
    }

    function testImportRejectsMismatchedTypeTag() public {
        // Envelope tagged as sbool, but imported as suint256.
        bytes memory env = _validEnvelope(SBOOL, address(this));
        vm.expectRevert("type tag mismatch");
        symvm.importCiphertext(SUINT256, env);
    }

    function testImportRejectsInactiveKey() public {
        SymVM.SystemInputAadV1 memory aad = _baseAad(SUINT256, address(this));
        aad.keyId = keccak256("stale.key");
        // Envelope keyId matches the (stale) aad keyId, so the internal
        // consistency check passes but the active-key check fails.
        vm.expectRevert("inactive key");
        symvm.importCiphertext(SUINT256, _encode(aad, aad.keyId));
    }

    function testImportRejectsEnvelopeKeyIdMismatch() public {
        SymVM.SystemInputAadV1 memory aad = _baseAad(SUINT256, address(this));
        // Envelope keyId differs from the aad keyId.
        vm.expectRevert("key_id mismatch");
        symvm.importCiphertext(SUINT256, _encode(aad, keccak256("envelope.key")));
    }

    function testImportRejectsBadVersionAndKind() public {
        SymVM.SystemInputAadV1 memory badVersion =
            _baseAad(SUINT256, address(this));
        badVersion.version = 2;
        vm.expectRevert("bad aad version");
        symvm.importCiphertext(SUINT256, _encode(badVersion, KEY_ID));

        SymVM.SystemInputAadV1 memory badKind = _baseAad(SUINT256, address(this));
        badKind.kind = 2;
        vm.expectRevert("bad aad kind");
        symvm.importCiphertext(SUINT256, _encode(badKind, KEY_ID));
    }

    function testImportRejectsMalformedPayloads() public {
        vm.expectRevert("malformed ciphertext");
        symvm.importCiphertext(SUINT256, hex"010203");

        // Well-formed envelope wrapper, but the aad bytes are too short.
        SymVM.SystemCiphertextV1 memory envelope = SymVM.SystemCiphertextV1({
            keyId: KEY_ID,
            ciphertext: hex"cafe",
            aad: hex"0102"
        });
        vm.expectRevert("malformed aad");
        symvm.importCiphertext(SUINT256, abi.encode(envelope));
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

    function _typeTag(uint8 handleType) private pure returns (string memory) {
        return handleType == SUINT256 ? "suint256" : "sbool";
    }

    function _baseAad(
        uint8 handleType,
        address contractAddr
    ) private view returns (SymVM.SystemInputAadV1 memory) {
        return SymVM.SystemInputAadV1({
            version: 1,
            kind: 1,
            chainId: block.chainid,
            domainId: DOMAIN,
            contractAddr: contractAddr,
            typeTag: _typeTag(handleType),
            keyId: KEY_ID
        });
    }

    function _encode(
        SymVM.SystemInputAadV1 memory aad,
        bytes32 envelopeKeyId
    ) private pure returns (bytes memory) {
        SymVM.SystemCiphertextV1 memory envelope = SymVM.SystemCiphertextV1({
            keyId: envelopeKeyId,
            ciphertext: hex"deadbeef",
            aad: abi.encode(aad)
        });
        return abi.encode(envelope);
    }

    function _validEnvelope(
        uint8 handleType,
        address contractAddr
    ) private view returns (bytes memory) {
        return _encode(_baseAad(handleType, contractAddr), KEY_ID);
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
