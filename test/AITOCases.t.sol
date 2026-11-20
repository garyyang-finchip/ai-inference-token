// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {AITOBase} from "./AITOBase.sol";
import {AITOLedger} from "../assets/erc-9999/contracts/AITOLedger.sol";
import {AITOWrapper20} from "../assets/erc-9999/contracts/AITOWrapper20.sol";
import {IAITOBinding} from "../assets/erc-9999/contracts/interfaces/IAITOBinding.sol";
import {IAITOInstrument} from "../assets/erc-9999/contracts/interfaces/IAITOInstrument.sol";
import {
    SeriesTerms,
    SeriesExtension,
    Authorization,
    ConsumptionRequest,
    RequestRecord,
    RequestState,
    RecordKind,
    Outcome,
    AcceptanceRule,
    BindingType,
    ConsumptionPath
} from "../assets/erc-9999/contracts/interfaces/AITOTypes.sol";

/// @notice The worked cases of the specification, with the same numbers.
contract AITOCasesTest is AITOBase {
    // ------------------------------------------------------------------
    // Case A. A supplier's quota: native binding, wrap, unwrap, consume.
    // ------------------------------------------------------------------

    function test_caseA_supplierQuotaNativeAndWrapped() public {
        SeriesTerms memory t = _textTerms(supplier);

        // 1. The supplier anchors the records the series is issued under.
        vm.startPrank(supplier);
        records.anchor(t.unit, RecordKind.Unit, bytes32(0), "ipfs://unit");
        records.anchor(t.grade, RecordKind.Grade, bytes32(0), "ipfs://grade");
        records.anchor(t.source, RecordKind.Source, bytes32(0), "ipfs://source");
        records.anchor(t.termsHash, RecordKind.Terms, bytes32(0), "ipfs://terms");
        vm.stopPrank();

        // 2. Series, fulfiller, 3. issuance against a declared basis.
        uint256 seriesId = _seriesWith(t, distributor, 1_000_000);
        assertEq(ledger.issuedOf(seriesId), 1_000_000);

        // 4. Transfer on the native ERC-1155 carrier.
        vm.prank(distributor);
        ledger.safeTransferFrom(distributor, holder, seriesId, 300_000, "");

        // 5. Wrap 200,000 into ERC-20.
        AITOWrapper20 wrapper = new AITOWrapper20(address(ledger), seriesId, "Wrapped Inference Quota", "wAITO", 18);
        vm.prank(holder);
        ledger.safeTransferFrom(holder, address(wrapper), seriesId, 200_000, "");
        assertEq(wrapper.balanceOf(holder), 200_000e18);

        // 6. Transfer 50,000 in wrapped form, 7. unwrap them.
        vm.prank(holder);
        wrapper.transfer(holder2, 50_000e18);
        vm.prank(holder2);
        wrapper.unwrap(50_000, holder2);
        assertEq(ledger.availableOf(seriesId, holder2), 50_000);

        // 8. The holder authorizes an agent: a ceiling of 20,000, nothing reserved.
        Authorization memory a = _authorization(holder2, consumer, seriesId, 20_000);
        bytes32 authorizationId = ledger.hashAuthorization(a);
        assertEq(ledger.availableOf(seriesId, holder2), 50_000);

        // 9. The agent signs request r for at most 4,000; the supplier places the hold.
        bytes32 key = _hold(a, HOLDER2_PK, CONSUMER_PK, keccak256("case-a/r"), supplier, 4_000);
        assertEq(ledger.availableOf(seriesId, holder2), 46_000);
        assertEq(ledger.heldBy(seriesId, holder2), 4_000);

        // 10. Usage claim: 6,000 input, 2,100 output. 2,100 + 0.25 x 6,000 = 3,600.
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(6_000, 2_100, 0), Outcome.Completed, keccak256("case-a/evidence"));
        assertEq(ledger.requestOf(key).claimed, 3_600);
        assertEq(ledger.availableOf(seriesId, holder2), 46_000, "a claim alone deducts nothing");

        // 11. No objection inside 600 seconds: the claim is accepted by rule and settled.
        vm.warp(block.timestamp + 601);
        ledger.finalize(key);

        RequestRecord memory q = ledger.requestOf(key);
        assertEq(uint8(q.state), uint8(RequestState.Settled));
        assertEq(q.deducted, 3_600);
        assertEq(ledger.availableOf(seriesId, holder2), 46_400, "3,600 deducted, 400 released");
        assertEq(ledger.heldOf(seriesId), 0);
        assertEq(ledger.consumedOf(seriesId), 3_600);
        assertEq(ledger.usedOf(authorizationId), 3_600);

        // Final positions.
        assertEq(ledger.availableOf(seriesId, distributor), 700_000);
        assertEq(ledger.availableOf(seriesId, holder), 100_000);
        assertEq(wrapper.balanceOf(holder), 150_000e18);
        assertEq(wrapper.lockedUnits(), 150_000);
        assertEq(wrapper.totalSupply(), 150_000e18);
        // 700,000 + 100,000 + 46,400 + 150,000 locked + 3,600 consumed = 1,000,000 issued
        address[] memory accounts = new address[](5);
        accounts[0] = distributor;
        accounts[1] = holder;
        accounts[2] = holder2;
        accounts[3] = address(wrapper);
        accounts[4] = supplier;
        _assertAccounting(seriesId, accounts);

        // What an independent agent can resolve from the wrapped token alone.
        (address home, uint256 id, BindingType bindingType,, ConsumptionPath path) = wrapper.aitoBinding(0);
        assertEq(uint8(bindingType), uint8(BindingType.Wrap));
        assertEq(uint8(path), uint8(ConsumptionPath.UnwrapFirst));
        SeriesTerms memory resolved = IAITOInstrument(home).seriesOf(id);
        assertEq(resolved.responsibleParty, supplier);
        (, uint64 anchoredAt,, string memory unitUri) = records.recordOf(resolved.issuer, resolved.unit);
        assertGt(anchoredAt, 0);
        assertEq(unitUri, "ipfs://unit");
    }

    // ------------------------------------------------------------------
    // Case B. An agent issues against its own capacity; another agent consumes.
    // Every proposition is self-attested, and says so.
    // ------------------------------------------------------------------

    uint256 internal constant ALPHA_PK = 0xA1FA;
    uint256 internal constant BETA_PK = 0xBE7A;
    uint256 internal constant GAMMA_PK = 0x6A33A;

    function _alphaTerms(address alpha) internal pure returns (SeriesTerms memory t) {
        t.issuer = alpha;
        t.responsibleParty = alpha;
        t.unit = keccak256("unit:alpha-text-tokens:v1");
        t.grade = keccak256("grade:alpha-small-model-q4:v1");
        t.source = keccak256("source:alpha-own-hardware");
        t.termsHash = keccak256("terms:alpha-30d");
        t.cap = 5_000_000;
        t.validFrom = T0;
        t.validUntil = T0 + 30 days;
        t.transferable = true;
        t.roundUp = true;
        t.acceptanceRule = AcceptanceRule.Optimistic;
        t.objectionWindow = 600;
        t.maxHoldDuration = 600;
        t.components = new bytes32[](2);
        t.components[0] = bytes32("input");
        t.components[1] = bytes32("output");
        t.weights = new uint256[](2);
        t.weights[0] = 200_000;
        t.weights[1] = 1_000_000;
        t.outcomeMasks = new uint256[](6);
        t.outcomeMasks[uint8(Outcome.Completed)] = 3;
        t.outcomeMasks[uint8(Outcome.Partial)] = 3;
        t.outcomeMasks[uint8(Outcome.Refused)] = 1;
        t.outcomeMasks[uint8(Outcome.TimedOut)] = 0;
        t.outcomeMasks[uint8(Outcome.CancelledByConsumer)] = 3;
        t.outcomeMasks[uint8(Outcome.ProviderError)] = 0;
        t.extensions = new SeriesExtension[](0);
    }

    function test_caseB_agentSelfIssuedAndConsumedByAnotherAgent() public {
        address alpha = vm.addr(ALPHA_PK);
        address beta = vm.addr(BETA_PK);
        address gamma = vm.addr(GAMMA_PK);

        // 1. Supply statement and issuance basis, 2. issuance to itself.
        SeriesTerms memory t = _alphaTerms(alpha);
        uint256 seriesId = _seriesWith(t, alpha, 1_000_000);
        assertEq(ledger.issuedOf(seriesId), 1_000_000);

        // 3. Transfer to another agent.
        vm.prank(alpha);
        ledger.safeTransferFrom(alpha, beta, seriesId, 200_000, "");

        // 4. Consumption authorization: 50,000, seven days.
        Authorization memory a = _authorization(beta, gamma, seriesId, 50_000);
        bytes32 authorizationId = ledger.hashAuthorization(a);

        // 5. Hold of 3,000 for request r1.
        bytes32 r1 = keccak256("case-b/r1");
        bytes32 key = _hold(a, BETA_PK, GAMMA_PK, r1, alpha, 3_000);
        assertEq(ledger.availableOf(seriesId, beta), 197_000);

        // 6. Delivery happens off chain. 7. Usage claim: 2,000 input, 1,400 output.
        //    1,400 + 0.2 x 2,000 = 1,800. The only evidence is the fulfiller's own statement.
        vm.prank(alpha);
        ledger.claimUsage(key, _usage2(2_000, 1_400), Outcome.Completed, keccak256("alpha signed statement"));
        assertEq(ledger.requestOf(key).claimed, 1_800);

        // 8. The consuming agent accepts by signature. 9. Deduction and release.
        bytes memory acceptance = _acceptSig(GAMMA_PK, key);
        ledger.accept(key, acceptance);

        assertEq(ledger.availableOf(seriesId, beta), 198_200);
        assertEq(ledger.requestOf(key).deducted, 1_800);
        assertEq(ledger.heldOf(seriesId), 0, "1,200 released");
        assertEq(ledger.usedOf(authorizationId), 1_800, "48,200 left under the ceiling");
        assertEq(ledger.consumedOf(seriesId), 1_800);

        // 10. A retry of r1 has no second effect.
        ConsumptionRequest memory retry = _request(a, r1, alpha, 3_000);
        bytes memory holderSig = _sig(BETA_PK, retry.authorizationId);
        bytes memory consumerSig = _sig(GAMMA_PK, ledger.hashRequest(retry));
        vm.prank(alpha);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.RequestExists.selector, key));
        ledger.hold(a, holderSig, retry, consumerSig);
        assertEq(ledger.availableOf(seriesId, beta), 198_200);

        // The five things an independent agent must be able to resolve.
        (address home, uint256 id,,, ConsumptionPath path) = IAITOBinding(address(ledger)).aitoBinding(seriesId);
        SeriesTerms memory s = IAITOInstrument(home).seriesOf(id);
        assertEq(id, seriesId); // which entitlement
        assertEq(s.responsibleParty, alpha); // who owes supply
        assertTrue(ledger.isFulfiller(seriesId, alpha)); // who may fulfil
        assertEq(uint8(s.acceptanceRule), uint8(AcceptanceRule.Optimistic)); // how a claim is accepted
        assertEq(uint8(path), uint8(ConsumptionPath.Direct)); // where the balance is reduced
        assertEq(ledger.quoteCharge(seriesId, _usage2(2_000, 1_400), Outcome.Refused), 400); // failure handling
        assertEq(ledger.quoteCharge(seriesId, _usage2(2_000, 1_400), Outcome.ProviderError), 0);

        address[] memory accounts = new address[](3);
        accounts[0] = alpha;
        accounts[1] = beta;
        accounts[2] = gamma;
        _assertAccounting(seriesId, accounts);
    }

    // ------------------------------------------------------------------
    // Case C. Inference that is not counted in text tokens.
    // The kernel does not change; only the Unit does.
    // ------------------------------------------------------------------

    function test_caseC_imageInferenceUnit() public {
        SeriesTerms memory t = _textTerms(supplier);
        t.unit = keccak256("unit:image-kilopixel-steps:v1");
        t.grade = keccak256("grade:diffusion-service-version:v3");
        t.termsHash = keccak256("terms:image-quota");
        t.acceptanceRule = AcceptanceRule.CoSign;
        t.objectionWindow = 0;
        t.components = new bytes32[](2);
        t.components[0] = bytes32("kilopixel_steps");
        t.components[1] = bytes32("upscale_kilopixels");
        t.weights = new uint256[](2);
        t.weights[0] = 1_000_000;
        t.weights[1] = 500_000;
        for (uint256 i; i < 6; ++i) {
            t.outcomeMasks[i] = 0;
        }
        t.outcomeMasks[uint8(Outcome.Completed)] = 3;
        t.outcomeMasks[uint8(Outcome.Partial)] = 3;
        t.outcomeMasks[uint8(Outcome.CancelledByConsumer)] = 3;
        uint256 seriesId = _seriesWith(t, holder, 10_000_000);

        // One 1024 x 1024 image at 30 steps is 1,048.576 kilopixels x 30 = 31,457.28, reported as 31,458.
        // A 2x upscale adds 4,194.304 kilopixels, reported as 4,195, charged at 0.5.
        Authorization memory a = _authorization(holder, consumer, seriesId, 100_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, keccak256("case-c/r"), supplier, 40_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage2(31_458, 4_195), Outcome.Completed, bytes32(0));
        // 31,458 + 0.5 x 4,195 = 33,555.5, rounded up to 33,556
        assertEq(ledger.requestOf(key).claimed, 33_556);

        bytes memory acceptance = _acceptSig(CONSUMER_PK, key);
        ledger.accept(key, acceptance);
        assertEq(ledger.availableOf(seriesId, holder), 10_000_000 - 33_556);
    }

    // ------------------------------------------------------------------
    // Case D. Two suppliers issue under the same Unit and Grade without any pool.
    // A shared reference unit makes them comparable; it does not make them one obligation.
    // ------------------------------------------------------------------

    function test_caseD_sameGradeTwoSuppliersTwoSeries() public {
        address supplierY = vm.addr(0x5AFE);
        SeriesTerms memory x = _textTerms(supplier);
        SeriesTerms memory y = _textTerms(supplierY);
        y.unit = x.unit;
        y.grade = x.grade;

        uint256 seriesX = _seriesWith(x, holder, 1_000);
        uint256 seriesY = _seriesWith(y, holder, 1_000);
        assertTrue(seriesX != seriesY, "different obligor, different series");
        assertEq(ledger.seriesOf(seriesX).unit, ledger.seriesOf(seriesY).unit);
        assertEq(ledger.seriesOf(seriesX).grade, ledger.seriesOf(seriesY).grade);

        // The same usage is charged identically under the shared schedule.
        assertEq(
            ledger.quoteCharge(seriesX, _usage3(6_000, 2_100, 0), Outcome.Completed),
            ledger.quoteCharge(seriesY, _usage3(6_000, 2_100, 0), Outcome.Completed)
        );

        // Supplier Y cannot fulfil against units of supplier X.
        Authorization memory a = _authorization(holder, consumer, seriesX, 500);
        ConsumptionRequest memory r = _request(a, keccak256("case-d/r"), supplierY, 100);
        bytes memory holderSig = _sig(HOLDER_PK, r.authorizationId);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplierY);
        vm.expectRevert(AITOLedger.NotFulfiller.selector);
        ledger.hold(a, holderSig, r, consumerSig);

        // A wrapper of one series does not accept the other.
        AITOWrapper20 wrapperX = new AITOWrapper20(address(ledger), seriesX, "wX", "wX", 18);
        vm.prank(holder);
        vm.expectRevert(AITOWrapper20.UnexpectedToken.selector);
        ledger.safeTransferFrom(holder, address(wrapperX), seriesY, 1, "");
    }
}
