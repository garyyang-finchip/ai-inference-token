// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {AITOLedger} from "../assets/erc-8506/contracts/AITOLedger.sol";
import {AITORecords} from "../assets/erc-8506/contracts/AITORecords.sol";
import {AITOWrapper20} from "../assets/erc-8506/contracts/AITOWrapper20.sol";
import {
    SeriesTerms,
    SeriesExtension,
    Authorization,
    ConsumptionRequest,
    RequestRecord,
    RequestState,
    Outcome,
    AcceptanceRule
} from "../assets/erc-8506/contracts/interfaces/AITOTypes.sol";

/// @dev A contract account that validates signatures of one owner key (ERC-1271).
contract SmartAccount is IERC1271, ERC1155Holder {
    address public immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        (address signer,,) = ECDSA.tryRecover(hash, signature);
        return signer == owner ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }

    function call(address target, bytes calldata data) external returns (bytes memory) {
        require(msg.sender == owner, "not owner");
        (bool ok, bytes memory ret) = target.call(data);
        require(ok, "call failed");
        return ret;
    }
}

/// @dev A ledger that declares it implements one extension. Used to show that a party which
/// does not understand a critical extension must refuse to operate on the series.
contract ExtensionLedger is AITOLedger {
    bytes32 public constant EXTENSION = keccak256("example.extension.v1");

    function supportsExtension(bytes32 extension) public pure override returns (bool) {
        return extension == EXTENSION;
    }
}

abstract contract AITOBase is Test {
    uint64 internal constant T0 = 1_800_000_000;

    uint256 internal constant SUPPLIER_PK = 0xA11CE;
    uint256 internal constant DISTRIBUTOR_PK = 0xD157;
    uint256 internal constant HOLDER_PK = 0xB0B;
    uint256 internal constant HOLDER2_PK = 0xB0B2;
    uint256 internal constant CONSUMER_PK = 0xC0FFEE;
    uint256 internal constant RESOLVER_PK = 0x5E501;
    uint256 internal constant OUTSIDER_PK = 0xBAD;

    AITOLedger internal ledger;
    AITORecords internal records;

    address internal supplier;
    address internal distributor;
    address internal holder;
    address internal holder2;
    address internal consumer;
    address internal resolver;
    address internal outsider;

    bytes32 internal constant BASIS = keccak256("basis:own-capacity:2027Q1");

    function setUp() public virtual {
        vm.warp(T0);
        ledger = new AITOLedger();
        records = new AITORecords();
        supplier = vm.addr(SUPPLIER_PK);
        distributor = vm.addr(DISTRIBUTOR_PK);
        holder = vm.addr(HOLDER_PK);
        holder2 = vm.addr(HOLDER2_PK);
        consumer = vm.addr(CONSUMER_PK);
        resolver = vm.addr(RESOLVER_PK);
        outsider = vm.addr(OUTSIDER_PK);
    }

    // ---------------------------------------------------------------- terms

    /// @dev Text inference quota: components input, output, cache_read with weights 0.25, 1, 0.025.
    function _textTerms(address issuer) internal pure returns (SeriesTerms memory t) {
        t.issuer = issuer;
        t.responsibleParty = issuer;
        t.unit = keccak256("unit:text-tokens:v1");
        t.grade = keccak256("grade:fixed-model:v1");
        t.source = keccak256(abi.encode("source:own-capacity", issuer));
        t.termsHash = keccak256(abi.encode("terms:stock-quota:90d", issuer));
        t.cap = 10_000_000;
        t.validFrom = T0;
        t.validUntil = T0 + 90 days;
        t.transferable = true;
        t.scheduleMutable = false;
        t.roundUp = true;
        t.acceptanceRule = AcceptanceRule.Optimistic;
        t.objectionWindow = 600;
        t.resolutionWindow = 0;
        t.maxHoldDuration = 900;
        t.resolver = address(0);
        t.components = new bytes32[](3);
        t.components[0] = bytes32("input");
        t.components[1] = bytes32("output");
        t.components[2] = bytes32("cache_read");
        t.weights = new uint256[](3);
        t.weights[0] = 250_000;
        t.weights[1] = 1_000_000;
        t.weights[2] = 25_000;
        t.outcomeMasks = new uint256[](6);
        t.outcomeMasks[uint8(Outcome.Completed)] = 7;
        t.outcomeMasks[uint8(Outcome.Partial)] = 7;
        t.outcomeMasks[uint8(Outcome.Refused)] = 1;
        t.outcomeMasks[uint8(Outcome.TimedOut)] = 0;
        t.outcomeMasks[uint8(Outcome.CancelledByConsumer)] = 7;
        t.outcomeMasks[uint8(Outcome.ProviderError)] = 0;
        t.extensions = new SeriesExtension[](0);
    }

    function _create(SeriesTerms memory t) internal returns (uint256 seriesId) {
        vm.prank(t.issuer);
        seriesId = ledger.createSeries(t, "ipfs://terms");
    }

    /// @dev Creates the text series of `supplier`, registers the supplier as fulfiller and issues `amount` to `to`.
    function _seriesWith(SeriesTerms memory t, address to, uint256 amount) internal returns (uint256 seriesId) {
        seriesId = _create(t);
        vm.prank(t.responsibleParty);
        ledger.setFulfiller(seriesId, t.responsibleParty, true);
        vm.prank(t.issuer);
        ledger.issue(seriesId, to, amount, BASIS);
    }

    // ---------------------------------------------------------------- signatures

    function _sig(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _authorization(address holder_, address consumer_, uint256 seriesId, uint256 cap)
        internal
        view
        returns (Authorization memory a)
    {
        a = Authorization({
            holder: holder_,
            consumer: consumer_,
            seriesId: seriesId,
            cap: cap,
            validAfter: uint64(block.timestamp),
            validUntil: uint64(block.timestamp + 7 days),
            scope: bytes32(0),
            nonce: 1
        });
    }

    function _request(Authorization memory a, bytes32 requestId, address fulfiller, uint256 maxAmount)
        internal
        view
        returns (ConsumptionRequest memory r)
    {
        r = ConsumptionRequest({
            authorizationId: ledger.hashAuthorization(a),
            requestId: requestId,
            fulfiller: fulfiller,
            maxAmount: maxAmount,
            holdUntil: uint64(block.timestamp + 600),
            scope: bytes32(0)
        });
    }

    function _hold(
        Authorization memory a,
        uint256 holderPk,
        uint256 consumerPk,
        bytes32 requestId,
        address fulfiller,
        uint256 maxAmount
    ) internal returns (bytes32 requestKey) {
        ConsumptionRequest memory r = _request(a, requestId, fulfiller, maxAmount);
        bytes memory holderSig = _sig(holderPk, r.authorizationId);
        bytes memory consumerSig = _sig(consumerPk, ledger.hashRequest(r));
        vm.prank(fulfiller);
        requestKey = ledger.hold(a, holderSig, r, consumerSig);
    }

    function _usage3(uint256 input, uint256 output, uint256 cacheRead) internal pure returns (uint256[] memory u) {
        u = new uint256[](3);
        u[0] = input;
        u[1] = output;
        u[2] = cacheRead;
    }

    function _usage2(uint256 a, uint256 b) internal pure returns (uint256[] memory u) {
        u = new uint256[](2);
        u[0] = a;
        u[1] = b;
    }

    function _usage1(uint256 a) internal pure returns (uint256[] memory u) {
        u = new uint256[](1);
        u[0] = a;
    }

    function _acceptSig(uint256 consumerPk, bytes32 requestKey) internal view returns (bytes memory) {
        RequestRecord memory q = ledger.requestOf(requestKey);
        return _sig(consumerPk, ledger.hashAcceptance(requestKey, q.claimHash, q.claimed));
    }

    // ---------------------------------------------------------------- accounting

    /// @dev issued == consumed + retired + lapsed + held + sum of available balances.
    function _assertAccounting(uint256 seriesId, address[] memory accounts) internal view {
        uint256 available;
        for (uint256 i; i < accounts.length; ++i) {
            available += ledger.availableOf(seriesId, accounts[i]);
        }
        assertEq(
            ledger.issuedOf(seriesId),
            ledger.consumedOf(seriesId) + ledger.retiredOf(seriesId) + ledger.lapsedOf(seriesId)
                + ledger.heldOf(seriesId) + available,
            "accounting identity"
        );
        assertEq(ledger.balanceOf(address(ledger), seriesId), ledger.heldOf(seriesId), "escrow equals held");
    }
}
