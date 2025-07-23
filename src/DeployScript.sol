// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/BlockForgeBounties.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address bobaTokenAddress = vm.envAddress("BOBA_TOKEN_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        BlockForgeBounties bounties = new BlockForgeBounties(bobaTokenAddress);

        vm.stopBroadcast();
    }
}