// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {AITORecords} from "../assets/erc-9999/contracts/AITORecords.sol";
import {IAITORecords} from "../assets/erc-9999/contracts/interfaces/IAITORecords.sol";
import {RecordKind} from "../assets/erc-9999/contracts/interfaces/AITOTypes.sol";

contract AITORecordsTest is Test {
    AITORecords internal records;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    bytes32 internal constant ID = keccak256("record");

    function setUp() public {
        vm.warp(1_800_000_000);
        records = new AITORecords();
    }

    function test_anchor_isKeyedByPublisher() public {
        vm.expectEmit(true, true, true, true);
        emit IAITORecords.RecordAnchored(ID, RecordKind.Unit, alice, bytes32(0), "ipfs://unit");
        vm.prank(alice);
        records.anchor(ID, RecordKind.Unit, bytes32(0), "ipfs://unit");

        (RecordKind kind, uint64 anchoredAt, bytes32 supersedes, string memory uri) = records.recordOf(alice, ID);
        assertEq(uint8(kind), uint8(RecordKind.Unit));
        assertEq(anchoredAt, 1_800_000_000);
        assertEq(supersedes, bytes32(0));
        assertEq(uri, "ipfs://unit");

        // Bob has not anchored it, and may do so under his own name without touching Alice's record.
        (, uint64 bobAt,,) = records.recordOf(bob, ID);
        assertEq(bobAt, 0);
        vm.prank(bob);
        records.anchor(ID, RecordKind.Unit, bytes32(0), "https://mirror.example/unit");
        (,,, string memory aliceUri) = records.recordOf(alice, ID);
        assertEq(aliceUri, "ipfs://unit");
    }

    function test_anchor_cannotBeReplaced() public {
        vm.startPrank(alice);
        records.anchor(ID, RecordKind.Grade, bytes32(0), "ipfs://grade");
        vm.expectRevert(abi.encodeWithSelector(AITORecords.AlreadyAnchored.selector, alice, ID));
        records.anchor(ID, RecordKind.Grade, bytes32(0), "ipfs://other");
        vm.stopPrank();
    }

    function test_anchor_newVersionNamesTheOldOne() public {
        bytes32 v2 = keccak256("record v2");
        vm.startPrank(alice);
        records.anchor(ID, RecordKind.Grade, bytes32(0), "ipfs://v1");
        records.anchor(v2, RecordKind.Grade, ID, "ipfs://v2");
        vm.stopPrank();
        (,, bytes32 supersedes,) = records.recordOf(alice, v2);
        assertEq(supersedes, ID);
        // The old record is untouched.
        (,,, string memory uri) = records.recordOf(alice, ID);
        assertEq(uri, "ipfs://v1");
    }

    function test_anchor_rejectsDegenerateInput() public {
        vm.startPrank(alice);
        vm.expectRevert(AITORecords.ZeroIdentifier.selector);
        records.anchor(bytes32(0), RecordKind.Unit, bytes32(0), "x");
        vm.expectRevert(AITORecords.SupersedesItself.selector);
        records.anchor(ID, RecordKind.Unit, ID, "x");
        vm.stopPrank();
    }

    function test_relocate_changesOnlyTheLocation() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(AITORecords.NotAnchored.selector, alice, ID));
        records.relocate(ID, "ipfs://new");

        records.anchor(ID, RecordKind.Source, bytes32(0), "ipfs://old");
        vm.expectEmit(true, true, false, true);
        emit IAITORecords.RecordRelocated(ID, alice, "ipfs://new");
        records.relocate(ID, "ipfs://new");
        vm.stopPrank();

        (RecordKind kind, uint64 anchoredAt,, string memory uri) = records.recordOf(alice, ID);
        assertEq(uint8(kind), uint8(RecordKind.Source));
        assertEq(anchoredAt, 1_800_000_000);
        assertEq(uri, "ipfs://new");
    }

    function test_anchorBatch() public {
        bytes32 root = keccak256("root");
        vm.startPrank(alice);
        vm.expectRevert(AITORecords.EmptyBatch.selector);
        records.anchorBatch(root, RecordKind.Receipt, 0, "ipfs://batch");
        vm.expectRevert(AITORecords.ZeroIdentifier.selector);
        records.anchorBatch(bytes32(0), RecordKind.Receipt, 3, "ipfs://batch");

        vm.expectEmit(true, true, true, true);
        emit IAITORecords.BatchAnchored(root, RecordKind.Receipt, alice, 128, "ipfs://batch");
        records.anchorBatch(root, RecordKind.Receipt, 128, "ipfs://batch");
        vm.expectRevert(abi.encodeWithSelector(AITORecords.AlreadyAnchored.selector, alice, root));
        records.anchorBatch(root, RecordKind.Receipt, 128, "ipfs://batch");
        vm.stopPrank();

        (RecordKind kind, uint64 anchoredAt, uint256 count, string memory uri) = records.batchOf(alice, root);
        assertEq(uint8(kind), uint8(RecordKind.Receipt));
        assertEq(anchoredAt, 1_800_000_000);
        assertEq(count, 128);
        assertEq(uri, "ipfs://batch");
    }

    function test_supportsInterface() public view {
        assertTrue(records.supportsInterface(type(IAITORecords).interfaceId));
        assertTrue(records.supportsInterface(type(IERC165).interfaceId));
        assertFalse(records.supportsInterface(0xffffffff));
    }
}
