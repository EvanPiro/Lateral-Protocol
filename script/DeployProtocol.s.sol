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

    address linkTokenAddress = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address linkPriceFeedAddress = 0x42585eD362B3f1BCa95c640FdFf35Ef899212734;
    address functionsOracleProxyAddress =
        0x649a2C205BE7A3d5e99206CEEFF30c794f0E31EC;
    address registryProxyAddress = 0x3c79f56407DCB9dc9b852D139a317246f43750Cc;

    address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address uniswapV2Router = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    address priceFeedBenchmark = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    uint256 minRatio = 100;

    address WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address LINK = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address[] _assetsAddress = [WETH, LINK];
    uint256[] _targetWeights = [50, 50];
    uint8[] _decimals = [18, 18];
    address constant ETHUSD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant LINKETH = 0x42585eD362B3f1BCa95c640FdFf35Ef899212734;
    AggregatorV3Interface private priceFeedEthUsd =
        AggregatorV3Interface(ETHUSD);
    AggregatorV3Interface private priceFeedLinkEth =
        AggregatorV3Interface(LINKETH);
    AggregatorV3Interface[] _priceFeeds = [priceFeedEthUsd, priceFeedLinkEth];
    string[] _baseCurrencies = ["USD", "ETH"];

    function run() external {
        IERC20 weth = IERC20(WETH);
        IERC20 link = IERC20(0x779877A7B0D9E8603169DdbD7836e478b4624789);
        IERC20 usdt = IERC20(0x6175a8471C2122f778445e7E07A164250a19E661);
        IERC20 dai = IERC20(0x7AF17A48a6336F7dc1beF9D485139f7B6f4FB5C8);
        uint256 amountToMint1 = 10 ** 18 * 1000;

        vm.startBroadcast(deployerPrivateKey);

        Notary notary = new Notary(WETH, 3000);
        address notaryAddress = address(notary);

        Coin coin = new Coin(address(notary));
        address coinAddress = address(coin);

        Portfolio portfolio = new Portfolio(uniswapV2Router, notaryAddress);
        address portfolioAddress = address(portfolio);

        WeightProvider weightProvider = new WeightProvider(
            functionsOracleProxyAddress,
            address(notary),
            wethAddress
        );
        address weightProviderAddress = address(weightProvider);

        notary.activate(coinAddress, portfolioAddress, weightProviderAddress);
        Vault vault = Vault(notary.openVault(priceFeedBenchmark));

        weth.approve(address(vault), amountToMint1);
        link.approve(address(vault), amountToMint1);
        dai.approve(address(vault), amountToMint1);
        usdt.approve(address(vault), amountToMint1);
        coin.approve(address(vault), amountToMint1);

        notary.updateAssets(
            _assetsAddress,
            _targetWeights,
            _decimals,
            _priceFeeds,
            _baseCurrencies
        );

        // Functions

        // WeightProvider weightProvider = new WeightProvider(
        //     functionsOracleProxyAddress,
        //     address(1111),
        //     wethAddress
        // );
        // address weightProviderAddress = address(weightProvider);

        // FunctionsBillingRegistry registry = FunctionsBillingRegistry(
        //     registryProxyAddress
        // );
        // uint64 subId = registry.createSubscription();

        // IERC1363 linkToken = IERC1363(linkTokenAddress);

        // console.log(linkToken.balanceOf(deployerAddress));

        // linkToken.transferAndCall(
        //     deployerAddress,
        //     10 ether,
        //     abi.encodePacked(subId)
        // );
        // console.log(subId);
        // registry.addConsumer(subId, weightProviderAddress);
        // weightProvider.setSubId(subId);
        // weightProvider.executeRequest{gas: 1000000}();

        vm.stopBroadcast();
    }
}
