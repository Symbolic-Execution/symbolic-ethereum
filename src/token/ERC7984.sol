// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC7984, IERC165} from "./IERC7984.sol";
import {SYM} from "../symvm/SYM.sol";
import {suint256, sbool} from "../symvm/Types.sol";

/// @title ERC7984
/// @notice Reference implementation of ERC-7984 Confidential Fungible Token
///         built on the SYM library.
/// @dev TODO: implement full ERC-7984 token logic.
abstract contract ERC7984 is IERC7984 {
    /// @dev ERC-7984 interface identifier, per the draft standard.
    bytes4 private constant _ERC7984_INTERFACE_ID = 0x4958f2a4;

    // ── State ───────────────────────────────────────────────────────────

    string private _name;
    string private _symbol;

    mapping(address => suint256) private _balances;
    suint256 private _totalSupply;

    /// @dev Operator grants: (holder => operator => expiry timestamp).
    mapping(address => mapping(address => uint48)) private _operators;

    // ── Constructor ─────────────────────────────────────────────────────

    constructor(string memory name_, string memory symbol_, address symvm) {
        _name = name_;
        _symbol = symbol_;
        SYM.setSymVM(symvm);
    }

    // ── ERC-165 ─────────────────────────────────────────────────────────

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == _ERC7984_INTERFACE_ID;
    }

    // ── Metadata ────────────────────────────────────────────────────────

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @notice Returns a URI for contract-level metadata.
    /// @dev Empty by default; implementers may override.
    function contractURI() public view virtual returns (string memory) {
        return "";
    }

    // ── Balances ────────────────────────────────────────────────────────

    function confidentialBalanceOf(
        address account
    ) external view returns (bytes32) {
        return suint256.unwrap(_balances[account]);
    }

    function confidentialTotalSupply() external view returns (bytes32) {
        return suint256.unwrap(_totalSupply);
    }

    // ── Transfers ───────────────────────────────────────────────────────

    function confidentialTransfer(
        address to,
        bytes32 amount
    ) external returns (bytes32 transferred) {
        return _transfer(msg.sender, to, suint256.wrap(amount));
    }

    function confidentialTransfer(
        address to,
        bytes32 amount,
        bytes calldata
    ) external returns (bytes32 transferred) {
        return _transfer(msg.sender, to, suint256.wrap(amount));
    }

    function confidentialTransferFrom(
        address from,
        address to,
        bytes32 amount
    ) external returns (bytes32 transferred) {
        require(isOperator(from, msg.sender), "not operator");
        return _transfer(from, to, suint256.wrap(amount));
    }

    function confidentialTransferFrom(
        address from,
        address to,
        bytes32 amount,
        bytes calldata
    ) external returns (bytes32 transferred) {
        require(isOperator(from, msg.sender), "not operator");
        return _transfer(from, to, suint256.wrap(amount));
    }

    // ── Operators ───────────────────────────────────────────────────────

    function setOperator(address operator, uint48 until) external {
        _operators[msg.sender][operator] = until;
        emit OperatorSet(msg.sender, operator, until);
    }

    function isOperator(
        address holder,
        address spender
    ) public view returns (bool) {
        if (holder == spender) return true;
        return _operators[holder][spender] >= block.timestamp;
    }

    // ── Internal ────────────────────────────────────────────────────────

    function _transfer(
        address from,
        address to,
        suint256 amount
    ) internal returns (bytes32) {
        require(from != address(0), "transfer from zero");
        require(to != address(0), "transfer to zero");
        require(SYM.isInitialized(_balances[from]), "zero balance");

        suint256 zero = SYM.fromPlaintext(0);

        // Silent failure: if balance < amount, transfer zero instead
        sbool canTransfer = SYM.gte(_balances[from], amount);
        suint256 transferValue = SYM.select(canTransfer, amount, zero);

        // Update sender balance
        suint256 newFromBalance = SYM.sub(_balances[from], transferValue);
        _balances[from] = newFromBalance;
        SYM.allow(newFromBalance, from);

        // Update receiver balance
        suint256 newToBalance;
        if (SYM.isInitialized(_balances[to])) {
            newToBalance = SYM.add(_balances[to], transferValue);
        } else {
            newToBalance = transferValue;
        }
        _balances[to] = newToBalance;
        SYM.allow(newToBalance, to);

        emit ConfidentialTransfer(from, to, suint256.unwrap(transferValue));

        return suint256.unwrap(transferValue);
    }

    /// @dev Mint confidential tokens to `to`.
    function _mint(address to, suint256 amount) internal {
        require(to != address(0), "mint to zero");

        suint256 newToBalance;
        if (SYM.isInitialized(_balances[to])) {
            newToBalance = SYM.add(_balances[to], amount);
        } else {
            newToBalance = amount;
        }
        _balances[to] = newToBalance;
        SYM.allow(newToBalance, to);

        if (SYM.isInitialized(_totalSupply)) {
            _totalSupply = SYM.add(_totalSupply, amount);
        } else {
            _totalSupply = amount;
        }

        emit ConfidentialTransfer(address(0), to, suint256.unwrap(amount));
    }
}
