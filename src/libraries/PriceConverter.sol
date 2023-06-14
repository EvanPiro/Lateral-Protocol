// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./BasketHandler.sol";
import "forge-std/Test.sol";

/**
 * @title Library that handle price conversion for basket and uint types
 * @dev This library implements Chainlink oracles.
 * getConversionRate will systematically convert to USD even if the base currency is not USD.
 *
 */
library PriceConverter {
    function getPrice(AggregatorV3Interface priceFeed) internal view returns (uint256) {
        (, int256 answer,,,) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();
        return uint256(answer * int256(1e18 / 10 ** decimals));
    }

    function getPriceOfBasket(Basket storage basketOfTokens)
        internal
        view
        returns (IERC20[] memory tokens, uint256[] memory prices)
    {
        uint256 length = basketOfTokens.erc20s.length;
        tokens = new IERC20[](length);
        prices = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            tokens[i] = basketOfTokens.erc20s[i];
            prices[i] = getPrice(basketOfTokens.priceFeedBasket[basketOfTokens.erc20s[i]]);
        }
        return (tokens, prices);
    }

    function getConversionRate(
        uint256 tokenAmount,
        AggregatorV3Interface priceFeed,
        uint8 decimals,
        AggregatorV3Interface priceFeedEth,
        string memory baseCurrency
    ) internal view returns (uint256) {
        uint256 tokenPrice = getPrice(priceFeed);
        uint256 tokenAmountInUsd;
        if (keccak256(abi.encodePacked(baseCurrency)) == keccak256(abi.encodePacked("USD"))) {
            tokenAmountInUsd = (tokenPrice * tokenAmount) / (10 ** decimals);
        } else {
            tokenAmountInUsd = (tokenPrice * tokenAmount * 1e18) / (10 ** decimals * getPrice(priceFeedEth));
        }
        return tokenAmountInUsd;
    }

    function getConversionRateOfBasket(
        Basket storage self,
        AggregatorV3Interface priceFeedEth,
        string memory baseCurrency
    ) internal view returns (uint256 price) {
        uint256 length = self.erc20s.length;
        (IERC20[] memory tokens, uint256[] memory prices) = getPriceOfBasket(self);
        for (uint256 i = 0; i < length; ++i) {
            price += getConversionRate(
                self.tokenAmts[tokens[i]],
                self.priceFeedBasket[tokens[i]],
                self.decimals[tokens[i]],
                priceFeedEth,
                baseCurrency
            );
        }
        return price;
    }
}
