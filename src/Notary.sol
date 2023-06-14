//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {KeeperCompatibleInterface} from
    "lib/chainlink/contracts/src/v0.8/interfaces/automation/KeeperCompatibleInterface.sol";
import {Vault} from "./Vault.sol";
import {Portfolio} from "./Portfolio.sol";
import {INotary} from "./INotary.sol";
import {IWeightProvider} from "./IWeightProvider.sol";

/**
 * @title Notary contract registers and authenticates vaults, portfolio, coin and weightProvider addresses.
 * @notice This contract is the liquidator and portfolio manager.
 * @dev This contract implements Chainlink Keepers.
 *
 * This contract allows users to open one or many vaults, which can be verified
 * during the minting of the stablecoin.
 * The chainlink keepers will trigger liquidations and portfolio rebalancing + chainlink function.
 */

contract Notary is Ownable, INotary, KeeperCompatibleInterface {
    event LiquidationAndRebalancing();
    event NoLiquidation();
    event RequestFailed();
    event VaultOpened(address);

    bool private activated;
    address private weth;
    uint24 private poolFee;

    address public vaultAddress;
    address public coinAddress;
    address public portfolioAddress;
    IWeightProvider public weightProvider;
    mapping(address => bool) public isValidVault;

    uint256 s_lastTimeStamp;
    uint256 i_interval;

    modifier isActivated() {
        require(activated, "Notary has not been activated");
        _;
    }

    constructor(address _weth, uint24 _poolFee) {
        weth = _weth;
        poolFee = _poolFee;
        s_lastTimeStamp = block.timestamp;
        i_interval = 30;
    }

    /**
     * @dev Activates the notary by providing the addresses of a token contract, portfolio and weightProvider
     * that have been configured to reference this address.
     */
    function activate(address _coinAddress, address _portfolio, address _weightProviderAddress) public onlyOwner {
        coinAddress = _coinAddress;
        portfolioAddress = _portfolio;
        weightProvider = IWeightProvider(_weightProviderAddress);

        activated = true;
    }

    /**
     * @dev Opens a vault for a specified vault owner address.
     */
    function openVault(address s_priceFeedBenchmark) public isActivated returns (address) {
        Vault vault = new Vault(
            coinAddress,
            address(this),
            portfolioAddress,
            s_priceFeedBenchmark
        );
        vaultAddress = address(vault);
        isValidVault[vaultAddress] = true;

        emit VaultOpened(vaultAddress);

        return vaultAddress;
    }

    /**
     * @dev This is the function that the chainlink Keeper nodes call
     * they look for the 'upKeepNeeded' to return true
     * The following should be true in order to return true:
     * 1. Our time interval should have passed
     * 2. Vault should have at least 1 user
     * 3. Our subscription is funded with LINK
     * Using bytes can allow to use function as parameters
     */
    function checkUpkeep(bytes memory /*checkData*/ )
        public
        override
        returns (bool upkeepNeeded, bytes memory /*performData*/ )
    {
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasUsers = (Vault(vaultAddress).getUsers().length > 0);
        upkeepNeeded = (timePassed && hasUsers);
        //         upkeepNeeded boolean to indicate whether the keeper should call
        //    * performUpkeep or not.
    }

    /**
     * @dev Once `checkUpkeep` is returning `true`, this function is called
     * and it kicks off the executeRequest function wich triggers a chainlink function and portfolio update.
     * It also triggers the liquidation all defaulted vaults.
     */
    function performUpkeep(bytes calldata /*performData*/ ) external override {
        (bool upkeepNeeded,) = checkUpkeep("");
        require(upkeepNeeded, "upkeepNeeded not needed");

        try weightProvider.executeRequest() {}
        catch {
            emit RequestFailed();
        }

        try this.liquidateVaults() {}
        catch {
            emit NoLiquidation();
        }

        emit LiquidationAndRebalancing();
    }

    /**
     * @dev Rebalances and updates the portfolio of collaterals.
     * The condition is the strategy chosen.
     * For the fixed model it will only updates once.
     * For the dynamic model it will be updated everyday (depending on the interval chosen)
     * For the no strategy it will not be updated
     */
    function updatePortfolio() public {
        require(
            msg.sender == address(weightProvider) || msg.sender == owner() || msg.sender == address(this),
            "must be weight provider to provide weight"
        );
        Vault vault = Vault(vaultAddress);
        uint256 numUsers = vault.getUsers().length;
        for (uint256 j = 0; j < numUsers; j++) {
            bool trigger = vault.getTrigger(vault.getUsers()[j]);
            if (vault.getStrategy(vault.getUsers()[j]) == Portfolio.STRATEGY.FIXED_MODEL && trigger == true) {
                vault.updateCollateralPortfolio(weth, poolFee, vault.getUsers()[j]);
                vault.updateTrigger(vault.getUsers()[j]);
            }
            if (vault.getStrategy(vault.getUsers()[j]) == Portfolio.STRATEGY.DYNAMIC_MODEL) {
                vault.updateCollateralPortfolio(weth, poolFee, vault.getUsers()[j]);
            }
        }
    }

    /**
     * @dev Liquidates the undercollateralized users.
     * It will run everyday (depending on the interval)
     */
    function liquidateVaults() public {
        require(msg.sender == owner() || msg.sender == address(this), "only the owner or Notary can call this function");
        Vault vault = Vault(vaultAddress);
        uint256 numUsers = vault.getUsers().length;
        for (uint256 j = 0; j < numUsers; j++) {
            vault.liquidate(vault.getUsers()[j]);
        }
    }

    // getter functions

    function getPortfolioAddress() public view returns (address) {
        return portfolioAddress;
    }

    function getActivated() public view returns (bool) {
        return activated;
    }

    function getWethAddress() public view returns (address) {
        return weth;
    }

    function getPoolFee() public view returns (uint24) {
        return poolFee;
    }
}
