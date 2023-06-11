// SPDX-License-Identifier: BlueOak-1.0.0
pragma solidity 0.8.17;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./PriceConverter.sol";

struct Basket {
    IERC20[] erc20s; // enumerated keys for refAmts
    mapping(IERC20 => uint256) tokenAmts; // Amount of tokens in decimals
    mapping(IERC20 => uint8) decimals;
    mapping(IERC20 => uint256) weightsInPercent; // {ref/BU}
    mapping(IERC20 => AggregatorV3Interface) priceFeedBasket;
    mapping(IERC20 => string) baseCurrency;
    bool emptyBasket; // The struct is not imported if the bool is not added (solidity bug ?)
}

/**
 * @title BasketLibrary
 * @author
 * @notice This is a library that manages and implements helpful function for Basket structs
 * @dev This functions will be used in the vault contract
 */
library BasketLib {
    uint256 constant FIX_ZERO = 0;

    using PriceConverter for uint256;

    function empty(Basket storage self, IERC20 token) public {
        delete self.tokenAmts[token];
        delete self.weightsInPercent[token];
        delete self.priceFeedBasket[token];

        uint256 length = self.erc20s.length;
        for (uint256 i = 0; i < length; i++) {
            if (self.erc20s[i] == token) {
                self.erc20s[i] = self.erc20s[length - 1];
                self.erc20s.pop();
                break;
            }
        }
    }

    /// Set self to a fresh, empty basket
    // self'.erc20s = [] (empty list)
    // self'.refAmts = {} (empty map)
    function empty(Basket storage self) public {
        uint256 length = self.erc20s.length;
        for (uint256 i = 0; i < length; ++i) {
            delete self.tokenAmts[self.erc20s[i]];
            delete self.weightsInPercent[self.erc20s[i]];
            delete self.priceFeedBasket[self.erc20s[i]];
            delete self.baseCurrency[self.erc20s[i]];
        }
        delete self.erc20s;
    }

    function setFrom(
        Basket storage self,
        address[] memory erc20s,
        uint256[] memory tokenAmts,
        uint8[] memory decimals,
        uint256[] memory weightsInPercent,
        AggregatorV3Interface[] memory priceFeedBasket,
        string[] memory baseCurrency
    ) internal {
        empty(self);
        uint256 length = erc20s.length;
        for (uint256 i = 0; i < length; ++i) {
            self.erc20s.push(IERC20(erc20s[i]));
            self.tokenAmts[IERC20(erc20s[i])] = tokenAmts[i];
            self.decimals[IERC20(erc20s[i])] = decimals[i];
            self.weightsInPercent[IERC20(erc20s[i])] = weightsInPercent[i];
            self.priceFeedBasket[IERC20(erc20s[i])] = priceFeedBasket[i];
            self.baseCurrency[IERC20(erc20s[i])] = baseCurrency[i];
        }
    }

    /// Set `self` equal to `other`
    function setFrom(Basket storage self, Basket storage other) internal {
        empty(self);
        uint256 length = other.erc20s.length;
        for (uint256 i = 0; i < length; ++i) {
            self.erc20s.push(other.erc20s[i]);
            self.tokenAmts[other.erc20s[i]] = other.tokenAmts[other.erc20s[i]];
            self.weightsInPercent[other.erc20s[i]] = other.weightsInPercent[other.erc20s[i]];
            self.priceFeedBasket[other.erc20s[i]] = other.priceFeedBasket[other.erc20s[i]];
        }
    }

    function updateWeights(Basket storage self, AggregatorV3Interface _priceFeedBenchmark) internal {
        uint256 length = self.erc20s.length;
        for (uint256 i = 0; i < length; ++i) {
            IERC20 _tok = self.erc20s[i];
            self.weightsInPercent[_tok] = (
                (getSingleBalance(self, _tok, _priceFeedBenchmark) * 100) / getBasketBalance(self, _priceFeedBenchmark)
            );
        }
    }

    /// Add `weight` to the refAmount of collateral token `tok` in the basket `self`
    // self'.refAmts[tok] = self.refAmts[tok] + weight
    // self'.erc20s is keys(self'.refAmts)
    function add(
        Basket storage self,
        IERC20 _tok,
        uint256 _amount,
        uint8 _decimal,
        AggregatorV3Interface _priceFeed,
        string memory _baseCurrency,
        AggregatorV3Interface _priceFeedBenchmark
    ) internal {
        if (_amount == FIX_ZERO) return;
        if (self.tokenAmts[_tok] == FIX_ZERO) {
            self.erc20s.push(_tok);
            self.tokenAmts[_tok] = _amount;
            self.decimals[_tok] = _decimal;
            self.priceFeedBasket[_tok] = _priceFeed;
            self.baseCurrency[_tok] = _baseCurrency;
        } else {
            self.tokenAmts[_tok] += _amount;
        }
        updateWeights(self, _priceFeedBenchmark);
    }

    function reduce(Basket storage self, IERC20 _tok, uint256 _amount, AggregatorV3Interface _priceFeedBenchmark)
        internal
    {
        if (_amount == FIX_ZERO) return;
        if (self.tokenAmts[_tok] == _amount) {
            empty(self, _tok);
        } else {
            self.tokenAmts[_tok] -= _amount;
        }
        updateWeights(self, _priceFeedBenchmark);
    }

    function Transfer(Basket storage self, address sender) internal {
        require(self.erc20s.length > 0, "Basket is empty");
        uint256 length = self.erc20s.length;
        for (uint256 i = 0; i < length; ++i) {
            self.erc20s[i].transfer(sender, self.tokenAmts[self.erc20s[i]]);
        }
        empty(self);
    }

    function getSingleBalance(Basket storage self, IERC20 token, AggregatorV3Interface _priceFeedBenchmark)
        internal
        view
        returns (uint256 balance)
    {
        balance = self.tokenAmts[token].getConversionRate(
            self.priceFeedBasket[token], self.decimals[token], _priceFeedBenchmark, self.baseCurrency[token]
        );
    }

    function getBasketBalance(Basket storage self, AggregatorV3Interface _priceFeedBenchmark)
        internal
        view
        returns (uint256 balance)
    {
        uint256 length = self.erc20s.length;
        for (uint256 i = 0; i < length; ++i) {
            balance += getSingleBalance(self, self.erc20s[i], _priceFeedBenchmark);
        }
    }

    function getTokenAmountsToSend(
        Basket storage self,
        uint256 positiveRemainingCollateralInDecimals,
        AggregatorV3Interface s_priceFeedBenchmark
    ) public view returns (uint256[] memory) {
        uint256[] memory tokenAmountstoSend = new uint256[](self.erc20s.length);
        for (uint256 i = 0; i < self.erc20s.length; i++) {
            uint256 tokenBalance = self.tokenAmts[self.erc20s[i]];
            uint256 tokenValueInUSD = PriceConverter.getConversionRate(
                tokenBalance,
                self.priceFeedBasket[self.erc20s[i]],
                self.decimals[self.erc20s[i]],
                s_priceFeedBenchmark,
                self.baseCurrency[self.erc20s[i]]
            );

            if (positiveRemainingCollateralInDecimals <= tokenValueInUSD) {
                tokenAmountstoSend[i] = (positiveRemainingCollateralInDecimals * 10 ** self.decimals[self.erc20s[i]])
                    / PriceConverter.getPrice(self.priceFeedBasket[self.erc20s[i]]);
                // s_collateral[_user].erc20s[i].transfer(_user, tokenAmountstoSend[i]);
                // s_collateral[_user].tokenAmts[
                //     s_collateral[_user].erc20s[i]
                // ] -= tokenAmountstoSend[i];
                break;
            } else {
                tokenAmountstoSend[i] = (
                    tokenValueInUSD / PriceConverter.getPrice(self.priceFeedBasket[self.erc20s[i]])
                ) * 10 ** self.decimals[self.erc20s[i]];
                // s_collateral[_user].erc20s[i].transfer(_user, tokenAmountstoSend[i]);
                // s_collateral[_user].tokenAmts[
                //     s_collateral[_user].erc20s[i]
                // ] -= tokenAmountstoSend[i];
                positiveRemainingCollateralInDecimals -= tokenValueInUSD;
            }
        }
        return tokenAmountstoSend;
    }
}
