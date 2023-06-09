// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Notary.sol";
import "../src/Portfolio.sol";
import "../src/Coin.sol";
import "../src/Vault.sol";

// Sepolia
contract DeployProtocol is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        address uniswapV2Router = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
        address priceFeedBenchmark = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        uint256 minRatio = 100;
        address WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
        IERC20 weth = IERC20(WETH);
        uint256 amountToMint1 = 10 ** 18;

        vm.startBroadcast(deployerPrivateKey);

        Notary notary = new Notary(minRatio);
        address notaryAddress = address(notary);
        Coin coin = new Coin(address(notary));
        Portfolio portfolio = new Portfolio(uniswapV2Router, notaryAddress);
        notary.activate(address(coin), address(portfolio));
        Vault vault = Vault(notary.openVault(priceFeedBenchmark));

        weth.approve(address(vault), amountToMint1);
        coin.approve(address(vault), amountToMint1 * 10);

        vm.stopBroadcast();
    }
}
