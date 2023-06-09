// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;

import "lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "./Notary.sol";
import "./BasketHandler.sol";
import "./PriceConverter.sol";
import "./Vault.sol";

contract Portfolio is Ownable {
    enum STRATEGY {
        NONE,
        FIXED_MODEL,
        DYNAMIC_MODEL
    }

    address[] private s_assetsAddress;
    uint256[] private s_tokenAmounts;
    uint256[] private s_targetWeights;
    uint8[] private s_decimals;
    string[] private s_baseCurrencies;
    mapping(address => STRATEGY) private s_strategy;
    AggregatorV3Interface[] public s_priceFeeds;

    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    // ISwapRouter immutable i_router;
    IUniswapV2Router02 immutable i_routerV2;
    address immutable i_notary;

    event RebalanceEvent(STRATEGY strategy);

    // Basket targetAssets;

    modifier onlyNotary() {
        require(msg.sender == i_notary, "Only the notary can call this function");
        _;
    }

    modifier onlyAuthorized() {
        require(Notary(i_notary).isValidPosition(msg.sender), "Caller is not authorized");
        _;
    }

    constructor(address _uniswapV2Router, address _notaryAddress) {
        // i_router = ISwapRouter(_uniswapV3Router);
        i_routerV2 = IUniswapV2Router02(_uniswapV2Router);
        i_notary = _notaryAddress;
        // for (uint256 i = 0; i < length; ++i) {
        //     targetAssets.add(tokens[i], decimals[i], weights[i], priceFeeds[i]);
        // }
    }

    function updateAssets(
        address[] memory _assetsAddress,
        uint256[] memory _targetWeights,
        uint8[] memory _decimals,
        AggregatorV3Interface[] memory _priceFeeds,
        string[] memory _baseCurrencies
    ) public onlyNotary {
        s_assetsAddress = _assetsAddress;
        s_targetWeights = _targetWeights;
        s_priceFeeds = _priceFeeds;
        s_decimals = _decimals;
        s_baseCurrencies = _baseCurrencies;
    }

    function updateWeights(uint256[] memory _targetWeights) public onlyNotary {
        s_targetWeights = _targetWeights;
    }

    function swapSingleHopExactAmountInV2(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin)
        internal
        returns (uint256 amountOut)
    {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(address(i_routerV2), amountIn);

        address[] memory path;
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts =
            i_routerV2.swapExactTokensForTokens(amountIn, amountOutMin, path, msg.sender, block.timestamp);

        // amounts[0] = WETH amount, amounts[1] = DAI amount
        return amounts[1];
    }

    // function swapExactInputSingleHop(
    //     address tokenIn,
    //     address tokenOut,
    //     uint24 poolFee,
    //     uint amountIn,
    //     bool zeroForOne
    // ) internal returns (uint amountOut) {
    //     IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    //     IERC20(tokenIn).approve(address(i_router), amountIn);

    //     ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
    //         .ExactInputSingleParams({
    //             tokenIn: tokenIn,
    //             tokenOut: tokenOut,
    //             fee: poolFee,
    //             recipient: msg.sender,
    //             deadline: block.timestamp,
    //             amountIn: amountIn,
    //             amountOutMinimum: 0,
    //             sqrtPriceLimitX96: getSqrtPriceLimitX96(zeroForOne)
    //         });

    //     amountOut = i_router.exactInputSingle(params);
    // }

    function calculateTargetInputs(uint256 totalAmountInDecimals, uint256[] memory targetWeights)
        public
        pure
        returns (uint256[] memory targetAmountsInDecimals)
    {
        uint256 length = targetWeights.length;
        targetAmountsInDecimals = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            targetAmountsInDecimals[i] = (totalAmountInDecimals * targetWeights[i]) / 100;
        }
    }

    function rebalancePortfolio(Vault vault, address weth, uint24 _poolFee, address _user) external onlyAuthorized {
        uint256 length = vault.getTokens(_user).length;
        // Rebalance the portfolio by swapping assets
        uint256 wethAmount;
        for (uint256 i = 0; i < length; i++) {
            if (address(vault.getTokens(_user)[i]) == weth) {
                wethAmount += vault.getAmounts(vault.getTokens(_user)[i], _user);
                continue;
            } else {
                // swapExactInputSingleHop(
                //     address(vault.getTokens(_user)[i]),
                //     weth,
                //     _poolFee,
                //     vault.getAmounts(vault.getTokens(_user)[i], _user),
                //     true
                // );
                wethAmount += swapSingleHopExactAmountInV2(
                    address(vault.getTokens(_user)[i]), weth, vault.getAmounts(vault.getTokens(_user)[i], _user), 0
                );
            }
        }
        uint256[] memory targetAmountsInDecimals = calculateTargetInputs(wethAmount, s_targetWeights);

        uint256 lengthW = s_targetWeights.length;
        // Rebalance the portfolio by swapping assets
        for (uint256 i = 0; i < lengthW; i++) {
            // s_tokenAmounts.push(
            //     swapExactInputSingleHop(
            //         weth,
            //         s_assetsAddress[i],
            //         _poolFee,
            //         targetAmountsInDecimals[i],
            //         false
            //     )
            // );
            s_tokenAmounts.push(swapSingleHopExactAmountInV2(weth, s_assetsAddress[i], targetAmountsInDecimals[i], 0));
        }
        uint256 wethBalance = IERC20(weth).balanceOf(address(vault));
        if (wethBalance > 0) {
            s_tokenAmounts.push(wethBalance);
            s_assetsAddress.push(weth);
            s_targetWeights.push(1);
            s_decimals.push(18);
            s_priceFeeds.push(vault.getBenchmarkFeed(_user));
        }

        uint256 lengthV = vault.getTokens(_user).length;
        for (uint256 i = 0; i < lengthV; ++i) {
            uint256 token1Balance = IERC20(vault.getTokens(_user)[i]).balanceOf(address(vault));
            // console.log("************");
            // console.log(token1Balance);
            if (address(vault.getTokens(_user)[i]) != weth) {
                // uint256 token1Balance = IERC20(vault.getTokens()[i]).balanceOf(
                //     address(vault)
                // );
                // console.log("************");
                // console.log(token1Balance);
                if (token1Balance > 0) {
                    s_tokenAmounts.push(token1Balance);
                    s_assetsAddress.push(address(vault.getTokens(_user)[i]));
                    s_targetWeights.push(1);
                    s_decimals.push(vault.getDecimals(vault.getTokens(_user)[i], _user));
                    s_priceFeeds.push(vault.getPriceFeeds(vault.getTokens(_user)[i], _user));
                }
            }
        }
    }

    function getSqrtPriceLimitX96(bool zeroForOne) internal pure returns (uint160) {
        return zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1;
    }

    function getAssets() public view returns (address[] memory) {
        return s_assetsAddress;
    }

    function getAmounts() public view returns (uint256[] memory) {
        return s_tokenAmounts;
    }

    function getWeights() public view returns (uint256[] memory) {
        return s_targetWeights;
    }

    function getDecimals() public view returns (uint8[] memory) {
        return s_decimals;
    }

    function getPriceFeeds() public view returns (AggregatorV3Interface[] memory) {
        return s_priceFeeds;
    }

    function getBaseCurrencies() public view returns (string[] memory) {
        return s_baseCurrencies;
    }
}
