// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Functions, FunctionsClient} from "./dev/functions/FunctionsClient.sol";
import {Notary} from "./Notary.sol";

/**
 * @dev Notary contract registers and authenticates Positions.
 *
 * This contract allows users to open positions, which can be verified
 * during the minting of the stablecoin.
 */
contract WeightProvider is FunctionsClient {
    string public source =
        "var b=await Functions.makeHttpRequest({url:'https://www.signdb.com/.netlify/functions/optimize'});return Functions.encodeUint256(Math.round(b.data['weight']));";

    Notary notary;

    constructor(address _oracleAddress, address _notaryAddress) FunctionsClient(_oracleAddress) {
        notary = Notary(_notaryAddress);
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
    }
}
