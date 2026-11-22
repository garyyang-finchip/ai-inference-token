// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {AITORecords} from "../assets/erc-8506/contracts/AITORecords.sol";
import {AITOLedger} from "../assets/erc-8506/contracts/AITOLedger.sol";
import {AITOWrapper20} from "../assets/erc-8506/contracts/AITOWrapper20.sol";
import {
    SeriesTerms,
    SeriesExtension,
    Authorization,
    ConsumptionRequest,
    RequestRecord,
    RequestState,
    RecordKind,
    Outcome,
    AcceptanceRule
} from "../assets/erc-8506/contracts/interfaces/AITOTypes.sol";

/// @notice Runs the two worked cases of the specification on a live network and records what
/// happened. Driven by scripts/evidence-run.sh, one phase per invocation:
///
///   deploy   registry and ledger, gas for the accounts of the run
///   caseA1   Case A up to the usage claim
///   caseA2   Case A settlement, after the objection window
///   caseB    Case B, whole
///   report   reads the final state, checks it against the specification, writes evidence.json
///
/// Environment: NETWORK (anvil or sepolia), DEPLOYER_PK, and for the deploy phase GAS_PRICE_WEI
/// with the gas budgets GAS_SUPPLIER, GAS_ALPHA, GAS_DISTRIBUTOR, GAS_HOLDER and GAS_HOLDER2.
/// The accounts of the run are derived from DEPLOYER_PK; deployments/<network>/plan.json
/// (written by tools/aito.mjs plan) holds their addresses, the record identifiers and the terms.
contract AITOEvidence is Script {
    string internal network;
    string internal dir;
    string internal plan;
    uint256 internal deployerPk;

    AITORecords internal records;
    AITOLedger internal ledger;
    AITOWrapper20 internal wrapperA;
    bytes32 internal keyA;
    bytes32 internal keyB;

    // ---------------------------------------------------------------- phases

    function deploy() external {
        _init(false);
        // The driver sets how much gas each account is funded for and at which price.
        uint256 gasPrice = vm.envUint("GAS_PRICE_WEI");

        vm.startBroadcast(deployerPk);
        records = new AITORecords();
        ledger = new AITOLedger();
        _fund("supplier", vm.envUint("GAS_SUPPLIER") * gasPrice);
        _fund("alpha", vm.envUint("GAS_ALPHA") * gasPrice);
        _fund("distributor", vm.envUint("GAS_DISTRIBUTOR") * gasPrice);
        _fund("holder", vm.envUint("GAS_HOLDER") * gasPrice);
        _fund("holder2", vm.envUint("GAS_HOLDER2") * gasPrice);
        vm.stopBroadcast();

        _save();
        console2.log("records", address(records));
        console2.log("ledger ", address(ledger));
    }

    function caseA1() external {
        _init(true);
        SeriesTerms memory t = _terms("caseA");
        uint256 seriesId = vm.parseJsonUint(plan, ".caseA.seriesId");
        require(ledger.seriesIdOf(t) == seriesId, "plan and contract disagree on the series id");
        address supplier = _addr("supplier");
        address holder2 = _addr("holder2");

        // 1-3. Records, series, fulfiller, issuance against the declared basis.
        vm.startBroadcast(_pk("supplier"));
        _anchor("caseA", t);
        ledger.createSeries(t, vm.parseJsonString(plan, ".caseA.termsURI"));
        ledger.setFulfiller(seriesId, supplier, true);
        ledger.issue(seriesId, _addr("distributor"), 1_000_000, vm.parseJsonBytes32(plan, ".caseA.basisRef"));
        vm.stopBroadcast();

        // 4. Transfer on the native carrier.
        vm.startBroadcast(_pk("distributor"));
        ledger.safeTransferFrom(_addr("distributor"), _addr("holder"), seriesId, 300_000, "");
        vm.stopBroadcast();

        // 5-6. Wrap 200,000 and move 50,000 in wrapped form.
        vm.startBroadcast(deployerPk);
        wrapperA = new AITOWrapper20(address(ledger), seriesId, "Wrapped AITO Evidence Quota A", "wAITO-A", 18);
        vm.stopBroadcast();
        vm.startBroadcast(_pk("holder"));
        ledger.safeTransferFrom(_addr("holder"), address(wrapperA), seriesId, 200_000, "");
        wrapperA.transfer(holder2, 50_000e18);
        vm.stopBroadcast();

        // 7. Unwrap.
        vm.startBroadcast(_pk("holder2"));
        wrapperA.unwrap(50_000, holder2);
        vm.stopBroadcast();

        // 8-10. Authorization (signed off chain), hold, usage claim.
        Authorization memory a = _authorization(holder2, _addr("consumer"), seriesId, 20_000);
        ConsumptionRequest memory r = _request(a, keccak256("evidence/case-a/r"), supplier, 4_000);
        bytes memory holderSig = _sign(_pk("holder2"), r.authorizationId);
        bytes memory consumerSig = _sign(_pk("consumer"), ledger.hashRequest(r));
        uint256[] memory usage = new uint256[](3);
        usage[0] = 6_000;
        usage[1] = 2_100;

        vm.startBroadcast(_pk("supplier"));
        keyA = ledger.hold(a, holderSig, r, consumerSig);
        ledger.claimUsage(keyA, usage, Outcome.Completed, keccak256("evidence/case-a/usage statement"));
        vm.stopBroadcast();

        _save();
    }

    function caseA2() external {
        _init(true);
        vm.startBroadcast(deployerPk);
        ledger.finalize(keyA);
        vm.stopBroadcast();
    }

    function caseB() external {
        _init(true);
        SeriesTerms memory t = _terms("caseB");
        uint256 seriesId = vm.parseJsonUint(plan, ".caseB.seriesId");
        require(ledger.seriesIdOf(t) == seriesId, "plan and contract disagree on the series id");
        address alpha = _addr("alpha");
        address beta = _addr("beta");

        Authorization memory a = _authorization(beta, _addr("gamma"), seriesId, 50_000);
        ConsumptionRequest memory r = _request(a, keccak256("evidence/case-b/r1"), alpha, 3_000);
        bytes memory holderSig = _sign(_pk("beta"), r.authorizationId);
        bytes memory consumerSig = _sign(_pk("gamma"), ledger.hashRequest(r));
        uint256[] memory usage = new uint256[](2);
        usage[0] = 2_000;
        usage[1] = 1_400;

        // 1-7. Supply statement, issuance, transfer, hold, usage claim: all by the agent itself.
        vm.startBroadcast(_pk("alpha"));
        _anchor("caseB", t);
        ledger.createSeries(t, vm.parseJsonString(plan, ".caseB.termsURI"));
        ledger.setFulfiller(seriesId, alpha, true);
        ledger.issue(seriesId, alpha, 1_000_000, vm.parseJsonBytes32(plan, ".caseB.basisRef"));
        ledger.safeTransferFrom(alpha, beta, seriesId, 200_000, "");
        keyB = ledger.hold(a, holderSig, r, consumerSig);
        ledger.claimUsage(keyB, usage, Outcome.Completed, keccak256("evidence/case-b/usage statement"));
        vm.stopBroadcast();

        // 8-9. The consuming agent accepts by signature; anyone may relay it.
        RequestRecord memory q = ledger.requestOf(keyB);
        bytes memory acceptance = _sign(_pk("gamma"), ledger.hashAcceptance(keyB, q.claimHash, q.claimed));
        vm.startBroadcast(deployerPk);
        ledger.accept(keyB, acceptance);
        vm.stopBroadcast();

        _save();
    }

    function report() external {
        _init(true);
        uint256 seriesA = vm.parseJsonUint(plan, ".caseA.seriesId");
        uint256 seriesB = vm.parseJsonUint(plan, ".caseB.seriesId");
        RequestRecord memory qa = ledger.requestOf(keyA);
        RequestRecord memory qb = ledger.requestOf(keyB);

        // Case A: 3,600 deducted and 400 released; positions add up to what was issued.
        require(qa.state == RequestState.Settled && qa.deducted == 3_600 && qa.held == 4_000, "case A request");
        require(ledger.availableOf(seriesA, _addr("distributor")) == 700_000, "case A distributor");
        require(ledger.availableOf(seriesA, _addr("holder")) == 100_000, "case A holder");
        require(ledger.availableOf(seriesA, _addr("holder2")) == 46_400, "case A holder2");
        require(wrapperA.lockedUnits() == 150_000 && wrapperA.totalSupply() == 150_000e18, "case A wrapper");
        require(ledger.consumedOf(seriesA) == 3_600 && ledger.heldOf(seriesA) == 0, "case A counters");
        require(ledger.issuedOf(seriesA) == 700_000 + 100_000 + 46_400 + 150_000 + 3_600, "case A identity");

        // Case B: 1,800 deducted and 1,200 released.
        require(qb.state == RequestState.Settled && qb.deducted == 1_800 && qb.held == 3_000, "case B request");
        require(ledger.availableOf(seriesB, _addr("alpha")) == 800_000, "case B alpha");
        require(ledger.availableOf(seriesB, _addr("beta")) == 198_200, "case B beta");
        require(ledger.usedOf(qb.authorizationId) == 1_800, "case B authorization");
        require(ledger.issuedOf(seriesB) == 800_000 + 198_200 + 1_800, "case B identity");
        require(ledger.isReceipt(qa.receiptHash) && ledger.isReceipt(qb.receiptHash), "receipts");

        string memory a = "caseA";
        vm.serializeString(a, "seriesId", vm.toString(seriesA));
        vm.serializeAddress(a, "wrapper", address(wrapperA));
        vm.serializeBytes32(a, "requestKey", keyA);
        vm.serializeUint(a, "held", qa.held);
        vm.serializeUint(a, "deducted", qa.deducted);
        vm.serializeUint(a, "released", qa.held - qa.deducted);
        vm.serializeBytes32(a, "claimHash", qa.claimHash);
        vm.serializeBytes32(a, "receiptHash", qa.receiptHash);
        vm.serializeUint(a, "issued", ledger.issuedOf(seriesA));
        vm.serializeUint(a, "consumed", ledger.consumedOf(seriesA));
        vm.serializeUint(a, "distributorUnits", ledger.availableOf(seriesA, _addr("distributor")));
        vm.serializeUint(a, "holderUnits", ledger.availableOf(seriesA, _addr("holder")));
        vm.serializeUint(a, "holder2Units", ledger.availableOf(seriesA, _addr("holder2")));
        string memory aJson = vm.serializeUint(a, "wrapperLockedUnits", wrapperA.lockedUnits());

        string memory b = "caseB";
        vm.serializeString(b, "seriesId", vm.toString(seriesB));
        vm.serializeBytes32(b, "requestKey", keyB);
        vm.serializeUint(b, "held", qb.held);
        vm.serializeUint(b, "deducted", qb.deducted);
        vm.serializeUint(b, "released", qb.held - qb.deducted);
        vm.serializeBytes32(b, "claimHash", qb.claimHash);
        vm.serializeBytes32(b, "receiptHash", qb.receiptHash);
        vm.serializeUint(b, "issued", ledger.issuedOf(seriesB));
        vm.serializeUint(b, "consumed", ledger.consumedOf(seriesB));
        vm.serializeUint(b, "alphaUnits", ledger.availableOf(seriesB, _addr("alpha")));
        vm.serializeUint(b, "betaUnits", ledger.availableOf(seriesB, _addr("beta")));
        string memory bJson = vm.serializeUint(b, "authorizationUsed", ledger.usedOf(qb.authorizationId));

        string memory root = "evidence";
        vm.serializeString(root, "network", network);
        vm.serializeUint(root, "chainId", block.chainid);
        vm.serializeUint(root, "readAtBlock", block.number);
        vm.serializeAddress(root, "deployer", vm.addr(deployerPk));
        vm.serializeAddress(root, "records", address(records));
        vm.serializeAddress(root, "ledger", address(ledger));
        vm.serializeString(root, "caseA", aJson);
        string memory out = vm.serializeString(root, "caseB", bJson);
        vm.writeJson(out, string.concat(dir, "evidence.json"));
        console2.log("all checks passed; wrote", string.concat(dir, "evidence.json"));
    }

    // ---------------------------------------------------------------- helpers

    function _init(bool loadState) internal {
        network = vm.envString("NETWORK");
        deployerPk = vm.envUint("DEPLOYER_PK");
        dir = string.concat("deployments/", network, "/");
        plan = vm.readFile(string.concat(dir, "plan.json"));
        require(vm.parseJsonUint(plan, ".chainId") == block.chainid, "plan is for another chain");
        require(vm.parseJsonAddress(plan, ".deployer") == vm.addr(deployerPk), "plan is for another deployer key");
        require(_addr("supplier") == vm.addr(_pk("supplier")), "plan accounts do not match the key");

        if (loadState) {
            string memory state = vm.readFile(string.concat(dir, "state.json"));
            records = AITORecords(vm.parseJsonAddress(state, ".records"));
            ledger = AITOLedger(vm.parseJsonAddress(state, ".ledger"));
            wrapperA = AITOWrapper20(vm.parseJsonAddress(state, ".wrapperA"));
            keyA = vm.parseJsonBytes32(state, ".keyA");
            keyB = vm.parseJsonBytes32(state, ".keyB");
        }
    }

    function _save() internal {
        string memory s = "state";
        vm.serializeAddress(s, "records", address(records));
        vm.serializeAddress(s, "ledger", address(ledger));
        vm.serializeAddress(s, "wrapperA", address(wrapperA));
        vm.serializeBytes32(s, "keyA", keyA);
        string memory out = vm.serializeBytes32(s, "keyB", keyB);
        vm.writeJson(out, string.concat(dir, "state.json"));
    }

    function _pk(string memory label) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(deployerPk, label)));
    }

    function _addr(string memory label) internal view returns (address) {
        return vm.parseJsonAddress(plan, string.concat(".actors.", label));
    }

    function _fund(string memory label, uint256 amount) internal {
        (bool ok,) = payable(_addr(label)).call{value: amount}("");
        require(ok, "funding failed");
    }

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _anchor(string memory which, SeriesTerms memory t) internal {
        string memory p = string.concat(".", which, ".");
        records.anchor(t.unit, RecordKind.Unit, bytes32(0), vm.parseJsonString(plan, string.concat(p, "unitURI")));
        records.anchor(t.grade, RecordKind.Grade, bytes32(0), vm.parseJsonString(plan, string.concat(p, "gradeURI")));
        records.anchor(
            t.source, RecordKind.Source, bytes32(0), vm.parseJsonString(plan, string.concat(p, "sourceURI"))
        );
        records.anchor(
            t.termsHash, RecordKind.Terms, bytes32(0), vm.parseJsonString(plan, string.concat(p, "termsURI"))
        );
    }

    function _authorization(address holder, address consumer, uint256 seriesId, uint256 cap)
        internal
        view
        returns (Authorization memory)
    {
        return Authorization({
            holder: holder,
            consumer: consumer,
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
        returns (ConsumptionRequest memory)
    {
        return ConsumptionRequest({
            authorizationId: ledger.hashAuthorization(a),
            requestId: requestId,
            fulfiller: fulfiller,
            maxAmount: maxAmount,
            holdUntil: uint64(block.timestamp + 3000),
            scope: bytes32(0)
        });
    }

    function _terms(string memory which) internal view returns (SeriesTerms memory t) {
        string memory p = string.concat(".", which, ".terms.");
        t.issuer = vm.parseJsonAddress(plan, string.concat(p, "issuer"));
        t.responsibleParty = vm.parseJsonAddress(plan, string.concat(p, "responsibleParty"));
        t.unit = vm.parseJsonBytes32(plan, string.concat(p, "unit"));
        t.grade = vm.parseJsonBytes32(plan, string.concat(p, "grade"));
        t.source = vm.parseJsonBytes32(plan, string.concat(p, "source"));
        t.termsHash = vm.parseJsonBytes32(plan, string.concat(p, "termsHash"));
        t.cap = vm.parseJsonUint(plan, string.concat(p, "cap"));
        t.validFrom = uint64(vm.parseJsonUint(plan, string.concat(p, "validFrom")));
        t.validUntil = uint64(vm.parseJsonUint(plan, string.concat(p, "validUntil")));
        t.transferable = vm.parseJsonBool(plan, string.concat(p, "transferable"));
        t.scheduleMutable = vm.parseJsonBool(plan, string.concat(p, "scheduleMutable"));
        t.roundUp = vm.parseJsonBool(plan, string.concat(p, "roundUp"));
        t.acceptanceRule = AcceptanceRule(vm.parseJsonUint(plan, string.concat(p, "acceptanceRule")));
        t.objectionWindow = uint32(vm.parseJsonUint(plan, string.concat(p, "objectionWindow")));
        t.resolutionWindow = uint32(vm.parseJsonUint(plan, string.concat(p, "resolutionWindow")));
        t.maxHoldDuration = uint32(vm.parseJsonUint(plan, string.concat(p, "maxHoldDuration")));
        t.resolver = vm.parseJsonAddress(plan, string.concat(p, "resolver"));
        t.components = vm.parseJsonBytes32Array(plan, string.concat(p, "components"));
        t.weights = vm.parseJsonUintArray(plan, string.concat(p, "weights"));
        t.outcomeMasks = vm.parseJsonUintArray(plan, string.concat(p, "outcomeMasks"));
        t.extensions = new SeriesExtension[](0);
    }
}
