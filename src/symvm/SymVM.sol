// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISymVM} from "./ISymVM.sol";
import {SBOOL, SUINT256} from "./Types.sol";

/// @title SymVM
/// @notice On-chain handle registry, operation dispatch, and authorization.
/// @dev TODO: implement ciphertext AAD validation.
contract SymVM is ISymVM {
    // ── State ───────────────────────────────────────────────────────────

    /// @dev The domain identifier for this symVM instance.
    bytes32 public immutable domainId;

    /// @dev Per-contract handle nonce: (contract => nonce).
    mapping(address => uint64) private _nonces;

    /// @dev Handle ownership: (handleId => creating contract).
    mapping(bytes32 => address) private _owners;

    /// @dev Handle type: (handleId => HandleType). Zero means unset.
    mapping(bytes32 => uint8) private _handleTypes;

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
        _requireValidHandleType(handleType);
        // TODO: validate aad bindings (contract, key_id, type_tag, domain_id, chain_id)
        handleId = _createHandle(msg.sender, handleType);

        emit HandleImportedV1(
            domainId, msg.sender, handleId, handleType, systemCiphertext
        );
    }

    function fromPlaintext(
        uint8 handleType,
        bytes32 value
    ) external returns (bytes32 handleId) {
        _requireValidHandleType(handleType);
        if (handleType == SBOOL) {
            require(
                value == bytes32(0) || value == bytes32(uint256(1)),
                "invalid bool"
            );
        }

        handleId = _createHandle(msg.sender, handleType);

        emit HandleFromPlaintextV1(
            domainId, msg.sender, handleId, handleType, value
        );
    }

    // ── Operations ──────────────────────────────────────────────────────

    function add(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(1, SUINT256, SUINT256, a, b);
    }

    function sub(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(2, SUINT256, SUINT256, a, b);
    }

    function eq(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(3, SUINT256, SBOOL, a, b);
    }

    function lt(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(4, SUINT256, SBOOL, a, b);
    }

    function lte(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(5, SUINT256, SBOOL, a, b);
    }

    function gt(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(6, SUINT256, SBOOL, a, b);
    }

    function gte(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(7, SUINT256, SBOOL, a, b);
    }

    function and_(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(8, SBOOL, SBOOL, a, b);
    }

    function or_(bytes32 a, bytes32 b) external returns (bytes32) {
        return _binaryOp(9, SBOOL, SBOOL, a, b);
    }

    function not_(bytes32 a) external returns (bytes32) {
        _requireAuthorized(a, msg.sender);
        _requireHandleType(a, SBOOL);

        bytes32[] memory inputs = new bytes32[](1);
        inputs[0] = a;

        bytes32 outputId = _createHandle(msg.sender, SBOOL);

        emit OperationRequestedV1(
            domainId, msg.sender, outputId, SBOOL, 10, inputs
        );

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
        _requireHandleType(pred, SBOOL);

        uint8 outputType = _handleTypes[whenTrue];
        require(outputType == _handleTypes[whenFalse], "type mismatch");

        bytes32[] memory inputs = new bytes32[](3);
        inputs[0] = pred;
        inputs[1] = whenTrue;
        inputs[2] = whenFalse;

        bytes32 outputId = _createHandle(msg.sender, outputType);

        emit OperationRequestedV1(
            domainId, msg.sender, outputId, outputType, 11, inputs
        );

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

    function _createHandle(
        address caller,
        uint8 handleType
    ) private returns (bytes32) {
        uint64 nonce = _nonces[caller];
        bytes32 handleId = keccak256(abi.encode(domainId, caller, nonce));
        _nonces[caller] = nonce + 1;
        _owners[handleId] = caller;
        _handleTypes[handleId] = handleType;
        return handleId;
    }

    function _isAuthorized(
        bytes32 handleId,
        address account
    ) private view returns (bool) {
        address owner = _owners[handleId];
        if (owner == address(0)) return false;

        // Owner is always authorized
        if (owner == account) return true;

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
        require(_owners[handleId] != address(0), "unknown handle");
        require(_isAuthorized(handleId, account), "not authorized");
    }

    function _requireValidHandleType(uint8 handleType) private pure {
        require(handleType == SUINT256 || handleType == SBOOL, "invalid type");
    }

    function _requireHandleType(
        bytes32 handleId,
        uint8 expectedType
    ) private view {
        require(_handleTypes[handleId] == expectedType, "invalid input type");
    }

    function _binaryOp(
        uint8 opCode,
        uint8 inputType,
        uint8 outputType,
        bytes32 a,
        bytes32 b
    ) private returns (bytes32) {
        _requireAuthorized(a, msg.sender);
        _requireAuthorized(b, msg.sender);
        _requireHandleType(a, inputType);
        _requireHandleType(b, inputType);

        bytes32[] memory inputs = new bytes32[](2);
        inputs[0] = a;
        inputs[1] = b;

        bytes32 outputId = _createHandle(msg.sender, outputType);

        emit OperationRequestedV1(
            domainId, msg.sender, outputId, outputType, opCode, inputs
        );

        return outputId;
    }
}
