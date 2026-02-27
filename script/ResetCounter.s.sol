// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Counter} from "../src/Counter.sol";
import {InEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

// Reset the Counter to a new encrypted value.
//
// On testnets, creating a valid InEuint32 requires the cofhe/sdk JavaScript library
// to generate the ZK proof and signature. This script accepts pre-computed encrypted input
// components via environment variables.
//
// For local testing, use the test suite instead (test/Counter.t.sol) which uses mock helpers.
//
// Usage on testnet:
//   1. Use the cofhe/sdk to generate encrypted input components off-chain
//   2. Pass them as env vars: CT_HASH, SECURITY_ZONE, UTYPE, SIGNATURE
//   3. Run: forge script script/ResetCounter.s.sol --rpc-url <network> --broadcast
contract ResetCounter is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address counterAddress = vm.envAddress("COUNTER_ADDRESS");

        // Read pre-computed encrypted input components
        uint256 ctHash = vm.envUint("CT_HASH");
        uint8 securityZone = uint8(vm.envUint("SECURITY_ZONE"));
        uint8 utype = uint8(vm.envUint("UTYPE"));
        bytes memory signature = vm.envBytes("SIGNATURE");

        InEuint32 memory encryptedValue = InEuint32({
            ctHash: ctHash,
            securityZone: securityZone,
            utype: utype,
            signature: signature
        });

        Counter counter = Counter(counterAddress);

        vm.startBroadcast(deployerPrivateKey);
        counter.reset(encryptedValue);
        vm.stopBroadcast();

        console.log("Counter reset successfully");
    }
}
