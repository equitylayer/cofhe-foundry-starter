// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {CoFheTest} from "@cofhe/mock-contracts/foundry/CoFheTest.sol";
import {euint32, InEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {Permission} from "@cofhe/mock-contracts/Permissioned.sol";
import {Counter} from "../src/Counter.sol";

contract CounterTest is Test, CoFheTest {
    Counter public counter;
    address public bob;
    address public alice;
    uint256 public bobKey;
    uint256 public aliceKey;

    function setUp() public {
        (bob, bobKey) = makeAddrAndKey("bob");
        (alice, aliceKey) = makeAddrAndKey("alice");

        vm.prank(bob);
        counter = new Counter();
    }

    // --- Functionality ---

    function test_ShouldIncrementTheCounter() public {
        assertHashValue(counter.count(), uint32(0));

        vm.prank(bob);
        counter.increment();

        assertHashValue(counter.count(), uint32(1));
    }

    function test_ShouldDecrementTheCounter() public {
        vm.prank(bob);
        counter.increment();
        assertHashValue(counter.count(), uint32(1));

        vm.prank(bob);
        counter.decrement();
        assertHashValue(counter.count(), uint32(0));
    }

    function test_ShouldEncryptInputAndResetCounter() public {
        InEuint32 memory encrypted = createInEuint32(2000, bob);

        vm.prank(bob);
        counter.reset(encrypted);

        assertHashValue(counter.count(), uint32(2000));
    }

    function test_ShouldHandleMultipleOperationsInSequence() public {
        InEuint32 memory encrypted = createInEuint32(10, bob);
        vm.prank(bob);
        counter.reset(encrypted);

        // 10 -> 11 -> 12 -> 13 -> 12
        vm.startPrank(bob);
        counter.increment();
        counter.increment();
        counter.increment();
        counter.decrement();
        vm.stopPrank();

        assertHashValue(counter.count(), uint32(12));
    }

    // --- On-chain Decryption (new flow: allowPublic → decryptForTx → publishDecryptResult) ---

    function test_ShouldRevertBeforeDecryptionPublished() public {
        InEuint32 memory encrypted = createInEuint32(42, bob);
        vm.prank(bob);
        counter.reset(encrypted);

        // Allow public decryption but don't publish result yet
        vm.prank(bob);
        counter.allowCounterPublicly();

        // Result not yet published on-chain
        vm.expectRevert("Value is not ready");
        counter.getDecryptedValue();
    }

    function test_ShouldReturnDecryptedValueAfterPublish() public {
        InEuint32 memory encrypted = createInEuint32(42, bob);
        vm.prank(bob);
        counter.reset(encrypted);

        // Step 1: Allow public decryption
        vm.prank(bob);
        counter.allowCounterPublicly();

        // Step 2: Simulate off-chain decryption (client.decryptForTx)
        uint256 ctHash = uint256(euint32.unwrap(counter.count()));
        (bool allowed, , uint256 plaintext) = decryptForTxWithoutPermit(ctHash);
        assertTrue(allowed, "Should be allowed to decrypt");
        assertEq(plaintext, 42);

        // Step 3: Publish verified result on-chain
        counter.revealCounter(uint32(plaintext), "");

        // Step 4: Read the result
        uint256 decryptedValue = counter.getDecryptedValue();
        assertEq(decryptedValue, 42);
    }

    // --- Mock Storage ---

    function test_ShouldCheckPlaintextDirectly() public {
        vm.prank(bob);
        counter.increment();

        uint256 countHash = uint256(euint32.unwrap(counter.count()));
        uint256 plaintext = mockStorage(countHash);
        assertEq(plaintext, 1);
    }

    function test_ShouldCheckPlaintextViaAssertHashValue() public {
        vm.startPrank(bob);
        counter.increment();
        counter.increment();
        vm.stopPrank();

        assertHashValue(counter.count(), uint32(2));
    }

    // --- ACL & Permit Unsealing ---

    function test_CallerCanUnsealAfterIncrement() public {
        vm.prank(bob);
        counter.increment();

        uint256 countHash = uint256(euint32.unwrap(counter.count()));

        Permission memory bobPermit = createPermissionSelf(bob);
        bobPermit.sealingKey = createSealingKey(1);
        bobPermit = signPermissionSelf(bobPermit, bobKey);

        (bool allowed, , uint256 decrypted) = queryDecrypt(
            countHash,
            block.chainid,
            bobPermit
        );
        assertTrue(allowed, "Bob should be allowed to unseal");
        assertEq(decrypted, 1, "Decrypted value should be 1");
    }

    function test_NonCallerCannotUnsealAfterIncrement() public {
        vm.prank(bob);
        counter.increment();

        uint256 countHash = uint256(euint32.unwrap(counter.count()));

        // Alice has no ACL permission on this count
        Permission memory alicePermit = createPermissionSelf(alice);
        alicePermit.sealingKey = createSealingKey(2);
        alicePermit = signPermissionSelf(alicePermit, aliceKey);

        (bool allowed, string memory error, ) = queryDecrypt(
            countHash,
            block.chainid,
            alicePermit
        );
        assertFalse(
            allowed,
            "Alice should NOT be allowed to unseal bob's count"
        );
        assertEq(error, "NotAllowed");
    }

    function test_SealOutputPermissionFlow() public {
        vm.prank(bob);
        counter.increment();

        uint256 countHash = uint256(euint32.unwrap(counter.count()));

        bytes32 sealingKey = createSealingKey(42);
        Permission memory bobPermit = createPermissionSelf(bob);
        bobPermit.sealingKey = sealingKey;
        bobPermit = signPermissionSelf(bobPermit, bobKey);

        (bool allowed, , bytes32 sealedValue) = querySealOutput(
            countHash,
            block.chainid,
            bobPermit
        );
        assertTrue(allowed, "Bob should be allowed to seal");

        uint256 unsealed = unseal(sealedValue, sealingKey);
        assertEq(unsealed, 1, "Unsealed value should be 1");
    }

    function test_PermissionTransfersToNewCaller() public {
        vm.prank(bob);
        counter.increment();

        // Alice increments -- she gets allowSender on the new count
        vm.prank(alice);
        counter.increment();

        uint256 countHash = uint256(euint32.unwrap(counter.count()));

        // Alice can unseal the current count
        Permission memory alicePermit = createPermissionSelf(alice);
        alicePermit.sealingKey = createSealingKey(3);
        alicePermit = signPermissionSelf(alicePermit, aliceKey);

        (bool aliceAllowed, , uint256 aliceDecrypted) = queryDecrypt(
            countHash,
            block.chainid,
            alicePermit
        );
        assertTrue(aliceAllowed, "Alice should unseal the current count");
        assertEq(aliceDecrypted, 2);

        // Bob cannot unseal the current count (alice was the last caller)
        Permission memory bobPermit = createPermissionSelf(bob);
        bobPermit.sealingKey = createSealingKey(4);
        bobPermit = signPermissionSelf(bobPermit, bobKey);

        (bool bobAllowed, string memory error, ) = queryDecrypt(
            countHash,
            block.chainid,
            bobPermit
        );
        assertFalse(bobAllowed, "Bob should NOT unseal alice's count");
        assertEq(error, "NotAllowed");
    }

    // --- Fuzz Tests ---

    function testFuzz_ResetCounter(uint32 value) public {
        InEuint32 memory encrypted = createInEuint32(value, bob);

        vm.prank(bob);
        counter.reset(encrypted);

        assertHashValue(counter.count(), value);
    }
}
