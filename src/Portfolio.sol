// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;

import "lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./Notary.sol";
import "./BasketHandler.sol";
import "./PriceConverter.sol";
import "./Vault.sol";

contract Portfolio {
    enum STRATEGY {
        FIXED_MODEL,
        DYNAMIC_MODEL
    }

    address[] private s_assetsAddress;
    uint256[] private s_tokenAmounts;
    uint256[] private s_targetWeights;
    uint8[] private s_decimals;
    STRATEGY private s_strategy;
    AggregatorV3Interface[] public s_priceFeeds;

    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;
    ISwapRouter immutable i_router;
    ISwapRouter immutable i_routerV2;
    address immutable i_notary;
    address immutable i_dev;

    event RebalanceEvent(STRATEGY strategy);

    // Basket targetAssets;

    modifier onlyNotary() {
        require(
            msg.sender == i_notary,
            "Only the notary can call this function"
        );
        _;
    }

    modifier onlyNotaryOrDev() {
        require(
            msg.sender == i_notary || msg.sender == i_dev,
            "Only the notary or developer can call this function"
        );
        _;
    }

    modifier onlyAuthorized() {
        require(
            Notary(i_notary).isValidPosition(msg.sender),
            "Caller is not authorized"
        );
        _;
    }

    constructor(
        address _uniswapV3Router, // IERC20[] memory tokens, // uint8[] memory decimals, // uint256[] memory weights, // AggregatorV3Interface[] memory priceFeeds
        address __uniswapV2Router,
        address _notaryAddress,
        address dev
    ) {
        i_router = ISwapRouter(_uniswapV3Router);
        i_router = ISwapRouter(_uniswapV2Router);
        i_notary = _notaryAddress;
        i_dev = dev;
        // for (uint256 i = 0; i < length; ++i) {
        //     targetAssets.add(tokens[i], decimals[i], weights[i], priceFeeds[i]);
        // }
    }

    function updateStrategy(uint256 strategy) public {}

    function updateAssets(
        address[] memory _assetsAddress,
        uint256[] memory _targetWeights,
        uint8[] memory _decimals,
        AggregatorV3Interface[] memory _priceFeeds
    ) public onlyNotaryOrDev {
        s_assetsAddress = _assetsAddress;
        s_targetWeights = _targetWeights;
        s_priceFeeds = _priceFeeds;
        s_decimals = _decimals;
    }

    function swapSingleHopExactAmountIn(
        address tokenIn,
        address tokenOut,
        uint amountIn,
        uint amountOutMin
    ) external returns (uint amountOut) {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(address(router), amountIn);

        address[] memory path;
        path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        uint[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            msg.sender,
            block.timestamp
        );

        // amounts[0] = WETH amount, amounts[1] = DAI amount
        return amounts[1];
    }

    function swapExactInputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint amountIn,
        bool zeroForOne
    ) internal returns (uint amountOut) {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(address(i_router), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: getSqrtPriceLimitX96(zeroForOne)
            });

        amountOut = i_router.exactInputSingle(params);
    }

    function calculateTargetInputs(
        uint256 totalAmountInDecimals,
        uint256[] memory targetWeights
    ) public pure returns (uint256[] memory targetAmountsInDecimals) {
        uint256 length = targetWeights.length;
        targetAmountsInDecimals = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            targetAmountsInDecimals[i] =
                (totalAmountInDecimals * targetWeights[i]) /
                100;
        }
    }

    function rebalancePortfolio(
        Vault vault,
        address weth,
        uint24 _poolFee
    ) external onlyAuthorized {
        uint256 length = vault.getTokens().length;
        // Rebalance the portfolio by swapping assets
        for (uint256 i = 0; i < length; i++) {
            if (address(vault.getTokens()[i]) == weth) {
                continue;
            } else {
                swapExactInputSingleHop(
                    address(vault.getTokens()[i]),
                    weth,
                    _poolFee,
                    vault.getAmounts(vault.getTokens()[i]),
                    true
                );
            }
        }
        uint256[] memory targetAmountsInDecimals = calculateTargetInputs(
            IERC20(weth).balanceOf(msg.sender),
            s_targetWeights
        );

        uint256 lengthW = s_targetWeights.length;
        // Rebalance the portfolio by swapping assets
        for (uint256 i = 0; i < lengthW; i++) {
            s_tokenAmounts.push(
                swapExactInputSingleHop(
                    weth,
                    s_assetsAddress[i],
                    _poolFee,
                    targetAmountsInDecimals[i],
                    false
                )
            );
        }
    }

    function getSqrtPriceLimitX96(
        bool zeroForOne
    ) internal pure returns (uint160) {
        return zeroForOne ? 0 : MAX_SQRT_RATIO - 1;
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

    function getPriceFeeds()
        public
        view
        returns (AggregatorV3Interface[] memory)
    {
        return s_priceFeeds;
    }

    function getStrategy() public view returns (STRATEGY) {
        return s_strategy;
    }
}
