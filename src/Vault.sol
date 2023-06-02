// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./BasketHandler.sol";
import "./PriceConverter.sol";
import "./Coin.sol";
import "./Portfolio.sol";

/**
 * @dev Position contract manages a tokenized debt position.
 *
 * This contract provides the means for an account to manage their debt position
 * through enforcing adequate collatoralization while withdrawing debt tokens.
 */
contract Vault is Ownable {
    using BasketLib for Basket;
    using PriceConverter for Basket;
    Coin private immutable coin;
    uint256 public debt; // In coins 18 Decimals
    bool public isInsolvent;
    Basket public collateral;
    uint256 public constant RATIO = 150;
    uint256 public constant COLLATERAL_DECIMAL = 1e18;
    address public user;
    uint256 public constant RATE = 500;
    uint256 public constant PENALTY = 500;
    uint256 private s_lastTimeStamp;
    address public notary;
    uint public constant ERC_DECIMAL = 1e18;
    uint8 public STABLE_DECIMAL;
    Portfolio public portfolio;

    event UserDefaulted(address indexed debtor, uint256 debt);

    constructor(
        IERC20[] memory tokens,
        uint8[] memory decimals,
        uint256[] memory weights,
        AggregatorV3Interface[] memory priceFeeds,
        address _coinAddress,
        address _owner,
        address _notary,
        address _uniswapV3Router
    ) {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ++i) {
            collateral.add(tokens[i], decimals[i], weights[i], priceFeeds[i]);
        }
        coin = Coin(_coinAddress);
        transferOwnership(_owner);
        user = _owner;
        debt = 0;
        s_lastTimeStamp = block.timestamp;
        isInsolvent = false;
        notary = _notary;
        STABLE_DECIMAL = coin.decimals();
        portfolio = new Portfolio(_uniswapV3Router);
    }

    /**
     *
     * @dev calculate the total collateral amount in USD needed to hedge against
     *      the total exposure
     */
    function calculateCollateralTotalAmountInDecimals(
        uint256 _stablecoinAmount
    ) public view returns (uint256) {
        return
            (((_stablecoinAmount * ERC_DECIMAL) / 10 ** STABLE_DECIMAL) *
                RATIO) / 100;
    }

    // function calculateCollateralTotalAmount(
    //     uint256 _stablecoinAmount
    // ) public view returns (uint256) {
    //     return
    //         (collateral.getConversionRateOfBasket(_stablecoinAmount) * RATIO) /
    //         100;
    // }

    function TotalBalanceInDecimals() public view returns (uint256) {
        return
            (collateral.getBasketBalance(address(this)) * ERC_DECIMAL) /
            10 ** STABLE_DECIMAL;
    }

    /**
     * @dev Returns true if the contract's debt position can increase by a specified amount.
     */
    function canTake(uint256 _moreDebt) public view returns (bool) {
        require(_moreDebt > 0, "Cannot take 0");
        uint256 totalCollateralInDecimals = TotalBalanceInDecimals();
        console.log(totalCollateralInDecimals);

        uint256 debtInCoins = debt + _moreDebt;
        console.log(debtInCoins);
        return
            ((totalCollateralInDecimals * 100) /
                ((debtInCoins * ERC_DECIMAL) / 10 ** STABLE_DECIMAL)) >= RATIO;
    }

    /**
     * @dev Takes out loan against collateral if the vault is solvent
     *  An approve function needs to be added in case of liquidation
     */
    function take(address _receiver, uint256 _moreDebt) public onlyOwner {
        require(canTake(_moreDebt), "Position cannot take debt");
        coin.mint(address(this), _receiver, _moreDebt);
        debt = debt + _moreDebt;
    }

    modifier onlyNotary() {
        require(msg.sender == notary);
        _;
    }

    function getAccruedInterest() public view returns (uint256) {
        return
            ((debt * RATE * (block.timestamp - s_lastTimeStamp) * ERC_DECIMAL) /
                10 ** STABLE_DECIMAL) / 100;
    }

    function getLiquidationPenalty() public view returns (uint256) {
        return ((PENALTY * debt * ERC_DECIMAL) / 10 ** STABLE_DECIMAL) / 100;
    }

    /**
     * @dev Liquidates vault if ratio gets low.
     * This function is called by the Notary contract/ Liquidator
     */
    function liquidate() public {
        uint256 totalCollateralInDecimals = TotalBalanceInDecimals();
        console.log(totalCollateralInDecimals);
        uint256 cRatio = (totalCollateralInDecimals * 100) /
            (debt * ERC_DECIMAL);
        require(cRatio < 20000, "Position is collateralized");
        require(isInsolvent == false);

        // 1. Receive Loan Stablecoins from the debtor
        // uint256 stablecoinAmount = coin.balanceOf(msg.sender);
        // Need to check available tokens
        // Aprove function needs to be added in the take loan function
        uint256 accruedInterest = getAccruedInterest();
        console.log(accruedInterest);
        uint256 penalty = getLiquidationPenalty();
        console.log(penalty);

        uint256 stablecoinBalance = coin.balanceOf(user);
        console.log(stablecoinBalance);
        if (debt > stablecoinBalance) {
            if (stablecoinBalance > 0) {
                coin.transferFrom(user, address(this), stablecoinBalance);
            }
            debt = debt - stablecoinBalance;
        } else {
            coin.transferFrom(user, address(this), debt);
            debt = 0;
        }

        // 2. Return Remaining Collateral to the debtor (after deducting fee)
        // If available stables < debt, reduce the collateral by the missing amount
        // Since this is basket like col, reduce each balance until 0 then repeat
        int256 remainingCollateralInDecimals = int256(
            totalCollateralInDecimals
        ) -
            int256(accruedInterest) -
            int256(penalty) -
            int256(debt);
        if (remainingCollateralInDecimals < 0) {
            debt += uint256(-remainingCollateralInDecimals);
            remainingCollateralInDecimals = 0;
        } else {
            uint256 positiveRemainingCollateralInDecimals = uint256(
                remainingCollateralInDecimals
            );
            // Convert the remainingCollateral to token amounts
            uint256[] memory tokenAmountstoSend = new uint256[](
                collateral.erc20s.length
            );
            for (uint256 i = 0; i < collateral.erc20s.length; i++) {
                IERC20 token = collateral.erc20s[i];
                uint8 decimal = collateral.decimals[token];
                uint256 tokenBalance = token.balanceOf(address(this));
                uint256 tokenPrice = PriceConverter.getPrice(
                    collateral.priceFeedBasket[token]
                );
                uint256 tokenValueInUSD = (PriceConverter.getConversionRate(
                    tokenBalance,
                    collateral.priceFeedBasket[token]
                ) * ERC_DECIMAL) / 10 ** decimal;
                console.log(positiveRemainingCollateralInDecimals);
                console.log(tokenValueInUSD);
                console.log("--");

                if (positiveRemainingCollateralInDecimals <= tokenValueInUSD) {
                    // Remaining collateral is smaller than the token amount
                    tokenAmountstoSend[i] =
                        (positiveRemainingCollateralInDecimals *
                            10 ** decimal) /
                        tokenPrice;
                    // Transfer the remaining collateral to the debtor then get out of loop
                    console.log(
                        tokenValueInUSD - positiveRemainingCollateralInDecimals
                    );
                    console.log(positiveRemainingCollateralInDecimals);
                    console.log(tokenPrice);
                    console.log(tokenAmountstoSend[i]);
                    collateral.erc20s[i].transfer(user, tokenAmountstoSend[i]);
                    break;
                } else {
                    console.log("we here");
                    // Remaining collateral is larger than the token amount
                    // uint256 tokenPrice = PriceConverter.getPrice(
                    //     collateral.priceFeedBasket[token]
                    // );
                    tokenAmountstoSend[i] =
                        (tokenValueInUSD / tokenPrice) *
                        10 ** decimal;
                    console.log(tokenAmountstoSend[i]);
                    // Transfer the maximum collateral portion to the debtor then loop again
                    collateral.erc20s[i].transfer(user, tokenAmountstoSend[i]);
                    positiveRemainingCollateralInDecimals -= tokenValueInUSD;
                }
            }
        }
        console.log("--");

        // 3. Burn Loan Stablecoins (optional)
        // burn the stablecoins received
        console.log(coin.balanceOf(address(this)));
        uint256 receivedDebt = coin.balanceOf(address(this));
        if (receivedDebt > 0) {
            coin.burn(address(this), receivedDebt);
        }
        console.log(coin.balanceOf(address(this)));
        // Send the remaining fees/collateral to the Notary contract
        for (uint256 i = 0; i < collateral.erc20s.length; i++) {
            IERC20 token = collateral.erc20s[i];
            uint256 tokenBalance = token.balanceOf(address(this));
            console.log(tokenBalance);
            if (tokenBalance > 0) {
                token.transfer(notary, tokenBalance);
            }
            console.log(token.balanceOf(address(notary)));
        }

        if (debt == 0) {
            // If all the debt is paid, free this contract once again
            isInsolvent = false;
        } else {
            // Lock the contract
            // The user defaulted and cannot repay debt and/or fees
            // This case should never happen because collaterallisation is at least 150%
            // Since approve function has been called
            // a transferfrom can be sent again to retrieve the missing debt
            // Once the user gets funds.
            isInsolvent = true;
            emit UserDefaulted(user, debt);
        }
    }

    function RetrieveAll() public onlyOwner {
        require(coin.balanceOf(msg.sender) >= 0, "Balance is 0");
        uint256 _stablecoinAmount = coin.balanceOf(msg.sender);
        coin.burn(msg.sender, _stablecoinAmount);
        collateral.Transfer(msg.sender, address(this));
    }

    function getWeights(IERC20 token) public view returns (uint256) {
        return collateral.weightsInPercent[token];
    }

    function getTokens() public view returns (IERC20[] memory) {
        return collateral.erc20s;
    }

    function getDecimals(IERC20 token) public view returns (uint8) {
        return collateral.decimals[token];
    }

    function getPriceFeed(
        IERC20 token
    ) public view returns (AggregatorV3Interface) {
        return collateral.priceFeedBasket[token];
    }
}
