// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Counter} from "../src/Counter.sol";
import {euint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

contract IncrementCounter is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address counterAddress = vm.envAddress("COUNTER_ADDRESS");

        Counter counter = Counter(counterAddress);

        vm.startBroadcast(deployerPrivateKey);
        counter.increment();
        vm.stopBroadcast();

        console.log("Counter incremented. New count hash:", uint256(euint32.unwrap(counter.count())));
    }
}
