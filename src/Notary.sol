// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
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
    Vault[] public vaults;
    uint256 vaultID;

    event VaultOpened(address vaultAddress);

    uint256 public immutable RATIO;
    address public coinAddress;

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
    function activate(address _coinAddress) public onlyOwner {
        // @Todo check for notary address, investigate recursive implications.
        coinAddress = _coinAddress;
        activated = true;
    }

    /**
     * @dev Opens a position for a specified vault owner address.
     */
    function openVault(
        IERC20[] memory tokens,
        uint8[] memory decimals,
        uint256[] memory weights,
        AggregatorV3Interface[] memory priceFeeds,
        address ownerAddress
    ) public isActivated returns (address positionAddress) {
        Vault vault = new Vault(
            tokens,
            decimals,
            weights,
            priceFeeds,
            coinAddress,
            ownerAddress,
            address(this)
        );
        address _vaultAddress = address(vault);

        isValidPosition[_vaultAddress] = true;
        vaults.push(vault);
        vaultID += 1;

        emit VaultOpened(_vaultAddress);
        return _vaultAddress;
    }

    function liquidateVaults() public onlyOwner {
        uint256 length = vaults.length;
        for (uint256 i = 0; i < length; i++) {
            vaults[i].liquidate();
        }
    }
}
