// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1155Errors, IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {AITOBase, ExtensionLedger} from "./AITOBase.sol";
import {AITOLedger} from "../assets/erc-8506/contracts/AITOLedger.sol";
import {AITOWrapper20} from "../assets/erc-8506/contracts/AITOWrapper20.sol";
import {AITORecords} from "../assets/erc-8506/contracts/AITORecords.sol";
import {IAITOBinding} from "../assets/erc-8506/contracts/interfaces/IAITOBinding.sol";
import {IAITOWrapper20} from "../assets/erc-8506/contracts/interfaces/IAITOWrapper20.sol";
import {
    SeriesTerms,
    SeriesExtension,
    Authorization,
    ConsumptionRequest,
    Outcome,
    BindingType,
    ConsumptionPath
} from "../assets/erc-8506/contracts/interfaces/AITOTypes.sol";

contract AITOWrapperTest is AITOBase {
    uint256 internal seriesId;
    AITOWrapper20 internal wrapper;
    uint256 internal constant SCALE = 1e18;

    function setUp() public override {
        super.setUp();
        seriesId = _seriesWith(_textTerms(supplier), holder, 300_000);
        wrapper = new AITOWrapper20(address(ledger), seriesId, "Wrapped Inference Quota", "wAITO", 18);
    }

    function _assertBacked() internal view {
        assertEq(wrapper.totalSupply(), wrapper.lockedUnits() * SCALE, "every wrapped token is backed");
    }

    function test_binding_resolvesToTheSeries() public view {
        (address home, uint256 id, BindingType bindingType, uint256 carrierPerUnit, ConsumptionPath path) =
            wrapper.aitoBinding(0);
        assertEq(home, address(ledger));
        assertEq(id, seriesId);
        assertEq(uint8(bindingType), uint8(BindingType.Wrap));
        assertEq(carrierPerUnit, SCALE);
        assertEq(uint8(path), uint8(ConsumptionPath.UnwrapFirst));
        assertEq(wrapper.ledger(), address(ledger));
        assertEq(wrapper.seriesId(), seriesId);
        assertEq(wrapper.unitScale(), SCALE);
        assertEq(wrapper.decimals(), 18);

        assertTrue(wrapper.supportsInterface(type(IAITOBinding).interfaceId));
        assertTrue(wrapper.supportsInterface(type(IAITOWrapper20).interfaceId));
        assertTrue(wrapper.supportsInterface(type(IERC1155Receiver).interfaceId));
        assertTrue(wrapper.supportsInterface(type(IERC165).interfaceId));
        assertFalse(wrapper.supportsInterface(0xffffffff));
    }

    function test_wrap_byDirectTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit IAITOWrapper20.Wrapped(holder, holder, 200_000);
        vm.prank(holder);
        ledger.safeTransferFrom(holder, address(wrapper), seriesId, 200_000, "");

        assertEq(wrapper.balanceOf(holder), 200_000 * SCALE);
        assertEq(wrapper.lockedUnits(), 200_000);
        assertEq(ledger.availableOf(seriesId, holder), 100_000);
        _assertBacked();
    }

    function test_wrap_toAnotherRecipient() public {
        vm.prank(holder);
        ledger.safeTransferFrom(holder, address(wrapper), seriesId, 1_000, abi.encode(holder2));
        assertEq(wrapper.balanceOf(holder2), 1_000 * SCALE);
        assertEq(wrapper.balanceOf(holder), 0);
        _assertBacked();
    }

    function test_wrap_withOperatorApproval() public {
        vm.startPrank(holder);
        ledger.setApprovalForAll(address(wrapper), true);
        wrapper.wrap(50_000, holder2);
        vm.stopPrank();
        assertEq(wrapper.balanceOf(holder2), 50_000 * SCALE);
        assertEq(wrapper.lockedUnits(), 50_000);
        _assertBacked();
    }

    function test_unwrap_returnsExactlyTheLockedUnits() public {
        vm.prank(holder);
        ledger.safeTransferFrom(holder, address(wrapper), seriesId, 200_000, "");
        vm.prank(holder);
        wrapper.transfer(holder2, 50_000 * SCALE);

        vm.expectEmit(true, true, false, true);
        emit IAITOWrapper20.Unwrapped(holder2, holder2, 50_000);
        vm.prank(holder2);
        wrapper.unwrap(50_000, holder2);

        assertEq(ledger.availableOf(seriesId, holder2), 50_000);
        assertEq(wrapper.balanceOf(holder2), 0);
        assertEq(wrapper.lockedUnits(), 150_000);
        _assertBacked();

        // Nobody can unwrap more than they hold in wrapped form.
        vm.prank(holder2);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder2, 0, 1 * SCALE)
        );
        wrapper.unwrap(1, holder2);
    }

    function test_wrappedUnitsCannotBeConsumed() public {
        vm.prank(holder);
        ledger.safeTransferFrom(holder, address(wrapper), seriesId, 300_000, "");
        assertEq(ledger.availableOf(seriesId, holder), 0);

        // The owner of wrapped tokens has no native units to reserve.
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        ConsumptionRequest memory r = _request(a, keccak256("r"), supplier, 1_000);
        bytes memory holderSig = _sig(HOLDER_PK, r.authorizationId);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        vm.expectRevert(
            abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, holder, 0, 1_000, seriesId)
        );
        ledger.hold(a, holderSig, r, consumerSig);

        // Nobody can authorize consumption in the wrapper's name: it validates no signature
        // and registers no authorization.
        Authorization memory b = _authorization(address(wrapper), consumer, seriesId, 50_000);
        ConsumptionRequest memory rb = _request(b, keccak256("r"), supplier, 1_000);
        bytes memory forged = _sig(HOLDER_PK, rb.authorizationId);
        bytes memory consumerSigB = _sig(CONSUMER_PK, ledger.hashRequest(rb));
        vm.prank(supplier);
        vm.expectRevert(AITOLedger.InvalidHolderSignature.selector);
        ledger.hold(b, forged, rb, consumerSigB);

        vm.prank(holder);
        vm.expectRevert(AITOLedger.NotHolder.selector);
        ledger.authorize(b);
    }

    function test_unwrapDoesNotRestoreConsumedUnits() public {
        // Wrap 100,000, unwrap 10,000, consume 1,900 of them, then try to get more out than was put in.
        vm.prank(holder);
        ledger.safeTransferFrom(holder, address(wrapper), seriesId, 100_000, abi.encode(holder2));
        vm.prank(holder2);
        wrapper.unwrap(10_000, holder2);

        Authorization memory a = _authorization(holder2, consumer, seriesId, 5_000);
        bytes32 key = _hold(a, HOLDER2_PK, CONSUMER_PK, keccak256("r"), supplier, 3_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
        vm.warp(block.timestamp + 601);
        ledger.finalize(key);
        assertEq(ledger.availableOf(seriesId, holder2), 8_100);

        vm.startPrank(holder2);
        ledger.safeTransferFrom(holder2, address(wrapper), seriesId, 8_100, "");
        assertEq(wrapper.balanceOf(holder2), 98_100 * SCALE);
        vm.expectRevert();
        wrapper.unwrap(98_101, holder2);
        wrapper.unwrap(98_100, holder2);
        vm.stopPrank();

        assertEq(ledger.availableOf(seriesId, holder2), 98_100);
        assertEq(ledger.consumedOf(seriesId), 1_900);
        assertEq(wrapper.totalSupply(), 0);
        assertEq(wrapper.lockedUnits(), 0);
    }

    function test_wrapper_rejectsOtherTokens() public {
        // Another series on the same ledger.
        SeriesTerms memory t = _textTerms(supplier);
        t.termsHash = keccak256("another series");
        uint256 other = _seriesWith(t, holder, 1_000);
        vm.prank(holder);
        vm.expectRevert(AITOWrapper20.UnexpectedToken.selector);
        ledger.safeTransferFrom(holder, address(wrapper), other, 1, "");

        // The same series id on another ledger.
        AITOLedger otherLedger = new AITOLedger();
        vm.startPrank(supplier);
        uint256 sameTerms = otherLedger.createSeries(_textTerms(supplier), "ipfs://terms");
        otherLedger.issue(sameTerms, holder, 1_000, BASIS);
        vm.stopPrank();
        assertEq(sameTerms, seriesId, "identical terms give the same identifier on any ledger");
        vm.prank(holder);
        vm.expectRevert(AITOWrapper20.UnexpectedToken.selector);
        otherLedger.safeTransferFrom(holder, address(wrapper), sameTerms, 1, "");

        // Batches of several ids are not accepted.
        uint256[] memory ids = new uint256[](2);
        uint256[] memory values = new uint256[](2);
        ids[0] = seriesId;
        ids[1] = other;
        values[0] = 1;
        values[1] = 1;
        vm.prank(holder);
        vm.expectRevert(AITOWrapper20.BatchNotSupported.selector);
        ledger.safeBatchTransferFrom(holder, address(wrapper), ids, values, "");
        assertEq(wrapper.totalSupply(), 0);
    }

    function test_wrapper_refusesSeriesItCannotCarry() public {
        // Not transferable.
        SeriesTerms memory t = _textTerms(supplier);
        t.transferable = false;
        uint256 soulbound = _create(t);
        vm.expectRevert(AITOWrapper20.NotTransferable.selector);
        new AITOWrapper20(address(ledger), soulbound, "x", "x", 18);

        // Unknown series.
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.UnknownSeries.selector, uint256(99)));
        new AITOWrapper20(address(ledger), 99, "x", "x", 18);

        // Not an AITO ledger.
        AITORecords notALedger = new AITORecords();
        vm.expectRevert(AITOWrapper20.NotAnAITOLedger.selector);
        new AITOWrapper20(address(notALedger), seriesId, "x", "x", 18);

        // A critical extension the wrapper does not understand.
        ExtensionLedger ext = new ExtensionLedger();
        SeriesTerms memory e = _textTerms(supplier);
        e.extensions = new SeriesExtension[](1);
        e.extensions[0] = SeriesExtension({id: ext.EXTENSION(), critical: true, data: ""});
        vm.prank(supplier);
        uint256 extended = ext.createSeries(e, "ipfs://terms");
        vm.expectRevert(abi.encodeWithSelector(AITOWrapper20.UnknownCriticalExtension.selector, ext.EXTENSION()));
        new AITOWrapper20(address(ext), extended, "x", "x", 18);

        // An extension that is not critical does not stop the wrapper.
        e.extensions[0].critical = false;
        vm.prank(supplier);
        uint256 annotated = ext.createSeries(e, "ipfs://terms");
        new AITOWrapper20(address(ext), annotated, "x", "x", 18);
    }

    function test_wrapper_zeroDecimals() public {
        AITOWrapper20 plain = new AITOWrapper20(address(ledger), seriesId, "Plain", "pAITO", 0);
        vm.prank(holder);
        ledger.safeTransferFrom(holder, address(plain), seriesId, 7, "");
        assertEq(plain.balanceOf(holder), 7);
        assertEq(plain.unitScale(), 1);
        vm.prank(holder);
        plain.unwrap(7, holder);
        assertEq(plain.totalSupply(), 0);
    }

    function test_wrapper_expiry() public {
        SeriesTerms memory t = _textTerms(supplier);
        vm.prank(holder);
        ledger.safeTransferFrom(holder, address(wrapper), seriesId, 1_000, "");
        assertFalse(wrapper.expired());
        vm.warp(uint256(t.validUntil) + 1);
        assertTrue(wrapper.expired());

        // Unwrapping still works; what comes out is no longer consumable.
        vm.prank(holder);
        wrapper.unwrap(1_000, holder);
        assertEq(ledger.consumableOf(seriesId, holder), 0);
    }

    function testFuzz_wrapUnwrapKeepsBacking(uint32 wrapUnits, uint32 unwrapUnits) public {
        wrapUnits = uint32(bound(wrapUnits, 1, 300_000));
        unwrapUnits = uint32(bound(unwrapUnits, 0, wrapUnits));
        vm.startPrank(holder);
        ledger.safeTransferFrom(holder, address(wrapper), seriesId, wrapUnits, "");
        wrapper.unwrap(unwrapUnits, holder);
        vm.stopPrank();
        assertEq(wrapper.lockedUnits(), uint256(wrapUnits) - unwrapUnits);
        assertEq(ledger.availableOf(seriesId, holder) + wrapper.lockedUnits(), 300_000);
        _assertBacked();
    }
}
