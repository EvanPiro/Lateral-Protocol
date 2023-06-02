// SPDX-License-Identifier: BlueOak-1.0.0
pragma solidity 0.8.17;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./PriceConverter.sol";

struct Basket {
    IERC20[] erc20s; // enumerated keys for refAmts
    mapping(IERC20 => uint8) decimals;
    mapping(IERC20 => uint256) weightsInPercent; // {ref/BU}
    mapping(IERC20 => AggregatorV3Interface) priceFeedBasket;
    bool empty;
}

/*
 * @title BasketLibP0
 */
library BasketLib {
    uint256 constant FIX_ZERO = 0;
    using PriceConverter for uint256;

    /// Set self to a fresh, empty basket
    // self'.erc20s = [] (empty list)
    // self'.refAmts = {} (empty map)
    function empty(Basket storage self) internal {
        uint256 length = self.erc20s.length;
        for (uint256 i = 0; i < length; ++i) {
            delete self.weightsInPercent[self.erc20s[i]];
            delete self.priceFeedBasket[self.erc20s[i]];
        }
        delete self.erc20s;
    }

    /// Set `self` equal to `other`
    function setFrom(Basket storage self, Basket storage other) internal {
        empty(self);
        uint256 length = other.erc20s.length;
        for (uint256 i = 0; i < length; ++i) {
            self.erc20s.push(other.erc20s[i]);
            self.weightsInPercent[other.erc20s[i]] = other.weightsInPercent[
                other.erc20s[i]
            ];
            self.priceFeedBasket[other.erc20s[i]] = other.priceFeedBasket[
                other.erc20s[i]
            ];
        }
    }

    /// Add `weight` to the refAmount of collateral token `tok` in the basket `self`
    // self'.refAmts[tok] = self.refAmts[tok] + weight
    // self'.erc20s is keys(self'.refAmts)
    function add(
        Basket storage self,
        IERC20 _tok,
        uint8 _decimal,
        uint256 _weight,
        AggregatorV3Interface _priceFeed
    ) internal {
        if (_weight == FIX_ZERO) return;
        if (self.weightsInPercent[_tok] == FIX_ZERO) {
            self.erc20s.push(_tok);
            self.decimals[_tok] = _decimal;
            self.weightsInPercent[_tok] = _weight;
            self.priceFeedBasket[_tok] = _priceFeed;
        } else {
            self.weightsInPercent[_tok] += _weight;
        }
    }

    function getBasketBalance(
        Basket storage self,
        address account
    ) internal view returns (uint256 balance) {
        uint256 length = self.erc20s.length;
        for (uint256 i = 0; i < length; ++i) {
            balance += ((self.erc20s[i].balanceOf(account).getConversionRate(
                self.priceFeedBasket[self.erc20s[i]]
            ) * 1e18) / 10 ** self.decimals[self.erc20s[i]]);
        }
    }

    function Transfer(
        Basket storage self,
        address sender,
        address positionAddress
    ) internal {
        require(self.erc20s.length > 0, "Basket is empty");
        uint256 length = self.erc20s.length;
        for (uint256 i = 0; i < length; ++i) {
            self.erc20s[i].transfer(
                sender,
                self.erc20s[i].balanceOf(positionAddress)
            );
        }
    }
}
