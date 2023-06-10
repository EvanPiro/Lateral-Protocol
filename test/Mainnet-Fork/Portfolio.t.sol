// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/Vault.sol";
import "../../src/WeightProvider.sol";
// import "../src/UniswapV3Examples.sol";

address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
address constant PAXG = 0x45804880De22913dAFE09f4980848ECE6EcbAf78;
address constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
address constant router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
address constant ROUTERV02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

address constant ETHUSD = 0xb49f677943BC038e9857d61E7d053CaA2C1734C1;
address constant DAIETH = 0x773616E4d11A78F511299002da57A0a94577F1f4;
address constant USDCETH = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;
address constant BTCETH = 0xdeb288F737066589598e9214E782fa5A8eD689e8;
address constant PAXGETH = 0x9B97304EA12EFed0FAd976FBeCAad46016bf269e;
address constant LINKETH = 0xDC530D9457755926550b59e8ECcdaE7624181557;

uint8 constant WETHdecimals = 18;
uint8 constant DAIdecimals = 18;
uint8 constant USDCdecimals = 6;
uint8 constant WBTCdecimals = 8;
uint8 constant PAXGdecimals = 18;
uint8 constant LINKdecimals = 18;

contract UniV3Test is Test {
    IERC20 private weth = IERC20(WETH);
    IERC20 private dai = IERC20(DAI);
    IERC20 private wbtc = IERC20(WBTC);
    IERC20 private usdc = IERC20(USDC);
    IERC20 private paxg = IERC20(PAXG);
    IERC20 private link = IERC20(LINK);

    AggregatorV3Interface private priceFeedEthUsd =
        AggregatorV3Interface(ETHUSD);
    AggregatorV3Interface private priceFeedDaiEth =
        AggregatorV3Interface(DAIETH);
    AggregatorV3Interface private priceFeedBtcEth =
        AggregatorV3Interface(BTCETH);
    AggregatorV3Interface private priceFeedUsdEth =
        AggregatorV3Interface(USDCETH);
    AggregatorV3Interface private priceFeedPaxGeth =
        AggregatorV3Interface(PAXGETH);
    AggregatorV3Interface private priceFeedLinkEth =
        AggregatorV3Interface(LINKETH);

    address[] _assetsAddress = [PAXG, USDC, WBTC];
    uint256[] _targetWeights = [40, 40, 20];
    uint8[] _decimals = [PAXGdecimals, USDCdecimals, WBTCdecimals];
    AggregatorV3Interface[] _priceFeeds = [
        priceFeedPaxGeth,
        priceFeedUsdEth,
        priceFeedBtcEth
    ];

    string[] _baseCurrencies = ["ETH", "ETH", "ETH"];

    uint256 public constant INITIAL_DEPOSIT = 100;
    uint256 public constant RATIO = 150;
    Vault public vault;

    uint256 public amountToMint1;
    uint256 public amountToMint2;
    uint256 public amountToMint3;
    Notary notary;

    function setUp() public {
        vm.startPrank(address(1));
        // @Todo deploy mock oracle
        address functionsOracleAddress = address(111);

        // @Todo set up mock functionsOracleProxyAddress contract
        notary = new Notary(WETH, 3000);
        Coin coin = new Coin(address(notary));
        Portfolio portfolio = new Portfolio(ROUTERV02, address(notary));
        WeightProvider weightProvider = new WeightProvider(
            functionsOracleAddress,
            address(notary),
            WETH
        );

        notary.activate(
            address(coin),
            address(portfolio),
            address(weightProvider)
        );
        vault = Vault(notary.openVault(ETHUSD));

        console.log("Vault created!");

        amountToMint1 = 100 * 10 ** WETHdecimals;
        amountToMint2 = 100 * 10 ** DAIdecimals;
        amountToMint3 = 100 * 10 ** LINKdecimals;
        deal(WETH, address(1), amountToMint1);
        deal(DAI, address(1), amountToMint2);
        deal(LINK, address(1), amountToMint3);

        weth.approve(address(vault), amountToMint1);
        dai.approve(address(vault), amountToMint2);
        link.approve(address(vault), amountToMint3);

        vault.addOneCollateral(
            address(weth),
            amountToMint1,
            WETHdecimals,
            address(priceFeedEthUsd),
            "USD"
        );
        vault.addOneCollateral(
            address(dai),
            amountToMint2,
            DAIdecimals,
            address(priceFeedDaiEth),
            "ETH"
        );
        vault.addOneCollateral(
            address(link),
            amountToMint3,
            LINKdecimals,
            address(priceFeedLinkEth),
            "ETH"
        );

        vault.updateStrategy(2);

        // portfolio.updateAssets(
        //     _assetsAddress,
        //     _targetWeights,
        //     _decimals,
        //     _priceFeeds
        // );
    }

    function testupdateCollateralPortfolio() public {
        notary.updateAssets(
            _assetsAddress,
            _targetWeights,
            _decimals,
            _priceFeeds,
            _baseCurrencies
        );
        notary.updatePortfolio();
        address receiver = address(1);
        // vault.updateCollateralPortfolio(WETH, 3000);
        console.log(address(vault.getTokens(receiver)[0]));
        console.log(vault.getWeights(vault.getTokens(receiver)[0], receiver));
        console.log(vault.getAmounts(vault.getTokens(receiver)[0], receiver));
        console.log(vault.getDecimals(vault.getTokens(receiver)[0], receiver));
        //console.log(vault.getPriceFeeds(vault.getTokens()[0]));
        console.log("--");
        console.log(address(vault.getTokens(receiver)[1]));
        console.log(vault.getWeights(vault.getTokens(receiver)[1], receiver));
        console.log(vault.getAmounts(vault.getTokens(receiver)[1], receiver));
        console.log(vault.getDecimals(vault.getTokens(receiver)[1], receiver));
        console.log("--");
        console.log(address(vault.getTokens(receiver)[2]));
        console.log(vault.getWeights(vault.getTokens(receiver)[2], receiver));
        console.log(vault.getAmounts(vault.getTokens(receiver)[2], receiver));
        console.log(vault.getDecimals(vault.getTokens(receiver)[2], receiver));

        // console.log("------");
        // console.log(address(vault.getTokens(receiver)[3]));
        // console.log(vault.getWeights(vault.getTokens(receiver)[3], receiver));
        // console.log(vault.getAmounts(vault.getTokens(receiver)[3], receiver));
        // console.log(vault.getDecimals(vault.getTokens(receiver)[3], receiver));

        // console.log("------");
        // console.log(address(vault.getTokens()[4]));
        // console.log(vault.getWeights(vault.getTokens()[4]));
        // console.log(vault.getAmounts(vault.getTokens()[4]));
        // console.log(vault.getDecimals(vault.getTokens()[4]));

        // console.log("------");
        // console.log(address(vault.getTokens()[5]));
        // console.log(vault.getWeights(vault.getTokens()[5]));
        // console.log(vault.getAmounts(vault.getTokens()[5]));
        // console.log(vault.getDecimals(vault.getTokens()[5]));

        // console.log("------");
        // console.log(address(vault.getTokens()[6]));
        // console.log(vault.getWeights(vault.getTokens()[6]));
        // console.log(vault.getAmounts(vault.getTokens()[6]));
        // console.log(vault.getDecimals(vault.getTokens()[6]));
    }
}
