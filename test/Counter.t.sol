// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {CoFheTest} from "@cofhe/mock-contracts/foundry/CoFheTest.sol";
import {FHE, euint32, InEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {
    MockPermissioned,
    Permission
} from "@cofhe/mock-contracts/Permissioned.sol";
import {Counter} from "../src/Counter.sol";

contract CounterTest is Test, CoFheTest {
    Counter public counter;
    address public bob;
    address public alice;
    uint256 public bobKey;

    function setUp() public {
        // CoFheTest constructor already called etchFhenixMocks()
        // which deploys MockTaskManager, MockACL, MockZkVerifier, etc. at their fixed addresses

        // Create labeled accounts with known private keys
        (bob, bobKey) = makeAddrAndKey("bob");
        alice = makeAddr("alice");

        // Deploy Counter as bob
        vm.prank(bob);
        counter = new Counter();
    }

    // =========================================
    // Functionality Tests
    // =========================================

    function test_ShouldIncrementTheCounter() public {
        // Initial count should be 0
        assertHashValue(counter.count(), uint32(0));

        // Increment as bob
        vm.prank(bob);
        counter.increment();

        // Count should be 1
        assertHashValue(counter.count(), uint32(1));
    }

    function test_ShouldDecrementTheCounter() public {
        // First increment to 1 so we can decrement back to 0
        vm.prank(bob);
        counter.increment();
        assertHashValue(counter.count(), uint32(1));

        // Decrement back to 0
        vm.prank(bob);
        counter.decrement();
        assertHashValue(counter.count(), uint32(0));
    }

    function test_ShouldEncryptInputAndResetCounter() public {
        // Create encrypted input with value 2000
        InEuint32 memory encrypted = createInEuint32(2000, bob);

        // Reset as bob
        vm.prank(bob);
        counter.reset(encrypted);

        // Verify count is 2000
        assertHashValue(counter.count(), uint32(2000));
    }

    function test_ShouldHandleMultipleOperationsInSequence() public {
        // Reset to 10
        InEuint32 memory encrypted = createInEuint32(10, bob);
        vm.prank(bob);
        counter.reset(encrypted);

        // Increment 3 times: 10 -> 11 -> 12 -> 13
        vm.startPrank(bob);
        counter.increment();
        counter.increment();
        counter.increment();

        // Decrement once: 13 -> 12
        counter.decrement();
        vm.stopPrank();

        assertHashValue(counter.count(), uint32(12));
    }

    // =========================================
    // On-chain Decryption Tests
    // =========================================

    function test_ShouldRevertBeforeDecryptionReturned() public {
        // Reset to 42
        InEuint32 memory encrypted = createInEuint32(42, bob);
        vm.prank(bob);
        counter.reset(encrypted);

        // Request on-chain decryption
        vm.prank(bob);
        counter.decryptCounter();

        // Should revert because the mock async delay has not passed
        vm.expectRevert("Value is not ready");
        counter.getDecryptedValue();
    }

    function test_ShouldReturnDecryptedValueAfterTimePassed() public {
        // Reset to 42
        InEuint32 memory encrypted = createInEuint32(42, bob);
        vm.prank(bob);
        counter.reset(encrypted);

        // Request on-chain decryption
        vm.prank(bob);
        counter.decryptCounter();

        // Advance time to allow mock coprocessor to process the decryption callback
        // MockTaskManager uses: asyncOffset = (block.timestamp % 10) + 1
        vm.warp(block.timestamp + 100);

        // Now the decrypted value should be available
        uint256 decryptedValue = counter.getDecryptedValue();
        assertEq(decryptedValue, 42);
    }

    // =========================================
    // Mock Storage Tests (equivalent of Mock Logging)
    // =========================================

    function test_ShouldCheckPlaintextDirectly() public {
        // Increment
        vm.prank(bob);
        counter.increment();

        // Read plaintext directly from mock storage
        uint256 countHash = euint32.unwrap(counter.count());
        uint256 plaintext = mockStorage(countHash);
        assertEq(plaintext, 1);
    }

    function test_ShouldCheckPlaintextViaAssertHashValue() public {
        vm.startPrank(bob);
        counter.increment();
        counter.increment();
        vm.stopPrank();

        // assertHashValue checks both that the hash exists in mock storage
        // and that its plaintext equals the expected value
        assertHashValue(counter.count(), uint32(2));
    }

    // =========================================
    // Permission Tests
    // =========================================

    function test_SelfPermitShouldBeValid() public {
        // Create a self-permission for bob
        Permission memory permission = createPermissionSelf(bob);
        permission.sealingKey = createSealingKey(1);

        // Sign the permission with bob's private key
        permission = signPermissionSelf(permission, bobKey);

        // Verify the permission is valid on-chain
        bool isValid = mockAcl.checkPermitValidity(permission);
        assertTrue(isValid);
    }

    function test_ExpiredPermitShouldRevert() public {
        // Warp to a realistic timestamp (Foundry starts at timestamp=1)
        vm.warp(1700000000);

        // Create a self-permission with an expired timestamp
        Permission memory permission = createBasePermission();
        permission.issuer = bob;
        permission.expiration = uint64(block.timestamp) - 3600; // 1 hour ago
        permission.sealingKey = createSealingKey(1);

        // Sign the permission
        permission = signPermissionSelf(permission, bobKey);

        // Should revert with PermissionInvalid_Expired
        vm.expectRevert(MockPermissioned.PermissionInvalid_Expired.selector);
        mockAcl.checkPermitValidity(permission);
    }

    function test_InvalidSignatureShouldRevert() public {
        // Create a self-permission for bob
        Permission memory permission = createPermissionSelf(bob);
        permission.sealingKey = createSealingKey(1);

        // Sign with bob's key
        permission = signPermissionSelf(permission, bobKey);

        // Tamper with the signature
        permission
            .issuerSignature = hex"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";

        // Should revert with PermissionInvalid_IssuerSignature
        vm.expectRevert(
            MockPermissioned.PermissionInvalid_IssuerSignature.selector
        );
        mockAcl.checkPermitValidity(permission);
    }

    // =========================================
    // Fuzz Tests (Foundry-native advantage)
    // =========================================

    function testFuzz_ResetCounter(uint32 value) public {
        InEuint32 memory encrypted = createInEuint32(value, bob);

        vm.prank(bob);
        counter.reset(encrypted);

        assertHashValue(counter.count(), value);
    }
}
