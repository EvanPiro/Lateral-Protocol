//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Functions, FunctionsClient} from "./dev/functions/FunctionsClient.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWeightProvider} from "./IWeightProvider.sol";
import {INotary} from "./INotary.sol";
import {Portfolio} from "./Portfolio.sol";

/**
 * @dev Notary contract registers and authenticates Positions.
 *
 * This contract allows users to open positions, which can be verified
 * during the minting of the stablecoin.
 */
contract WeightProvider is Ownable, IWeightProvider, FunctionsClient {
    using Functions for Functions.Request;

    string public source =
        "const b=Functions.makeHttpRequest({ url:'https://www.signdb.com/.netlify/functions/optimize'});const c=Promise.resolve(b);return Functions.encodeUint256(Math.round(c.data['weight']));";
    INotary notary;
    uint64 subId;
    address wethAddress;
    uint24 poolFee = 3000;
    uint32 functionsGasLimit = 500_000;
    uint256 mostRecentWeight;

    constructor(address _oracleAddress, address _notaryAddress, address _wethAddress) FunctionsClient(_oracleAddress) {
        notary = INotary(_notaryAddress);
        wethAddress = _wethAddress;
    }

    function setSubId(uint64 _subId) public onlyOwner {
        subId = _subId;
    }

    function setFunctionsGasLimit(uint32 _functionsGasLimit) public onlyOwner {
        functionsGasLimit = _functionsGasLimit;
    }

    function executeRequest() external override returns (bytes32) {
        require(subId != 0, "Subscription ID must be set before redeeming");
        Functions.Request memory req;
        req.initializeRequest(Functions.Location.Inline, Functions.CodeLanguage.JavaScript, source);
        return sendRequest(req, subId, functionsGasLimit);
    }

    /**
     * @notice User defined function to handle a response
     * @param requestId The request ID, returned by sendRequest()
     * @param response Aggregated response from the user code
     * @param err Aggregated error from the user code or from the execution pipeline
     * Either response or error parameter will be set, but never both
     */
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        uint256 weight = uint256(bytes32(response));
        uint256[] memory weights;
        Portfolio portfolio = Portfolio(notary.getPortfolioAddress());
        weights[0] = weight;
        weights[1] = 1 - weight;
        mostRecentWeight = weight;
        portfolio.updateWeights(weights);
        // portfolio.updateAssets(_assetsAddress, _targetWeights, _decimals, _priceFeeds, _baseCurrencies);
        notary.updatePortfolio();
    }
}
