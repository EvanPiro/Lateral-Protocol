// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./MockV3Aggregator.sol";
import "../src/Position.sol";
import "../src/Notary.sol";

contract PositionTest is Test {
    ERC20 private mockToken1;
    ERC20 private mockToken2;
    ERC20 private mockToken3;
    AggregatorV3Interface private mockPriceFeed1;
    AggregatorV3Interface private mockPriceFeed2;
    AggregatorV3Interface private mockPriceFeed3;
    Position private position;
    uint256 public constant INITIAL_DEPOSIT = 100;
    uint256 public constant RATIO = 150;
    Notary notary;
    Coin coin;

    function setUp() public {
        mockToken1 = new ERC20("Test1", "T1");
        mockToken2 = new ERC20("Test2", "T2");
        mockToken3 = new ERC20("Test3", "T3");
        mockPriceFeed1 = new MockV3Aggregator(8, 10000000000);
        mockPriceFeed2 = new MockV3Aggregator(8, 20000000000);
        mockPriceFeed3 = new MockV3Aggregator(8, 30000000000);

        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = mockToken1;
        tokens[1] = mockToken2;
        tokens[2] = mockToken3;

        uint256[] memory weights = new uint256[](3);
        weights[0] = 30;
        weights[1] = 30;
        weights[2] = 40;

        AggregatorV3Interface[] memory priceFeeds = new AggregatorV3Interface[](
            3
        );
        priceFeeds[0] = mockPriceFeed1;
        priceFeeds[1] = mockPriceFeed2;
        priceFeeds[2] = mockPriceFeed3;

        notary = new Notary(RATIO);
        coin = new Coin(address(notary));

        position = new Position(
            tokens,
            weights,
            priceFeeds,
            address(coin),
            address(1)
        );
        console.log("Done");
        console.log(address(2));
        console.log(address(1));
        console.log(address(1));

        mockToken1._mint(address(1), 1000 * 30);
        mockToken2._mint(address(1), 1000 * 30);
        mockToken3._mint(address(1), 1000 * 40);

        vm.startPrank(address(1));
        mockToken1.transfer(
            address(position),
            (INITIAL_DEPOSIT * weights[0]) / 100
        );
        mockToken2.transfer(
            address(position),
            (INITIAL_DEPOSIT * weights[1]) / 100
        );
        mockToken3.transfer(
            address(position),
            (INITIAL_DEPOSIT * weights[2]) / 100
        );
    }

    function testCalculateCollateralTotalAmount() public {
        uint256 stablecoinAmount = 100;
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
        uint256 collateralTotal = position.calculateCollateralTotalAmount(
            stablecoinAmount
        );
        console.log(expectedCollateralTotal);
        console.log(collateralTotal);
        assertEq(collateralTotal, expectedCollateralTotal);
    }

    function testCanTake() public {
        uint256 moreDebt = 100;
        bool canTakeDebt = position.canTake(moreDebt);
        console.log(canTakeDebt);
        assertTrue(canTakeDebt);
    }

    function testCanNotTake() public {
        uint256 moreDebt = 15000;
        bool canTakeDebt = position.canTake(moreDebt);
        console.log(canTakeDebt);
        assertFalse(canTakeDebt);
    }

    function testTake() public {
        uint256 moreDebt = 100;
        address receiver = address(1);
        position.take(receiver, moreDebt);
        uint256 debt = position.debt();
        uint256 balance = coin.balanceOf(receiver);
        assertEq(debt, moreDebt);
        assertEq(balance, moreDebt);
    }

    function testRetrieve() public {
        uint256 moreDebt = 100;
        address receiver = address(1);
        position.take(receiver, moreDebt);
        uint256 debt = position.debt();

        position.RetrieveAll();
        uint256 balance = coin.balanceOf(receiver);
        assertEq(balance, 0);
    }
}
