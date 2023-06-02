// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;

import "lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./BasketHandler.sol";
import "./PriceConverter.sol";
import "./Vault.sol";

contract Portfolio {
    ISwapRouter immutable router;

    // Basket targetAssets;

    constructor(
        address _uniswapV3Router // IERC20[] memory tokens, // uint8[] memory decimals, // uint256[] memory weights, // AggregatorV3Interface[] memory priceFeeds
    ) {
        router = ISwapRouter(_uniswapV3Router);
        // for (uint256 i = 0; i < length; ++i) {
        //     targetAssets.add(tokens[i], decimals[i], weights[i], priceFeeds[i]);
        // }
    }

    function swapExactInputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint amountIn
    ) external returns (uint amountOut) {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(address(router), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = router.exactInputSingle(params);
    }

    // function rebalancePortfolio(
    //     address[] memory targetAssets,
    //     uint256[] memory targetWeights
    // ) external {
    //     require(
    //         targetAssets.length == targetWeights.length,
    //         "Invalid target weights"
    //     );

    //     // Get the current collateral and calculate the total value
    //     IERC20[] memory collateralAssets = collateral.getTokens();
    //     uint256[] memory collateralAmounts = collateral.getBalances();
    //     uint256 totalValue = totalBalanceInUSD();

    //     // Calculate the target values based on the target weights
    //     uint256[] memory targetValues = collateral.calculateTargetValues(
    //         totalValue,
    //         targetWeights
    //     );

    //     // Rebalance the portfolio by swapping assets
    //     for (uint256 i = 0; i < collateralAssets.length; i++) {
    //         address collateralAsset = address(collateralAssets[i]);
    //         uint256 amountToRebalance = int256(collateralAmounts[i]) -
    //             int256(targetValues[i]);

    //         if (amountToRebalance > 0) {
    //             // Need to sell some of this asset
    //             uint256 amountOut = uint256(amountToRebalance);
    //             uint256 amountIn = uniswapV3(
    //                 amountOut,
    //                 collateralAsset,
    //                 targetAssets[i]
    //             );
    //             collateral.updateBalance(
    //                 collateralAssets[i],
    //                 collateralAmounts[i].sub(amountIn)
    //             );
    //         } else if (amountToRebalance < 0) {
    //             // Need to buy more of this asset
    //             uint256 amountIn = uint256(-amountToRebalance);
    //             uint256 amountOut = uniswapV3(
    //                 amountIn,
    //                 targetAssets[i],
    //                 collateralAsset
    //             );
    //             collateral.updateBalance(
    //                 collateralAssets[i],
    //                 collateralAmounts[i].add(amountOut)
    //             );
    //         }
    //     }
    // }
    function calculateTargetValues(
        uint256 totalValueInDecimals,
        uint256[] memory targetWeights
    ) public returns (uint256[] memory targetAmountsInUsdDecimals) {
        uint256 length = targetWeights.length;
        targetAmountsInUsdDecimals = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            targetAmountsInUsdDecimals[i] =
                (totalValueInDecimals * targetWeights[i]) /
                100;
        }
    }

    function calculateAmountsToRebalance(
        Vault vault,
        address[] memory targetAssets,
        uint256[] memory targetAmountsInUsdDecimals
    )
        public
        returns (
            IERC20[] memory tokenToSwap,
            uint256[] memory colAmounts,
            address[] memory tokenToreceive
        )
    {
        // uint256 lengthCol = vault.getTokens().length;
        // uint256 lengthColTarget = targetAmountsInUsdDecimals.length;
        uint256 k = 0;
        tokenToSwap = new IERC20[](
            vault.getTokens().length + targetAmountsInUsdDecimals.length
        );
        colAmounts = new uint256[](
            vault.getTokens().length + targetAmountsInUsdDecimals.length
        );
        tokenToreceive = new address[](
            vault.getTokens().length + targetAmountsInUsdDecimals.length
        );

        for (uint256 i = 0; i < vault.getTokens().length; i++) {
            // IERC20 token = vault.getTokens()[i];
            // uint8 decimal = vault.getDecimals(vault.getTokens()[i]);
            // uint256 tokenBalance = vault.getTokens()[i].balanceOf(address(vault));
            // uint256 tokenPrice = PriceConverter.getPrice(
            //     vault.getPriceFeed(vault.getTokens()[i])
            // );
            uint256 tokenValueInUsdDecimals = (PriceConverter.getConversionRate(
                vault.getTokens()[i].balanceOf(address(vault)),
                vault.getPriceFeed(vault.getTokens()[i])
            ) * vault.ERC_DECIMAL()) /
                10 ** vault.getDecimals(vault.getTokens()[i]);

            for (uint256 j = 0; j < targetAmountsInUsdDecimals.length; j++) {
                if (tokenValueInUsdDecimals > targetAmountsInUsdDecimals[j]) {
                    tokenToSwap[k] = vault.getTokens()[i];
                    colAmounts[k] =
                        (targetAmountsInUsdDecimals[j] *
                            10 ** vault.getDecimals(vault.getTokens()[i])) /
                        PriceConverter.getPrice(
                            vault.getPriceFeed(vault.getTokens()[i])
                        );
                    tokenToreceive[k] = targetAssets[j];
                    k = k + 1;
                    tokenValueInUsdDecimals -= targetAmountsInUsdDecimals[j];
                    console.log(colAmounts[k]);
                    // console.log(tokenToSwap[k]);
                    console.log(tokenToreceive[k]);
                } else {
                    tokenToSwap[k] = vault.getTokens()[i];
                    colAmounts[k] =
                        (tokenValueInUsdDecimals *
                            10 ** vault.getDecimals(vault.getTokens()[i])) /
                        PriceConverter.getPrice(
                            vault.getPriceFeed(vault.getTokens()[i])
                        );
                    tokenToreceive[k] = targetAssets[j];
                    targetAmountsInUsdDecimals[j] -= tokenValueInUsdDecimals;
                    console.log(colAmounts[k]);
                    // console.log(tokenToSwap[k]);
                    console.log(tokenToreceive[k]);
                    k = k + 1;
                    tokenValueInUsdDecimals = 0;

                    break;
                }
            }
        }
    }

    // function rebalancePortfolio(
    //     Vault vault,
    //     address[] memory targetAssets,
    //     uint256[] memory targetWeights
    // ) external {
    //     // // Get the position from the positionId
    //     // Position storage position = positions[positionId];

    //     // Ensure the position is active
    //     // require(position.active, "Invalid position");

    //     // Get the current collateral and calculate the total value
    //     // address[] memory collateralAssets = position.collateralAssets;
    //     // uint256[] memory collateralAmounts = position.collateralAmounts;
    //     uint256 totalValueInDecimals = vault.TotalBalanceInDecimals();

    //     // Calculate the target Amounts based on the target weights
    //     uint256[] memory targetAmountsInUsdDecimals = calculateTargetValues(
    //         totalValueInDecimals,
    //         targetWeights
    //     );

    //     // Calculate the amounts needed to rebalance
    //     // This
    //     int256[] memory amountsToRebalance = calculateAmountsToRebalance(
    //         collateralAssets,
    //         collateralAmounts,
    //         targetAmountsInTokenDecimals
    //     );

    //     // Rebalance the portfolio by swapping assets
    //     for (uint256 i = 0; i < collateralAssets.length; i++) {
    //         address collateralAsset = collateralAssets[i];
    //         int256 amountToRebalance = amountsToRebalance[i];

    //         if (amountToRebalance > 0) {
    //             // Need to buy more of this asset
    //             uint256 amountIn = uint256(amountToRebalance);
    //             uint256 amountOut = uniswapV3(
    //                 amountIn,
    //                 address(targetAssets[i]),
    //                 collateralAsset
    //             );
    //             position.collateralAmounts[i] = collateralAmounts[i].add(
    //                 amountOut
    //             );
    //         } else if (amountToRebalance < 0) {
    //             // Need to sell some of this asset
    //             uint256 amountOut = uint256(-amountToRebalance);
    //             uint256 amountIn = uniswapV3(
    //                 amountOut,
    //                 collateralAsset,
    //                 address(targetAssets[i])
    //             );
    //             position.collateralAmounts[i] = collateralAmounts[i].sub(
    //                 amountIn
    //             );
    //         }
    //     }

    //     emit RebalanceEvent(
    //         positionId,
    //         collateralAssets,
    //         collateralAmounts,
    //         targetAssets,
    //         targetWeights
    //     );
    // }
}
