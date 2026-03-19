# Writing Foundry Tests with CoFHE

## Test Setup

Every test contract must inherit from both `Test` (forge-std) and `CoFheTest` (mock infrastructure). `CoFheTest`'s constructor automatically deploys all mock contracts (MockTaskManager, MockACL, MockZkVerifier, MockZkVerifierSigner, MockThresholdNetwork) at their expected addresses.

```solidity
import {Test} from "forge-std/Test.sol";
import {CoFheTest} from "@cofhe/mock-contracts/foundry/CoFheTest.sol";
import {FHE, euint32, InEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

contract MyTest is Test, CoFheTest {
    function setUp() public {
        // CoFheTest constructor already ran -- mocks are ready.
        // Deploy your contracts here.
    }
}
```

Only import the types you actually use. Available types:

```solidity
// Encrypted types (each wraps a uint256 hash)
ebool, euint8, euint16, euint32, euint64, euint128, euint256, eaddress

// Encrypted input structs (for passing user-encrypted values to contracts)
InEbool, InEuint8, InEuint16, InEuint32, InEuint64, InEuint128, InEuint256, InEaddress
```

---

## Encrypted Types

All encrypted types (`ebool`, `euint8`, ..., `eaddress`) are `bytes32` newtypes. The value they hold is a **hash** (pointer) into the mock storage -- not the plaintext.

| Type | Plaintext equivalent |
|------|---------------------|
| `ebool` | `bool` |
| `euint8` | `uint8` |
| `euint16` | `uint16` |
| `euint32` | `uint32` |
| `euint64` | `uint64` |
| `euint128` | `uint128` |
| `euint256` | `uint256` |
| `eaddress` | `address` |

### unwrap / wrap

Convert between the encrypted newtype and its raw `bytes32` hash:

```solidity
euint32 encrypted = FHE.asEuint32(42);

// Get the raw hash (bytes32)
bytes32 hash = euint32.unwrap(encrypted);

// Reconstruct from hash
euint32 restored = euint32.wrap(hash);
```

Use `unwrap` when you need the raw hash. Since `mockStorage()`, `queryDecrypt()`, and other helpers expect `uint256`, cast with `uint256(euint32.unwrap(value))`.

---

## FHE Operations Reference

### Trivial Encryption (plaintext to encrypted)

Converts a public value into an encrypted type. The value is known, so this does not provide confidentiality -- only FHE-operation compatibility.

```solidity
ebool    a = FHE.asEbool(true);
euint8   b = FHE.asEuint8(255);
euint16  c = FHE.asEuint16(1000);
euint32  d = FHE.asEuint32(42);
euint64  e = FHE.asEuint64(1_000_000_000);
euint128 f = FHE.asEuint128(type(uint64).max);
eaddress g = FHE.asEaddress(msg.sender);
```

Use in contracts for constants (e.g., `FHE.asEuint32(1)` for a ONE value).

### Encrypted Input Verification (user-encrypted to on-chain)

Converts a signed encrypted input struct into an on-chain encrypted type. This is how users send private data to contracts.

```solidity
function deposit(InEuint32 memory encryptedAmount) public {
    euint32 amount = FHE.asEuint32(encryptedAmount);
    // amount is now an on-chain encrypted value
}
```

See [Creating Encrypted Inputs in Tests](#createine----creating-encrypted-inputs) for how to create `InE*` structs in tests.

### Arithmetic

All available for `euint8`, `euint16`, `euint32`, `euint64`, `euint128`, `euint256`:

```solidity
euint32 sum  = FHE.add(a, b);   // a + b
euint32 diff = FHE.sub(a, b);   // a - b
euint32 prod = FHE.mul(a, b);   // a * b
euint32 quot = FHE.div(a, b);   // a / b  (integer division, truncates)
euint32 rem  = FHE.rem(a, b);   // a % b
euint32 sq   = FHE.square(a);   // a * a  (more efficient than mul(a, a))
```

### Comparisons

Return `ebool`. Available for all integer types and `eaddress`:

```solidity
ebool isEqual     = FHE.eq(a, b);    // a == b
ebool isNotEqual  = FHE.ne(a, b);    // a != b
ebool isLess      = FHE.lt(a, b);    // a < b
ebool isLessEq    = FHE.lte(a, b);   // a <= b
ebool isGreater   = FHE.gt(a, b);    // a > b
ebool isGreaterEq = FHE.gte(a, b);   // a >= b
```

### Min / Max

```solidity
euint32 lower  = FHE.min(a, b);
euint32 higher = FHE.max(a, b);
```

### Bitwise Operations

Available for all integer types. Boolean versions work on `ebool`:

```solidity
euint32 result = FHE.and(a, b);   // bitwise AND
euint32 result = FHE.or(a, b);    // bitwise OR
euint32 result = FHE.xor(a, b);   // bitwise XOR
euint32 result = FHE.not(a);      // bitwise NOT

// Boolean versions
ebool result = FHE.and(boolA, boolB);
ebool result = FHE.or(boolA, boolB);
ebool result = FHE.not(boolA);
```

### Bit Shifts

```solidity
euint32 result = FHE.shl(a, shift);   // shift left
euint32 result = FHE.shr(a, shift);   // shift right
euint32 result = FHE.rol(a, shift);   // rotate left
euint32 result = FHE.ror(a, shift);   // rotate right
```

### Select (Encrypted Conditional)

The FHE equivalent of a ternary operator. Picks between two values based on an encrypted condition **without revealing the condition**.

```solidity
euint32 result = FHE.select(condition, ifTrue, ifFalse);
```

Works with all encrypted types (`euint*`, `ebool`, `eaddress`):

```solidity
// Real-world pattern: apply fee based on encrypted threshold
ebool isLargeAmount = FHE.gt(amount, threshold);
euint32 fee = FHE.select(isLargeAmount, highFee, lowFee);
euint32 net = FHE.sub(amount, fee);
```

### Decryption (New Flow)

Decryption uses a three-step flow: **permission** (on-chain) → **decrypt** (off-chain) → **publish/verify** (on-chain with proof).

```solidity
// In your contract:

// Step 1: Grant public decryption permission
function allowBalancePublicly() public {
    FHE.allowPublic(balance);
}

// Step 3: Publish verified result on-chain (called after off-chain decryption)
function revealBalance(uint32 plaintext, bytes memory signature) public {
    FHE.publishDecryptResult(balance, plaintext, signature);
}

// Step 4: Read the published result
function getBalance() external view returns (uint256) {
    (uint256 value, bool ready) = FHE.getDecryptResultSafe(balance);
    if (!ready) revert("Not ready");
    return value;
}
```

In production, Step 2 happens off-chain via the client SDK (`client.decryptForTx(ctHash).withoutPermit().execute()`), which returns the decrypted value and a Threshold Network signature.

In tests, use `decryptForTxWithoutPermit()` from `CoFheTest` to simulate the off-chain step:

```solidity
function test_DecryptFlow() public {
    myContract.allowBalancePublicly();

    // Simulate off-chain decryption (client SDK)
    uint256 ctHash = uint256(euint32.unwrap(myContract.balance()));
    (bool allowed, , uint256 plaintext) = decryptForTxWithoutPermit(ctHash);
    assertTrue(allowed);

    // Publish result on-chain
    myContract.revealBalance(uint32(plaintext), "");

    // Read the result
    uint256 result = myContract.getBalance();
    assertEq(result, expectedValue);
}
```

#### publishDecryptResult vs verifyDecryptResult

| Aspect | `publishDecryptResult` | `verifyDecryptResult` |
|--------|------------------------|----------------------|
| **Storage** | Stores result on-chain | No storage |
| **Visibility** | Other contracts can read via `getDecryptResultSafe` | Private to current call |
| **Use case** | Public reveals (auctions, votes, counters) | One-time verification (transfers, burns) |

---

## Access Control (ACL)

Every FHE operation produces a new ciphertext hash. You must explicitly grant permissions on each new hash, or subsequent operations will fail on the real coprocessor.

### FHE.allowThis(value)

Grants the **current contract** (`address(this)`) permission to operate on the encrypted value. Call this after every operation that produces a new ciphertext the contract needs to use later.

```solidity
count = FHE.add(count, ONE);
FHE.allowThis(count);  // contract can use `count` in future operations
```

### FHE.allowSender(value)

Grants `msg.sender` permission to **view/unseal** the encrypted value off-chain. Call this when the caller should be able to decrypt their own data.

```solidity
count = FHE.add(count, ONE);
FHE.allowThis(count);     // contract can operate on it
FHE.allowSender(count);   // caller can unseal it via permit
```

### FHE.allow(value, address)

Grants a **specific address** permission.

```solidity
FHE.allow(secret, auditorAddress);
```

### FHE.allowGlobal(value)

Grants **anyone** permission. Use carefully -- this effectively makes the value public.

```solidity
FHE.allowGlobal(publicResult);
```

### FHE.allowTransient(value, address)

Grants temporary permission that expires at the end of the current transaction. Uses EVM transient storage (`tstore`).

```solidity
FHE.allowTransient(intermediate, helperContract);
```

### Typical Pattern

Every contract function that modifies encrypted state should call both `allowThis` and `allowSender`:

```solidity
function increment() public {
    count = FHE.add(count, ONE);
    FHE.allowThis(count);     // so the contract can use count next time
    FHE.allowSender(count);   // so the caller can unseal count
}
```

---

## CoFheTest Helper Functions

These functions are available in your test contract when you inherit `CoFheTest`.

### assertHashValue -- Assert Encrypted Values

The primary assertion for FHE tests. Checks that the plaintext behind an encrypted value equals the expected value.

**Typed overloads** (recommended -- handles unwrapping automatically):

```solidity
assertHashValue(ebool encrypted,    bool expected);
assertHashValue(euint8 encrypted,   uint8 expected);
assertHashValue(euint16 encrypted,  uint16 expected);
assertHashValue(euint32 encrypted,  uint32 expected);
assertHashValue(euint64 encrypted,  uint64 expected);
assertHashValue(euint128 encrypted, uint128 expected);
assertHashValue(eaddress encrypted, address expected);

// All overloads also accept a custom failure message as third parameter
assertHashValue(euint32 encrypted, uint32 expected, string memory message);
```

**Raw hash overload** (when you already have the hash):

```solidity
assertHashValue(uint256 ctHash, uint256 expected);
```

**Example:**

```solidity
euint32 count = counter.count();
assertHashValue(count, uint32(42));
```

### createInE* -- Creating Encrypted Inputs

Create signed encrypted input structs that simulate a user encrypting a value client-side. The `sender` parameter determines which address the signature is valid for.

```solidity
InEbool    input = createInEbool(true, sender);
InEuint8   input = createInEuint8(255, sender);
InEuint16  input = createInEuint16(1000, sender);
InEuint32  input = createInEuint32(42, sender);
InEuint64  input = createInEuint64(1e12, sender);
InEuint128 input = createInEuint128(val, sender);
InEuint256 input = createInEuint256(val, sender);
InEaddress input = createInEaddress(addr, sender);
```

There are also 3-parameter overloads that accept a `securityZone` (default is 0):

```solidity
InEuint32 input = createInEuint32(42, 0, sender);
```

**Important: msg.sender must match.** When a contract calls `FHE.asEuint32(input)`, the library verifies the input signature against `msg.sender`. Since FHE is a Solidity library (internal calls), `msg.sender` is the address calling the contract externally. You must `vm.prank` as the same address used in `createInE*`:

```solidity
InEuint32 memory encrypted = createInEuint32(2000, bob);
vm.prank(bob);  // msg.sender inside the contract = bob
counter.reset(encrypted);
```

If you call `FHE.asE*()` directly in your test (not through a contract), `msg.sender` is the test contract itself. To test with a different sender, route through a helper contract:

```solidity
contract EncryptedInputHelper {
    function verifyEuint32(InEuint32 memory input) external returns (euint32) {
        return FHE.asEuint32(input);
    }
}

// In test:
InEuint32 memory input = createInEuint32(42, alice);
vm.prank(alice);
euint32 result = helper.verifyEuint32(input);
```

### mockStorage -- Read Plaintext from Mock

Reads the plaintext stored behind an encrypted hash. Useful for low-level verification without going through typed assertions.

```solidity
uint256 ctHash = uint256(euint32.unwrap(counter.count()));
uint256 plaintext = mockStorage(ctHash);
assertEq(plaintext, 42);
```

### inMockStorage -- Check if Hash Exists

Checks whether a ciphertext hash has an entry in the mock storage.

```solidity
euint32 a = FHE.asEuint32(100);
assertTrue(inMockStorage(uint256(euint32.unwrap(a))));
```

### Permission & Permit Helpers

These functions test the off-chain permit flow -- how users prove they have ACL access to unseal encrypted values.

#### createPermissionSelf(address issuer)

Creates a self-permission (user accessing their own data):

```solidity
Permission memory permit = createPermissionSelf(bob);
```

#### createPermissionShared(address issuer, address recipient)

Creates a shared permission (owner sharing access with another party):

```solidity
Permission memory permit = createPermissionShared(bob, alice);
```

#### createSealingKey(uint256 seed)

Creates a sealing key for re-encryption:

```solidity
bytes32 sealingKey = createSealingKey(42);
permit.sealingKey = sealingKey;
```

#### signPermissionSelf(Permission memory, uint256 privateKey)

Signs a self-permission with an EIP-712 signature:

```solidity
Permission memory permit = createPermissionSelf(bob);
permit.sealingKey = createSealingKey(1);
permit = signPermissionSelf(permit, bobKey);
```

#### signPermissionShared / signPermissionRecipient

For shared permissions (two-step signing):

```solidity
Permission memory permit = createPermissionShared(bob, alice);
permit = signPermissionShared(permit, bobKey);       // issuer signs
permit.sealingKey = createSealingKey(1);
permit = signPermissionRecipient(permit, aliceKey);   // recipient signs
```

#### queryDecrypt vs querySealOutput + unseal

Both check ACL permissions, but they simulate different flows:

- **`queryDecrypt`** -- Returns the **raw plaintext** directly. One step, gives you the number.
- **`querySealOutput`** + **`unseal`** -- Two steps. `querySealOutput` returns the value **sealed (re-encrypted)** under the permit's sealing key as an opaque `bytes32`. `unseal` then decrypts it client-side using the matching key.

In production, `queryDecrypt` wouldn't exist -- clients use `querySealOutput` to get a sealed value and decrypt it locally with their private sealing key. Both are available in tests so you can verify ACL permissions using whichever flow your application uses.

#### queryDecrypt(uint256 ctHash, uint256 chainId, Permission memory)

Attempts to decrypt a value using a signed permission. Returns whether the caller has ACL access.

```solidity
(bool allowed, string memory error, uint256 decrypted) = queryDecrypt(
    ctHash,
    block.chainid,
    signedPermit
);
assertTrue(allowed);
assertEq(decrypted, expectedValue);
```

If the address does not have ACL permission:

```solidity
(bool allowed, string memory error, ) = queryDecrypt(ctHash, block.chainid, permit);
assertFalse(allowed);
assertEq(error, "NotAllowed");
```

#### querySealOutput(uint256 ctHash, uint256 chainId, Permission memory)

Seals (re-encrypts) a value under the permit's sealing key. Returns an opaque `bytes32` -- not readable without the key:

```solidity
(bool allowed, , bytes32 sealedValue) = querySealOutput(ctHash, block.chainid, permit);
assertTrue(allowed);
```

#### unseal(bytes32 sealed, bytes32 sealingKey)

Decrypts a sealed value from `querySealOutput` using the corresponding sealing key to get back the plaintext:

```solidity
uint256 plaintext = unseal(sealedValue, sealingKey);
assertEq(plaintext, 1);
```

### decryptForTxWithoutPermit / decryptForTxWithPermit -- Simulate Off-chain Decryption

These simulate the off-chain `client.decryptForTx()` SDK call. They check ACL permissions and return the plaintext from mock storage.

```solidity
// Public decryption (after FHE.allowPublic was called)
(bool allowed, string memory error, uint256 plaintext) = decryptForTxWithoutPermit(ctHash);

// Restricted decryption (after FHE.allow was called for a specific address)
(bool allowed, string memory error, uint256 plaintext) = decryptForTxWithPermit(ctHash, permit);
```

Use these in tests to get the plaintext value before calling `publishDecryptResult` or `verifyDecryptResult` on your contract.

### setLog(bool)

Enable/disable logging of FHE operations for debugging:

```solidity
setLog(true);  // prints FHE operations to console
```

---

## Common Test Patterns

### 1. Basic Operation Test

```solidity
function test_Addition() public {
    euint32 a = FHE.asEuint32(10);
    euint32 b = FHE.asEuint32(20);
    euint32 result = FHE.add(a, b);
    assertHashValue(result, uint32(30));
}
```

### 2. Testing Contract Functions

```solidity
function test_Increment() public {
    assertHashValue(counter.count(), uint32(0));

    vm.prank(bob);
    counter.increment();

    assertHashValue(counter.count(), uint32(1));
}
```

### 3. Encrypted User Input

```solidity
function test_ResetWithEncryptedInput() public {
    InEuint32 memory encrypted = createInEuint32(2000, bob);

    vm.prank(bob);
    counter.reset(encrypted);

    assertHashValue(counter.count(), uint32(2000));
}
```

### 4. On-chain Decryption (New Flow)

```solidity
function test_DecryptFlow() public {
    // Step 1: Allow public decryption
    vm.prank(bob);
    counter.allowCounterPublicly();

    // Before publish: not ready
    vm.expectRevert("Value is not ready");
    counter.getDecryptedValue();

    // Step 2: Simulate off-chain decryption
    uint256 ctHash = uint256(euint32.unwrap(counter.count()));
    (bool allowed, , uint256 plaintext) = decryptForTxWithoutPermit(ctHash);
    assertTrue(allowed);

    // Step 3: Publish result on-chain
    counter.revealCounter(uint32(plaintext), "");

    // Step 4: Read result
    uint256 value = counter.getDecryptedValue();
    assertEq(value, expectedValue);
}
```

### 5. ACL / Permit Verification

Test that only the caller who executed an operation can unseal the result:

```solidity
function test_CallerCanUnseal() public {
    vm.prank(bob);
    counter.increment();

    uint256 ctHash = uint256(euint32.unwrap(counter.count()));

    Permission memory permit = createPermissionSelf(bob);
    permit.sealingKey = createSealingKey(1);
    permit = signPermissionSelf(permit, bobKey);

    (bool allowed, , uint256 decrypted) = queryDecrypt(
        ctHash, block.chainid, permit
    );
    assertTrue(allowed);
    assertEq(decrypted, 1);
}

function test_NonCallerCannotUnseal() public {
    vm.prank(bob);
    counter.increment();

    uint256 ctHash = uint256(euint32.unwrap(counter.count()));

    Permission memory alicePermit = createPermissionSelf(alice);
    alicePermit.sealingKey = createSealingKey(2);
    alicePermit = signPermissionSelf(alicePermit, aliceKey);

    (bool allowed, string memory error, ) = queryDecrypt(
        ctHash, block.chainid, alicePermit
    );
    assertFalse(allowed);
    assertEq(error, "NotAllowed");
}
```

### 6. Seal / Unseal Flow

```solidity
function test_SealAndUnseal() public {
    vm.prank(bob);
    counter.increment();

    uint256 ctHash = uint256(euint32.unwrap(counter.count()));
    bytes32 sealingKey = createSealingKey(42);

    Permission memory permit = createPermissionSelf(bob);
    permit.sealingKey = sealingKey;
    permit = signPermissionSelf(permit, bobKey);

    (bool allowed, , bytes32 sealedValue) = querySealOutput(
        ctHash, block.chainid, permit
    );
    assertTrue(allowed);

    uint256 plaintext = unseal(sealedValue, sealingKey);
    assertEq(plaintext, 1);
}
```

### 7. Fuzz Testing

```solidity
function testFuzz_Add(uint32 a, uint32 b) public {
    vm.assume(uint64(a) + uint64(b) <= type(uint32).max);
    euint32 ea = FHE.asEuint32(a);
    euint32 eb = FHE.asEuint32(b);
    euint32 result = FHE.add(ea, eb);
    assertHashValue(result, a + b);
}
```

### 8. Low-level Mock Storage Inspection

```solidity
function test_InspectStorage() public {
    euint32 a = FHE.asEuint32(111);
    euint32 b = FHE.asEuint32(222);
    euint32 c = FHE.add(a, b);

    assertTrue(inMockStorage(uint256(euint32.unwrap(c))));
    assertEq(mockStorage(uint256(euint32.unwrap(c))), 333);
}
```

---

## ACL Enforcement in the Mock

The mock **does enforce ACL** on FHE operation inputs. Every FHE operation (`add`, `sub`, `mul`, etc.) goes through `MockTaskManager.createTask()`, which calls `checkAllowed()` on each input ciphertext hash:

```
Contract calls FHE.add(a, b)
  → Impl.mathOp() calls ITaskManager.createTask(...)
    → validateEncryptedHashes() loops over inputs
      → checkAllowed(ctHash):
          if NOT trivially encrypted AND NOT allowed → revert ACLNotAllowed
```

**Trivially encrypted values** (created via `FHE.asEuint32(plaintext)`) skip the ACL check -- they are public constants and always allowed. But **operation results** (from `FHE.add`, `FHE.sub`, etc.) are not trivially encrypted, so they require ACL permission.

This means if a contract forgets to call `FHE.allowThis()` on an operation result, the next operation using that result will revert with `ACLNotAllowed(ctHash, sender)`.

### What can be tested

| Check | How to test |
|-------|------------|
| Contract has permission to operate | Forget `FHE.allowThis()` on a result, then use it in another operation -- should revert with `ACLNotAllowed` |
| Caller can unseal a value | Use `queryDecrypt()` or `querySealOutput()` with a signed permit -- returns `allowed = true` |
| Unauthorized address cannot unseal | Same flow with a different address -- returns `allowed = false, error = "NotAllowed"` |
| Permission transfers on new operation | After a new caller executes an operation, only they can unseal the new result |
| Global permissions | Call `FHE.allowGlobal()` -- any address can then unseal |
| Transient permissions | Call `FHE.allowTransient()` -- permission only lasts for the current transaction |

### Testing ACL reverts

You can verify that missing permissions cause reverts:

```solidity
function test_RevertWithoutAllowThis() public {
    // Create a value and deliberately skip allowThis
    euint32 a = FHE.asEuint32(10);  // trivially encrypted, always allowed
    euint32 b = FHE.asEuint32(5);
    euint32 result = FHE.add(a, b); // result is NOT trivially encrypted
    // FHE.allowThis(result);       // <-- deliberately skipped

    // Using `result` in another operation should revert
    // because the contract doesn't have ACL permission on it
    vm.expectRevert();
    FHE.add(result, a);
}
```

> **Note:** This only applies to non-trivially encrypted values. `FHE.asEuint32(plaintext)` always passes the ACL check regardless of permissions.

---

## Mock Limitations

The mock contracts simulate FHE behavior deterministically for testing. Be aware of these differences from the real coprocessor:

| Operation | Mock behavior | Real coprocessor |
|-----------|--------------|-----------------|
| `FHE.not(value)` | Boolean NOT (`value == 1 ? 0 : 1`) | Bitwise NOT |
| `FHE.rol(a, b)` | Simple shift left (no wrap) | True bit rotation |
| `FHE.ror(a, b)` | Simple shift right (no wrap) | True bit rotation |
| Decryption | `decryptResultSigner` defaults to `address(0)`, so any signature (including empty `""`) is accepted | Requires valid Threshold Network signature |
| Trivially encrypted ACL | Skipped (always allowed) | Same behavior |
