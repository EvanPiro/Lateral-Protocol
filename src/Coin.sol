//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Basket} from "./libraries/BasketHandler.sol";
import {PriceConverter} from "./libraries/PriceConverter.sol";
import {Notary} from "./Notary.sol";

/**
 * @dev Coin contract manages the supply of the stable coin.
 *
 * This contract is simple ER20 token contract with constraints on minting, where minting
 * is limited to a Notary registered Vault that is above the mininum collateralization
 * ratio.
 */
contract Coin is ERC20 {
    Notary notary;

    modifier onlyAuthorized() {
        require(notary.isValidVault(msg.sender), "Caller is not authorized");
        _;
    }

    constructor(address _notaryAddress) ERC20("LateralProtcol USD", "LATP") {
        notary = Notary(_notaryAddress);
    }

    function decimals() public view override returns (uint8) {
        return 18;
    }

    /**
     * @dev Mints for authenticated position contracts.
     */

    function mint(address _positionAddress, address _receiver, uint256 _moreDebt) external onlyAuthorized {
        _mint(_receiver, _moreDebt);
    }

    function burn(address owner, uint256 _stablecoinAmount) external onlyAuthorized {
        require(_stablecoinAmount > 0, "Invalid stablecoin amount");

        _burn(owner, _stablecoinAmount);
    }
}
