// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "lib/chainlink/contracts/src/v0.8/interfaces/automation/KeeperCompatibleInterface.sol";
import "./BasketHandler.sol";
import "./PriceConverter.sol";
import "./Vault.sol";
import "lib/chainlink/contracts/src/v0.8/dev/functions/FunctionsClient.sol";

/**
 * @dev Notary contract registers and authenticates Positions.
 *
 * This contract allows users to open positions, which can be verified
 * during the minting of the stablecoin.
 */
contract Notary is Ownable, KeeperCompatibleInterface, FunctionsClient {
    mapping(address => bool) public isValidPosition;
    address public vaultAddress;
    // Vault[] public vaults;
    // uint256 vaultID;

    event VaultOpened(address vaultAddress);

    uint256 public immutable RATIO;
    address public coinAddress;
    address public portfolioAddress;
    uint256 s_lastTimeStamp;
    uint256 i_interval;

    bool public activated;

    modifier isActivated() {
        require(activated, "Notary has not been activated");
        _;
    }

    constructor(uint256 _minRatio, address _oracleAddress) FunctionsClient(_oracleAddress) {
        RATIO = _minRatio;
        s_lastTimeStamp = block.timestamp;
        i_interval = 30;
    }

    /**
     * @dev Activates the notary by providing the address of a token contract
     * that has been configured to reference this address.
     */
    function activate(
        address _coinAddress,
        address _portfolio
    ) public onlyOwner {
        // @Todo check for notary address, investigate recursive implications.
        coinAddress = _coinAddress;
        portfolioAddress = _portfolio;
        activated = true;
    }

    /**
     * @dev Opens a position for a specified vault owner address.
     */
    function openVault(
        address s_priceFeedBenchmark
    ) public isActivated returns (address) {
        Vault vault = new Vault(
            coinAddress,
            address(this),
            portfolioAddress,
            s_priceFeedBenchmark
        );
        vaultAddress = address(vault);

        isValidPosition[vaultAddress] = true;
        // vaults.push(vault);
        // vaultID += 1;

        emit VaultOpened(vaultAddress);
        return vaultAddress;
    }

    function checkUpkeep(
        bytes memory /*checkData*/
    )
        public
        override
        returns (bool upkeepNeeded, bytes memory /*performData*/)
    {
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasUsers = (Vault(vaultAddress).getUsers().length > 0);
        upkeepNeeded = (timePassed && hasUsers);
        //         upkeepNeeded boolean to indicate whether the keeper should call
        //    * performUpkeep or not.
    }

    function performUpkeep(bytes calldata /*performData*/) external override {
        // Request the random number
        // Once we get it, do something with it
        // 2 transaction process
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {}

        liquidateVaults();

        //call execute requests
    }

    /**
 * @notice User defined function to handle a response
   * @param requestId The request ID, returned by sendRequest()
   * @param response Aggregated response from the user code
   * @param err Aggregated error from the user code or from the execution pipeline
   * Either response or error parameter will be set, but never both
   */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        uint256 weight = uint256(bytes32(response));
        uint256[2] memory _targetWeights;
        _targetWeights[0] = weight;
        _targetWeights[1] = 1 - weight;
    }


    // perform upkeep -> execute request
    // fulfill request -> updateAssetsAndPortfolio
    // fulfill request will pass the ratio to updateAssetsAndPortfolio
    // function performUpKeep()
    // chainlink functions
    // Portfolio rebalancing if strategy is dynamic
    // liquidations

    function updateAssetsAndPortfolioTestnet(
        // address[] memory _assetsAddress,
        uint256[] memory _targetWeights,
        // uint8[] memory _decimals,
        // AggregatorV3Interface[] memory _priceFeeds,
        address weth,
        uint24 _poolFee
    ) public onlyOwner {
        Portfolio(portfolioAddress).updateWeights(_targetWeights);
        Vault vault = Vault(vaultAddress);
        uint256 numUsers = vault.getUsers().length;
        for (uint256 j = 0; j < numUsers; j++) {
            if (
                vault.getStrategy(vault.getUsers()[j]) ==
                Portfolio.STRATEGY.DYNAMIC_MODEL
            ) {
                vault.updateCollateralPortfolio(
                    weth,
                    _poolFee,
                    vault.getUsers()[j]
                );
            }
        }
    }

    function updateAssetsAndPortfolio(
        address[] memory _assetsAddress,
        uint256[] memory _targetWeights,
        uint8[] memory _decimals,
        AggregatorV3Interface[] memory _priceFeeds,
        address weth,
        uint24 _poolFee
    ) public onlyOwner {
        Portfolio(portfolioAddress).updateAssets(
            _assetsAddress,
            _targetWeights,
            _decimals,
            _priceFeeds
        );
        Vault vault = Vault(vaultAddress);
        uint256 numUsers = vault.getUsers().length;
        for (uint256 j = 0; j < numUsers; j++) {
            if (
                vault.getStrategy(vault.getUsers()[j]) ==
                Portfolio.STRATEGY.DYNAMIC_MODEL
            ) {
                vault.updateCollateralPortfolio(
                    weth,
                    _poolFee,
                    vault.getUsers()[j]
                );
            }
        }
    }

    function liquidateVaults() public onlyOwner {
        Vault vault = Vault(vaultAddress);
        uint256 numUsers = vault.getUsers().length;
        for (uint256 j = 0; j < numUsers; j++) {
            vault.liquidate(vault.getUsers()[j]);
        }
    }
}
