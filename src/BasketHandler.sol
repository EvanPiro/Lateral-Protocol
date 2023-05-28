// SPDX-License-Identifier: BlueOak-1.0.0
pragma solidity 0.8.17;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

struct Basket {
    IERC20[] erc20s; // enumerated keys for refAmts
    mapping(IERC20 => uint256) weights; // {ref/BU}
}

uint256 constant FIX_ZERO = 0;

/*
 * @title BasketLibP0
 */
library BasketLib {
    using BasketLib for Basket;

    /// Set self to a fresh, empty basket
    // self'.erc20s = [] (empty list)
    // self'.refAmts = {} (empty map)
    function empty(Basket storage self) internal {
        uint256 length = self.erc20s.length;
        for (uint256 i = 0; i < length; ++i)
            self.weights[self.erc20s[i]] = FIX_ZERO;
        delete self.erc20s;
    }

    /// Set `self` equal to `other`
    function setFrom(Basket storage self, Basket storage other) internal {
        empty(self);
        uint256 length = other.erc20s.length;
        for (uint256 i = 0; i < length; ++i) {
            self.erc20s.push(other.erc20s[i]);
            self.weights[other.erc20s[i]] = other.weights[other.erc20s[i]];
        }
    }

    /// Add `weight` to the refAmount of collateral token `tok` in the basket `self`
    // self'.refAmts[tok] = self.refAmts[tok] + weight
    // self'.erc20s is keys(self'.refAmts)
    function add(Basket storage self, IERC20 tok, uint256 _weight) internal {
        if (_weight == FIX_ZERO) return;
        if (self.weights[tok] == FIX_ZERO) {
            self.erc20s.push(tok);
            self.weights[tok] = _weight;
        } else {
            self.weights[tok] += _weight;
        }
    }
}
