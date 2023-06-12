// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

// import "lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Notary} from "./Notary.sol";
import {Basket} from "./libraries/BasketHandler.sol";
import "./libraries/PriceConverter.sol";
import {Vault} from "./Vault.sol";

/**
 * @title Portfolio contract updates the basket collateral portfolio into new target assets.
 * @notice This contract can update the targets assets and swap old tokens for new ones.
 * @dev This contract implements uniswapV2/V3 swap functions to swap tokens.
 */
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
    AggregatorV3Interface[] private s_priceFeeds;
    string[] private s_baseCurrencies;
    mapping(address => STRATEGY) private s_strategy;

    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    // ISwapRouter immutable i_router;
    IUniswapV2Router02 immutable i_routerV2;
    address immutable i_notary;
    address immutable i_weightProvider;

    event RebalanceEvent(STRATEGY strategy);

    modifier onlyNotary() {
        require(msg.sender == i_notary, "Only the notary can call this function");
        _;
    }

    modifier onlyOwnerOrWeightProvider() {
        require(
            msg.sender == owner() || msg.sender == i_weightProvider,
            "Only the owner or weightProvider can call this function"
        );
        _;
    }

    modifier onlyAuthorized() {
        require(Notary(i_notary).isValidVault(msg.sender), "Caller is not authorized");
        _;
    }

    constructor(address _uniswapV2Router, address _notaryAddress, address _weightProvider) {
        // i_router = ISwapRouter(_uniswapV3Router);
        i_routerV2 = IUniswapV2Router02(_uniswapV2Router);
        i_notary = _notaryAddress;
        i_weightProvider = _weightProvider;
    }

    /**
     * @dev Updates the targets Assets by providing the tokens addresses, weights ...
     * The goal is to have this function be automatically called and updated, without providing any data.
     * A chainlink function will call an API that executes a model which will chose the target assets and weights.
     * We are currently trying to find a way to make the Chainlink request return an array rather than int.
     */
    function updateAssets(
        address[] memory _assetsAddress,
        uint256[] memory _targetWeights,
        uint8[] memory _decimals,
        AggregatorV3Interface[] memory _priceFeeds,
        string[] memory _baseCurrencies
    ) public onlyOwnerOrWeightProvider {
        s_assetsAddress = _assetsAddress;
        s_targetWeights = _targetWeights;
        s_priceFeeds = _priceFeeds;
        s_decimals = _decimals;
        s_baseCurrencies = _baseCurrencies;
    }

    /**
     * @dev Updates only the weights of the target assets. Currently the Chainlink request function
     * can only retrieve one interger. Currently the portfolio can only be rebalanced into 2 assets.
     * The other weight will be calculated using the first one retrieved.
     */
    function updateWeights(uint256[] memory _targetWeights) public onlyOwnerOrWeightProvider {
        s_targetWeights = _targetWeights;
    }

    /**
     * @dev Function to swap tokens.
     * It uses the swapExactTokensForTokens from UniswapV2.
     */
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

    /**
     * @dev Function to swap tokens.
     * It uses the swapExactTokensForTokens from UniswapV3.
     * Currently we are favoring UniswapV2 because more liquid pools exist there.
     */
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

    /**
     * @dev Calculates the amounts that will be used for each swap.
     * It corresponds to the amountIn in the Uniswap Function.
     */
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

    /**
     * @dev Function that will do all the rebalancing.
     * Can only be called by authenticated vault contracts.
     * It will perform two series of swaps:
     * 1. Swap everything to Weth
     * 2. Swap to targets assets using the target Amounts calculated via calculateTargetInputs() function
     */
    function rebalancePortfolio(Vault vault, address weth, uint24 _poolFee, address _user) external onlyAuthorized {
        uint256 length = vault.getTokens(_user).length;
        // Rebalance the portfolio by swapping assets
        uint256 wethAmount;
        for (uint256 i = 0; i < length; i++) {
            if (address(vault.getTokens(_user)[i]) == weth) {
                wethAmount += vault.getAmounts(vault.getTokens(_user)[i], _user);
                continue;
            } else {
                wethAmount += swapSingleHopExactAmountInV2(
                    address(vault.getTokens(_user)[i]), weth, vault.getAmounts(vault.getTokens(_user)[i], _user), 0
                );
            }
        }
        uint256[] memory targetAmountsInDecimals = calculateTargetInputs(wethAmount, s_targetWeights);
        uint256 lengthW = s_targetWeights.length;
        delete s_tokenAmounts;
        // Rebalance the portfolio by swapping assets
        for (uint256 i = 0; i < lengthW; i++) {
            if (s_assetsAddress[i] == weth) {
                s_tokenAmounts.push(targetAmountsInDecimals[i]);
            } else {
                s_tokenAmounts.push(
                    swapSingleHopExactAmountInV2(weth, s_assetsAddress[i], targetAmountsInDecimals[i], 0)
                );
            }
        }
    }

    //getter functions

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
