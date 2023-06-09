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

/**
 * @dev Notary contract registers and authenticates Positions.
 *
 * This contract allows users to open positions, which can be verified
 * during the minting of the stablecoin.
 */
contract Notary is Ownable {
    mapping(address => bool) public isValidPosition;
    address public vaultAddress;
    // Vault[] public vaults;
    // uint256 vaultID;

    event VaultOpened(address vaultAddress);

    uint256 public immutable RATIO;
    address public coinAddress;
    address public portfolioAddress;

    bool public activated;

    modifier isActivated() {
        require(activated, "Notary has not been activated");
        _;
    }

    constructor(uint256 _minRatio) {
        RATIO = _minRatio;
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

    // function checkUpkeep(
    //     bytes memory /*checkData*/
    // ) public override returns (bool upkeepNeeded, bytes memory /*performData*/) {

    //     upkeepNeeded = ()
    // }


    // perform upkeep -> execute request
    // fulfill request -> updateAssetsAndPortfolio
    // fulfill request will pass the ratio to updateAssetsAndPortfolio
    // function performUpKeep()
    // chainlink functions
    // Portfolio rebalancing if strategy is dynamic
    // liquidations

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
