// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface INotary {
    function updateAssetsAndPortfolioTestnet(
        uint256[] memory _targetWeights
    ) external;
}
