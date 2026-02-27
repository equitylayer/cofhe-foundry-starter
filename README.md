# CoFHE Foundry Starter

A starter template for developing Fully Homomorphic Encryption (FHE) smart contracts using [Fhenix CoFHE](https://www.fhenix.io/) and [Foundry](https://getfoundry.sh/).

## Prerequisites

- [Foundry](https://getfoundry.sh/) (`forge`, `cast`, `anvil`)
- [Node.js](https://nodejs.org/) (v18+) and npm

## Quick Start

```bash
# Clone the repository
git clone <repo-url>
cd cofhe-foundry-starter

# Install Solidity dependencies
npm install

# Compile contracts
forge build

# Run tests
forge test -vvv
```

## Project Structure

```
├── src/
│   └── Counter.sol           # Example FHE counter contract
├── test/
│   └── Counter.t.sol         # Comprehensive Solidity tests
├── script/
│   ├── DeployCounter.s.sol   # Deployment script
│   ├── IncrementCounter.s.sol # Increment interaction
│   └── ResetCounter.s.sol    # Reset with encrypted input
├── foundry.toml              # Foundry configuration
├── package.json              # npm dependencies
└── remappings.txt            # Solidity import remappings
```

## How FHE Testing Works

Tests use `CoFheTest` from `@cofhe/mock-contracts`, which provides:

- **Mock contract deployment** at fixed addresses (MockTaskManager, MockACL, etc.)
- **Encrypted input creation** via `createInEuint32(value, sender)` — no JS SDK needed
- **Plaintext assertions** via `assertHashValue(encryptedValue, expectedPlaintext)`
- **Permission testing** via `createPermissionSelf()` and `signPermissionSelf()`

The mock system stores plaintext behind ciphertext hashes, enabling deterministic testing entirely in Solidity.

### Example Test

```solidity
function test_ShouldIncrementTheCounter() public {
    // Initial count should be 0
    assertHashValue(counter.count(), uint32(0));

    // Increment as bob
    vm.prank(bob);
    counter.increment();

    // Count should be 1
    assertHashValue(counter.count(), uint32(1));
}
```

## FHE Operations

The `Counter.sol` contract demonstrates these FHE operations:

| Operation | Description |
|-----------|-------------|
| `FHE.asEuint32(value)` | Create encrypted uint32 from plaintext |
| `FHE.add(a, b)` | Encrypted addition |
| `FHE.sub(a, b)` | Encrypted subtraction |
| `FHE.gte(a, b)` | Encrypted greater-than-or-equal |
| `FHE.allowThis(value)` | Grant this contract access to value |
| `FHE.allowSender(value)` | Grant msg.sender access to value |
| `FHE.decrypt(value)` | Request on-chain decryption (async) |
| `FHE.getDecryptResultSafe(value)` | Retrieve decryption result |

## Deployment

### Setup

```bash
cp .env.example .env
# Edit .env with your private key and RPC URLs
```

### Deploy to Testnet

```bash
# Ethereum Sepolia
npm run deploy:eth-sepolia

# Arbitrum Sepolia
npm run deploy:arb-sepolia

# Base Sepolia
npm run deploy:base-sepolia
```

### Interact with Deployed Contract

```bash
# Set the deployed contract address
export COUNTER_ADDRESS=0x...

# Increment the counter
source .env && forge script script/IncrementCounter.s.sol --rpc-url eth-sepolia --broadcast
```

## Gas Report

```bash
npm run test:gas
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `@fhenixprotocol/cofhe-contracts` | FHE type definitions and operations (FHE.sol) |
| `@cofhe/mock-contracts` | Mock contracts for local testing + Foundry helpers |
| `@openzeppelin/contracts` | Standard contract utilities |
| `forge-std` | Foundry standard library (Test, Script, cheatcodes) |

## Configuration Notes

- **EVM Version**: `cancun` — required for MockACL's transient storage (`tstore`/`tload`)
- **Code Size Limit**: `100000` — mock contracts exceed the default 24KB limit
- **Solidity Version**: `0.8.25` — compatible with CoFHE contracts

## Resources

- [Fhenix Documentation](https://docs.fhenix.zone/)
- [Foundry Book](https://book.getfoundry.sh/)
- [CoFHE Contracts](https://github.com/FhenixProtocol/cofhe-contracts)
