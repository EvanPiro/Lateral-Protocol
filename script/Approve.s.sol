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
contract Approve is Script {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        IERC20 usdt = IERC20(0x6175a8471C2122f778445e7E07A164250a19E661);
        IERC20 dai = IERC20(0x7AF17A48a6336F7dc1beF9D485139f7B6f4FB5C8);
        IERC20 link = IERC20(0x779877A7B0D9E8603169DdbD7836e478b4624789);
        usdt.approve(
            0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008,
            100 * 10 ** 18
        );
        // usdt.approve(
        //     0xd0bBD6eD1f18D92e70Ca4A478F191f8150e8a536,
        //     100 * 10 ** 18
        // );
        // Vault vault = Vault(0xd0bBD6eD1f18D92e70Ca4A478F191f8150e8a536);
        // vault.addOneCollateral(
        //     0x6175a8471C2122f778445e7E07A164250a19E661,
        //     1000000000000000000,
        //     18,
        //     0xAb5c49580294Aff77670F839ea425f5b78ab3Ae7,
        //     "USD"
        // );
        link.approve(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008, 20 * 10 ** 18);
        dai.approve(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008, 100 * 10 ** 18);

        vm.stopBroadcast();
    }
}
