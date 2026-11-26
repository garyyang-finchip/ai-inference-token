// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {AITOBase, SmartAccount} from "./AITOBase.sol";
import {AITOLedger} from "../assets/erc-8506/contracts/AITOLedger.sol";
import {IAITOConsumption} from "../assets/erc-8506/contracts/interfaces/IAITOConsumption.sol";
import {
    SeriesTerms,
    Authorization,
    ConsumptionRequest,
    RequestRecord,
    RequestState,
    Outcome,
    AcceptanceRule
} from "../assets/erc-8506/contracts/interfaces/AITOTypes.sol";

contract AITOConsumptionTest is AITOBase {
    uint256 internal seriesId;
    bytes32 internal constant R1 = keccak256("request-1");
    bytes32 internal constant R2 = keccak256("request-2");

    function setUp() public override {
        super.setUp();
        seriesId = _seriesWith(_textTerms(supplier), holder, 100_000);
    }

    function _accounts() internal view returns (address[] memory a) {
        a = new address[](5);
        a[0] = supplier;
        a[1] = holder;
        a[2] = holder2;
        a[3] = consumer;
        a[4] = outsider;
    }

    // ---------------------------------------------------------------- authorization

    function test_authorization_isACeilingNotAReservation() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 id = ledger.hashAuthorization(a);
        vm.prank(holder);
        ledger.authorize(a);

        assertEq(ledger.usedOf(id), 0);
        assertEq(ledger.availableOf(seriesId, holder), 100_000, "nothing is reserved by authorizing");
        assertEq(ledger.heldOf(seriesId), 0);

        // The holder can still move every unit.
        vm.prank(holder);
        ledger.safeTransferFrom(holder, holder2, seriesId, 100_000, "");
    }

    function test_authorize_onlyTheHolder() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        vm.prank(consumer);
        vm.expectRevert(AITOLedger.NotHolder.selector);
        ledger.authorize(a);
    }

    function test_hold_withARegisteredAuthorizationNeedsNoHolderSignature() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        vm.prank(holder);
        ledger.authorize(a);

        ConsumptionRequest memory r = _request(a, R1, supplier, 3_000);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        bytes32 key = ledger.hold(a, "", r, consumerSig);
        assertEq(ledger.requestOf(key).held, 3_000);
    }

    function test_transferApprovalIsNotAConsumptionAuthorization() public {
        // The consumer is an approved ERC-1155 operator of the holder, and also the fulfiller.
        vm.prank(holder);
        ledger.setApprovalForAll(consumer, true);
        vm.prank(supplier);
        ledger.setFulfiller(seriesId, consumer, true);

        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        ConsumptionRequest memory r = _request(a, R1, consumer, 3_000);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        // The operator signs in place of the holder: not accepted.
        bytes memory forged = _sig(CONSUMER_PK, r.authorizationId);

        vm.prank(consumer);
        vm.expectRevert(AITOLedger.InvalidHolderSignature.selector);
        ledger.hold(a, forged, r, consumerSig);

        vm.prank(consumer);
        vm.expectRevert(AITOLedger.InvalidHolderSignature.selector);
        ledger.hold(a, "", r, consumerSig);
    }

    function test_revoke_blocksNewHoldsOnly() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);

        vm.prank(consumer);
        vm.expectRevert(AITOLedger.NotHolder.selector);
        ledger.revoke(a);

        vm.prank(holder);
        ledger.revoke(a);
        assertTrue(ledger.isRevoked(ledger.hashAuthorization(a)));

        ConsumptionRequest memory r = _request(a, R2, supplier, 1_000);
        bytes memory holderSig = _sig(HOLDER_PK, r.authorizationId);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.AuthorizationRevoked.selector, r.authorizationId));
        ledger.hold(a, holderSig, r, consumerSig);

        // The request that was already held still settles.
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(4_000, 1_000, 0), Outcome.Completed, bytes32(0));
        vm.warp(block.timestamp + 601);
        ledger.finalize(key);
        assertEq(uint8(ledger.requestOf(key).state), uint8(RequestState.Settled));
    }

    // ---------------------------------------------------------------- hold

    function test_hold_movesUnitsOutOfTheHoldersBalance() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 authorizationId = ledger.hashAuthorization(a);
        bytes32 expectedKey = ledger.requestKeyOf(consumer, R1);

        vm.expectEmit(true, true, true, true);
        emit IAITOConsumption.Held(
            expectedKey, authorizationId, supplier, consumer, R1, seriesId, holder, 3_000, uint64(block.timestamp + 600)
        );
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        assertEq(key, expectedKey);

        RequestRecord memory q = ledger.requestOf(key);
        assertEq(uint8(q.state), uint8(RequestState.Held));
        assertEq(q.held, 3_000);
        assertEq(q.holder, holder);
        assertEq(q.consumer, consumer);
        assertEq(q.fulfiller, supplier);

        assertEq(ledger.availableOf(seriesId, holder), 97_000);
        assertEq(ledger.heldBy(seriesId, holder), 3_000);
        assertEq(ledger.heldOf(seriesId), 3_000);
        assertEq(ledger.usedOf(authorizationId), 3_000);
        _assertAccounting(seriesId, _accounts());

        // Held units cannot be transferred out: the holder no longer has them.
        vm.prank(holder);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC1155Errors.ERC1155InsufficientBalance.selector, holder, 97_000, 97_001, seriesId
            )
        );
        ledger.safeTransferFrom(holder, holder2, seriesId, 97_001, "");
    }

    function test_hold_sameLogicalRequestCannotBeHeldTwice() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);

        ConsumptionRequest memory r = _request(a, R1, supplier, 3_000);
        bytes memory holderSig = _sig(HOLDER_PK, r.authorizationId);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.RequestExists.selector, key));
        ledger.hold(a, holderSig, r, consumerSig);
        assertEq(ledger.heldOf(seriesId), 3_000);
    }

    function test_hold_requestKeysAreScopedToTheConsumer() public {
        // Another consumer using the same requestId does not collide with this one.
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);

        Authorization memory b = _authorization(holder, outsider, seriesId, 50_000);
        bytes32 key2 = _hold(b, HOLDER_PK, OUTSIDER_PK, R1, supplier, 1_000);
        assertEq(key2, ledger.requestKeyOf(outsider, R1));
        assertEq(ledger.heldOf(seriesId), 4_000);
    }

    function test_hold_cumulativeCap() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 5_000);
        _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);

        ConsumptionRequest memory r = _request(a, R2, supplier, 2_001);
        bytes memory holderSig = _sig(HOLDER_PK, r.authorizationId);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.AuthorizationCapExceeded.selector, r.authorizationId));
        ledger.hold(a, holderSig, r, consumerSig);

        _hold(a, HOLDER_PK, CONSUMER_PK, R2, supplier, 2_000);
        assertEq(ledger.usedOf(ledger.hashAuthorization(a)), 5_000);
    }

    function test_hold_releasedAllowanceReturnsToTheCap() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 5_000);
        bytes32 id = ledger.hashAuthorization(a);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 5_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(0, 1_200, 0), Outcome.Completed, bytes32(0));
        vm.warp(block.timestamp + 601);
        ledger.finalize(key);
        // 1,200 spent, 3,800 back under the cap
        assertEq(ledger.usedOf(id), 1_200);
        _hold(a, HOLDER_PK, CONSUMER_PK, R2, supplier, 3_800);
        assertEq(ledger.usedOf(id), 5_000);
    }

    function test_hold_rejectsWrongParties() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        ConsumptionRequest memory r = _request(a, R1, supplier, 3_000);
        bytes memory holderSig = _sig(HOLDER_PK, r.authorizationId);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));

        // Somebody other than the fulfiller named in the request.
        vm.prank(outsider);
        vm.expectRevert(AITOLedger.NotFulfiller.selector);
        ledger.hold(a, holderSig, r, consumerSig);

        // A fulfiller the responsible party has not allowed.
        ConsumptionRequest memory r2 = _request(a, R1, outsider, 3_000);
        bytes memory consumerSig2 = _sig(CONSUMER_PK, ledger.hashRequest(r2));
        vm.prank(outsider);
        vm.expectRevert(AITOLedger.NotFulfiller.selector);
        ledger.hold(a, holderSig, r2, consumerSig2);

        // A request signed by somebody other than the authorized consumer.
        bytes memory wrongConsumerSig = _sig(OUTSIDER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        vm.expectRevert(AITOLedger.InvalidConsumerSignature.selector);
        ledger.hold(a, holderSig, r, wrongConsumerSig);

        // An authorization signed by somebody other than the holder.
        bytes memory wrongHolderSig = _sig(OUTSIDER_PK, r.authorizationId);
        vm.prank(supplier);
        vm.expectRevert(AITOLedger.InvalidHolderSignature.selector);
        ledger.hold(a, wrongHolderSig, r, consumerSig);

        // A request that points at another authorization.
        ConsumptionRequest memory r3 = _request(a, R1, supplier, 3_000);
        r3.authorizationId = keccak256("another authorization");
        vm.prank(supplier);
        vm.expectRevert(AITOLedger.AuthorizationMismatch.selector);
        ledger.hold(a, holderSig, r3, consumerSig);
    }

    function test_hold_authorizationWindow() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        a.validAfter = uint64(block.timestamp + 100);
        ConsumptionRequest memory r = _request(a, R1, supplier, 3_000);
        bytes memory holderSig = _sig(HOLDER_PK, r.authorizationId);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));

        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.AuthorizationNotActive.selector, r.authorizationId));
        ledger.hold(a, holderSig, r, consumerSig);

        vm.warp(uint256(a.validUntil) + 1);
        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.AuthorizationNotActive.selector, r.authorizationId));
        ledger.hold(a, holderSig, r, consumerSig);
    }

    function test_hold_scope() public {
        bytes32 session = keccak256("session-7");
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        a.scope = session;

        ConsumptionRequest memory r = _request(a, R1, supplier, 3_000);
        bytes memory holderSig = _sig(HOLDER_PK, r.authorizationId);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        vm.expectRevert(AITOLedger.ScopeMismatch.selector);
        ledger.hold(a, holderSig, r, consumerSig);

        r.scope = session;
        consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        ledger.hold(a, holderSig, r, consumerSig);
        assertEq(ledger.heldOf(seriesId), 3_000);
    }

    function test_hold_boundsOfTheReservation() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes memory holderSig = _sig(HOLDER_PK, ledger.hashAuthorization(a));

        ConsumptionRequest memory r = _request(a, R1, supplier, 0);
        _expectInvalidHold(a, holderSig, r);

        r = _request(a, R1, supplier, 3_000);
        r.holdUntil = uint64(block.timestamp);
        _expectInvalidHold(a, holderSig, r);

        r = _request(a, R1, supplier, 3_000);
        r.holdUntil = uint64(block.timestamp + 901); // maxHoldDuration is 900
        _expectInvalidHold(a, holderSig, r);
    }

    function _expectInvalidHold(Authorization memory a, bytes memory holderSig, ConsumptionRequest memory r)
        private
    {
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        vm.expectRevert(AITOLedger.InvalidHold.selector);
        ledger.hold(a, holderSig, r, consumerSig);
    }

    function test_hold_seriesMustBeConsumable() public {
        SeriesTerms memory t = _textTerms(supplier);
        t.validFrom = T0 + 30 days;
        t.validUntil = T0 + 120 days;
        uint256 later = _seriesWith(t, holder, 10_000);

        Authorization memory a = _authorization(holder, consumer, later, 5_000);
        a.validUntil = uint64(T0 + 365 days);
        ConsumptionRequest memory r = _request(a, R1, supplier, 1_000);
        bytes memory holderSig = _sig(HOLDER_PK, r.authorizationId);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.SeriesNotConsumable.selector, later));
        ledger.hold(a, holderSig, r, consumerSig);

        // A hold may not outlive the series.
        vm.warp(uint256(t.validUntil) - 100);
        r = _request(a, R1, supplier, 1_000);
        consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        vm.expectRevert(AITOLedger.InvalidHold.selector);
        ledger.hold(a, holderSig, r, consumerSig);

        vm.warp(uint256(t.validUntil) + 1);
        r = _request(a, R1, supplier, 1_000);
        consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.SeriesNotConsumable.selector, later));
        ledger.hold(a, holderSig, r, consumerSig);
    }

    function test_hold_needsUnits() public {
        Authorization memory a = _authorization(holder2, consumer, seriesId, 50_000);
        ConsumptionRequest memory r = _request(a, R1, supplier, 1);
        bytes memory holderSig = _sig(HOLDER2_PK, r.authorizationId);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        vm.expectRevert(
            abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, holder2, 0, 1, seriesId)
        );
        ledger.hold(a, holderSig, r, consumerSig);
    }

    // ---------------------------------------------------------------- claim

    function test_claim_onlyTheHoldingFulfillerWithinTheHold() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);

        vm.prank(outsider);
        vm.expectRevert(AITOLedger.NotFulfiller.selector);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));

        vm.prank(supplier);
        vm.expectRevert(AITOLedger.UsageLengthMismatch.selector);
        ledger.claimUsage(key, _usage2(2_000, 1_400), Outcome.Completed, bytes32(0));

        vm.warp(block.timestamp + 601);
        vm.prank(supplier);
        vm.expectRevert(AITOLedger.HoldExpired.selector);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
    }

    function test_claim_isBoundedByTheHold() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);

        // 2,000 x 0.25 + 4,000 = 4,500 computed, above the 3,000 held
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 4_000, 0), Outcome.Completed, bytes32(0));
        RequestRecord memory q = ledger.requestOf(key);
        assertEq(q.computed, 4_500);
        assertEq(q.claimed, 3_000);

        vm.warp(block.timestamp + 601);
        ledger.finalize(key);
        assertEq(ledger.requestOf(key).deducted, 3_000);
        assertEq(ledger.availableOf(seriesId, holder), 97_000);
    }

    function test_claim_cannotBeMadeTwice() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.startPrank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.WrongState.selector, RequestState.Claimed));
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- optimistic acceptance

    function test_optimistic_silenceSettlesAfterTheWindow() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        bytes32 evidence = keccak256("signed usage statement");
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, evidence);

        vm.expectRevert(AITOLedger.ObjectionWindowOpen.selector);
        ledger.finalize(key);
        vm.warp(block.timestamp + 600);
        vm.expectRevert(AITOLedger.ObjectionWindowOpen.selector);
        ledger.finalize(key);

        vm.warp(block.timestamp + 1);
        vm.expectEmit(true, true, false, true);
        emit IAITOConsumption.Accepted(key, address(0), AcceptanceRule.Optimistic, 1_900);
        vm.prank(outsider);
        ledger.finalize(key);

        RequestRecord memory q = ledger.requestOf(key);
        assertEq(uint8(q.state), uint8(RequestState.Settled));
        assertEq(q.deducted, 1_900); // 2,000 x 0.25 + 1,400
        assertEq(q.evidenceRoot, evidence);
        assertTrue(ledger.isReceipt(q.receiptHash));

        assertEq(ledger.availableOf(seriesId, holder), 98_100);
        assertEq(ledger.heldOf(seriesId), 0);
        assertEq(ledger.consumedOf(seriesId), 1_900);
        assertEq(ledger.usedOf(ledger.hashAuthorization(a)), 1_900);
        _assertAccounting(seriesId, _accounts());
    }

    function test_optimistic_consumerMayAcceptEarly() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));

        bytes memory wrong = _acceptSig(OUTSIDER_PK, key);
        vm.expectRevert(AITOLedger.InvalidConsumerSignature.selector);
        ledger.accept(key, wrong);

        bytes memory sig = _acceptSig(CONSUMER_PK, key);
        vm.expectEmit(true, true, false, true);
        emit IAITOConsumption.Accepted(key, consumer, AcceptanceRule.Optimistic, 1_900);
        ledger.accept(key, sig);
        assertEq(ledger.consumedOf(seriesId), 1_900);
    }

    function test_optimistic_objectionWithoutResolverDeductsNothing() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));

        vm.prank(outsider);
        vm.expectRevert(AITOLedger.NotConsumerOrHolder.selector);
        ledger.object(key, "metering");

        vm.expectEmit(true, true, true, true);
        emit IAITOConsumption.Released(key, seriesId, holder, 3_000);
        vm.prank(consumer);
        ledger.object(key, "metering");

        assertEq(uint8(ledger.requestOf(key).state), uint8(RequestState.Released));
        assertEq(ledger.availableOf(seriesId, holder), 100_000);
        assertEq(ledger.consumedOf(seriesId), 0);
        assertEq(ledger.usedOf(ledger.hashAuthorization(a)), 0);
        _assertAccounting(seriesId, _accounts());
    }

    function test_optimistic_objectionOnlyInsideTheWindow() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
        vm.warp(block.timestamp + 601);
        vm.prank(holder);
        vm.expectRevert(AITOLedger.ObjectionWindowClosed.selector);
        ledger.object(key, "late");
    }

    function test_optimistic_resolverDecidesADisputedClaim() public {
        SeriesTerms memory t = _textTerms(supplier);
        t.resolver = resolver;
        t.resolutionWindow = 3 days;
        uint256 id = _seriesWith(t, holder, 100_000);

        Authorization memory a = _authorization(holder, consumer, id, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
        vm.prank(holder);
        ledger.object(key, "output was truncated");
        assertEq(uint8(ledger.requestOf(key).state), uint8(RequestState.Disputed));
        assertEq(ledger.heldOf(id), 3_000, "units stay reserved while disputed");

        // Nobody but the fulfiller can release while the resolver still has time.
        vm.prank(outsider);
        vm.expectRevert(AITOLedger.NotReleasable.selector);
        ledger.release(key);

        vm.prank(outsider);
        vm.expectRevert(AITOLedger.NotResolver.selector);
        ledger.resolve(key, 1_000);

        vm.prank(resolver);
        vm.expectRevert(AITOLedger.AmountAboveClaim.selector);
        ledger.resolve(key, 1_901);

        vm.expectEmit(true, true, false, true);
        emit IAITOConsumption.Accepted(key, resolver, AcceptanceRule.Optimistic, 1_000);
        vm.prank(resolver);
        ledger.resolve(key, 1_000);
        assertEq(ledger.requestOf(key).deducted, 1_000);
        assertEq(ledger.availableOf(id, holder), 99_000);
    }

    function test_optimistic_disputeTimesOutInFavourOfTheHolder() public {
        SeriesTerms memory t = _textTerms(supplier);
        t.resolver = resolver;
        t.resolutionWindow = 3 days;
        uint256 id = _seriesWith(t, holder, 100_000);

        Authorization memory a = _authorization(holder, consumer, id, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
        vm.prank(consumer);
        ledger.object(key, "metering");

        vm.warp(block.timestamp + 3 days + 1);
        vm.prank(resolver);
        vm.expectRevert(AITOLedger.ResolutionWindowClosed.selector);
        ledger.resolve(key, 1_000);

        vm.prank(outsider);
        ledger.release(key);
        assertEq(ledger.availableOf(id, holder), 100_000);
    }

    function test_optimistic_consumerMayAcceptADisputedClaim() public {
        SeriesTerms memory t = _textTerms(supplier);
        t.resolver = resolver;
        t.resolutionWindow = 3 days;
        uint256 id = _seriesWith(t, holder, 100_000);
        Authorization memory a = _authorization(holder, consumer, id, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
        vm.prank(holder);
        ledger.object(key, "checking");

        bytes memory sig = _acceptSig(CONSUMER_PK, key);
        ledger.accept(key, sig);
        assertEq(ledger.requestOf(key).deducted, 1_900);
    }

    // ---------------------------------------------------------------- co-sign acceptance

    function test_coSign_noSignatureNoDeduction() public {
        SeriesTerms memory t = _textTerms(supplier);
        t.acceptanceRule = AcceptanceRule.CoSign;
        t.objectionWindow = 0;
        uint256 id = _seriesWith(t, holder, 100_000);

        Authorization memory a = _authorization(holder, consumer, id, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));

        vm.expectRevert(AITOLedger.RuleMismatch.selector);
        ledger.finalize(key);
        vm.prank(consumer);
        vm.expectRevert(AITOLedger.RuleMismatch.selector);
        ledger.object(key, "n/a");

        vm.prank(outsider);
        vm.expectRevert(AITOLedger.NotReleasable.selector);
        ledger.release(key);

        vm.warp(block.timestamp + 601);
        vm.prank(outsider);
        ledger.release(key);
        assertEq(ledger.availableOf(id, holder), 100_000);
        assertEq(ledger.consumedOf(id), 0);
    }

    function test_coSign_signatureSettles() public {
        SeriesTerms memory t = _textTerms(supplier);
        t.acceptanceRule = AcceptanceRule.CoSign;
        t.objectionWindow = 0;
        uint256 id = _seriesWith(t, holder, 100_000);

        Authorization memory a = _authorization(holder, consumer, id, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));

        bytes memory sig = _acceptSig(CONSUMER_PK, key);
        vm.prank(outsider); // anyone may relay the consumer's signature
        ledger.accept(key, sig);
        assertEq(ledger.requestOf(key).deducted, 1_900);
        assertEq(ledger.availableOf(id, holder), 98_100);
    }

    // ---------------------------------------------------------------- provider-metered acceptance

    function test_providerMetered_claimSettlesAtOnce() public {
        SeriesTerms memory t = _textTerms(supplier);
        t.acceptanceRule = AcceptanceRule.ProviderMetered;
        t.objectionWindow = 0;
        uint256 id = _seriesWith(t, holder, 100_000);

        Authorization memory a = _authorization(holder, consumer, id, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);

        vm.expectEmit(true, true, false, true);
        emit IAITOConsumption.Accepted(key, supplier, AcceptanceRule.ProviderMetered, 1_900);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));

        RequestRecord memory q = ledger.requestOf(key);
        assertEq(uint8(q.state), uint8(RequestState.Settled));
        assertEq(q.deducted, 1_900);
        assertEq(ledger.availableOf(id, holder), 98_100);
    }

    // ---------------------------------------------------------------- release

    function test_release_expiredHoldByAnyone() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);

        vm.prank(outsider);
        vm.expectRevert(AITOLedger.NotReleasable.selector);
        ledger.release(key);

        vm.warp(block.timestamp + 601);
        vm.prank(outsider);
        ledger.release(key);
        assertEq(uint8(ledger.requestOf(key).state), uint8(RequestState.Released));
        assertEq(ledger.availableOf(seriesId, holder), 100_000);
        assertEq(ledger.usedOf(ledger.hashAuthorization(a)), 0);
    }

    function test_release_fulfillerMayGiveBackAtAnyTime() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.prank(supplier);
        ledger.release(key);
        assertEq(ledger.availableOf(seriesId, holder), 100_000);

        // An unobjected optimistic claim can also be waived by the fulfiller.
        bytes32 key2 = _hold(a, HOLDER_PK, CONSUMER_PK, R2, supplier, 3_000);
        vm.startPrank(supplier);
        ledger.claimUsage(key2, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
        ledger.release(key2);
        vm.stopPrank();
        assertEq(ledger.availableOf(seriesId, holder), 100_000);
    }

    function test_release_unobjectedOptimisticClaimIsNotReleasableByOthers() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
        vm.warp(block.timestamp + 10_000);
        vm.prank(holder);
        vm.expectRevert(AITOLedger.NotReleasable.selector);
        ledger.release(key);
    }

    // ---------------------------------------------------------------- release horizon (section 5.5)

    function _holdAt(Authorization memory a, bytes32 requestId, uint256 maxAmount, uint64 holdUntil)
        internal
        returns (bytes32 requestKey)
    {
        ConsumptionRequest memory r = _request(a, requestId, supplier, maxAmount);
        r.holdUntil = holdUntil;
        bytes memory holderSig = _sig(HOLDER_PK, r.authorizationId);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        requestKey = ledger.hold(a, holderSig, r, consumerSig);
    }

    /// A claim made at `holdUntil`, objected to at the end of the objection window and left undecided keeps
    /// the units held until `holdUntil + objectionWindow + resolutionWindow`, which is at most
    /// `maxHoldDuration + objectionWindow + resolutionWindow` after the hold. After that anyone may release.
    function test_releaseHorizon_optimisticWithResolverIsHoldPlusBothWindows() public {
        SeriesTerms memory t = _textTerms(supplier);
        t.resolver = resolver;
        t.resolutionWindow = 1 days;
        uint256 id = _seriesWith(t, holder, 100_000);
        Authorization memory a = _authorization(holder, consumer, id, 50_000);

        // vm.getBlockTimestamp: block.timestamp read into a local may be re-read after vm.warp under via-IR.
        uint256 heldAt = vm.getBlockTimestamp();
        uint64 holdUntil = uint64(heldAt + t.maxHoldDuration);
        bytes32 key = _holdAt(a, R1, 3_000, holdUntil);

        vm.warp(holdUntil);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
        assertEq(ledger.requestOf(key).claimedAt, holdUntil, "a claim at holdUntil is accepted");

        vm.warp(uint256(holdUntil) + t.objectionWindow);
        vm.prank(holder);
        ledger.object(key, "metering");
        assertEq(ledger.requestOf(key).disputedAt, uint256(holdUntil) + t.objectionWindow);

        uint256 horizon = uint256(holdUntil) + t.objectionWindow + t.resolutionWindow;
        assertEq(horizon, heldAt + t.maxHoldDuration + t.objectionWindow + t.resolutionWindow);

        vm.warp(horizon);
        vm.prank(outsider);
        vm.expectRevert(AITOLedger.NotReleasable.selector);
        ledger.release(key);
        assertEq(ledger.heldOf(id), 3_000, "held until the release horizon");

        vm.warp(horizon + 1);
        vm.prank(outsider);
        ledger.release(key);
        assertEq(uint8(ledger.requestOf(key).state), uint8(RequestState.Released));
        assertEq(ledger.availableOf(id, holder), 100_000);
        _assertAccounting(id, _accounts());
    }

    /// Without a resolver the horizon is `holdUntil + objectionWindow`, and the holder can end the request
    /// itself by finalizing the claim; it does not depend on the fulfiller.
    function test_releaseHorizon_holderFinalizesAfterTheObjectionWindow() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        uint64 holdUntil = uint64(vm.getBlockTimestamp() + 900);
        bytes32 key = _holdAt(a, R1, 3_000, holdUntil);

        vm.warp(holdUntil);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));

        vm.warp(uint256(holdUntil) + 600);
        vm.prank(holder);
        vm.expectRevert(AITOLedger.ObjectionWindowOpen.selector);
        ledger.finalize(key);

        vm.warp(uint256(holdUntil) + 601);
        vm.prank(holder);
        ledger.finalize(key);
        assertEq(uint8(ledger.requestOf(key).state), uint8(RequestState.Settled));
        assertEq(ledger.requestOf(key).deducted, 1_900);
        assertEq(ledger.availableOf(seriesId, holder), 98_100);
        _assertAccounting(seriesId, _accounts());
    }

    // ---------------------------------------------------------------- one effect per logical request

    function test_settledRequestHasNoSecondEffect() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
        bytes memory sig = _acceptSig(CONSUMER_PK, key);
        ledger.accept(key, sig);
        uint256 consumed = ledger.consumedOf(seriesId);

        bytes memory settled = abi.encodeWithSelector(AITOLedger.WrongState.selector, RequestState.Settled);

        // Retry of the acceptance.
        vm.expectRevert(settled);
        ledger.accept(key, sig);
        // Retry of the settlement by timeout.
        vm.warp(block.timestamp + 601);
        vm.expectRevert(settled);
        ledger.finalize(key);
        // A second claim.
        vm.prank(supplier);
        vm.expectRevert(settled);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
        // A release after settlement.
        vm.prank(supplier);
        vm.expectRevert(settled);
        ledger.release(key);
        // The same logical request submitted again as a new hold.
        ConsumptionRequest memory r = _request(a, R1, supplier, 3_000);
        bytes memory holderSig = _sig(HOLDER_PK, r.authorizationId);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.RequestExists.selector, key));
        ledger.hold(a, holderSig, r, consumerSig);

        assertEq(ledger.consumedOf(seriesId), consumed);
        assertEq(ledger.availableOf(seriesId, holder), 98_100);
    }

    function test_releasedRequestCannotBeSettled() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.prank(supplier);
        ledger.release(key);

        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.WrongState.selector, RequestState.Released));
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
    }

    function test_receiptIsNotAnIssuanceBasis() public {
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
        bytes memory sig = _acceptSig(CONSUMER_PK, key);
        ledger.accept(key, sig);

        bytes32 receiptHash = ledger.requestOf(key).receiptHash;
        vm.prank(supplier);
        vm.expectRevert(abi.encodeWithSelector(AITOLedger.ReceiptIsNotABasis.selector, receiptHash));
        ledger.issue(seriesId, supplier, 1_900, receiptHash);
    }

    // ---------------------------------------------------------------- expiry

    function test_expiry_claimMadeInTimeStillSettlesAndTheRestLapses() public {
        SeriesTerms memory t = _textTerms(supplier);
        vm.warp(uint256(t.validUntil) - 700);
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));

        vm.warp(uint256(t.validUntil) + 1);
        ledger.lapse(seriesId, holder);
        assertEq(ledger.lapsedOf(seriesId), 97_000, "reserved units are not lapsed from escrow");

        ledger.finalize(key);
        assertEq(ledger.consumedOf(seriesId), 1_900);
        assertEq(ledger.availableOf(seriesId, holder), 1_100, "released after expiry");
        ledger.lapse(seriesId, holder);
        assertEq(ledger.lapsedOf(seriesId), 98_100);
        _assertAccounting(seriesId, _accounts());
    }

    // ---------------------------------------------------------------- contract accounts (ERC-1271)

    function test_contractAccountsAsHolderAndConsumer() public {
        SmartAccount holderAccount = new SmartAccount(holder);
        SmartAccount consumerAccount = new SmartAccount(consumer);
        vm.prank(supplier);
        ledger.issue(seriesId, address(holderAccount), 10_000, BASIS);

        Authorization memory a = _authorization(address(holderAccount), address(consumerAccount), seriesId, 5_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, 3_000);
        assertEq(key, ledger.requestKeyOf(address(consumerAccount), R1));

        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(2_000, 1_400, 0), Outcome.Completed, bytes32(0));
        bytes memory sig = _acceptSig(CONSUMER_PK, key);
        ledger.accept(key, sig);
        assertEq(ledger.availableOf(seriesId, address(holderAccount)), 8_100);

        // A signature by a key the contract account does not recognise is rejected.
        ConsumptionRequest memory r = _request(a, R2, supplier, 1_000);
        bytes memory badHolderSig = _sig(OUTSIDER_PK, r.authorizationId);
        bytes memory consumerSig = _sig(CONSUMER_PK, ledger.hashRequest(r));
        vm.prank(supplier);
        vm.expectRevert(AITOLedger.InvalidHolderSignature.selector);
        ledger.hold(a, badHolderSig, r, consumerSig);
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_settlementNeverDeductsMoreThanTheHold(uint64 maxAmount, uint64 input, uint64 output)
        public
    {
        maxAmount = uint64(bound(maxAmount, 1, 50_000));
        Authorization memory a = _authorization(holder, consumer, seriesId, 50_000);
        bytes32 key = _hold(a, HOLDER_PK, CONSUMER_PK, R1, supplier, maxAmount);
        vm.prank(supplier);
        ledger.claimUsage(key, _usage3(input, output, 0), Outcome.Completed, bytes32(0));
        vm.warp(block.timestamp + 601);
        ledger.finalize(key);

        RequestRecord memory q = ledger.requestOf(key);
        assertLe(q.deducted, maxAmount);
        assertEq(q.deducted, q.computed > maxAmount ? maxAmount : q.computed);
        assertEq(ledger.availableOf(seriesId, holder), 100_000 - q.deducted);
        assertEq(ledger.usedOf(ledger.hashAuthorization(a)), q.deducted);
        _assertAccounting(seriesId, _accounts());
    }
}
