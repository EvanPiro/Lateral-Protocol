// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IWeightProvider {
    function executeRequest() external returns (bytes32);
}
