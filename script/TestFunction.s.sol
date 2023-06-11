// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Notary.sol";
import "../src/Portfolio.sol";
import "../src/Coin.sol";
import "../src/Vault.sol";
import {WeightProvider} from "../src/WeightProvider.sol";
import {FunctionsBillingRegistry} from "../src/dev/functions/FunctionsBillingRegistry.sol";
import {IERC1363} from "lib/openzeppelin-contracts/contracts/interfaces/IERC1363.sol";

// Sepolia
contract DeployProtocol is Script {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        address wpAddress = 0x3D01BE50fB2f399EF01A8cB60AA6De174f91fCd2;

        // Functions

        WeightProvider weightProvider = WeightProvider(0x3D01BE50fB2f399EF01A8cB60AA6De174f91fCd2);
        weightProvider.executeRequest();

        vm.stopBroadcast();
    }
}
