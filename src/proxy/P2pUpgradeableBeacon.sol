// SPDX-FileCopyrightText: 2026 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "../@openzeppelin/contracts/utils/Address.sol";

error P2pUpgradeableBeacon__ImplementationIsNotAContract(address implementation);
error P2pUpgradeableBeacon__ZeroOwnerAddress();
error P2pUpgradeableBeacon__CallerIsNotTheOwner(address caller);
error P2pUpgradeableBeacon__ZeroNewOwnerAddress();

/// @title Upgradeable Beacon for P2pSsvProxy fleet
/// @dev Minimal beacon implementation. The owner can upgrade the implementation
/// for all P2pBeaconProxy instances that reference this beacon.
contract P2pUpgradeableBeacon is IBeacon {
    address private s_implementation;
    address private s_owner;

    /// @dev Emitted when the implementation is upgraded.
    event P2pUpgradeableBeacon__Upgraded(address indexed implementation);

    /// @dev Emitted when ownership is transferred.
    event P2pUpgradeableBeacon__OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Deploy the beacon with an initial implementation and owner.
    /// @param implementation_ The initial implementation contract address
    /// @param owner_ The owner who can call upgradeTo
    constructor(address implementation_, address owner_) {
        if (!Address.isContract(implementation_)) revert P2pUpgradeableBeacon__ImplementationIsNotAContract(implementation_);
        if (owner_ == address(0)) revert P2pUpgradeableBeacon__ZeroOwnerAddress();
        s_implementation = implementation_;
        s_owner = owner_;
        emit P2pUpgradeableBeacon__Upgraded(implementation_);
        emit P2pUpgradeableBeacon__OwnershipTransferred(address(0), owner_);
    }

    modifier onlyOwner() {
        if (msg.sender != s_owner) revert P2pUpgradeableBeacon__CallerIsNotTheOwner(msg.sender);
        _;
    }

    /// @inheritdoc IBeacon
    function implementation() public view override returns (address) {
        return s_implementation;
    }

    /// @notice Upgrade the beacon to a new implementation.
    /// @param newImplementation The new implementation contract address
    function upgradeTo(address newImplementation) public onlyOwner {
        if (!Address.isContract(newImplementation)) revert P2pUpgradeableBeacon__ImplementationIsNotAContract(newImplementation);
        s_implementation = newImplementation;
        emit P2pUpgradeableBeacon__Upgraded(newImplementation);
    }

    /// @notice Returns the current owner.
    function owner() public view returns (address) {
        return s_owner;
    }

    /// @notice Transfer ownership of the beacon.
    /// @param newOwner The new owner address
    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner == address(0)) revert P2pUpgradeableBeacon__ZeroNewOwnerAddress();
        emit P2pUpgradeableBeacon__OwnershipTransferred(s_owner, newOwner);
        s_owner = newOwner;
    }
}
