// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MyToken.sol";

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast();
        new MyToken("MyToken", "MTK", 1_000_000e18);
        vm.stopBroadcast();
    }
}