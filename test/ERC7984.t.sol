// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC7984} from "../src/token/ERC7984.sol";
import {SYM} from "../src/symvm/SYM.sol";
import {SymVM} from "../src/symvm/SymVM.sol";
import {suint256, SBOOL, SUINT256} from "../src/symvm/Types.sol";

contract ERC7984Harness is ERC7984 {
    constructor(address symvm) ERC7984("Symbolic Token", "SYM", symvm) {}

    function amountPlain(uint256 value) external returns (bytes32) {
        return suint256.unwrap(SYM.fromPlaintext(value));
    }

    function mintPlain(
        address to,
        uint256 value
    ) external returns (bytes32) {
        suint256 amount = SYM.fromPlaintext(value);
        _mint(to, amount);
        return suint256.unwrap(amount);
    }
}

contract ERC7984Test is Test {
    bytes32 private constant DOMAIN = keccak256("symbolic.test.domain");

    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant OPERATOR = address(0x0FEE);

    SymVM private symvm;
    ERC7984Harness private token;

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

    event ConfidentialTransfer(
        address indexed from,
        address indexed to,
        bytes32 indexed amount
    );

    event OperatorSet(
        address indexed holder,
        address indexed operator,
        uint48 until
    );

    function setUp() public {
        vm.warp(100);
        symvm = new SymVM(DOMAIN);
        token = new ERC7984Harness(address(symvm));
    }

    function testMetadata() public view {
        assertEq(token.name(), "Symbolic Token");
        assertEq(token.symbol(), "SYM");
        assertEq(token.decimals(), 18);
    }

    function testFirstMintSetsBalanceAndTotalSupplyToAmountHandle() public {
        bytes32 amount = _tokenHandle(0);

        _expectPlain(0, 10);
        _expectTransfer(address(0), ALICE, amount);

        bytes32 returned = token.mintPlain(ALICE, 10);

        assertEq(returned, amount);
        assertEq(token.confidentialBalanceOf(ALICE), amount);
        assertEq(token.confidentialTotalSupply(), amount);
        assertTrue(symvm.isAllowed(amount, ALICE));
    }

    function testSecondMintAddsBalanceAndTotalSupply() public {
        bytes32 firstAmount = token.mintPlain(ALICE, 10);
        bytes32 secondAmount = _tokenHandle(1);
        bytes32 newBalance = _tokenHandle(2);
        bytes32 newSupply = _tokenHandle(3);

        _expectPlain(1, 4);
        _expectOperation(2, SUINT256, 1, _inputs2(firstAmount, secondAmount));
        _expectOperation(3, SUINT256, 1, _inputs2(firstAmount, secondAmount));
        _expectTransfer(address(0), ALICE, secondAmount);

        bytes32 returned = token.mintPlain(ALICE, 4);

        assertEq(returned, secondAmount);
        assertEq(token.confidentialBalanceOf(ALICE), newBalance);
        assertEq(token.confidentialTotalSupply(), newSupply);
        assertTrue(symvm.isAllowed(newBalance, ALICE));
    }

    function testTransferToEmptyRecipientStoresTransferValueDirectly() public {
        bytes32 aliceBalance = token.mintPlain(ALICE, 10);
        bytes32 amount = token.amountPlain(4);
        bytes32 zero = _tokenHandle(2);
        bytes32 canTransfer = _tokenHandle(3);
        bytes32 transferValue = _tokenHandle(4);
        bytes32 newAliceBalance = _tokenHandle(5);

        _expectPlain(2, 0);
        _expectOperation(3, SBOOL, 7, _inputs2(aliceBalance, amount));
        _expectOperation(4, SUINT256, 11, _inputs3(canTransfer, amount, zero));
        _expectOperation(5, SUINT256, 2, _inputs2(aliceBalance, transferValue));
        _expectTransfer(ALICE, BOB, transferValue);

        vm.prank(ALICE);
        bytes32 returned = token.confidentialTransfer(BOB, amount);

        assertEq(returned, transferValue);
        assertEq(token.confidentialBalanceOf(ALICE), newAliceBalance);
        assertEq(token.confidentialBalanceOf(BOB), transferValue);
        assertTrue(symvm.isAllowed(newAliceBalance, ALICE));
        assertTrue(symvm.isAllowed(transferValue, BOB));
    }

    function testTransferToExistingRecipientEmitsReceiverAdd() public {
        bytes32 aliceBalance = token.mintPlain(ALICE, 10);
        bytes32 bobStartingBalance = token.mintPlain(BOB, 1);
        bytes32 amount = token.amountPlain(4);
        bytes32 zero = _tokenHandle(4);
        bytes32 canTransfer = _tokenHandle(5);
        bytes32 transferValue = _tokenHandle(6);
        bytes32 newAliceBalance = _tokenHandle(7);
        bytes32 newBobBalance = _tokenHandle(8);

        _expectPlain(4, 0);
        _expectOperation(5, SBOOL, 7, _inputs2(aliceBalance, amount));
        _expectOperation(6, SUINT256, 11, _inputs3(canTransfer, amount, zero));
        _expectOperation(7, SUINT256, 2, _inputs2(aliceBalance, transferValue));
        _expectOperation(
            8, SUINT256, 1, _inputs2(bobStartingBalance, transferValue)
        );
        _expectTransfer(ALICE, BOB, transferValue);

        vm.prank(ALICE);
        bytes32 returned = token.confidentialTransfer(BOB, amount);

        assertEq(returned, transferValue);
        assertEq(token.confidentialBalanceOf(ALICE), newAliceBalance);
        assertEq(token.confidentialBalanceOf(BOB), newBobBalance);
        assertTrue(symvm.isAllowed(newAliceBalance, ALICE));
        assertTrue(symvm.isAllowed(newBobBalance, BOB));
    }

    function testZeroAddressMintAndTransferPathsRevert() public {
        vm.expectRevert("mint to zero");
        token.mintPlain(address(0), 1);

        bytes32 amount = token.amountPlain(1);

        vm.prank(address(0));
        vm.expectRevert("transfer from zero");
        token.confidentialTransfer(BOB, amount);

        token.mintPlain(ALICE, 10);

        vm.prank(ALICE);
        vm.expectRevert("transfer to zero");
        token.confidentialTransfer(address(0), amount);
    }

    function testOperatorFlowRequiresApprovalAndRespectsExpiry() public {
        token.mintPlain(ALICE, 10);
        bytes32 amount = token.amountPlain(1);

        assertFalse(token.isOperator(ALICE, OPERATOR));

        vm.prank(OPERATOR);
        vm.expectRevert("not operator");
        token.confidentialTransferFrom(ALICE, BOB, amount);

        uint48 expiry = uint48(block.timestamp + 10);

        vm.expectEmit(true, true, true, true, address(token));
        emit OperatorSet(ALICE, OPERATOR, expiry);

        vm.prank(ALICE);
        token.setOperator(OPERATOR, expiry);

        assertTrue(token.isOperator(ALICE, OPERATOR));

        vm.prank(OPERATOR);
        token.confidentialTransferFrom(ALICE, BOB, amount);

        vm.warp(expiry + 1);
        bytes32 laterAmount = token.amountPlain(1);

        assertFalse(token.isOperator(ALICE, OPERATOR));

        vm.prank(OPERATOR);
        vm.expectRevert("not operator");
        token.confidentialTransferFrom(ALICE, BOB, laterAmount);
    }

    function _expectPlain(uint64 nonce, uint256 value) private {
        vm.expectEmit(true, true, true, true, address(symvm));
        emit HandleFromPlaintextV1(
            DOMAIN, address(token), _tokenHandle(nonce), SUINT256, bytes32(value)
        );
    }

    function _expectOperation(
        uint64 outputNonce,
        uint8 outputType,
        uint8 operation,
        bytes32[] memory inputs
    ) private {
        vm.expectEmit(true, true, true, true, address(symvm));
        emit OperationRequestedV1(
            DOMAIN,
            address(token),
            _tokenHandle(outputNonce),
            outputType,
            operation,
            inputs
        );
    }

    function _expectTransfer(address from, address to, bytes32 amount) private {
        vm.expectEmit(true, true, true, true, address(token));
        emit ConfidentialTransfer(from, to, amount);
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

    function _tokenHandle(uint64 nonce) private view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN, address(token), nonce));
    }
}
