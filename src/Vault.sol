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
 * @dev Vault contract manages a tokenized debt position.
 *
 * This contract provides the means for an account to manage their debt position
 * through enforcing adequate collatoralization while withdrawing debt tokens.
 */
contract Vault {
    using BasketLib for Basket;
    using PriceConverter for Basket;

    uint256 private s_debt; // In coins amount
    bool private s_isInsolvent;
    Basket private s_collateral;
    address private s_user;
    uint256 private s_lastTimeStamp;
    address private s_notary;
    Portfolio public s_portfolio;

    Coin private immutable i_coin;
    uint8 private immutable i_stablecoin_decimals;
    uint256 private constant RATIO = 150;
    uint256 private constant RATE = 5;
    uint256 private constant PENALTY = 13;
    uint256 private constant ERC_DECIMAL = 1e18;
    uint256 private constant MAX_ALLOWANCE = 2 ** 256 - 1;

    event CollateralAdded(address token, uint256 tokAmount);
    event CoinMinted(address indexed debtor, uint256 debt);
    event DebtPayed(uint256 tokAmount);
    event VaultLiquidated();
    event CollateralRetrieved();
    event UserDefaulted(address indexed debtor, uint256 debt);
    event RebalanceEvent(Portfolio.STRATEGY strategy);

    modifier onlyNotary() {
        require(
            msg.sender == s_notary,
            "Only the notary can call this function"
        );
        _;
    }

    modifier onlyUser() {
        require(msg.sender == s_user, "Only the user can call this function");
        _;
    }

    modifier onlyNotaryOrUser() {
        require(msg.sender == s_user || msg.sender == s_notary);
        _;
    }

    constructor(
        address _coinAddress,
        address _user,
        address _notary,
        address _portfolio,
        address _EthUSD
    ) {
        i_coin = Coin(_coinAddress);
        s_user = _user;
        s_debt = 0;
        s_lastTimeStamp = block.timestamp;
        s_isInsolvent = false;
        s_notary = _notary;
        i_stablecoin_decimals = i_coin.decimals();
        s_portfolio = Portfolio(_portfolio);
        s_collateral.priceFeedEth = AggregatorV3Interface(_EthUSD);
    }

    function addOneCollateral(
        address _tokenAddress,
        uint256 _amount,
        uint8 _decimal,
        AggregatorV3Interface _priceFeed
    ) public onlyUser {
        IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount);
        s_collateral.add(IERC20(_tokenAddress), _amount, _decimal, _priceFeed);
        emit CollateralAdded(_tokenAddress, _amount);
    }

    function addBasketCollateral(
        address[] memory _tokenAddress,
        uint256[] memory _tokenAmts,
        uint8[] memory _decimals,
        AggregatorV3Interface[] memory _priceFeeds
    ) public onlyUser {
        uint256 length = _tokenAddress.length;
        for (uint256 i = 0; i < length; ++i) {
            IERC20(_tokenAddress[i]).transferFrom(
                msg.sender,
                address(this),
                _tokenAmts[i]
            );
            s_collateral.add(
                IERC20(_tokenAddress[i]),
                _tokenAmts[i],
                _decimals[i],
                _priceFeeds[i]
            );
            emit CollateralAdded(_tokenAddress[i], _tokenAmts[i]);
        }
    }

    /**
     * @dev Takes out loan against collateral if the vault is solvent
     *  An approve function needs to be added in case of liquidation
     */
    function take(address _receiver, uint256 _moreDebt) public onlyUser {
        require(canTake(_moreDebt), "Position cannot take more debt");
        require(s_isInsolvent == false, "Debtor needs to pay debt first");
        require(
            IERC20(i_coin).allowance(msg.sender, address(this)) == _moreDebt,
            "Insufficient allowance"
        );

        i_coin.mint(address(this), _receiver, _moreDebt);
        s_debt += _moreDebt;
        emit CoinMinted(_receiver, _moreDebt);
    }

    /**
     * @dev Liquidates vault if ratio gets low.
     * This function is called by the Notary contract/ Liquidator
     */
    function liquidate() public {
        uint256 cRatio = getCurrentRatio();
        require(cRatio < 20000, "Position is collateralized");
        require(s_isInsolvent == false);

        // Pause the contract until liquidation process is finished
        s_isInsolvent == true;

        // 1. Receive Loan Stablecoins from the debtor
        // uint256 stablecoinAmount = coin.balanceOf(msg.sender);
        // Need to check available tokens
        // Aprove function needs to be added in the take loan function
        uint256 totalCollateralInDecimals = TotalBalanceInDecimals();
        uint256 accruedInterest = getAccruedInterest();
        console.log(accruedInterest);
        uint256 penalty = getLiquidationPenalty();
        console.log(penalty);

        uint256 stablecoinBalance = i_coin.balanceOf(s_user);
        console.log(stablecoinBalance);
        if (s_debt > stablecoinBalance) {
            if (stablecoinBalance > 0) {
                i_coin.transferFrom(s_user, address(this), stablecoinBalance);
            }
            s_debt = s_debt - stablecoinBalance;
        } else {
            i_coin.transferFrom(s_user, address(this), s_debt);
            s_debt = 0;
        }

        // 2. Return Remaining Collateral to the debtor (after deducting fee)
        // If available stables < debt, reduce the collateral by the missing amount
        // Since this is basket like col, reduce each balance until 0 then repeat
        int256 remainingCollateralInDecimals = int256(
            totalCollateralInDecimals
        ) -
            int256(accruedInterest) -
            int256(penalty) -
            int256(s_debt);
        if (remainingCollateralInDecimals < 0) {
            s_debt += uint256(-remainingCollateralInDecimals);
            remainingCollateralInDecimals = 0;
        } else {
            uint256 positiveRemainingCollateralInDecimals = uint256(
                remainingCollateralInDecimals
            );
            // Convert the remainingCollateral to token amounts
            uint256[] memory tokenAmountstoSend = new uint256[](
                s_collateral.erc20s.length
            );
            for (uint256 i = 0; i < s_collateral.erc20s.length; i++) {
                IERC20 token = s_collateral.erc20s[i];
                uint8 decimal = s_collateral.decimals[token];
                uint256 tokenBalance = token.balanceOf(address(this));
                uint256 tokenPrice = PriceConverter.getPrice(
                    s_collateral.priceFeedBasket[token]
                );
                uint256 tokenValueInUSD = PriceConverter.getConversionRate(
                    tokenBalance,
                    s_collateral.priceFeedBasket[token],
                    decimal,
                    s_collateral.priceFeedEth
                );
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
                    s_collateral.erc20s[i].transfer(
                        s_user,
                        tokenAmountstoSend[i]
                    );
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
                    s_collateral.erc20s[i].transfer(
                        s_user,
                        tokenAmountstoSend[i]
                    );
                    positiveRemainingCollateralInDecimals -= tokenValueInUSD;
                }
            }
        }
        console.log("--");

        // 3. Burn Loan Stablecoins (optional)
        // burn the stablecoins received
        console.log(i_coin.balanceOf(address(this)));
        uint256 receivedDebt = i_coin.balanceOf(address(this));
        if (receivedDebt > 0) {
            i_coin.burn(address(this), receivedDebt);
        }
        console.log(i_coin.balanceOf(address(this)));
        // Send the remaining fees/collateral to the Notary contract
        for (uint256 i = 0; i < s_collateral.erc20s.length; i++) {
            IERC20 token = s_collateral.erc20s[i];
            uint256 tokenBalance = token.balanceOf(address(this));
            console.log(tokenBalance);
            if (tokenBalance > 0) {
                token.transfer(s_notary, tokenBalance);
            }
            console.log(token.balanceOf(address(s_notary)));
        }

        if (s_debt == 0) {
            // If all the debt is paid, free this contract once again
            s_isInsolvent = false;
            emit VaultLiquidated();
        } else {
            // Lock the contract
            // The user defaulted and cannot repay debt and/or fees
            // This case should never happen because collaterallisation is at least 150%
            // Since approve function has been called
            // a transferfrom can be sent again to retrieve the missing debt
            // Once the user gets funds.
            s_isInsolvent = true;
            emit UserDefaulted(s_user, s_debt);
        }
    }

    function payDebt(uint256 _amount) public onlyNotaryOrUser {
        i_coin.transferFrom(msg.sender, address(this), _amount);
        i_coin.burn(address(this), _amount);
        s_debt -= _amount;
    }

    function updateCollateralPortfolio(
        address weth,
        uint24 _poolFee
    ) public onlyNotaryOrUser {
        uint256 length = s_collateral.erc20s.length;
        for (uint256 i = 0; i < length; i++) {
            s_collateral.erc20s[i].approve(
                address(s_portfolio),
                s_collateral.tokenAmts[s_collateral.erc20s[i]]
            );
        }
        IERC20(weth).approve(address(s_portfolio), MAX_ALLOWANCE);
        s_portfolio.rebalancePortfolio(this, weth, _poolFee);
        s_collateral.setFrom(
            s_portfolio.getAssets(),
            s_portfolio.getAmounts(),
            s_portfolio.getDecimals(),
            s_portfolio.getWeights(),
            s_portfolio.getPriceFeeds()
        );
        s_collateral.updateWeights();
        emit RebalanceEvent(s_portfolio.getStrategy());
    }

    function retrieveCollateral(
        address _tokAddress,
        uint256 _tokAmount
    ) public onlyUser {
        uint256 nRatio;
        if (s_debt == 0) {
            nRatio = 200;
        } else {
            nRatio =
                getCurrentRatio() -
                getCurrentRatio(
                    PriceConverter.getConversionRate(
                        _tokAmount,
                        s_collateral.priceFeedBasket[IERC20(_tokAddress)],
                        s_collateral.decimals[IERC20(_tokAddress)],
                        s_collateral.priceFeedEth
                    )
                );
        }
        require(
            nRatio > RATIO,
            "After retrieving the collateral, the position will be undercollateralized"
        );
        require(s_isInsolvent == false, "User needs to pay debt first");

        IERC20(_tokAddress).transfer(msg.sender, _tokAmount);
        s_collateral.reduce(IERC20(_tokAddress), _tokAmount);
        emit CollateralRetrieved();
    }

    function RetrieveAll() public onlyUser {
        require(s_debt > 0, "No debt");
        require(
            s_debt <= i_coin.balanceOf(msg.sender),
            "Balance is lower than debt"
        );
        payDebt(s_debt);
        s_collateral.Transfer(msg.sender);
        emit CollateralRetrieved();
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
            (((_stablecoinAmount * ERC_DECIMAL) / 10 ** i_stablecoin_decimals) *
                RATIO) / 100;
    }

    function TotalBalanceInDecimals() public view returns (uint256) {
        return
            (s_collateral.getBasketBalance() * ERC_DECIMAL) /
            10 ** i_stablecoin_decimals;
    }

    /**
     * @dev Returns true if the contract's debt position can increase by a specified amount.
     */
    function canTake(uint256 _moreDebt) public view returns (bool) {
        require(_moreDebt > 0, "Cannot take 0");
        require(s_isInsolvent == false, "Debtor needs to pay debt first");

        uint256 totalCollateralInDecimals = TotalBalanceInDecimals();
        console.log(totalCollateralInDecimals);

        uint256 debtInCoins = s_debt + _moreDebt;
        console.log(debtInCoins);
        return
            ((totalCollateralInDecimals * 100) /
                ((debtInCoins * ERC_DECIMAL) / 10 ** i_stablecoin_decimals)) >=
            RATIO;
    }

    function getAccruedInterest() public view returns (uint256) {
        return
            ((s_debt *
                RATE *
                (block.timestamp - s_lastTimeStamp) *
                ERC_DECIMAL) / 10 ** i_stablecoin_decimals) / 100;
    }

    function getLiquidationPenalty() public view returns (uint256) {
        return
            ((PENALTY * s_debt * ERC_DECIMAL) / 10 ** i_stablecoin_decimals) /
            100;
    }

    function getCurrentRatio() public view returns (uint256) {
        uint256 totalCollateralInDecimals = TotalBalanceInDecimals();
        uint256 cRatio;
        if (s_debt == 0) {
            cRatio = 200;
        } else {
            cRatio =
                ((totalCollateralInDecimals * 100) / ERC_DECIMAL) /
                (s_debt / 10 ** i_stablecoin_decimals);
        }
        return cRatio;
    }

    function getCurrentRatio(uint256 amount) public view returns (uint256) {
        uint256 cRatio;
        if (s_debt == 0) {
            cRatio = 200;
        } else {
            cRatio = (amount * 100) / (s_debt * ERC_DECIMAL);
        }
        return cRatio;
    }

    function getWeights(IERC20 token) public view returns (uint256) {
        return s_collateral.weightsInPercent[token];
    }

    function getTokens() public view returns (IERC20[] memory) {
        return s_collateral.erc20s;
    }

    function getAmounts(IERC20 token) public view returns (uint256) {
        return s_collateral.tokenAmts[token];
    }

    function getDecimals(IERC20 token) public view returns (uint8) {
        return s_collateral.decimals[token];
    }

    function getPriceFeeds(
        IERC20 token
    ) public view returns (AggregatorV3Interface) {
        return s_collateral.priceFeedBasket[token];
    }

    function getBenchmarkFeed() public view returns (AggregatorV3Interface) {
        return s_collateral.priceFeedEth;
    }

    function getDebt() public view returns (uint256) {
        return s_debt;
    }

    function getIsInsolvent() public view returns (bool) {
        return s_isInsolvent;
    }

    function getUser() public view returns (address) {
        return s_user;
    }

    function getlasTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getNotary() public view returns (address) {
        return s_notary;
    }

    function getStablecoinDecimals() public view returns (uint8) {
        return i_stablecoin_decimals;
    }

    function getRatio() public view returns (uint256) {
        return RATIO;
    }

    function getPenalty() public view returns (uint256) {
        return PENALTY;
    }

    function getRate() public view returns (uint256) {
        return RATE;
    }

    function getErcDecimals() public view returns (uint256) {
        return ERC_DECIMAL;
    }
}
