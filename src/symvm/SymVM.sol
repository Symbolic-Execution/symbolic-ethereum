// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISymVM} from "./ISymVM.sol";

/// @title SymVM
/// @notice On-chain handle registry, operation dispatch, and authorization.
/// @dev TODO: implement handle creation, operation dispatch, event emission,
///      input validation, and authorization logic.
contract SymVM is ISymVM {
    // ── State ───────────────────────────────────────────────────────────

    /// @dev The domain identifier for this symVM instance.
    bytes32 public immutable domainId;

    /// @dev Per-contract handle nonce: (contract => nonce).
    mapping(address => uint64) private _nonces;

    /// @dev Handle ownership: (handleId => creating contract).
    mapping(bytes32 => address) private _owners;

    /// @dev Persistent authorization: (handleId => account => allowed).
    mapping(bytes32 => mapping(address => bool)) private _allowed;

    // ── Events ──────────────────────────────────────────────────────────

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

    // ── Constructor ─────────────────────────────────────────────────────

    constructor(bytes32 _domainId) {
        domainId = _domainId;
    }

    // ── Handle creation ─────────────────────────────────────────────────

    function importCiphertext(
        uint8 handleType,
        bytes calldata systemCiphertext
    ) external returns (bytes32 handleId) {
        // TODO: validate aad bindings (contract, key_id, type_tag, domain_id, chain_id)
        handleId = _createHandle(msg.sender);
        _owners[handleId] = msg.sender;

        emit HandleImportedV1(
            domainId, msg.sender, handleId, handleType, systemCiphertext
        );
    }

    function fromPlaintext(
        uint8 handleType,
        bytes32 value
    ) external returns (bytes32 handleId) {
        handleId = _createHandle(msg.sender);
        _owners[handleId] = msg.sender;

        emit HandleFromPlaintextV1(
            domainId, msg.sender, handleId, handleType, value
        );
    }

    // ── Operations ──────────────────────────────────────────────────────

    function add(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(1, a, b);
    }

    function sub(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(2, a, b);
    }

    function eq(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(3, a, b);
    }

    function lt(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(4, a, b);
    }

    function lte(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(5, a, b);
    }

    function gt(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(6, a, b);
    }

    function gte(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(7, a, b);
    }

    function and_(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(8, a, b);
    }

    function or_(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(9, a, b);
    }

    function not_(bytes32 a) external returns (bytes32) {
        _requireAuthorized(a, msg.sender);

        bytes32[] memory inputs = new bytes32[](1);
        inputs[0] = a;

        bytes32 outputId = _createHandle(msg.sender);
        _owners[outputId] = msg.sender;

        // TODO: derive output type from input type
        emit OperationRequestedV1(domainId, msg.sender, outputId, 0, 10, inputs);

        return outputId;
    }

    function select(
        bytes32 pred,
        bytes32 whenTrue,
        bytes32 whenFalse
    ) external returns (bytes32) {
        _requireAuthorized(pred, msg.sender);
        _requireAuthorized(whenTrue, msg.sender);
        _requireAuthorized(whenFalse, msg.sender);

        bytes32[] memory inputs = new bytes32[](3);
        inputs[0] = pred;
        inputs[1] = whenTrue;
        inputs[2] = whenFalse;

        bytes32 outputId = _createHandle(msg.sender);
        _owners[outputId] = msg.sender;

        // TODO: derive output type from branch types
        emit OperationRequestedV1(domainId, msg.sender, outputId, 0, 11, inputs);

        return outputId;
    }

    // ── Authorization ───────────────────────────────────────────────────

    function allow(bytes32 handleId, address target) external {
        require(_owners[handleId] == msg.sender, "not owner");
        _allowed[handleId][target] = true;
    }

    function revoke(bytes32 handleId, address target) external {
        require(_owners[handleId] == msg.sender, "not owner");
        _allowed[handleId][target] = false;
    }

    function allowTransient(bytes32 handleId, address target) external {
        require(_owners[handleId] == msg.sender, "not owner");
        // EIP-1153 transient storage
        bytes32 slot = keccak256(abi.encode(handleId, target));
        assembly {
            tstore(slot, 1)
        }
    }

    function isAllowed(
        bytes32 handleId,
        address account
    ) external view returns (bool) {
        return _isAuthorized(handleId, account);
    }

    // ── Internals ───────────────────────────────────────────────────────

    function _createHandle(address caller) private returns (bytes32) {
        uint64 nonce = _nonces[caller];
        bytes32 handleId = keccak256(abi.encode(domainId, caller, nonce));
        _nonces[caller] = nonce + 1;
        return handleId;
    }

    function _isAuthorized(
        bytes32 handleId,
        address account
    ) private view returns (bool) {
        // Owner is always authorized
        if (_owners[handleId] == account) return true;

        // Persistent grant
        if (_allowed[handleId][account]) return true;

        // Transient grant (EIP-1153)
        bytes32 slot = keccak256(abi.encode(handleId, account));
        uint256 val;
        assembly {
            val := tload(slot)
        }
        return val != 0;
    }

    function _requireAuthorized(bytes32 handleId, address account) private view {
        require(handleId != bytes32(0), "uninitialized handle");
        require(_isAuthorized(handleId, account), "not authorized");
    }

    function _binaryOp(
        uint8 opCode,
        bytes32 a,
        bytes32 b
    ) private returns (bytes32) {
        _requireAuthorized(a, msg.sender);
        _requireAuthorized(b, msg.sender);

        bytes32[] memory inputs = new bytes32[](2);
        inputs[0] = a;
        inputs[1] = b;

        bytes32 outputId = _createHandle(msg.sender);
        _owners[outputId] = msg.sender;

        // TODO: derive output type from operation and input types
        emit OperationRequestedV1(domainId, msg.sender, outputId, 0, opCode, inputs);

        return outputId;
    }
}
