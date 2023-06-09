// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../Mocks/MockERC20.sol";
import "../Mocks/MockV3Aggregator.sol";
import "../../src/Vault.sol";
import "../../src/Notary.sol";
import {WeightProvider} from "../../src/WeightProvider.sol";

contract VaultTest is Test {
    MockERC20 private mockToken1;
    MockERC20 private mockToken2;
    MockERC20 private mockToken3;
    AggregatorV3Interface private mockPriceFeed1;
    AggregatorV3Interface private mockPriceFeed2;
    AggregatorV3Interface private mockPriceFeed3;
    AggregatorV3Interface private mockPriceFeedETHUSD;
    Vault private vault;
    uint256 public constant INITIAL_DEPOSIT = 100;
    uint256 public constant RATIO = 150;
    Notary notary;
    Coin coin;
    Portfolio portfolio;
    IERC20[] public tokens;
    uint256 public amountToMint1;
    uint256 public amountToMint2;
    uint256 public amountToMint3;

    struct Variables {
        uint256 balanceCoinUserBefore;
        uint256 balanceCoinNotaryBefore;
        uint256 balanceCoinVaultBefore;
        uint256 balanceCoin1UserBefore;
        uint256 balanceCoin2UserBefore;
        uint256 balanceCoin3UserBefore;
        uint256 balanceCoin1VaultBefore;
        uint256 balanceCoin2VaultBefore;
        uint256 balanceCoin3VaultBefore;
        uint256 balanceCoinUserAfter;
        uint256 balanceCoinNotaryAfter;
        uint256 balanceCoinVaultAfter;
        uint256 balanceCoin1UserAfter;
        uint256 balanceCoin2UserAfter;
        uint256 balanceCoin3UserAfter;
        uint256 balanceCoin1NotaryAfter;
        uint256 balanceCoin2NotaryAfter;
        uint256 balanceCoin3NotaryAfter;
        uint256 balanceCoin1VaultAfter;
        uint256 balanceCoin2VaultAfter;
        uint256 balanceCoin3VaultAfter;
    }

    function setUp() public {
        mockToken1 = new MockERC20();
        mockToken2 = new MockERC20();
        mockToken3 = new MockERC20();
        mockPriceFeed1 = new MockV3Aggregator(8, 100000000);
        mockPriceFeed2 = new MockV3Aggregator(8, 200000000);
        mockPriceFeed3 = new MockV3Aggregator(8, 300000000);
        mockPriceFeedETHUSD = new MockV3Aggregator(8, 100000000);

        tokens = new IERC20[](3);
        tokens[0] = mockToken1;
        tokens[1] = mockToken2;
        tokens[2] = mockToken3;

        uint256[] memory weights = new uint256[](3);
        weights[0] = 30;
        weights[1] = 30;
        weights[2] = 40;

        uint8[] memory decimals = new uint8[](3);
        decimals[0] = 6;
        decimals[1] = 10;
        decimals[2] = 18;

        AggregatorV3Interface[] memory priceFeeds = new AggregatorV3Interface[](
            3
        );
        priceFeeds[0] = mockPriceFeed1;
        priceFeeds[1] = mockPriceFeed2;
        priceFeeds[2] = mockPriceFeed3;

        address functionsOracleAddress = address(111);

        vm.startPrank(address(1));

        // @Todo set up mock functionsOracleProxyAddress contract
        notary = new Notary(RATIO);
        coin = new Coin(address(notary));
        address router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        address ROUTERV02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        portfolio = new Portfolio(
            // router,
            ROUTERV02,
            address(notary)
        );

        WeightProvider weightProvider = new WeightProvider(functionsOracleAddress, address(notary));

        notary.activate(address(coin), address(portfolio), address(weightProvider));
        vault = Vault(notary.openVault(address(mockPriceFeedETHUSD)));
        console.log(address(notary));
        console.log("Vault created!");

        amountToMint1 = 100 * 10 ** decimals[0];
        amountToMint2 = 100 * 10 ** decimals[1];
        amountToMint3 = 100 * 10 ** decimals[2];
        mockToken1.mint(address(1), amountToMint1);
        mockToken2.mint(address(1), amountToMint2);
        mockToken3.mint(address(1), amountToMint3);

        mockToken1.approve(address(vault), INITIAL_DEPOSIT * 10 ** decimals[0]);
        mockToken2.approve(address(vault), INITIAL_DEPOSIT * 10 ** decimals[1]);
        mockToken3.approve(address(vault), INITIAL_DEPOSIT * 10 ** decimals[2]);

        vault.addOneCollateral(
            address(mockToken1), INITIAL_DEPOSIT * 10 ** decimals[0], decimals[0], address(priceFeeds[0]), "ETH"
        );
        vault.addOneCollateral(
            address(mockToken2), INITIAL_DEPOSIT * 10 ** decimals[1], decimals[1], address(priceFeeds[1]), "ETH"
        );
        vault.addOneCollateral(
            address(mockToken3), INITIAL_DEPOSIT * 10 ** decimals[2], decimals[2], address(priceFeeds[2]), "ETH"
        );
    }

    function testCalculateCollateralTotalAmount() public {
        uint256 stablecoinAmount = 100 * 1e18;
        uint256 ratio = 150;
        uint256 expectedCollateralTotal = ((stablecoinAmount * ratio) / 100);
        uint256 collateralTotal = vault.calculateCollateralTotalAmountInDecimals(stablecoinAmount);
        assertEq(collateralTotal, expectedCollateralTotal);
    }

    function testCanTake() public {
        uint256 moreDebt = 100 * 1e18;
        bool canTakeDebt = vault.canTake(address(1), moreDebt);
        assertTrue(canTakeDebt);
    }

    function testCanNotTake() public {
        uint256 moreDebt = 15000 * 1e18;
        bool canTakeDebt = vault.canTake(address(1), moreDebt);
        assertFalse(canTakeDebt);
    }

    function testTake() public {
        uint256 moreDebt = 150 * 1e18;
        address receiver = address(1);
        coin.approve(address(vault), moreDebt);
        vault.take(moreDebt);
        uint256 debt = vault.getDebt(receiver);
        uint256 balance = coin.balanceOf(receiver);
        assertEq(debt, moreDebt);
        assertEq(balance, moreDebt);
    }

    function testPayDebt() public {
        uint256 moreDebt = 150 * 1e18;
        address receiver = address(1);
        coin.approve(address(vault), moreDebt);
        vault.take(moreDebt);
        uint256 balanceBefore = coin.balanceOf(receiver);
        vault.payDebt((moreDebt * 50) / 100);
        uint256 debt = vault.getDebt(receiver);
        uint256 balanceAfter = coin.balanceOf(receiver);
        assertEq(debt, moreDebt / 2);
        assertEq(balanceAfter, balanceBefore / 2);
    }

    function testretrieveCollateral() public {
        address receiver = address(1);
        address tokAddress = address(mockToken1);
        uint256 tokAmount = vault.getAmounts(mockToken1, receiver) / 3;
        uint256 weightBefore = vault.getWeights(mockToken1, receiver);
        uint256 amountBefore = vault.getAmounts(mockToken1, receiver);
        console.log(weightBefore);

        vault.retrieveCollateral(tokAddress, tokAmount);
        uint256 weightAfter = vault.getWeights(mockToken1, receiver);
        uint256 amountAfter = vault.getAmounts(mockToken1, receiver);
        console.log(weightAfter);

        assertTrue(weightBefore > weightAfter);
        assertTrue(amountBefore > amountAfter);
    }

    function testRetrieve() public {
        uint256 moreDebt = 150 * 1e18;
        address receiver = address(1);
        coin.approve(address(vault), moreDebt);
        vault.take(moreDebt);
        uint256 tokAmountVBefore = vault.getAmounts(mockToken1, receiver);
        uint256 tokAmountUBefore = mockToken1.balanceOf(receiver);

        vault.RetrieveAll();
        uint256 tokAmountVAfter = vault.getAmounts(mockToken1, receiver);
        uint256 tokAmountUAfter = mockToken1.balanceOf(receiver);

        assertEq(tokAmountUAfter, tokAmountVBefore);
        assertEq(tokAmountVAfter, tokAmountUBefore);
    }

    function testliquidate() public {
        uint256 moreDebt = 100 * 1e18;
        address receiver = address(1);
        coin.approve(address(vault), moreDebt);
        vault.take(moreDebt);
        Variables memory T;

        T.balanceCoinUserBefore = coin.balanceOf(receiver);
        T.balanceCoinNotaryBefore = coin.balanceOf(address(notary));
        T.balanceCoinVaultBefore = coin.balanceOf(address(vault));

        T.balanceCoin1UserBefore = tokens[0].balanceOf(receiver);
        T.balanceCoin2UserBefore = tokens[1].balanceOf(receiver);
        T.balanceCoin3UserBefore = tokens[2].balanceOf(receiver);

        T.balanceCoin1VaultBefore = tokens[0].balanceOf(address(vault));
        T.balanceCoin2VaultBefore = tokens[1].balanceOf(address(vault));
        T.balanceCoin3VaultBefore = tokens[2].balanceOf(address(vault));

//        notary.liquidateVaults();
        // vault.liquidate(address(1));

        T.balanceCoinUserAfter = coin.balanceOf(receiver);
        T.balanceCoinNotaryAfter = coin.balanceOf(address(notary));
        T.balanceCoinVaultAfter = coin.balanceOf(address(vault));

        T.balanceCoin1UserAfter = tokens[0].balanceOf(receiver);
        T.balanceCoin2UserAfter = tokens[1].balanceOf(receiver);
        T.balanceCoin3UserAfter = tokens[2].balanceOf(receiver);

        T.balanceCoin1NotaryAfter = tokens[0].balanceOf(address(notary));
        T.balanceCoin2NotaryAfter = tokens[1].balanceOf(address(notary));
        T.balanceCoin3NotaryAfter = tokens[2].balanceOf(address(notary));
        console.log("--");
        console.log(T.balanceCoin3NotaryAfter);

        T.balanceCoin1VaultAfter = tokens[0].balanceOf(address(vault));
        T.balanceCoin2VaultAfter = tokens[1].balanceOf(address(vault));
        T.balanceCoin3VaultAfter = tokens[2].balanceOf(address(vault));
        uint256 penalty = ((vault.getPenalty() * moreDebt) + ((vault.getRate() * moreDebt) / 86400)) / 3;
        uint256 collateralkept =
            (penalty * 10 ** vault.getDecimals(mockToken3, receiver)) / (100 * 10 ** vault.getStablecoinDecimals());
        console.log(collateralkept);

        assertEq(T.balanceCoinUserBefore, moreDebt);
        assertEq(T.balanceCoinNotaryBefore, 0);
        assertEq(T.balanceCoinVaultBefore, 0);

        assertEq(T.balanceCoin1VaultBefore, amountToMint1);
        assertEq(T.balanceCoin2VaultBefore, amountToMint2);
        assertEq(T.balanceCoin3VaultBefore, amountToMint3);
        assertEq(T.balanceCoin1UserBefore, 0);
        assertEq(T.balanceCoin2UserBefore, 0);
        assertEq(T.balanceCoin3UserBefore, 0);

        assertEq(T.balanceCoinUserAfter, 0);
        assertEq(T.balanceCoinNotaryAfter, 0);
        assertEq(T.balanceCoinVaultAfter, 0);

        assertEq(T.balanceCoin1VaultAfter, 0);
        assertEq(T.balanceCoin2VaultAfter, 0);
        assertEq(T.balanceCoin3VaultAfter, 0);

        assertEq(T.balanceCoin1UserAfter, amountToMint1);
        assertEq(T.balanceCoin2UserAfter, amountToMint2);
        assertEq(T.balanceCoin3UserAfter / 100, (amountToMint3 - collateralkept) / 100);
        console.log("Assertion");
        assertEq(T.balanceCoin1NotaryAfter, 0);
        assertEq(T.balanceCoin2NotaryAfter, 0);
        assertEq(T.balanceCoin3NotaryAfter / 100, collateralkept / 100);
    }

    // function testcalculateTargetValues() public {
    //     uint256 totalValueInDecimals = vault.TotalBalanceInDecimals();
    //     uint256[] memory targetWeights = new uint256[](3);
    //     targetWeights[0] = 30;
    //     targetWeights[1] = 30;
    //     targetWeights[2] = 40;

    //     uint256[] memory returnV = new uint256[](3);
    //     returnV = vault.portfolio().calculateTargetValues(
    //         totalValueInDecimals,
    //         targetWeights
    //     );
    //     console.log("we here");
    //     console.log(returnV[0]);
    //     console.log(returnV[1]);
    //     console.log(returnV[2]);

    //     address[] memory addressV = new address[](3);
    //     addressV[0] = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    //     addressV[1] = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    //     addressV[2] = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    //     IERC20[] memory tokenToSwap = new IERC20[](3);
    //     uint256[] memory colAmounts = new uint256[](3);
    //     address[] memory tokenToreceive = new address[](3);

    //     (tokenToSwap, colAmounts, tokenToreceive) = vault
    //         .portfolio()
    //         .calculateAmountsToRebalance(vault, addressV, returnV);

    //     // console.log(tokenToSwap[0]);
    // }
}
