//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface INotary {
    function updatePortfolio() external;

    function getPortfolioAddress() external view returns (address);
}
