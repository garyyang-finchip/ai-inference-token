// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {AITOBase, ExtensionLedger} from "./AITOBase.sol";
import {AITOLedger} from "../assets/erc-8506/contracts/AITOLedger.sol";
import {IAITOInstrument} from "../assets/erc-8506/contracts/interfaces/IAITOInstrument.sol";
import {IAITOConsumption} from "../assets/erc-8506/contracts/interfaces/IAITOConsumption.sol";
import {IAITOBinding} from "../assets/erc-8506/contracts/interfaces/IAITOBinding.sol";
import {
    SeriesTerms,
    SeriesExtension,
    Outcome,
    AcceptanceRule,
    BindingType,
    ConsumptionPath
} from "../assets/erc-8506/contracts/interfaces/AITOTypes.sol";

contract AITOSeriesTest is AITOBase {
    // ---------------------------------------------------------------- creation

    function test_createSeries_idIsHashOfTerms() public {
        SeriesTerms memory t = _textTerms(supplier);
        uint256 expected = uint256(keccak256(abi.encode(t)));
        assertEq(ledger.seriesIdOf(t), expected);

        vm.expectEmit(true, true, true, true);
        emit IAITOInstrument.SeriesCreated(expected, supplier, supplier, t.termsHash, "ipfs://terms");
        uint256 seriesId = _create(t);
        assertEq(seriesId, expected);

        SeriesTerms memory stored = ledger.seriesOf(seriesId);
        assertEq(keccak256(abi.encode(stored)), keccak256(abi.encode(t)));
        assertEq(ledger.termsURI(seriesId), "ipfs://terms");
        assertEq(ledger.uri(seriesId), "ipfs://terms");
        assertTrue(ledger.responsibilityAccepted(seriesId));
    }

    function test_createSeries_anyChangedTermIsAnotherSeries() public view {
        SeriesTerms memory t = _textTerms(supplier);
        uint256 base = ledger.seriesIdOf(t);

        SeriesTerms memory u = _textTerms(supplier);
        u.weights[0] = 250_001;
        assertTrue(ledger.seriesIdOf(u) != base, "schedule");

        u = _textTerms(supplier);
        u.validUntil += 1;
        assertTrue(ledger.seriesIdOf(u) != base, "validity");

        u = _textTerms(supplier);
        u.termsHash = keccak256("other document");
        assertTrue(ledger.seriesIdOf(u) != base, "terms document");

        u = _textTerms(supplier);
        u.outcomeMasks[uint8(Outcome.Refused)] = 0;
        assertTrue(ledger.seriesIdOf(u) != base, "outcome charging");
    }

    function test_createSeries_revertsForNonIssuer() public {
        SeriesTerms memory t = _textTerms(supplier);
        vm.prank(outsider);
        vm.expectRevert(AITOLedger.NotIssuer.selector);
        ledger.createSeries(t, "ipfs://terms");
    }

    function test_createSeries_revertsWhenItExists() public {
        SeriesTerms memory t = _textTerms(supplier);
        uint256 seriesId = _create(t);
        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.SeriesExists.selector, seriesId));
        ledger.createSeries(t, "ipfs://terms");
    }

    function test_createSeries_keyTermsMustBeDetermined() public {
        SeriesTerms memory t = _textTerms(supplier);
        t.unit = bytes32(0);
        _expectInvalid(t, "unit");

        t = _textTerms(supplier);
        t.grade = bytes32(0);
        _expectInvalid(t, "grade");

        t = _textTerms(supplier);
        t.source = bytes32(0);
        _expectInvalid(t, "source");

        t = _textTerms(supplier);
        t.termsHash = bytes32(0);
        _expectInvalid(t, "termsHash");

        t = _textTerms(supplier);
        t.responsibleParty = address(0);
        _expectInvalid(t, "responsibleParty");

        t = _textTerms(supplier);
        t.cap = 0;
        _expectInvalid(t, "cap");

        t = _textTerms(supplier);
        t.validUntil = t.validFrom;
        _expectInvalid(t, "validUntil");

        t = _textTerms(supplier);
        t.maxHoldDuration = 0;
        _expectInvalid(t, "maxHoldDuration");

        t = _textTerms(supplier);
        t.objectionWindow = 0;
        _expectInvalid(t, "objectionWindow");

        t = _textTerms(supplier);
        t.resolver = resolver;
        _expectInvalid(t, "resolutionWindow");

        t = _textTerms(supplier);
        t.weights = new uint256[](2);
        _expectInvalid(t, "weights");

        t = _textTerms(supplier);
        t.outcomeMasks = new uint256[](5);
        _expectInvalid(t, "outcomeMasks");

        t = _textTerms(supplier);
        t.outcomeMasks[0] = 8; // bit 3 names a component that does not exist
        _expectInvalid(t, "outcomeMasks");

        t = _textTerms(supplier);
        t.components[2] = t.components[0];
        _expectInvalid(t, "components");

        t = _textTerms(supplier);
        t.components = new bytes32[](0);
        t.weights = new uint256[](0);
        _expectInvalid(t, "components");
    }

    function _expectInvalid(SeriesTerms memory t, bytes32 member) private {
        vm.prank(t.issuer);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.InvalidTerms.selector, member));
        ledger.createSeries(t, "ipfs://terms");
    }

    function test_createSeries_mutableScheduleIsNotSupportedHere() public {
        SeriesTerms memory t = _textTerms(supplier);
        t.scheduleMutable = true;
        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.UnsupportedTerm.selector, bytes32("scheduleMutable")));
        ledger.createSeries(t, "ipfs://terms");
    }

    function test_createSeries_unknownCriticalExtensionIsRefused() public {
        bytes32 extension = keccak256("example.extension.v1");
        SeriesTerms memory t = _textTerms(supplier);
        t.extensions = new SeriesExtension[](1);
        t.extensions[0] = SeriesExtension({id: extension, critical: true, data: abi.encode(uint256(7))});
        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.UnknownCriticalExtension.selector, extension));
        ledger.createSeries(t, "ipfs://terms");

        // A ledger that implements the extension accepts the same terms.
        ExtensionLedger ext = new ExtensionLedger();
        vm.prank(supplier);
        ext.createSeries(t, "ipfs://terms");
        assertFalse(ledger.supportsExtension(extension));
        assertTrue(ext.supportsExtension(extension));
    }

    function test_createSeries_theTwoProfilesOfTheSpecificationAreNotImplementedHere() public {
        bytes32 periodic = keccak256("aito.profile.periodic-allowance.v1");
        bytes32 reserved = keccak256("aito.profile.reserved-capacity.v1");
        assertFalse(ledger.supportsExtension(periodic));
        assertFalse(ledger.supportsExtension(reserved));

        SeriesTerms memory t = _textTerms(supplier);
        t.extensions = new SeriesExtension[](1);
        t.extensions[0] = SeriesExtension({
            id: periodic,
            critical: true,
            data: abi.encode(uint64(T0), uint32(1 days), uint256(10_000), uint256(0))
        });
        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.UnknownCriticalExtension.selector, periodic));
        ledger.createSeries(t, "ipfs://terms");
    }

    function test_createSeries_nonCriticalExtensionIsCarriedAndCommitted() public {
        SeriesTerms memory t = _textTerms(supplier);
        uint256 plain = ledger.seriesIdOf(t);
        t.extensions = new SeriesExtension[](1);
        t.extensions[0] = SeriesExtension({id: keccak256("example.note.v1"), critical: false, data: hex"01"});
        uint256 seriesId = _create(t);
        assertTrue(seriesId != plain, "an extension is part of the terms");
        assertEq(ledger.seriesOf(seriesId).extensions[0].data, hex"01");

        // Changing only the parameters of an extension gives another series.
        t.extensions[0].data = hex"02";
        assertTrue(ledger.seriesIdOf(t) != seriesId);

        t.extensions[0].id = bytes32(0);
        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.InvalidTerms.selector, bytes32("extensions")));
        ledger.createSeries(t, "ipfs://terms");
    }

    // ---------------------------------------------------------------- responsibility

    function test_responsibility_mustBeAcceptedByTheObligor() public {
        SeriesTerms memory t = _textTerms(supplier);
        t.responsibleParty = distributor; // someone else is named as the obligor
        uint256 seriesId = _create(t);
        assertFalse(ledger.responsibilityAccepted(seriesId));

        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.ResponsibilityNotAccepted.selector, seriesId));
        ledger.issue(seriesId, holder, 1, BASIS);

        vm.prank(supplier);
        vm.expectRevert(AITOLedger.NotResponsibleParty.selector);
        ledger.acceptResponsibility(seriesId);

        vm.expectEmit(true, true, false, false);
        emit IAITOInstrument.ResponsibilityAccepted(seriesId, distributor);
        vm.prank(distributor);
        ledger.acceptResponsibility(seriesId);

        vm.prank(supplier);
        ledger.issue(seriesId, holder, 1, BASIS);
        assertEq(ledger.balanceOf(holder, seriesId), 1);
    }

    function test_setFulfiller_onlyResponsibleParty() public {
        uint256 seriesId = _create(_textTerms(supplier));
        vm.prank(outsider);
        vm.expectRevert(AITOLedger.NotResponsibleParty.selector);
        ledger.setFulfiller(seriesId, outsider, true);

        vm.prank(supplier);
        ledger.setFulfiller(seriesId, distributor, true);
        assertTrue(ledger.isFulfiller(seriesId, distributor));
        vm.prank(supplier);
        ledger.setFulfiller(seriesId, distributor, false);
        assertFalse(ledger.isFulfiller(seriesId, distributor));
    }

    // ---------------------------------------------------------------- issuance

    function test_issue_citesABasisAndRespectsTheCap() public {
        SeriesTerms memory t = _textTerms(supplier);
        uint256 seriesId = _create(t);

        vm.prank(outsider);
        vm.expectRevert(AITOLedger.NotIssuer.selector);
        ledger.issue(seriesId, holder, 1, BASIS);

        vm.prank(supplier);
        vm.expectRevert(AITOLedger.MissingBasis.selector);
        ledger.issue(seriesId, holder, 1, bytes32(0));

        vm.expectEmit(true, true, false, true);
        emit IAITOInstrument.Issued(seriesId, holder, t.cap, BASIS);
        vm.prank(supplier);
        ledger.issue(seriesId, holder, t.cap, BASIS);
        assertEq(ledger.issuedOf(seriesId), t.cap);

        vm.prank(supplier);
        vm.expectRevert(AITOLedger.CapExceeded.selector);
        ledger.issue(seriesId, holder, 1, BASIS);
    }

    function test_issue_notAfterExpiry() public {
        SeriesTerms memory t = _textTerms(supplier);
        uint256 seriesId = _create(t);
        vm.warp(uint256(t.validUntil) + 1);
        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.SeriesNotConsumable.selector, seriesId));
        ledger.issue(seriesId, holder, 1, BASIS);
    }

    function test_issue_unknownSeries() public {
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.UnknownSeries.selector, uint256(42)));
        ledger.issue(42, holder, 1, BASIS);
    }

    // ---------------------------------------------------------------- transfer, retire, lapse

    function test_transfer_isAPlainERC1155Transfer() public {
        uint256 seriesId = _seriesWith(_textTerms(supplier), holder, 1_000);
        vm.prank(holder);
        ledger.safeTransferFrom(holder, holder2, seriesId, 400, "");
        assertEq(ledger.balanceOf(holder, seriesId), 600);
        assertEq(ledger.balanceOf(holder2, seriesId), 400);
        assertEq(ledger.availableOf(seriesId, holder2), 400);
        assertEq(ledger.consumableOf(seriesId, holder2), 400);
    }

    function test_transfer_nonTransferableSeries() public {
        SeriesTerms memory t = _textTerms(supplier);
        t.transferable = false;
        uint256 seriesId = _seriesWith(t, holder, 1_000);

        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.NonTransferable.selector, seriesId));
        ledger.safeTransferFrom(holder, holder2, seriesId, 1, "");

        // Retiring one's own units is not a transfer between holders.
        vm.prank(holder);
        ledger.retire(seriesId, 100);
        assertEq(ledger.retiredOf(seriesId), 100);
    }

    function test_transfer_toTheLedgerItselfIsRejected() public {
        uint256 seriesId = _seriesWith(_textTerms(supplier), holder, 1_000);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidReceiver.selector, address(ledger)));
        ledger.safeTransferFrom(holder, address(ledger), seriesId, 1, "");
    }

    function test_retire_reducesOnlyTheCallersUnits() public {
        uint256 seriesId = _seriesWith(_textTerms(supplier), holder, 1_000);
        vm.expectEmit(true, true, false, true);
        emit IAITOInstrument.Retired(seriesId, holder, 250);
        vm.prank(holder);
        ledger.retire(seriesId, 250);
        assertEq(ledger.balanceOf(holder, seriesId), 750);
        assertEq(ledger.retiredOf(seriesId), 250);

        vm.prank(holder2);
        vm.expectRevert();
        ledger.retire(seriesId, 1);
    }

    function test_lapse_onlyAfterExpiry() public {
        SeriesTerms memory t = _textTerms(supplier);
        uint256 seriesId = _seriesWith(t, holder, 1_000);

        vm.expectRevert(abi.encodeWithSelector(AITOLedger.SeriesNotExpired.selector, seriesId));
        ledger.lapse(seriesId, holder);

        vm.warp(t.validUntil);
        assertEq(ledger.consumableOf(seriesId, holder), 1_000, "last valid second");
        vm.warp(uint256(t.validUntil) + 1);
        assertEq(ledger.consumableOf(seriesId, holder), 0, "expired");
        assertEq(ledger.availableOf(seriesId, holder), 1_000, "still recorded until lapsed");

        vm.expectEmit(true, true, false, true);
        emit IAITOInstrument.Lapsed(seriesId, holder, 1_000);
        vm.prank(outsider);
        ledger.lapse(seriesId, holder);
        assertEq(ledger.balanceOf(holder, seriesId), 0);
        assertEq(ledger.lapsedOf(seriesId), 1_000);

        vm.expectRevert(AITOLedger.EscrowAccount.selector);
        ledger.lapse(seriesId, address(ledger));
    }

    function test_consumable_notBeforeValidFrom() public {
        SeriesTerms memory t = _textTerms(supplier);
        t.validFrom = T0 + 30 days;
        t.validUntil = T0 + 120 days;
        uint256 seriesId = _seriesWith(t, holder, 1_000);
        assertEq(ledger.availableOf(seriesId, holder), 1_000);
        assertEq(ledger.consumableOf(seriesId, holder), 0);
        vm.warp(t.validFrom);
        assertEq(ledger.consumableOf(seriesId, holder), 1_000);
    }

    // ---------------------------------------------------------------- charging

    function test_quoteCharge_scheduleAndOutcomeMasks() public {
        uint256 seriesId = _create(_textTerms(supplier));
        // 2,100 output + 0.25 x 6,000 input = 3,600
        assertEq(ledger.quoteCharge(seriesId, _usage3(6_000, 2_100, 0), Outcome.Completed), 3_600);
        // cache reads at 0.025: 40,000 x 0.025 = 1,000
        assertEq(ledger.quoteCharge(seriesId, _usage3(0, 0, 40_000), Outcome.Completed), 1_000);
        // a refusal charges input only
        assertEq(ledger.quoteCharge(seriesId, _usage3(6_000, 2_100, 0), Outcome.Refused), 1_500);
        // a timeout before the first token and a provider error charge nothing
        assertEq(ledger.quoteCharge(seriesId, _usage3(6_000, 2_100, 0), Outcome.TimedOut), 0);
        assertEq(ledger.quoteCharge(seriesId, _usage3(6_000, 2_100, 0), Outcome.ProviderError), 0);
        // a partial delivery and a consumer cancellation charge what was reported
        assertEq(ledger.quoteCharge(seriesId, _usage3(6_000, 700, 0), Outcome.Partial), 2_200);
        assertEq(ledger.quoteCharge(seriesId, _usage3(6_000, 700, 0), Outcome.CancelledByConsumer), 2_200);
    }

    function test_quoteCharge_rounding() public {
        SeriesTerms memory up = _textTerms(supplier);
        uint256 upId = _create(up);
        SeriesTerms memory down = _textTerms(supplier);
        down.roundUp = false;
        uint256 downId = _create(down);

        // 1 input unit at 0.25
        assertEq(ledger.quoteCharge(upId, _usage3(1, 0, 0), Outcome.Completed), 1);
        assertEq(ledger.quoteCharge(downId, _usage3(1, 0, 0), Outcome.Completed), 0);
        // 4 input units at 0.25 is exactly 1 either way
        assertEq(ledger.quoteCharge(upId, _usage3(4, 0, 0), Outcome.Completed), 1);
        assertEq(ledger.quoteCharge(downId, _usage3(4, 0, 0), Outcome.Completed), 1);
    }

    function test_quoteCharge_usageMustMatchComponents() public {
        uint256 seriesId = _create(_textTerms(supplier));
        vm.expectRevert(AITOLedger.UsageLengthMismatch.selector);
        ledger.quoteCharge(seriesId, _usage2(1, 1), Outcome.Completed);
    }

    function testFuzz_quoteCharge_matchesTheSchedule(uint64 input, uint64 output, uint64 cacheRead) public {
        uint256 seriesId = _create(_textTerms(supplier));
        uint256 scaled = uint256(input) * 250_000 + uint256(output) * 1_000_000 + uint256(cacheRead) * 25_000;
        uint256 expected = (scaled + 999_999) / 1_000_000;
        assertEq(ledger.quoteCharge(seriesId, _usage3(input, output, cacheRead), Outcome.Completed), expected);
    }

    // ---------------------------------------------------------------- binding and interfaces

    function test_nativeBinding() public {
        uint256 seriesId = _create(_textTerms(supplier));
        (address home, uint256 id, BindingType bindingType, uint256 carrierPerUnit, ConsumptionPath path) =
            ledger.aitoBinding(seriesId);
        assertEq(home, address(ledger));
        assertEq(id, seriesId);
        assertEq(uint8(bindingType), uint8(BindingType.Native));
        assertEq(carrierPerUnit, 1);
        assertEq(uint8(path), uint8(ConsumptionPath.Direct));

        vm.expectRevert(abi.encodeWithSelector(AITOLedger.UnknownSeries.selector, uint256(7)));
        ledger.aitoBinding(7);
    }

    function test_supportsInterface_reportsOnlyWhatIsImplemented() public view {
        assertTrue(ledger.supportsInterface(type(IERC165).interfaceId));
        assertTrue(ledger.supportsInterface(type(IERC1155).interfaceId));
        assertTrue(ledger.supportsInterface(type(IERC1155MetadataURI).interfaceId));
        assertTrue(ledger.supportsInterface(type(IAITOInstrument).interfaceId));
        assertTrue(ledger.supportsInterface(type(IAITOConsumption).interfaceId));
        assertTrue(ledger.supportsInterface(type(IAITOBinding).interfaceId));
        assertFalse(ledger.supportsInterface(0xffffffff));
        assertFalse(ledger.supportsInterface(0x12345678));
    }
}
