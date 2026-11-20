// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {AITOLedger} from "../assets/erc-9999/contracts/AITOLedger.sol";
import {IAITORecords} from "../assets/erc-9999/contracts/interfaces/IAITORecords.sol";
import {IAITOInstrument} from "../assets/erc-9999/contracts/interfaces/IAITOInstrument.sol";
import {IAITOConsumption} from "../assets/erc-9999/contracts/interfaces/IAITOConsumption.sol";
import {IAITOBinding} from "../assets/erc-9999/contracts/interfaces/IAITOBinding.sol";
import {IAITOWrapper20} from "../assets/erc-9999/contracts/interfaces/IAITOWrapper20.sol";
import {IAITOPeriodic} from "../assets/erc-9999/contracts/interfaces/IAITOPeriodic.sol";
import {
    SeriesTerms,
    SeriesExtension,
    Authorization,
    ConsumptionRequest,
    RequestRecord,
    RequestState,
    Outcome,
    AcceptanceRule
} from "../assets/erc-9999/contracts/interfaces/AITOTypes.sol";

/// @notice Compares the contracts with vectors produced by tools/aito.mjs, an independent
/// implementation of the identifier, encoding and typed-data rules. Signatures in the vectors
/// were made outside Solidity and are replayed here against the ledger.
contract AITOVectorsTest is Test {
    string internal constant DIR = "assets/erc-9999/vectors/";

    AITOLedger internal ledger;
    string internal seriesJson;
    string internal eip;

    function setUp() public {
        seriesJson = vm.readFile(string.concat(DIR, "series.json"));
        eip = vm.readFile(string.concat(DIR, "typed-data.json"));

        vm.chainId(vm.parseJsonUint(eip, ".domain.chainId"));
        vm.warp(vm.parseJsonUint(eip, ".time"));
        address at = vm.parseJsonAddress(eip, ".domain.verifyingContract");
        deployCodeTo("AITOLedger.sol:AITOLedger", at);
        ledger = AITOLedger(at);
    }

    function _terms(string memory which) internal view returns (SeriesTerms memory t) {
        string memory p = string.concat(".", which, ".terms.");
        t.issuer = vm.parseJsonAddress(seriesJson, string.concat(p, "issuer"));
        t.responsibleParty = vm.parseJsonAddress(seriesJson, string.concat(p, "responsibleParty"));
        t.unit = vm.parseJsonBytes32(seriesJson, string.concat(p, "unit"));
        t.grade = vm.parseJsonBytes32(seriesJson, string.concat(p, "grade"));
        t.source = vm.parseJsonBytes32(seriesJson, string.concat(p, "source"));
        t.termsHash = vm.parseJsonBytes32(seriesJson, string.concat(p, "termsHash"));
        t.cap = vm.parseJsonUint(seriesJson, string.concat(p, "cap"));
        t.validFrom = uint64(vm.parseJsonUint(seriesJson, string.concat(p, "validFrom")));
        t.validUntil = uint64(vm.parseJsonUint(seriesJson, string.concat(p, "validUntil")));
        t.transferable = vm.parseJsonBool(seriesJson, string.concat(p, "transferable"));
        t.scheduleMutable = vm.parseJsonBool(seriesJson, string.concat(p, "scheduleMutable"));
        t.roundUp = vm.parseJsonBool(seriesJson, string.concat(p, "roundUp"));
        t.acceptanceRule = AcceptanceRule(vm.parseJsonUint(seriesJson, string.concat(p, "acceptanceRule")));
        t.objectionWindow = uint32(vm.parseJsonUint(seriesJson, string.concat(p, "objectionWindow")));
        t.resolutionWindow = uint32(vm.parseJsonUint(seriesJson, string.concat(p, "resolutionWindow")));
        t.maxHoldDuration = uint32(vm.parseJsonUint(seriesJson, string.concat(p, "maxHoldDuration")));
        t.resolver = vm.parseJsonAddress(seriesJson, string.concat(p, "resolver"));
        t.components = vm.parseJsonBytes32Array(seriesJson, string.concat(p, "components"));
        t.weights = vm.parseJsonUintArray(seriesJson, string.concat(p, "weights"));
        t.outcomeMasks = vm.parseJsonUintArray(seriesJson, string.concat(p, "outcomeMasks"));
        t.extensions = new SeriesExtension[](0);
    }

    function test_seriesIdentifiers() public view {
        assertEq(ledger.seriesIdOf(_terms("caseA")), vm.parseJsonUint(seriesJson, ".caseA.seriesId"));
        assertEq(ledger.seriesIdOf(_terms("caseB")), vm.parseJsonUint(seriesJson, ".caseB.seriesId"));
        assertEq(
            vm.toString(ledger.seriesIdOf(_terms("caseB"))), vm.parseJsonString(seriesJson, ".caseB.seriesIdDecimal")
        );
        // Component identifiers are short ASCII strings, left-aligned in 32 bytes.
        assertEq(_terms("caseB").components[0], bytes32("input"));
        assertEq(_terms("caseB").components[1], bytes32("output"));
    }

    function test_typedDataDomainAndTypeHashes() public view {
        assertEq(ledger.AUTHORIZATION_TYPEHASH(), vm.parseJsonBytes32(eip, ".typeHashes.Authorization"));
        assertEq(ledger.REQUEST_TYPEHASH(), vm.parseJsonBytes32(eip, ".typeHashes.ConsumptionRequest"));
        assertEq(ledger.ACCEPTANCE_TYPEHASH(), vm.parseJsonBytes32(eip, ".typeHashes.UsageAcceptance"));

        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            ledger.eip712Domain();
        assertEq(name, vm.parseJsonString(eip, ".domain.name"));
        assertEq(version, vm.parseJsonString(eip, ".domain.version"));
        assertEq(chainId, vm.parseJsonUint(eip, ".domain.chainId"));
        assertEq(verifyingContract, vm.parseJsonAddress(eip, ".domain.verifyingContract"));
        bytes32 separator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );
        assertEq(separator, vm.parseJsonBytes32(eip, ".domainSeparator"));
    }

    function test_caseB_replayedWithIndependentSignatures() public {
        address alpha = vm.parseJsonAddress(eip, ".accounts.alpha");
        address beta = vm.parseJsonAddress(eip, ".accounts.beta");
        address gamma = vm.parseJsonAddress(eip, ".accounts.gamma");

        SeriesTerms memory t = _terms("caseB");
        vm.startPrank(alpha);
        uint256 seriesId = ledger.createSeries(t, "ipfs://terms");
        ledger.setFulfiller(seriesId, alpha, true);
        ledger.issue(seriesId, alpha, 1_000_000, vm.parseJsonBytes32(seriesJson, ".caseB.basisRef"));
        ledger.safeTransferFrom(alpha, beta, seriesId, 200_000, "");
        vm.stopPrank();

        Authorization memory a = Authorization({
            holder: vm.parseJsonAddress(eip, ".authorization.holder"),
            consumer: vm.parseJsonAddress(eip, ".authorization.consumer"),
            seriesId: vm.parseJsonUint(eip, ".authorization.seriesId"),
            cap: vm.parseJsonUint(eip, ".authorization.cap"),
            validAfter: uint64(vm.parseJsonUint(eip, ".authorization.validAfter")),
            validUntil: uint64(vm.parseJsonUint(eip, ".authorization.validUntil")),
            scope: vm.parseJsonBytes32(eip, ".authorization.scope"),
            nonce: vm.parseJsonUint(eip, ".authorization.nonce")
        });
        assertEq(a.seriesId, seriesId);
        assertEq(a.holder, beta);
        assertEq(a.consumer, gamma);
        bytes32 authorizationId = vm.parseJsonBytes32(eip, ".authorizationId");
        assertEq(ledger.hashAuthorization(a), authorizationId, "authorization digest");

        ConsumptionRequest memory r = ConsumptionRequest({
            authorizationId: vm.parseJsonBytes32(eip, ".request.authorizationId"),
            requestId: vm.parseJsonBytes32(eip, ".request.requestId"),
            fulfiller: vm.parseJsonAddress(eip, ".request.fulfiller"),
            maxAmount: vm.parseJsonUint(eip, ".request.maxAmount"),
            holdUntil: uint64(vm.parseJsonUint(eip, ".request.holdUntil")),
            scope: vm.parseJsonBytes32(eip, ".request.scope")
        });
        assertEq(ledger.hashRequest(r), vm.parseJsonBytes32(eip, ".requestDigest"), "request digest");
        bytes32 requestKey = vm.parseJsonBytes32(eip, ".requestKey");
        assertEq(ledger.requestKeyOf(gamma, r.requestId), requestKey, "request key");

        // Hold with the two signatures from the vectors.
        vm.prank(alpha);
        bytes32 key = ledger.hold(
            a, vm.parseJsonBytes(eip, ".holderSignature"), r, vm.parseJsonBytes(eip, ".consumerSignature")
        );
        assertEq(key, requestKey);

        // Claim.
        uint256[] memory usage = vm.parseJsonUintArray(eip, ".usage");
        vm.prank(alpha);
        ledger.claimUsage(
            key, usage, Outcome(vm.parseJsonUint(eip, ".outcome")), vm.parseJsonBytes32(eip, ".evidenceRoot")
        );
        RequestRecord memory q = ledger.requestOf(key);
        assertEq(q.claimHash, vm.parseJsonBytes32(eip, ".claimHash"), "claim hash");
        assertEq(q.claimed, vm.parseJsonUint(eip, ".computed"), "deduction");
        assertEq(
            ledger.hashAcceptance(key, q.claimHash, q.claimed),
            vm.parseJsonBytes32(eip, ".acceptanceDigest"),
            "acceptance digest"
        );

        // Acceptance with the signature from the vectors.
        ledger.accept(key, vm.parseJsonBytes(eip, ".acceptanceSignature"));
        q = ledger.requestOf(key);
        assertEq(uint8(q.state), uint8(RequestState.Settled));
        assertEq(q.deducted, vm.parseJsonUint(eip, ".deducted"));
        assertEq(q.held - q.deducted, vm.parseJsonUint(eip, ".released"));
        assertEq(q.receiptHash, vm.parseJsonBytes32(eip, ".receiptHash"), "receipt hash");
        assertEq(ledger.availableOf(seriesId, beta), 198_200);
    }

    function test_recordIdentifierRule() public view {
        string memory json = vm.readFile(string.concat(DIR, "records.json"));
        string memory canonical = vm.parseJsonString(json, ".canonicalSample.canonical");
        assertEq(keccak256(bytes(canonical)), vm.parseJsonBytes32(json, ".canonicalSample.id"));
        // The Unit of Case B in the series vectors is that record.
        assertEq(_terms("caseB").unit, vm.parseJsonBytes32(json, ".canonicalSample.id"));
    }

    /// @dev Root of a batch of records: leaves are the identifiers in ascending order, each
    /// hashed with a 0x00 prefix; a parent hashes its two children with a 0x01 prefix; an odd
    /// last node is carried up unchanged.
    function _batchRoot(bytes32[] memory ids) internal pure returns (bytes32) {
        uint256 n = ids.length;
        require(n != 0, "a batch has at least one record");
        bytes32[] memory level = new bytes32[](n);
        for (uint256 i; i < n; ++i) {
            if (i != 0) require(uint256(ids[i]) > uint256(ids[i - 1]), "ascending, without duplicates");
            level[i] = keccak256(abi.encodePacked(bytes1(0x00), ids[i]));
        }
        while (n > 1) {
            for (uint256 i; i < n / 2; ++i) {
                level[i] = keccak256(abi.encodePacked(bytes1(0x01), level[2 * i], level[2 * i + 1]));
            }
            if (n % 2 == 1) level[n / 2] = level[n - 1];
            n = (n + 1) / 2;
        }
        return level[0];
    }

    function test_batchRootRule() public view {
        string memory json = vm.readFile(string.concat(DIR, "records.json"));
        bytes32[] memory ids = vm.parseJsonBytes32Array(json, ".batch.ids");
        bytes32 root = vm.parseJsonBytes32(json, ".batch.root");
        assertEq(ids.length, 3);
        assertEq(_batchRoot(ids), root);

        // Written out: with three records the third leaf is carried up unchanged.
        bytes32 l0 = keccak256(abi.encodePacked(bytes1(0x00), ids[0]));
        bytes32 l1 = keccak256(abi.encodePacked(bytes1(0x00), ids[1]));
        bytes32 l2 = keccak256(abi.encodePacked(bytes1(0x00), ids[2]));
        assertEq(keccak256(abi.encodePacked(bytes1(0x01), keccak256(abi.encodePacked(bytes1(0x01), l0, l1)), l2)), root);
        bytes32[] memory leaves = vm.parseJsonBytes32Array(json, ".batch.leaves");
        assertEq(leaves[0], l0);
        assertEq(leaves[1], l1);
        assertEq(leaves[2], l2);

        // The root of a batch of one record is its leaf, which is not the identifier itself.
        bytes32[] memory one = new bytes32[](1);
        one[0] = ids[0];
        assertEq(_batchRoot(one), l0);
        assertTrue(l0 != ids[0]);
    }

    function test_interfaceIdentifiers() public view {
        string memory json = vm.readFile(string.concat(DIR, "interfaces.json"));
        assertEq(bytes32(type(IAITORecords).interfaceId), bytes32(vm.parseJsonBytes(json, ".IAITORecords")));
        assertEq(bytes32(type(IAITOInstrument).interfaceId), bytes32(vm.parseJsonBytes(json, ".IAITOInstrument")));
        assertEq(bytes32(type(IAITOConsumption).interfaceId), bytes32(vm.parseJsonBytes(json, ".IAITOConsumption")));
        assertEq(bytes32(type(IAITOBinding).interfaceId), bytes32(vm.parseJsonBytes(json, ".IAITOBinding")));
        assertEq(bytes32(type(IAITOWrapper20).interfaceId), bytes32(vm.parseJsonBytes(json, ".IAITOWrapper20")));
        assertEq(bytes32(type(IAITOPeriodic).interfaceId), bytes32(vm.parseJsonBytes(json, ".IAITOPeriodic")));

        // The reference ledger implements neither optional profile and says so.
        assertFalse(ledger.supportsInterface(type(IAITOPeriodic).interfaceId));
        assertEq(
            keccak256("aito.profile.periodic-allowance.v1"),
            vm.parseJsonBytes32(json, '.extensions["aito.profile.periodic-allowance.v1"]')
        );
        assertEq(
            keccak256("aito.profile.reserved-capacity.v1"),
            vm.parseJsonBytes32(json, '.extensions["aito.profile.reserved-capacity.v1"]')
        );
    }
}
