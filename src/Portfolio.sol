// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;

import "lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./BasketHandler.sol";
import "./PriceConverter.sol";
import "./Coin.sol";

contract Portfolio {
    function uniswapV3(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) internal returns (uint256 amountOut) {
        address router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        uint24 fee = 3000;
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        ISwapRouter swapRouter = ISwapRouter(router);
        approveToken(tokenIn, address(swapRouter), amountIn);
        // multi hop swaps
        amountOut = swapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(tokenIn, fee, WETH, fee, tokenOut),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0
            })
        );
    }

    function rebalancePortfolio(
        address[] memory targetAssets,
        uint256[] memory targetWeights
    ) external {
        require(
            targetAssets.length == targetWeights.length,
            "Invalid target weights"
        );

        // Get the current collateral and calculate the total value
        IERC20[] memory collateralAssets = collateral.getTokens();
        uint256[] memory collateralAmounts = collateral.getBalances();
        uint256 totalValue = totalBalanceInUSD();

        // Calculate the target values based on the target weights
        uint256[] memory targetValues = collateral.calculateTargetValues(
            totalValue,
            targetWeights
        );

        // Rebalance the portfolio by swapping assets
        for (uint256 i = 0; i < collateralAssets.length; i++) {
            address collateralAsset = address(collateralAssets[i]);
            uint256 amountToRebalance = int256(collateralAmounts[i]) -
                int256(targetValues[i]);

            if (amountToRebalance > 0) {
                // Need to sell some of this asset
                uint256 amountOut = uint256(amountToRebalance);
                uint256 amountIn = uniswapV3(
                    amountOut,
                    collateralAsset,
                    targetAssets[i]
                );
                collateral.updateBalance(
                    collateralAssets[i],
                    collateralAmounts[i].sub(amountIn)
                );
            } else if (amountToRebalance < 0) {
                // Need to buy more of this asset
                uint256 amountIn = uint256(-amountToRebalance);
                uint256 amountOut = uniswapV3(
                    amountIn,
                    targetAssets[i],
                    collateralAsset
                );
                collateral.updateBalance(
                    collateralAssets[i],
                    collateralAmounts[i].add(amountOut)
                );
            }
        }
    }

    function rebalancePortfolio(
        uint256 positionId,
        address[] memory targetAssets,
        uint256[] memory targetWeights
    ) external {
        // Get the position from the positionId
        Position storage position = positions[positionId];

        // Ensure the position is active
        require(position.active, "Invalid position");

        // Get the current collateral and calculate the total value
        address[] memory collateralAssets = position.collateralAssets;
        uint256[] memory collateralAmounts = position.collateralAmounts;
        uint256 totalValue = calculateTotalValue(
            collateralAssets,
            collateralAmounts
        );

        // Calculate the target values based on the target weights
        uint256[] memory targetValues = calculateTargetValues(
            totalValue,
            targetWeights
        );

        // Calculate the amounts needed to rebalance
        int256[] memory amountsToRebalance = calculateAmountsToRebalance(
            collateralAssets,
            collateralAmounts,
            targetValues
        );

        // Rebalance the portfolio by swapping assets
        for (uint256 i = 0; i < collateralAssets.length; i++) {
            address collateralAsset = collateralAssets[i];
            int256 amountToRebalance = amountsToRebalance[i];

            if (amountToRebalance > 0) {
                // Need to buy more of this asset
                uint256 amountIn = uint256(amountToRebalance);
                uint256 amountOut = uniswapV3(
                    amountIn,
                    address(targetAssets[i]),
                    collateralAsset
                );
                position.collateralAmounts[i] = collateralAmounts[i].add(
                    amountOut
                );
            } else if (amountToRebalance < 0) {
                // Need to sell some of this asset
                uint256 amountOut = uint256(-amountToRebalance);
                uint256 amountIn = uniswapV3(
                    amountOut,
                    collateralAsset,
                    address(targetAssets[i])
                );
                position.collateralAmounts[i] = collateralAmounts[i].sub(
                    amountIn
                );
            }
        }

        emit RebalanceEvent(
            positionId,
            collateralAssets,
            collateralAmounts,
            targetAssets,
            targetWeights
        );
    }

    function liquidatePortfolio(uint256 positionId) external {
        // Get the position from the positionId
        Position storage position = positions[positionId];

        // Ensure the position is active
        require(position.active, "Invalid position");

        // Get the collateral assets and amounts
        address[] memory collateralAssets = position.collateralAssets;
        uint256[] memory collateralAmounts = position.collateralAmounts;

        // Liquidate the entire collateral portfolio
        for (uint256 i = 0; i < collateralAssets.length; i++) {
            address collateralAsset = collateralAssets[i];
            uint256 collateralAmount = collateralAmounts[i];

            if (collateralAmount > 0) {
                uint256 amountOut = liquidation(
                    collateralAsset,
                    position.debtAsset,
                    position.user,
                    collateralAmount
                );
                collateralAmounts[i] = 0;

                // Swap collateral asset to debt asset
                uniswapV3(amountOut, collateralAsset, position.debtAsset);
            }
        }

        emit LiquidationEvent(positionId, collateralAssets, collateralAmounts);
    }
}
