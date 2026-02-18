// SPDX-FileCopyrightText: 2024 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "../@openzeppelin/contracts/utils/Address.sol";

/// @title Upgradeable Beacon for P2pSsvProxy fleet
/// @dev Minimal beacon implementation. The owner can upgrade the implementation
/// for all P2pBeaconProxy instances that reference this beacon.
contract P2pUpgradeableBeacon is IBeacon {
    address private _implementation;
    address private _owner;

    /// @dev Emitted when the implementation is upgraded.
    event Upgraded(address indexed implementation);

    /// @dev Emitted when ownership is transferred.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Deploy the beacon with an initial implementation and owner.
    /// @param implementation_ The initial implementation contract address
    /// @param owner_ The owner who can call upgradeTo
    constructor(address implementation_, address owner_) {
        require(Address.isContract(implementation_), "P2pUpgradeableBeacon: implementation is not a contract");
        require(owner_ != address(0), "P2pUpgradeableBeacon: owner is the zero address");
        _implementation = implementation_;
        _owner = owner_;
        emit Upgraded(implementation_);
        emit OwnershipTransferred(address(0), owner_);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "P2pUpgradeableBeacon: caller is not the owner");
        _;
    }

    /// @inheritdoc IBeacon
    function implementation() public view override returns (address) {
        return _implementation;
    }

    /// @notice Upgrade the beacon to a new implementation.
    /// @param newImplementation The new implementation contract address
    function upgradeTo(address newImplementation) public onlyOwner {
        require(Address.isContract(newImplementation), "P2pUpgradeableBeacon: implementation is not a contract");
        _implementation = newImplementation;
        emit Upgraded(newImplementation);
    }

    /// @notice Returns the current owner.
    function owner() public view returns (address) {
        return _owner;
    }

    /// @notice Transfer ownership of the beacon.
    /// @param newOwner The new owner address
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "P2pUpgradeableBeacon: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}
