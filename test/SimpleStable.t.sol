pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "../src/SimpleStable.sol";
import "lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract MockAggregatorV3Interface is AggregatorV3Interface {
    function decimals() external view returns (uint8) {
        return 0;
    }

    function description() external view returns (string memory) {
        return "";
    }

    function version() external view returns (uint256) {
        return 0;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, 0, 0, 0, 0);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, 0, 0, 0, 0);
    }
}

contract SimpleStable is Test {
    uint256 minRatio = 150;
    AggregatorV3Interface aggregator;
    Notary notary;
    PriceFeed priceFeed;
    Coin coin;
    address owner = address(2);

    function setUp() public {
        aggregator = new MockAggregatorV3Interface();
        priceFeed = new PriceFeed(address(aggregator));
        notary = new Notary(minRatio, address(priceFeed));
        coin = new Coin(address(notary));
        notary.activate(address(coin));
    }

    function test_CanOpenPositionThroughNotary() public {
        address positionAddress = notary.openPosition(owner);
        Position position = Position(positionAddress);
        assertEq(position.minRatio(), minRatio);
    }

    function test_CannotTakeDebtBelowMinimumRatio() public {
        vm.startPrank(owner);
        address positionAddress = notary.openPosition(owner);
        Position position = Position(positionAddress);

        vm.expectRevert("Position cannot take debt");
        position.take(owner, 100000000);
        console.log(coin.balanceOf(owner));
        vm.stopPrank();
    }
}
