// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Notary.sol";
import "../src/Portfolio.sol";
import "../src/Coin.sol";


// Sepolia
contract DeployProtocol is Script {
    function run() external {

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        address uniswapV2Router = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
        address priceFeedBenchmark = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

        uint256 minRatio = 100;

        vm.startBroadcast(deployerPrivateKey);

        Notary notary = new Notary(minRatio);
        address notaryAddress = address(notary);
        Coin coin = new Coin(address(notary));
        Portfolio portfolio = new Portfolio(uniswapV2Router, notaryAddress);
        notary.activate(address(coin), address(portfolio));

        vm.stopBroadcast();
    }
}
