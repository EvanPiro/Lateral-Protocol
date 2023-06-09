// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
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
contract Vault is Ownable {
    using BasketLib for Basket;
    using PriceConverter for Basket;

    mapping(address => uint256) private s_debt;
    // uint256 private s_debt; // In coins amount
    mapping(address => bool) private s_isInsolvent;
    // bool private s_isInsolvent;
    mapping(address => Basket) private s_collateral;
    // Basket private s_collateral;
    address[] private s_users;
    mapping(address => uint256) private s_lastTimeStamp;
    // uint256 private s_lastTimeStamp;
    mapping(address => Portfolio.STRATEGY) private s_strategy;
    address private s_notary;
    Portfolio public s_portfolio;
    AggregatorV3Interface private s_priceFeedBenchmark;

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

    // modifier onlyUser() {
    //     require(msg.sender == s_user, "Only the user can call this function");
    //     _;
    // }

    // modifier onlyNotaryOrUser() {
    //     require(msg.sender == s_user || msg.sender == s_notary);
    //     _;
    // }

    constructor(
        address _coinAddress,
        address _notary,
        address _portfolio,
        address _priceFeedBenchmark
    ) {
        i_coin = Coin(_coinAddress);
        // s_user = _user;
        s_debt[msg.sender] = 0;
        s_lastTimeStamp[msg.sender] = block.timestamp;
        s_isInsolvent[msg.sender] = false;
        s_notary = _notary;
        i_stablecoin_decimals = i_coin.decimals();
        s_portfolio = Portfolio(_portfolio);
        s_priceFeedBenchmark = AggregatorV3Interface(_priceFeedBenchmark);
    }

    function addOneCollateral(
        address _tokenAddress,
        uint256 _amount,
        uint8 _decimal,
        address _priceFeed,
        string memory _baseCurrency
    ) public {
        IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount);
        s_collateral[msg.sender].add(
            IERC20(_tokenAddress),
            _amount,
            _decimal,
            AggregatorV3Interface(_priceFeed),
            _baseCurrency,
            s_priceFeedBenchmark
        );
        if (s_users.length == 0) {
            s_users.push(msg.sender);
        } else {
            bool exists = false;
            for (uint256 i = 0; i < s_users.length; i++) {
                if (s_users[i] == msg.sender) {
                    exists = true;
                    break;
                }
            }
            if (exists == false) {
                s_users.push(msg.sender);
            }
        }
        emit CollateralAdded(_tokenAddress, _amount);
    }

    function addBasketCollateral(
        address[] memory _tokenAddress,
        uint256[] memory _tokenAmts,
        uint8[] memory _decimals,
        address[] memory _priceFeeds,
        string[] memory _baseCurrencies
    ) public {
        uint256 length = _tokenAddress.length;
        for (uint256 i = 0; i < length; ++i) {
            IERC20(_tokenAddress[i]).transferFrom(
                msg.sender,
                address(this),
                _tokenAmts[i]
            );
            s_collateral[msg.sender].add(
                IERC20(_tokenAddress[i]),
                _tokenAmts[i],
                _decimals[i],
                AggregatorV3Interface(_priceFeeds[i]),
                _baseCurrencies[i],
                s_priceFeedBenchmark
            );

            emit CollateralAdded(_tokenAddress[i], _tokenAmts[i]);
        }
        if (s_users.length == 0) {
            s_users.push(msg.sender);
        } else {
            bool exists = false;
            for (uint256 i = 0; i < s_users.length; i++) {
                if (s_users[i] == msg.sender) {
                    exists = true;
                    break;
                }
            }
            if (exists == false) {
                s_users.push(msg.sender);
            }
        }
    }

    /**
     * @dev Takes out loan against collateral if the vault is solvent
     *  An approve function needs to be added in case of liquidation
     */
    function take(uint256 _moreDebt) public {
        require(
            canTake(msg.sender, _moreDebt),
            "Position cannot take more debt"
        );
        require(
            s_isInsolvent[msg.sender] == false,
            "Debtor needs to pay debt first"
        );
        require(
            IERC20(i_coin).allowance(msg.sender, address(this)) >= _moreDebt,
            "Insufficient allowance"
        );

        i_coin.mint(address(this), msg.sender, _moreDebt);
        s_debt[msg.sender] += _moreDebt;
        emit CoinMinted(msg.sender, _moreDebt);
    }

    function getTokenAmountsToSend(
        address _user,
        uint256 positiveRemainingCollateralInDecimals
    ) public onlyNotary returns (uint256[] memory) {
        uint256[] memory tokenAmountstoSend = new uint256[](
            s_collateral[_user].erc20s.length
        );
        for (uint256 i = 0; i < s_collateral[_user].erc20s.length; i++) {
            uint256 tokenBalance = s_collateral[_user].tokenAmts[
                s_collateral[_user].erc20s[i]
            ];
            uint256 tokenValueInUSD = PriceConverter.getConversionRate(
                tokenBalance,
                s_collateral[_user].priceFeedBasket[
                    s_collateral[_user].erc20s[i]
                ],
                s_collateral[_user].decimals[s_collateral[_user].erc20s[i]],
                s_priceFeedBenchmark,
                s_collateral[_user].baseCurrency[s_collateral[_user].erc20s[i]]
            );

            if (positiveRemainingCollateralInDecimals <= tokenValueInUSD) {
                tokenAmountstoSend[i] =
                    (positiveRemainingCollateralInDecimals *
                        10 **
                            s_collateral[_user].decimals[
                                s_collateral[_user].erc20s[i]
                            ]) /
                    PriceConverter.getPrice(
                        s_collateral[_user].priceFeedBasket[
                            s_collateral[_user].erc20s[i]
                        ]
                    );
                s_collateral[_user].erc20s[i].transfer(
                    _user,
                    tokenAmountstoSend[i]
                );
                s_collateral[_user].tokenAmts[
                    s_collateral[_user].erc20s[i]
                ] -= tokenAmountstoSend[i];
                break;
            } else {
                tokenAmountstoSend[i] =
                    (tokenValueInUSD /
                        PriceConverter.getPrice(
                            s_collateral[_user].priceFeedBasket[
                                s_collateral[_user].erc20s[i]
                            ]
                        )) *
                    10 **
                        s_collateral[_user].decimals[
                            s_collateral[_user].erc20s[i]
                        ];
                s_collateral[_user].erc20s[i].transfer(
                    _user,
                    tokenAmountstoSend[i]
                );
                s_collateral[_user].tokenAmts[
                    s_collateral[_user].erc20s[i]
                ] -= tokenAmountstoSend[i];
                positiveRemainingCollateralInDecimals -= tokenValueInUSD;
            }
        }
        return tokenAmountstoSend;
    }

    /**
     * @dev Liquidates vault if ratio gets low.
     * This function is called by the Notary contract/ Liquidator
     */
    function liquidate(address _user) public onlyNotary {
        uint256 cRatio = getCurrentRatio(_user);
        require(cRatio < 20000, "Position is collateralized");
        require(s_isInsolvent[_user] == false);

        // Pause the contract until liquidation process is finished
        s_isInsolvent[_user] == true;

        // 1. Receive Loan Stablecoins from the debtor
        // uint256 stablecoinAmount = coin.balanceOf(msg.sender);
        // Need to check available tokens
        // Aprove function needs to be added in the take loan function
        uint256 totalCollateralInDecimals = TotalBalanceInDecimals(_user);
        uint256 accruedInterest = getAccruedInterest(_user);
        console.log(accruedInterest);
        uint256 penalty = getLiquidationPenalty(_user);
        console.log(penalty);

        uint256 stablecoinBalance = i_coin.balanceOf(_user);
        console.log(stablecoinBalance);
        if (s_debt[_user] > stablecoinBalance) {
            if (stablecoinBalance > 0) {
                i_coin.transferFrom(_user, address(this), stablecoinBalance);
            }
            s_debt[_user] -= stablecoinBalance;
        } else {
            i_coin.transferFrom(_user, address(this), s_debt[_user]);
            s_debt[_user] = 0;
        }

        // 2. Return Remaining Collateral to the debtor (after deducting fee)
        // If available stables < debt, reduce the collateral by the missing amount
        // Since this is basket like col, reduce each balance until 0 then repeat
        int256 remainingCollateralInDecimals = int256(
            totalCollateralInDecimals
        ) -
            int256(accruedInterest) -
            int256(penalty) -
            int256(s_debt[_user]);
        console.log(accruedInterest);
        console.log(penalty);
        console.log(s_debt[_user]);
        console.log("----------------");
        if (remainingCollateralInDecimals < 0) {
            s_debt[_user] += uint256(-remainingCollateralInDecimals);
            remainingCollateralInDecimals = 0;
        } else {
            uint256 positiveRemainingCollateralInDecimals = uint256(
                remainingCollateralInDecimals
            );
            // Convert the remainingCollateral to token amounts
            uint256[] memory tokenAmountstoSend = new uint256[](
                s_collateral[_user].erc20s.length
            );
            tokenAmountstoSend = getTokenAmountsToSend(
                _user,
                positiveRemainingCollateralInDecimals
            );
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
        for (uint256 i = 0; i < s_collateral[_user].erc20s.length; i++) {
            IERC20 token = s_collateral[_user].erc20s[i];
            uint256 tokenBalance = s_collateral[_user].tokenAmts[token];
            console.log(tokenBalance);
            if (tokenBalance > 0) {
                token.transfer(s_notary, tokenBalance);
            }
            console.log(token.balanceOf(address(s_notary)));
        }

        if (s_debt[_user] == 0) {
            // If all the debt is paid, free this contract once again
            s_isInsolvent[_user] = false;
            emit VaultLiquidated();
        } else {
            // Lock the contract
            // The user defaulted and cannot repay debt and/or fees
            // This case should never happen because collaterallisation is at least 150%
            // Since approve function has been called
            // a transferfrom can be sent again to retrieve the missing debt
            // Once the user gets funds.
            s_isInsolvent[_user] = true;
            emit UserDefaulted(_user, s_debt[_user]);
        }
    }

    function payDebt(uint256 _amount) public {
        require(s_debt[msg.sender] >= _amount, "Debt is less than amount");

        i_coin.transferFrom(msg.sender, address(this), _amount);
        i_coin.burn(address(this), _amount);
        uint256 accruedInterest = getAccruedInterest(msg.sender);
        s_debt[msg.sender] -= _amount + accruedInterest;
    }

    function updateStrategy(uint256 _strategy) public {
        s_strategy[msg.sender] = Portfolio.STRATEGY(_strategy);
    }

    function updateCollateralPortfolio(
        address weth,
        uint24 _poolFee,
        address _user
    ) public onlyNotary {
        uint256 length = s_collateral[_user].erc20s.length;
        for (uint256 i = 0; i < length; i++) {
            s_collateral[_user].erc20s[i].approve(
                address(s_portfolio),
                s_collateral[_user].tokenAmts[s_collateral[_user].erc20s[i]]
            );
        }
        IERC20(weth).approve(address(s_portfolio), MAX_ALLOWANCE);
        s_portfolio.rebalancePortfolio(this, weth, _poolFee, _user);
        s_collateral[_user].setFrom(
            s_portfolio.getAssets(),
            s_portfolio.getAmounts(),
            s_portfolio.getDecimals(),
            s_portfolio.getWeights(),
            s_portfolio.getPriceFeeds(),
            s_portfolio.getBaseCurrencies()
        );
        s_collateral[_user].updateWeights(s_priceFeedBenchmark);
        emit RebalanceEvent(getStrategy(_user));
    }

    function retrieveCollateral(
        address _tokAddress,
        uint256 _tokAmount
    ) public {
        require(
            s_collateral[msg.sender].erc20s.length > 0,
            "There is no collateral"
        );
        uint256 nRatio;
        if (s_debt[msg.sender] == 0) {
            nRatio = 200;
        } else {
            nRatio =
                getCurrentRatio(msg.sender) -
                getCurrentRatio(
                    PriceConverter.getConversionRate(
                        _tokAmount,
                        s_collateral[msg.sender].priceFeedBasket[
                            IERC20(_tokAddress)
                        ],
                        s_collateral[msg.sender].decimals[IERC20(_tokAddress)],
                        s_priceFeedBenchmark,
                        s_collateral[msg.sender].baseCurrency[
                            IERC20(_tokAddress)
                        ]
                    ),
                    msg.sender
                );
        }
        require(
            nRatio > RATIO,
            "After retrieving the collateral, the position will be undercollateralized"
        );
        require(
            s_isInsolvent[msg.sender] == false,
            "User needs to pay debt first"
        );

        IERC20(_tokAddress).transfer(msg.sender, _tokAmount);
        s_collateral[msg.sender].reduce(
            IERC20(_tokAddress),
            _tokAmount,
            s_priceFeedBenchmark
        );
        emit CollateralRetrieved();
    }

    function RetrieveAll() public {
        require(s_debt[msg.sender] > 0, "No debt");
        require(
            s_debt[msg.sender] <= i_coin.balanceOf(msg.sender),
            "Balance is lower than debt"
        );
        payDebt(s_debt[msg.sender]);
        s_collateral[msg.sender].Transfer(msg.sender);
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

    function TotalBalanceInDecimals(
        address _user
    ) public view returns (uint256) {
        return
            (s_collateral[_user].getBasketBalance(s_priceFeedBenchmark) *
                ERC_DECIMAL) / 10 ** i_stablecoin_decimals;
    }

    /**
     * @dev Returns true if the contract's debt position can increase by a specified amount.
     */
    function canTake(
        address _user,
        uint256 _moreDebt
    ) public view returns (bool) {
        require(_moreDebt > 0, "Cannot take 0");
        require(
            s_isInsolvent[_user] == false,
            "Debtor needs to pay debt first"
        );

        uint256 totalCollateralInDecimals = TotalBalanceInDecimals(_user);

        uint256 debtInCoins = s_debt[_user] + _moreDebt;
        return
            ((totalCollateralInDecimals * 100) /
                ((debtInCoins * ERC_DECIMAL) / 10 ** i_stablecoin_decimals)) >=
            RATIO;
    }

    function getAccruedInterest(address _user) public view returns (uint256) {
        return
            ((((s_debt[_user] *
                RATE *
                (block.timestamp - s_lastTimeStamp[_user])) / 86400) *
                ERC_DECIMAL) / 10 ** i_stablecoin_decimals) / 100;
    }

    function getLiquidationPenalty(
        address _user
    ) public view returns (uint256) {
        return
            ((PENALTY * s_debt[_user] * ERC_DECIMAL) /
                10 ** i_stablecoin_decimals) / 100;
    }

    function getCurrentRatio(address _user) public view returns (uint256) {
        uint256 totalCollateralInDecimals = TotalBalanceInDecimals(_user);
        uint256 cRatio;
        if (s_debt[_user] == 0) {
            cRatio = 200;
        } else {
            cRatio =
                ((totalCollateralInDecimals * 100) / ERC_DECIMAL) /
                (s_debt[_user] / 10 ** i_stablecoin_decimals);
        }
        return cRatio;
    }

    function getCurrentRatio(
        uint256 amount,
        address _user
    ) public view returns (uint256) {
        uint256 cRatio;
        if (s_debt[_user] == 0) {
            cRatio = 200;
        } else {
            cRatio = (amount * 100) / (s_debt[_user] * ERC_DECIMAL);
        }
        return cRatio;
    }

    function getWeights(
        IERC20 token,
        address _user
    ) public view returns (uint256) {
        return s_collateral[_user].weightsInPercent[token];
    }

    function getTokens(address _user) public view returns (IERC20[] memory) {
        return s_collateral[_user].erc20s;
    }

    function getAmounts(
        IERC20 token,
        address _user
    ) public view returns (uint256) {
        return s_collateral[_user].tokenAmts[token];
    }

    function getDecimals(
        IERC20 token,
        address _user
    ) public view returns (uint8) {
        return s_collateral[_user].decimals[token];
    }

    function getPriceFeeds(
        IERC20 token,
        address _user
    ) public view returns (AggregatorV3Interface) {
        return s_collateral[_user].priceFeedBasket[token];
    }

    function getBenchmarkFeed(
        address _user
    ) public view returns (AggregatorV3Interface) {
        return s_priceFeedBenchmark;
    }

    function getDebt(address _user) public view returns (uint256) {
        return s_debt[_user];
    }

    function getIsInsolvent(address _user) public view returns (bool) {
        return s_isInsolvent[_user];
    }

    function getUsers() public view onlyNotary returns (address[] memory) {
        return s_users;
    }

    function getlasTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp[msg.sender];
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

    function getStrategy(
        address _user
    ) public view returns (Portfolio.STRATEGY) {
        return s_strategy[_user];
    }
}
