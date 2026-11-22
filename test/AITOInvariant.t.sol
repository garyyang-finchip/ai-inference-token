// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {AITOBase} from "./AITOBase.sol";
import {AITOLedger} from "../assets/erc-8506/contracts/AITOLedger.sol";
import {AITOWrapper20} from "../assets/erc-8506/contracts/AITOWrapper20.sol";
import {
    SeriesTerms,
    Authorization,
    ConsumptionRequest,
    RequestRecord,
    RequestState,
    Outcome
} from "../assets/erc-8506/contracts/interfaces/AITOTypes.sol";

/// @dev Drives the ledger and the wrapper through random sequences of legal and illegal calls.
contract AITOHandler is Test {
    AITOLedger public immutable ledger;
    AITOWrapper20 public immutable wrapper;
    uint256 public immutable seriesId;
    address public immutable supplier;
    uint256 internal immutable consumerPk;
    address internal immutable consumer;

    address[] public actors;
    Authorization[] internal auths;
    bytes32[] public keys;
    uint256 internal nextRequest;

    bytes32 internal constant BASIS = keccak256("basis");

    constructor(AITOLedger ledger_, AITOWrapper20 wrapper_, uint256 seriesId_, address supplier_, uint256 consumerPk_) {
        ledger = ledger_;
        wrapper = wrapper_;
        seriesId = seriesId_;
        supplier = supplier_;
        consumerPk = consumerPk_;
        consumer = vm.addr(consumerPk_);

        for (uint256 i; i < 3; ++i) {
            address actor = vm.addr(0x1000 + i);
            actors.push(actor);
            Authorization memory a = Authorization({
                holder: actor,
                consumer: consumer,
                seriesId: seriesId_,
                cap: 400_000,
                validAfter: uint64(block.timestamp),
                validUntil: uint64(block.timestamp + 80 days),
                scope: bytes32(0),
                nonce: i
            });
            auths.push(a);
            vm.prank(actor);
            ledger_.authorize(a);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function keyCount() external view returns (uint256) {
        return keys.length;
    }

    function authorizationOf(uint256 i) external view returns (Authorization memory) {
        return auths[i];
    }

    function issue(uint256 actorSeed, uint256 amount) external {
        amount = bound(amount, 1, 50_000);
        vm.prank(supplier);
        try ledger.issue(seriesId, actors[actorSeed % actors.length], amount, BASIS) {} catch {}
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, ledger.balanceOf(from, seriesId));
        vm.prank(from);
        ledger.safeTransferFrom(from, to, seriesId, amount, "");
    }

    function wrap(uint256 actorSeed, uint256 units) external {
        address actor = actors[actorSeed % actors.length];
        units = bound(units, 0, ledger.balanceOf(actor, seriesId));
        vm.prank(actor);
        ledger.safeTransferFrom(actor, address(wrapper), seriesId, units, "");
    }

    function unwrap(uint256 actorSeed, uint256 units) external {
        address actor = actors[actorSeed % actors.length];
        units = bound(units, 0, wrapper.balanceOf(actor) / wrapper.unitScale());
        vm.prank(actor);
        wrapper.unwrap(units, actor);
    }

    function retire(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 0, ledger.balanceOf(actor, seriesId) / 4);
        vm.prank(actor);
        ledger.retire(seriesId, amount);
    }

    function hold(uint256 actorSeed, uint256 maxAmount) external {
        uint256 i = actorSeed % actors.length;
        maxAmount = bound(maxAmount, 1, 20_000);
        Authorization memory a = auths[i];
        ConsumptionRequest memory r = ConsumptionRequest({
            authorizationId: ledger.hashAuthorization(a),
            requestId: bytes32(nextRequest++),
            fulfiller: supplier,
            maxAmount: maxAmount,
            holdUntil: uint64(block.timestamp + 600),
            scope: bytes32(0)
        });
        (uint8 v, bytes32 rr, bytes32 s) = vm.sign(consumerPk, ledger.hashRequest(r));
        vm.prank(supplier);
        try ledger.hold(a, "", r, abi.encodePacked(rr, s, v)) returns (bytes32 key) {
            keys.push(key);
        } catch {}
    }

    function claim(uint256 keySeed, uint64 input, uint64 output, uint8 outcome) external {
        if (keys.length == 0) return;
        bytes32 key = keys[keySeed % keys.length];
        uint256[] memory usage = new uint256[](3);
        usage[0] = bound(input, 0, 40_000);
        usage[1] = bound(output, 0, 40_000);
        vm.prank(supplier);
        try ledger.claimUsage(key, usage, Outcome(outcome % 6), bytes32(0)) {} catch {}
    }

    function finalize(uint256 keySeed) external {
        if (keys.length == 0) return;
        try ledger.finalize(keys[keySeed % keys.length]) {} catch {}
    }

    function accept(uint256 keySeed) external {
        if (keys.length == 0) return;
        bytes32 key = keys[keySeed % keys.length];
        RequestRecord memory q = ledger.requestOf(key);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(consumerPk, ledger.hashAcceptance(key, q.claimHash, q.claimed));
        try ledger.accept(key, abi.encodePacked(r, s, v)) {} catch {}
    }

    function object(uint256 keySeed) external {
        if (keys.length == 0) return;
        vm.prank(consumer);
        try ledger.object(keys[keySeed % keys.length], "fuzz") {} catch {}
    }

    function release(uint256 keySeed, bool byFulfiller) external {
        if (keys.length == 0) return;
        if (byFulfiller) vm.prank(supplier);
        try ledger.release(keys[keySeed % keys.length]) {} catch {}
    }

    /// @dev A whole request in one call, so that settlements are frequent in every run.
    function consume(uint256 actorSeed, uint256 maxAmount, uint64 input, uint64 output, uint8 ending) external {
        uint256 i = actorSeed % actors.length;
        maxAmount = bound(maxAmount, 1, 20_000);
        vm.prank(supplier);
        try ledger.issue(seriesId, actors[i], maxAmount, BASIS) {} catch {}

        uint256 before = keys.length;
        this.hold(i, maxAmount);
        if (keys.length == before) return;
        bytes32 key = keys[before];

        uint256[] memory usage = new uint256[](3);
        usage[0] = bound(input, 0, 40_000);
        usage[1] = bound(output, 0, 40_000);
        vm.prank(supplier);
        ledger.claimUsage(key, usage, Outcome.Completed, bytes32(0));

        ending = ending % 4;
        if (ending == 0) {
            this.accept(before);
        } else if (ending == 1) {
            vm.warp(block.timestamp + 601);
            ledger.finalize(key);
        } else if (ending == 2) {
            vm.prank(consumer);
            ledger.object(key, "fuzz");
        }
        // ending == 3 leaves the claim open for later calls
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 1, 1 hours));
    }
}

contract AITOInvariantTest is AITOBase {
    AITOHandler internal handler;
    AITOWrapper20 internal wrapper;
    uint256 internal seriesId;

    function setUp() public override {
        super.setUp();
        seriesId = _seriesWith(_textTerms(supplier), supplier, 1);
        wrapper = new AITOWrapper20(address(ledger), seriesId, "Wrapped", "wAITO", 18);
        handler = new AITOHandler(ledger, wrapper, seriesId, supplier, CONSUMER_PK);
        targetContract(address(handler));
    }

    /// issued == consumed + retired + lapsed + held + every available balance (wrapper included).
    function invariant_accountingIdentity() public view {
        uint256 available = ledger.availableOf(seriesId, supplier) + ledger.availableOf(seriesId, address(wrapper));
        uint256 heldByActors;
        for (uint256 i; i < handler.actorCount(); ++i) {
            address actor = handler.actors(i);
            available += ledger.availableOf(seriesId, actor);
            heldByActors += ledger.heldBy(seriesId, actor);
        }
        assertEq(
            ledger.issuedOf(seriesId),
            ledger.consumedOf(seriesId) + ledger.retiredOf(seriesId) + ledger.lapsedOf(seriesId)
                + ledger.heldOf(seriesId) + available
        );
        assertEq(heldByActors, ledger.heldOf(seriesId));
    }

    /// A unit is either available to its holder or held in escrow, never both.
    function invariant_escrowEqualsHeld() public view {
        assertEq(ledger.balanceOf(address(ledger), seriesId), ledger.heldOf(seriesId));
    }

    /// Every wrapped token is backed by a locked native unit.
    function invariant_wrapperIsBacked() public view {
        assertEq(wrapper.totalSupply(), wrapper.lockedUnits() * wrapper.unitScale());
    }

    /// No authorization is ever used beyond its ceiling, and what is recorded as used equals
    /// what its requests hold or have deducted.
    function invariant_authorizationCeilings() public view {
        uint256 n = handler.actorCount();
        uint256[] memory expected = new uint256[](n);
        for (uint256 k; k < handler.keyCount(); ++k) {
            RequestRecord memory q = ledger.requestOf(handler.keys(k));
            for (uint256 i; i < n; ++i) {
                if (q.holder != handler.actors(i)) continue;
                if (q.state == RequestState.Settled) expected[i] += q.deducted;
                else if (q.state != RequestState.Released) expected[i] += q.held;
            }
        }
        for (uint256 i; i < n; ++i) {
            bytes32 id = ledger.hashAuthorization(handler.authorizationOf(i));
            assertEq(ledger.usedOf(id), expected[i]);
            assertLe(ledger.usedOf(id), 400_000);
        }
    }

    /// Shown with -vv: how many requests each run drove to a final state.
    function afterInvariant() public view {
        uint256 settled;
        uint256 released;
        uint256 open;
        for (uint256 k; k < handler.keyCount(); ++k) {
            RequestState s = ledger.requestOf(handler.keys(k)).state;
            if (s == RequestState.Settled) ++settled;
            else if (s == RequestState.Released) ++released;
            else ++open;
        }
        console2.log("requests settled / released / open", settled, released, open);
        console2.log("consumed / wrapped units", ledger.consumedOf(seriesId), wrapper.lockedUnits());
    }

    /// A settled request never deducted more than it held.
    function invariant_deductionWithinHold() public view {
        for (uint256 k; k < handler.keyCount(); ++k) {
            RequestRecord memory q = ledger.requestOf(handler.keys(k));
            assertLe(q.deducted, q.held);
            assertLe(q.claimed, q.held);
        }
    }
}
