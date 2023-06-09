// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Notary.sol";
import "../src/Portfolio.sol";
import "../src/Coin.sol";
import "../src/Vault.sol";
import { WeightProvider } from "../src/WeightProvider.sol";

// Sepolia
contract DeployProtocol is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        address linkTokenAddress = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
        address linkPriceFeedAddress = 0x42585eD362B3f1BCa95c640FdFf35Ef899212734;
        address functionsOracleProxyAddress = 0x649a2C205BE7A3d5e99206CEEFF30c794f0E31EC;
        address functionsBillingRegistryProxyAddress = 0x3c79f56407DCB9dc9b852D139a317246f43750Cc;

        address uniswapV2Router = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
        address priceFeedBenchmark = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        uint256 minRatio = 100;

        vm.startBroadcast(deployerPrivateKey);

        Notary notary = new Notary(minRatio);
        address notaryAddress = address(notary);

        Coin coin = new Coin(address(notary));
        address coinAddress = address(coin);

        Portfolio portfolio = new Portfolio(uniswapV2Router, notaryAddress);
        address portfolioAddress = address(portfolio);

        WeightProvider weightProvider = new WeightProvider(functionsOracleProxyAddress, address(notary));

        address weightProviderAddress = address(weightProvider);

        notary.activate(coinAddress, portfolioAddress, weightProviderAddress);
        Vault vault = Vault(notary.openVault(priceFeedBenchmark));

        vm.stopBroadcast();
    }
}
