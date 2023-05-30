// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./BasketHandler.sol";
import "./PriceConverter.sol";
import "./Position.sol";

/**
 * @dev Notary contract registers and authenticates Positions.
 *
 * This contract allows users to open positions, which can be verified
 * during the minting of the stablecoin.
 */
contract Notary is Ownable {
    mapping(address => bool) public isValidPosition;

    event PositionOpened(address positionAddress);

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
    function openPosition(
        IERC20[] memory tokens,
        uint256[] memory weights,
        AggregatorV3Interface[] memory priceFeeds,
        address ownerAddress
    ) public isActivated returns (address positionAddress) {
        Position position = new Position(
            tokens,
            weights,
            priceFeeds,
            coinAddress,
            ownerAddress
        );
        address _positionAddress = address(position);

        isValidPosition[_positionAddress] = true;

        emit PositionOpened(_positionAddress);
        return _positionAddress;
    }
}
