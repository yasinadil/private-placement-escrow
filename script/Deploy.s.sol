// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {InvestmentFactory} from "../src/InvestmentFactory.sol";
import {InvestmentHelper} from "../src/InvestmentHelper.sol";
import {RestrictedToken} from "../src/RestrictedToken.sol";

/// Usage:
///   DEPLOYER=<addr> ADMIN=<multisig> forge script script/Deploy.s.sol --rpc-url $RPC_URL --account <keystore> --broadcast
contract Deploy is Script {
    function run() external returns (RestrictedToken token, InvestmentFactory factory, InvestmentHelper helper) {
        address deployer = vm.envAddress("DEPLOYER");
        address admin = vm.envAddress("ADMIN");

        vm.startBroadcast();
        token = new RestrictedToken(deployer);
        token.setAdmin(admin);
        factory = new InvestmentFactory(admin, address(token));
        token.setFactoryContract(address(factory));
        helper = new InvestmentHelper(address(token));
        token.transferOwnership(admin);
        vm.stopBroadcast();

        console.log("RestrictedToken  ", address(token));
        console.log("InvestmentFactory", address(factory));
        console.log("InvestmentHelper ", address(helper));
    }
}
