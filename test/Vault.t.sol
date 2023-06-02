// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./MockERC20.sol";
import "./MockV3Aggregator.sol";
import "../src/Vault.sol";
import "../src/Notary.sol";

contract VaultTest is Test {
    MockERC20 private mockToken1;
    MockERC20 private mockToken2;
    MockERC20 private mockToken3;
    AggregatorV3Interface private mockPriceFeed1;
    AggregatorV3Interface private mockPriceFeed2;
    AggregatorV3Interface private mockPriceFeed3;
    Vault private vault;
    uint256 public constant INITIAL_DEPOSIT = 100;
    uint256 public constant RATIO = 150;
    Notary notary;
    Coin coin;
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
        mockPriceFeed1 = new MockV3Aggregator(8, 10000000000);
        mockPriceFeed2 = new MockV3Aggregator(8, 20000000000);
        mockPriceFeed3 = new MockV3Aggregator(8, 30000000000);

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

        notary = new Notary(RATIO);
        coin = new Coin(address(notary));
        address router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

        vault = new Vault(
            tokens,
            decimals,
            weights,
            priceFeeds,
            address(coin),
            address(1),
            address(notary),
            router
        );
        console.log("Vault created!");

        amountToMint1 = 100 * 10 ** decimals[0];
        amountToMint2 = 100 * 10 ** decimals[1];
        amountToMint3 = 100 * 10 ** decimals[2];
        mockToken1.mint(address(1), amountToMint1);
        mockToken2.mint(address(1), amountToMint2);
        mockToken3.mint(address(1), amountToMint3);

        vm.startPrank(address(1));
        mockToken1.transfer(
            address(vault),
            (INITIAL_DEPOSIT * 10 ** decimals[0] * weights[0]) / 100
        );
        mockToken2.transfer(
            address(vault),
            (INITIAL_DEPOSIT * 10 ** decimals[1] * weights[1]) / 100
        );
        mockToken3.transfer(
            address(vault),
            (INITIAL_DEPOSIT * 10 ** decimals[2] * weights[2]) / 100
        );
    }

    function testCalculateCollateralTotalAmount() public {
        uint256 stablecoinAmount = 100 * 1e18;
        // uint256 conversionRate1 = 100;
        // uint256 conversionRate2 = 200;
        // uint256 conversionRate3 = 300;
        // uint256 w1 = 30;
        // uint256 w2 = 30;
        // uint256 w3 = 40;
        uint256 ratio = 150;
        uint256 expectedCollateralTotal = ((stablecoinAmount * ratio) / 100);
        // (conversionRate1 *
        //     w1 +
        //     conversionRate2 *
        //     w2 +
        //     conversionRate3 *
        //     w3)) / 100;
        uint256 collateralTotal = vault
            .calculateCollateralTotalAmountInDecimals(stablecoinAmount);
        assertEq(collateralTotal, expectedCollateralTotal);
    }

    function testCanTake() public {
        uint256 moreDebt = 100 * 1e18;
        bool canTakeDebt = vault.canTake(moreDebt);
        assertTrue(canTakeDebt);
    }

    function testCanNotTake() public {
        uint256 moreDebt = 15000 * 1e18;
        bool canTakeDebt = vault.canTake(moreDebt);
        assertFalse(canTakeDebt);
    }

    function testTake() public {
        uint256 moreDebt = 150 * 1e18;
        address receiver = address(1);
        vault.take(receiver, moreDebt);
        uint256 debt = vault.debt();
        uint256 balance = coin.balanceOf(receiver);
        assertEq(debt, moreDebt);
        assertEq(balance, moreDebt);
    }

    function testRetrieve() public {
        uint256 moreDebt = 100 * 1e18;
        address receiver = address(1);
        vault.take(receiver, moreDebt);
        uint256 debt = vault.debt();

        vault.RetrieveAll();
        uint256 balance = coin.balanceOf(receiver);
        assertEq(balance, 0);
    }

    function testliquidate() public {
        uint256 moreDebt = 150 * 1e18;
        address receiver = address(1);
        coin.approve(address(vault), moreDebt);
        vault.take(receiver, moreDebt);
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

        vault.liquidate();

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
        uint256 penalty = (vault.PENALTY() * moreDebt) / 100;
        uint256 collateralkept = (penalty) / 300;
        console.log(collateralkept);

        assertEq(T.balanceCoinUserBefore, moreDebt);
        assertEq(T.balanceCoinNotaryBefore, 0);
        assertEq(T.balanceCoinVaultBefore, 0);

        assertEq(
            T.balanceCoin1VaultBefore,
            (amountToMint1 * vault.getWeights(mockToken1)) / 100
        );
        assertEq(
            T.balanceCoin2VaultBefore,
            (amountToMint2 * vault.getWeights(mockToken2)) / 100
        );
        assertEq(
            T.balanceCoin3VaultBefore,
            (amountToMint3 * vault.getWeights(mockToken3)) / 100
        );
        assertEq(
            T.balanceCoin1UserBefore,
            ((amountToMint1 * (100 - vault.getWeights(mockToken1))) / 100)
        );
        assertEq(
            T.balanceCoin2UserBefore,
            ((amountToMint2 * (100 - vault.getWeights(mockToken2))) / 100)
        );
        assertEq(
            T.balanceCoin3UserBefore,
            ((amountToMint3 * (100 - vault.getWeights(mockToken3))) / 100)
        );

        assertEq(T.balanceCoinUserAfter, 0);
        assertEq(T.balanceCoinNotaryAfter, 0);
        assertEq(T.balanceCoinVaultAfter, 0);

        assertEq(T.balanceCoin1VaultAfter, 0);
        assertEq(T.balanceCoin2VaultAfter, 0);
        assertEq(T.balanceCoin3VaultAfter, 0);

        assertEq(T.balanceCoin1UserAfter, amountToMint1);
        assertEq(T.balanceCoin2UserAfter, amountToMint2);
        assertEq(T.balanceCoin3UserAfter, amountToMint3 - collateralkept);

        assertEq(T.balanceCoin1NotaryAfter, 0);
        assertEq(T.balanceCoin2NotaryAfter, 0);
        assertEq(T.balanceCoin3NotaryAfter, collateralkept);
    }

    function testcalculateTargetValues() public {
        uint256 totalValueInDecimals = vault.TotalBalanceInDecimals();
        uint256[] memory targetWeights = new uint256[](3);
        targetWeights[0] = 30;
        targetWeights[1] = 30;
        targetWeights[2] = 40;

        uint256[] memory returnV = new uint256[](3);
        returnV = vault.portfolio().calculateTargetValues(
            totalValueInDecimals,
            targetWeights
        );
        console.log("we here");
        console.log(returnV[0]);
        console.log(returnV[1]);
        console.log(returnV[2]);

        address[] memory addressV = new address[](3);
        addressV[0] = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        addressV[1] = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        addressV[2] = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

        IERC20[] memory tokenToSwap = new IERC20[](3);
        uint256[] memory colAmounts = new uint256[](3);
        address[] memory tokenToreceive = new address[](3);

        (
            tokenToSwap,
            colAmounts,
            tokenToreceive
        ) = vault.portfolio().calculateAmountsToRebalance(
                vault,
                addressV,
                returnV
            );

        // console.log(tokenToSwap[0]);
    }
}
