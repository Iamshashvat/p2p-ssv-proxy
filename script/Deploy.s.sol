// SPDX-FileCopyrightText: 2024 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import "../src/p2pSsvProxyFactory/P2pSsvProxyFactory.sol";
import "../src/mocks/IChangeOperator.sol";

contract Deploy is Script {

    function run() external returns (
        P2pSsvProxyFactory,
        P2pSsvProxy
    ) {
        address p2pOrgUnlimitedEthDepositor = vm.envAddress("P2P_ORG_UNLIMITED_ETH_DEPOSITOR");
        address feeDistributorFactory = vm.envAddress("FEE_DISTRIBUTOR_FACTORY");
        address referenceFeeDistributor = vm.envAddress("REFERENCE_FEE_DISTRIBUTOR");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        P2pSsvProxyFactory p2pSsvProxyFactory = new P2pSsvProxyFactory(
            p2pOrgUnlimitedEthDepositor,
            feeDistributorFactory,
            referenceFeeDistributor
        );
        P2pSsvProxy referenceP2pSsvProxy = new P2pSsvProxy();
        p2pSsvProxyFactory.setReferenceP2pSsvProxy(address(referenceP2pSsvProxy));

        IChangeOperator(address(feeDistributorFactory)).changeOperator(address(p2pSsvProxyFactory));

        p2pSsvProxyFactory.setSsvPerEthExchangeRateDividedByWei(uint112(vm.envUint("EXCHANGE_RATE")));
        p2pSsvProxyFactory.setMaxSsvTokenAmountPerValidator(uint112(vm.envUint("MAX_SSV_TOKEN_AMOUNT_PER_VALIDATOR")));

        vm.stopBroadcast();

        return (
            p2pSsvProxyFactory,
            referenceP2pSsvProxy
        );
    }
}
