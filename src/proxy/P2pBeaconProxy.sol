// SPDX-FileCopyrightText: 2026 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "../@openzeppelin/contracts/utils/Address.sol";

error P2pBeaconProxy__BeaconIsNotAContract(address beacon);
error P2pBeaconProxy__ImplementationIsNotAContract(address implementation);
error P2pBeaconProxy__InitFailed();

/// @title Minimal Beacon Proxy for P2pSsvProxy instances
/// @dev Stores the beacon address as an immutable. All calls are delegated to the implementation
/// returned by the beacon. Initialization data is executed via delegatecall in the constructor.
contract P2pBeaconProxy {
    /// @dev The beacon address is immutable -- the beacon itself manages the implementation pointer.
    address private immutable i_beacon;

    /// @notice Deploy a beacon proxy pointing to `beacon`, optionally initializing via `data`.
    /// @param beacon The UpgradeableBeacon address
    /// @param data   ABI-encoded initializer call (e.g. abi.encodeCall(P2pSsvProxy.initialize, (feeDistributor)))
    constructor(address beacon, bytes memory data) payable {
        if (!Address.isContract(beacon)) revert P2pBeaconProxy__BeaconIsNotAContract(beacon);
        address impl = IBeacon(beacon).implementation();
        if (!Address.isContract(impl)) revert P2pBeaconProxy__ImplementationIsNotAContract(impl);
        i_beacon = beacon;

        if (data.length > 0) {
            (bool success, bytes memory returndata) = impl.delegatecall(data);
            if (!success) {
                if (returndata.length > 0) {
                    assembly ("memory-safe") {
                        revert(add(returndata, 0x20), mload(returndata))
                    }
                }
                revert P2pBeaconProxy__InitFailed();
            }
        }
    }

    /// @dev Delegates the current call to the implementation from the beacon.
    function _delegate(address implementation) internal {
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /// @dev Fallback: delegate all calls to the beacon's current implementation.
    fallback() external payable {
        _delegate(IBeacon(i_beacon).implementation());
    }

    /// @dev Receive: delegate ETH reception to the beacon's current implementation.
    receive() external payable {
        _delegate(IBeacon(i_beacon).implementation());
    }
}
