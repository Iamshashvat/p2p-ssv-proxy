// SPDX-FileCopyrightText: 2024 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";

import "../src/p2pSsvProxyFactory/P2pSsvProxyFactory.sol";
import "../src/p2pSsvProxy/P2pSsvProxy.sol";
import "../src/proxy/P2pUpgradeableBeacon.sol";
import "../src/proxy/P2pBeaconProxy.sol";
import "../src/interfaces/ssv/ISSVClustersEth.sol";
import "../src/interfaces/ssv/ISSVNetworkEth.sol";
import "../src/interfaces/ssv/ISSVViews.sol";
import "../src/structs/P2pStructs.sol";
import "../src/access/OwnableBase.sol";

contract MockFeeDistributor is ERC165 {
    address private _client;

    constructor(address client_) {
        _client = client_;
    }

    function client() external view returns (address) { return _client; }
    function factory() external pure returns (address) { return address(0); }
    function service() external pure returns (address) { return address(0); }
    function clientBasisPoints() external pure returns (uint256) { return 9500; }
    function referrer() external pure returns (address) { return address(0); }
    function referrerBasisPoints() external pure returns (uint256) { return 0; }

    function initialize(FeeRecipient calldata, FeeRecipient calldata) external {}

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFeeDistributor).interfaceId || super.supportsInterface(interfaceId);
    }
}

contract MockFeeDistributorFactory is ERC165 {
    address private _owner;
    MockFeeDistributor public feeDistInstance;

    constructor(address owner_, address client_) {
        _owner = owner_;
        feeDistInstance = new MockFeeDistributor(client_);
    }

    function owner() external view returns (address) { return _owner; }
    function operator() external view returns (address) { return _owner; }

    function predictFeeDistributorAddress(
        address,
        FeeRecipient calldata,
        FeeRecipient calldata
    ) external view returns (address) {
        return address(feeDistInstance);
    }

    function createFeeDistributor(
        address,
        FeeRecipient calldata,
        FeeRecipient calldata
    ) external view returns (address) {
        return address(feeDistInstance);
    }

    function checkOperatorOrOwner(address) external view {}
    function checkP2pEth2Depositor(address) external view {}
    function check_Operator_Owner_P2pEth2Depositor(address) external view {}
    function allClientFeeDistributors(address) external pure returns (address[] memory) { return new address[](0); }
    function allFeeDistributors() external pure returns (address[] memory) { return new address[](0); }
    function p2pEth2Depositor() external pure returns (address) { return address(0); }
    function defaultClientBasisPoints() external pure returns (uint96) { return 9000; }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFeeDistributorFactory).interfaceId || super.supportsInterface(interfaceId);
    }
}

contract MockP2pOrgUnlimitedEthDepositor is ERC165 {
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IP2pOrgUnlimitedEthDepositor).interfaceId || super.supportsInterface(interfaceId);
    }

    function addEth(bytes32, uint96, address, FeeRecipient calldata, FeeRecipient calldata, bytes calldata)
        external payable returns (bytes32, address) { return (bytes32(0), address(0)); }
    function enableEip7251() external {}
    function rejectService(bytes32, string calldata) external {}
    function refund(bytes32, uint96, address) external {}
    function makeBeaconDeposit(bytes32, uint96, address, bytes[] calldata, bytes[] calldata, bytes32[] calldata) external {}
    function totalBalance() external pure returns (uint256) { return 0; }
    function getDepositId(bytes32, uint96, address) external pure returns (bytes32) { return bytes32(0); }
    function getDepositId(bytes32, uint96, address, FeeRecipient calldata, FeeRecipient calldata) external pure returns (bytes32) { return bytes32(0); }
    function depositAmount(bytes32) external pure returns (uint112) { return 0; }
    function depositExpiration(bytes32) external pure returns (uint40) { return 0; }
    function depositStatus(bytes32) external pure returns (ClientDepositStatus) { return ClientDepositStatus.None; }
}

// ──────────────────────────────────────────────
// Test contract
// ──────────────────────────────────────────────

contract HoodiEthUpgrade is Test {
    address public constant SSV_NETWORK = 0x58410Bef803ECd7E63B23664C586A6DB72DAf59c;

    address public owner;
    address public operator;
    address public nobody;
    address payable public client;

    P2pSsvProxyFactory public factory;
    P2pSsvProxy public referenceProxy;
    P2pUpgradeableBeacon public beacon;
    MockFeeDistributor public mockFeeDistributor;
    MockFeeDistributorFactory public mockFeeDistFactory;
    MockP2pOrgUnlimitedEthDepositor public mockEthDepositor;

    FeeRecipient public clientConfig;
    FeeRecipient public referrerConfig;

    address[] public allowedOperatorOwners;
    uint64[] public operatorIds;

    event P2pSsvProxy__EthReceived(address indexed _sender, uint256 _amount);
    event P2pSsvProxy__SuccessfullyCalledViaFallback(address indexed _caller, bytes4 indexed _selector);
    event P2pSsvProxy__P2pSsvProxyFactorySet(address indexed _oldFactory, address indexed _newFactory);
    event P2pSsvProxy__Initialized(address indexed _feeDistributor);
    event P2pSsvProxyFactory__EthRegistrationCompleted(address indexed _proxy, uint256 _ethToSsv);
    event P2pSsvProxyFactory__ClusterMigrationInitiated(address indexed _proxy, uint256 _ethDeposited);
    event P2pSsvProxyFactory__P2pSsvProxyCreated(address indexed _p2pSsvProxy, address indexed _client, address indexed _feeDistributor);
    event P2pSsvProxyFactory__BeaconSet(address indexed _beacon);

    function setUp() public {
        vm.createSelectFork("hoodi");

        owner = address(this);
        operator = address(0xB0B);
        nobody = address(0xdead);
        client = payable(address(0xc11e));

        mockEthDepositor = new MockP2pOrgUnlimitedEthDepositor();
        mockFeeDistFactory = new MockFeeDistributorFactory(owner, client);
        mockFeeDistributor = mockFeeDistFactory.feeDistInstance();

        factory = new P2pSsvProxyFactory(
            address(mockEthDepositor),
            address(mockFeeDistFactory),
            address(mockFeeDistributor)
        );

        referenceProxy = new P2pSsvProxy();
        factory.setReferenceP2pSsvProxy(address(referenceProxy));

        beacon = new P2pUpgradeableBeacon(address(referenceProxy), owner);

        operatorIds = new uint64[](4);
        operatorIds[0] = 1;
        operatorIds[1] = 2;
        operatorIds[2] = 3;
        operatorIds[3] = 4;

        allowedOperatorOwners = new address[](4);
        allowedOperatorOwners[0] = address(0xA1);
        allowedOperatorOwners[1] = address(0xA2);
        allowedOperatorOwners[2] = address(0xA3);
        allowedOperatorOwners[3] = address(0xA4);

        clientConfig = FeeRecipient({ recipient: client, basisPoints: 9500 });
        referrerConfig = FeeRecipient({ recipient: payable(address(0)), basisPoints: 0 });

        factory.setSsvPerEthExchangeRateDividedByWei(7539000000000000);
        factory.setMaxSsvTokenAmountPerValidator(30 ether);
    }

    function _getEmptyCluster() internal pure returns (ISSVNetworkCore.Cluster memory) {
        return ISSVNetworkCore.Cluster({
            validatorCount: 0,
            networkFeeIndex: 0,
            index: 0,
            active: true,
            balance: 0
        });
    }

    function _deployProxyViaClone() internal returns (address proxy) {
        proxy = factory.createP2pSsvProxy(address(mockFeeDistributor));
    }

    function _deployProxyViaBeacon() internal returns (address proxy) {
        factory.setBeacon(address(beacon));
        proxy = factory.createP2pSsvProxy(address(mockFeeDistributor));
    }

    function _mockSsvCall(bytes memory callData) internal {
        vm.mockCall(SSV_NETWORK, callData, "");
    }

    function _mockSsvCallWithValue(uint256 value, bytes memory callData) internal {
        vm.mockCall(SSV_NETWORK, value, callData, "");
    }

    function _mockSsvViewsOperator(uint64 opId, address opOwner) internal {
        address ssvViews = 0x5AdDb3f1529C5ec70D77400499eE4bbF328368fe;
        vm.mockCall(
            ssvViews,
            abi.encodeWithSelector(ISSVViews.getOperatorById.selector, opId),
            abi.encode(opOwner, uint256(0), uint32(0), address(0), false, false)
        );
    }

    function _buildSingleValidatorData() internal pure returns (bytes[] memory pubkeys, bytes[] memory sharesData) {
        pubkeys = new bytes[](1);
        pubkeys[0] = hex"aabbcc";
        sharesData = new bytes[](1);
        sharesData[0] = hex"ddeeff";
    }

    function _configureAllowedOperatorsAndIds() internal {
        factory.setAllowedSsvOperatorOwners(allowedOperatorOwners);

        _mockSsvViewsOperator(operatorIds[0], allowedOperatorOwners[0]);
        _mockSsvViewsOperator(operatorIds[1], allowedOperatorOwners[1]);
        _mockSsvViewsOperator(operatorIds[2], allowedOperatorOwners[2]);
        _mockSsvViewsOperator(operatorIds[3], allowedOperatorOwners[3]);

        factory.setSsvOperatorIds([operatorIds[0],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], allowedOperatorOwners[0]);
        factory.setSsvOperatorIds([operatorIds[1],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], allowedOperatorOwners[1]);
        factory.setSsvOperatorIds([operatorIds[2],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], allowedOperatorOwners[2]);
        factory.setSsvOperatorIds([operatorIds[3],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], allowedOperatorOwners[3]);
    }

    // ═══════════════════════════════════════════
    // A. Beacon Proxy Deployment
    // ═══════════════════════════════════════════

    function test_beaconProxyDeployment() public {
        factory.setBeacon(address(beacon));

        address proxy = factory.createP2pSsvProxy(address(mockFeeDistributor));

        assertTrue(proxy != address(0));
        assertEq(P2pSsvProxy(payable(proxy)).getFactory(), address(factory));
        assertEq(P2pSsvProxy(payable(proxy)).getClient(), client);
        assertEq(P2pSsvProxy(payable(proxy)).getFeeDistributor(), address(mockFeeDistributor));
        assertTrue(factory.isWhitelisted(proxy, 0));
    }

    function test_beaconProxyAddressPrediction() public {
        factory.setBeacon(address(beacon));

        address predicted = factory.predictP2pSsvProxyAddressBeacon(address(mockFeeDistributor));
        address actual = factory.createP2pSsvProxy(address(mockFeeDistributor));

        assertEq(predicted, actual);
    }

    function test_cloneFallbackWhenNoBeacon() public {
        address proxy = factory.createP2pSsvProxy(address(mockFeeDistributor));

        assertTrue(proxy != address(0));
        assertEq(P2pSsvProxy(payable(proxy)).getFactory(), address(factory));

        vm.expectRevert(P2pSsvProxyFactory__BeaconNotSet.selector);
        factory.predictP2pSsvProxyAddressBeacon(address(mockFeeDistributor));
    }

    // ═══════════════════════════════════════════
    // B. ETH-Native Proxy Methods
    // ═══════════════════════════════════════════

    function test_bulkRegisterValidatorsEth() public {
        address proxy = _deployProxyViaClone();

        (bytes[] memory pubkeys, bytes[] memory sharesData) = _buildSingleValidatorData();
        ISSVNetworkCore.Cluster memory cluster = _getEmptyCluster();

        vm.expectCall(
            SSV_NETWORK,
            1 ether,
            abi.encodeWithSelector(
                ISSVClustersEth.bulkRegisterValidator.selector,
                pubkeys,
                operatorIds,
                sharesData,
                cluster
            )
        );
        vm.expectCall(
            SSV_NETWORK,
            abi.encodeWithSelector(ISSVNetworkEth.setFeeRecipientAddress.selector, address(mockFeeDistributor))
        );
        _mockSsvCallWithValue(1 ether, abi.encodeWithSelector(
            ISSVClustersEth.bulkRegisterValidator.selector
        ));
        _mockSsvCall(abi.encodeWithSelector(ISSVNetworkEth.setFeeRecipientAddress.selector));

        vm.deal(address(factory), 10 ether);
        vm.prank(address(factory));
        P2pSsvProxy(payable(proxy)).bulkRegisterValidatorsEth{value: 1 ether}(
            pubkeys, operatorIds, sharesData, cluster
        );

        vm.prank(nobody);
        vm.expectRevert();
        P2pSsvProxy(payable(proxy)).bulkRegisterValidatorsEth{value: 1 ether}(
            pubkeys, operatorIds, sharesData, cluster
        );
    }

    function test_depositToSsvEth() public {
        address proxy = _deployProxyViaClone();

        ISSVNetworkCore.Cluster[] memory clusters = new ISSVNetworkCore.Cluster[](2);
        clusters[0] = _getEmptyCluster();
        clusters[1] = _getEmptyCluster();

        vm.expectCall(
            SSV_NETWORK,
            0.5 ether,
            abi.encodeWithSelector(ISSVClustersEth.deposit.selector, proxy, operatorIds, clusters[0])
        );
        vm.expectCall(
            SSV_NETWORK,
            0.5 ether,
            abi.encodeWithSelector(ISSVClustersEth.deposit.selector, proxy, operatorIds, clusters[1])
        );
        _mockSsvCallWithValue(0.5 ether, abi.encodeWithSelector(ISSVClustersEth.deposit.selector));

        vm.deal(proxy, 0);
        vm.deal(address(this), 10 ether);
        P2pSsvProxy(payable(proxy)).depositToSsvEth{value: 1 ether}(operatorIds, clusters);

        ISSVNetworkCore.Cluster[] memory empty = new ISSVNetworkCore.Cluster[](0);
        vm.expectRevert(P2pSsvProxy__AmountOfParametersError.selector);
        P2pSsvProxy(payable(proxy)).depositToSsvEth{value: 1 ether}(operatorIds, empty);
    }

    function test_depositToSsvEth_dustHandling() public {
        address proxy = _deployProxyViaClone();

        ISSVNetworkCore.Cluster[] memory clusters = new ISSVNetworkCore.Cluster[](3);
        clusters[0] = _getEmptyCluster();
        clusters[1] = _getEmptyCluster();
        clusters[2] = _getEmptyCluster();
        clusters[1].validatorCount = 1;
        clusters[2].validatorCount = 2;

        vm.expectCall(
            SSV_NETWORK,
            3,
            abi.encodeWithSelector(ISSVClustersEth.deposit.selector, proxy, operatorIds, clusters[0])
        );
        vm.expectCall(
            SSV_NETWORK,
            3,
            abi.encodeWithSelector(ISSVClustersEth.deposit.selector, proxy, operatorIds, clusters[1])
        );
        vm.expectCall(
            SSV_NETWORK,
            4,
            abi.encodeWithSelector(ISSVClustersEth.deposit.selector, proxy, operatorIds, clusters[2])
        );
        _mockSsvCallWithValue(3, abi.encodeWithSelector(ISSVClustersEth.deposit.selector));
        _mockSsvCallWithValue(4, abi.encodeWithSelector(ISSVClustersEth.deposit.selector));

        vm.deal(address(this), 10 ether);
        P2pSsvProxy(payable(proxy)).depositToSsvEth{value: 10}(operatorIds, clusters);
    }

    function test_reactivateEth() public {
        address proxy = _deployProxyViaClone();

        ISSVNetworkCore.Cluster[] memory clusters = new ISSVNetworkCore.Cluster[](1);
        clusters[0] = _getEmptyCluster();

        vm.expectCall(
            SSV_NETWORK,
            1 ether,
            abi.encodeWithSelector(ISSVClustersEth.reactivate.selector, operatorIds, clusters[0])
        );
        _mockSsvCallWithValue(1 ether, abi.encodeWithSelector(ISSVClustersEth.reactivate.selector));

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        P2pSsvProxy(payable(proxy)).reactivateEth{value: 1 ether}(operatorIds, clusters);

        vm.deal(nobody, 10 ether);
        vm.prank(nobody);
        vm.expectRevert();
        P2pSsvProxy(payable(proxy)).reactivateEth{value: 1 ether}(operatorIds, clusters);

        ISSVNetworkCore.Cluster[] memory empty = new ISSVNetworkCore.Cluster[](0);
        vm.prank(owner);
        vm.expectRevert(P2pSsvProxy__AmountOfParametersError.selector);
        P2pSsvProxy(payable(proxy)).reactivateEth{value: 1 ether}(operatorIds, empty);
    }

    function test_migrateClusterToETH_proxy() public {
        address proxy = _deployProxyViaClone();

        ISSVNetworkCore.Cluster memory cluster = _getEmptyCluster();

        vm.expectCall(
            SSV_NETWORK,
            5 ether,
            abi.encodeWithSelector(ISSVClustersEth.migrateClusterToETH.selector, operatorIds, cluster)
        );
        _mockSsvCallWithValue(5 ether, abi.encodeWithSelector(ISSVClustersEth.migrateClusterToETH.selector));

        vm.deal(address(factory), 10 ether);
        vm.prank(address(factory));
        P2pSsvProxy(payable(proxy)).migrateClusterToETH{value: 5 ether}(operatorIds, cluster);

        vm.deal(nobody, 10 ether);
        vm.prank(nobody);
        vm.expectRevert();
        P2pSsvProxy(payable(proxy)).migrateClusterToETH{value: 5 ether}(operatorIds, cluster);
    }

    function test_liquidateSSV_viaFallback_operatorSelector() public {
        address proxy = _deployProxyViaClone();

        factory.changeOperator(operator);

        bytes4 selector = ISSVClustersEth.liquidateSSV.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        factory.setAllowedSelectorsForOperator(selectors);

        ISSVNetworkCore.Cluster memory cluster = _getEmptyCluster();
        bytes memory callData = abi.encodeWithSelector(
            selector,
            proxy,
            operatorIds,
            cluster
        );

        vm.expectCall(SSV_NETWORK, callData);
        _mockSsvCall(callData);

        vm.prank(operator);
        (bool success,) = proxy.call(callData);
        assertTrue(success);
    }

    // ═══════════════════════════════════════════
    // C. ETH-Native Factory Methods
    // ═══════════════════════════════════════════

    function test_registerValidatorsEth() public {
        factory.setBeacon(address(beacon));
        _configureAllowedOperatorsAndIds();
        (bytes[] memory pubkeys, bytes[] memory sharesData) = _buildSingleValidatorData();

        vm.expectCall(
            SSV_NETWORK,
            1 ether,
            abi.encodeWithSelector(
                ISSVClustersEth.bulkRegisterValidator.selector,
                pubkeys,
                operatorIds,
                sharesData,
                _getEmptyCluster()
            )
        );
        vm.expectCall(
            SSV_NETWORK,
            abi.encodeWithSelector(ISSVNetworkEth.setFeeRecipientAddress.selector, address(mockFeeDistributor))
        );
        _mockSsvCallWithValue(1 ether, abi.encodeWithSelector(ISSVClustersEth.bulkRegisterValidator.selector));
        _mockSsvCall(abi.encodeWithSelector(ISSVNetworkEth.setFeeRecipientAddress.selector));

        vm.deal(client, 10 ether);
        vm.prank(client);
        address proxy = factory.registerValidatorsEth{value: 1 ether}(
            allowedOperatorOwners,
            operatorIds,
            pubkeys,
            sharesData,
            _getEmptyCluster(),
            clientConfig,
            referrerConfig
        );
        assertTrue(proxy != address(0));
        assertEq(P2pSsvProxy(payable(proxy)).getClient(), client);
    }

    function test_depositToSsvEth_factory() public {
        vm.expectCall(
            SSV_NETWORK,
            1 ether,
            abi.encodeWithSelector(ISSVClustersEth.deposit.selector, address(0x123), operatorIds, _getEmptyCluster())
        );
        _mockSsvCallWithValue(1 ether, abi.encodeWithSelector(ISSVClustersEth.deposit.selector));

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        factory.depositToSsvEth{value: 1 ether}(address(0x123), operatorIds, _getEmptyCluster());

        vm.deal(nobody, 10 ether);
        vm.prank(nobody);
        vm.expectRevert();
        factory.depositToSsvEth{value: 1 ether}(address(0x123), operatorIds, _getEmptyCluster());
    }

    function test_migrateClusterToETH_factory() public {
        address proxy = _deployProxyViaClone();

        vm.expectCall(
            SSV_NETWORK,
            5 ether,
            abi.encodeWithSelector(ISSVClustersEth.migrateClusterToETH.selector, operatorIds, _getEmptyCluster())
        );
        _mockSsvCallWithValue(5 ether, abi.encodeWithSelector(ISSVClustersEth.migrateClusterToETH.selector));

        vm.deal(owner, 10 ether);
        vm.expectEmit(true, false, false, true);
        emit P2pSsvProxyFactory__ClusterMigrationInitiated(proxy, 5 ether);
        vm.prank(owner);
        factory.migrateClusterToETH{value: 5 ether}(proxy, operatorIds, _getEmptyCluster());

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(P2pSsvProxyFactory__NotDeployedP2pSsvProxy.selector, address(0x999)));
        factory.migrateClusterToETH{value: 5 ether}(address(0x999), operatorIds, _getEmptyCluster());
    }

    function test_registerValidatorsEth_emitsEthRegistrationCompleted() public {
        factory.setBeacon(address(beacon));
        _configureAllowedOperatorsAndIds();
        (bytes[] memory pubkeys, bytes[] memory sharesData) = _buildSingleValidatorData();
        ISSVNetworkCore.Cluster memory cluster = _getEmptyCluster();

        uint256 registrationValue = 1 ether;
        _mockSsvCallWithValue(
            registrationValue,
            abi.encodeWithSelector(
                ISSVClustersEth.bulkRegisterValidator.selector,
                pubkeys,
                operatorIds,
                sharesData,
                cluster
            )
        );
        _mockSsvCall(abi.encodeWithSelector(ISSVNetworkEth.setFeeRecipientAddress.selector));

        address predictedProxy = factory.predictP2pSsvProxyAddressBeacon(address(mockFeeDistributor));

        vm.deal(client, 10 ether);
        vm.expectEmit(true, false, false, true);
        emit P2pSsvProxyFactory__EthRegistrationCompleted(predictedProxy, registrationValue);
        vm.prank(client);
        address proxy = factory.registerValidatorsEth{value: registrationValue}(
            allowedOperatorOwners,
            operatorIds,
            pubkeys,
            sharesData,
            cluster,
            clientConfig,
            referrerConfig
        );
        assertEq(proxy, predictedProxy);
    }

    function test_registerValidatorsEth_revertsWhenOperatorOwnerNotAllowed() public {
        factory.setBeacon(address(beacon));
        _configureAllowedOperatorsAndIds();
        (bytes[] memory pubkeys, bytes[] memory sharesData) = _buildSingleValidatorData();
        address[] memory wrongOwners = new address[](4);
        wrongOwners[0] = allowedOperatorOwners[0];
        wrongOwners[1] = allowedOperatorOwners[1];
        wrongOwners[2] = allowedOperatorOwners[2];
        wrongOwners[3] = address(0xBAD);

        vm.deal(client, 10 ether);
        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(
                P2pSsvProxyFactory__SsvOperatorNotAllowed.selector,
                address(0xBAD),
                operatorIds[3]
            )
        );
        factory.registerValidatorsEth{value: 1 ether}(
            wrongOwners,
            operatorIds,
            pubkeys,
            sharesData,
            _getEmptyCluster(),
            clientConfig,
            referrerConfig
        );
    }

    function test_deprecatedDepositEthAndRegisterValidators_reverts() public {
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = hex"1234";
        bytes32[] memory depositDataRoots = new bytes32[](1);
        depositDataRoots[0] = bytes32(uint256(1));
        DepositData memory depositData = DepositData({
            signatures: signatures,
            depositDataRoots: depositDataRoots
        });

        (bytes[] memory pubkeys, bytes[] memory sharesData) = _buildSingleValidatorData();

        SsvPayload memory payload;
        vm.expectRevert(P2pSsvProxyFactory__DeprecatedFunction.selector);
        factory.depositEthAndRegisterValidators(
            depositData,
            address(0x1234),
            payload,
            clientConfig,
            referrerConfig
        );

        vm.expectRevert(P2pSsvProxyFactory__DeprecatedFunction.selector);
        factory.depositEthAndRegisterValidators(
            depositData,
            address(0x1234),
            allowedOperatorOwners,
            operatorIds,
            pubkeys,
            sharesData,
            1 ether,
            _getEmptyCluster(),
            clientConfig,
            referrerConfig
        );
    }

    // ═══════════════════════════════════════════
    // D. ETH Reception and Withdrawal
    // ═══════════════════════════════════════════

    function test_proxyReceivesEth() public {
        address proxy = _deployProxyViaClone();

        vm.deal(address(this), 10 ether);

        vm.expectEmit(true, false, false, true, proxy);
        emit P2pSsvProxy__EthReceived(address(this), 1 ether);
        (bool success,) = proxy.call{value: 1 ether}("");
        assertTrue(success);

        assertEq(proxy.balance, 1 ether);
    }

    function test_withdrawEthToOwner() public {
        address proxy = _deployProxyViaClone();

        vm.deal(proxy, 2 ether);

        uint256 ownerBalBefore = owner.balance;

        vm.prank(owner);
        P2pSsvProxy(payable(proxy)).withdrawEthToOwner();

        assertEq(proxy.balance, 0);
        assertEq(owner.balance - ownerBalBefore, 2 ether);

        vm.deal(proxy, 1 ether);
        vm.prank(nobody);
        vm.expectRevert();
        P2pSsvProxy(payable(proxy)).withdrawEthToOwner();
    }

    function test_payableFallbackForwardsValue() public {
        address proxy = _deployProxyViaClone();

        bytes4 testSelector = bytes4(keccak256("someFunction(uint256)"));

        _mockSsvCallWithValue(0.5 ether, abi.encodeWithSelector(testSelector));

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        (bool success,) = proxy.call{value: 0.5 ether}(abi.encodeWithSelector(testSelector, uint256(42)));
        assertTrue(success);
    }

    function test_payableFallback_emitsSuccessEvent() public {
        address proxy = _deployProxyViaClone();
        bytes4 testSelector = bytes4(keccak256("anotherFunction(bytes32)"));

        _mockSsvCallWithValue(1, abi.encodeWithSelector(testSelector));

        vm.deal(owner, 10 ether);
        vm.expectEmit(true, true, false, false, proxy);
        emit P2pSsvProxy__SuccessfullyCalledViaFallback(owner, testSelector);
        vm.prank(owner);
        (bool success,) = proxy.call{value: 1}(abi.encodeWithSelector(testSelector, bytes32(uint256(1))));
        assertTrue(success);
    }

    function test_payableFallback_revertsWhenSelectorNotAllowlistedForOperator() public {
        address proxy = _deployProxyViaClone();
        factory.changeOperator(operator);
        bytes4[] memory allowedSelectors = new bytes4[](1);
        allowedSelectors[0] = bytes4(keccak256("allowedOnly()"));
        factory.setAllowedSelectorsForOperator(allowedSelectors);

        bytes4 testSelector = bytes4(keccak256("forbiddenSelector()"));

        vm.prank(operator);
        (bool success, bytes memory data) = proxy.call(abi.encodeWithSelector(testSelector));
        assertFalse(success);
        assertEq(
            data,
            abi.encodeWithSelector(P2pSsvProxy__SelectorNotAllowed.selector, operator, testSelector)
        );
    }

    function test_fallback_allowsClientWhenSelectorAllowlisted() public {
        address proxy = _deployProxyViaClone();
        bytes4 selector = IP2pSsvProxy.bulkExitValidator.selector;
        bytes4[] memory clientSelectors = new bytes4[](1);
        clientSelectors[0] = selector;
        factory.setAllowedSelectorsForClient(clientSelectors);

        bytes[] memory publicKeys = new bytes[](1);
        publicKeys[0] = hex"aa";
        bytes memory callData = abi.encodeWithSelector(selector, publicKeys, operatorIds);
        vm.expectCall(SSV_NETWORK, callData);
        _mockSsvCall(callData);

        vm.prank(client);
        (bool success,) = proxy.call(callData);
        assertTrue(success);
    }

    function test_hoodiSsvNetworkIsReachable() public view {
        string memory version = ISSVViews(0x5AdDb3f1529C5ec70D77400499eE4bbF328368fe).getVersion();
        assertTrue(bytes(version).length > 0);
    }

    // ═══════════════════════════════════════════
    // E. Mutable Factory
    // ═══════════════════════════════════════════

    function test_setP2pSsvProxyFactory() public {
        address proxy = _deployProxyViaClone();

        P2pSsvProxyFactory factory2 = new P2pSsvProxyFactory(
            address(mockEthDepositor),
            address(mockFeeDistFactory),
            address(mockFeeDistributor)
        );

        vm.expectEmit(true, true, false, false, proxy);
        emit P2pSsvProxy__P2pSsvProxyFactorySet(address(factory), address(factory2));
        vm.prank(owner);
        P2pSsvProxy(payable(proxy)).setP2pSsvProxyFactory(address(factory2));

        assertEq(P2pSsvProxy(payable(proxy)).getFactory(), address(factory2));
    }

    function test_setP2pSsvProxyFactory_accessControl() public {
        address proxy = _deployProxyViaClone();

        P2pSsvProxyFactory factory2 = new P2pSsvProxyFactory(
            address(mockEthDepositor),
            address(mockFeeDistFactory),
            address(mockFeeDistributor)
        );

        vm.prank(nobody);
        vm.expectRevert();
        P2pSsvProxy(payable(proxy)).setP2pSsvProxyFactory(address(factory2));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(P2pSsvProxy__NotP2pSsvProxyFactory.selector, nobody));
        P2pSsvProxy(payable(proxy)).setP2pSsvProxyFactory(nobody);
    }

    function test_initializeCannotBeCalledTwice() public {
        address proxy = _deployProxyViaClone();

        vm.prank(address(factory));
        vm.expectRevert(P2pSsvProxy__AlreadyInitialized.selector);
        P2pSsvProxy(payable(proxy)).initialize(address(mockFeeDistributor));
    }

    // ═══════════════════════════════════════════
    // F. Beacon Management
    // ═══════════════════════════════════════════

    function test_setBeacon() public {
        vm.expectEmit(true, false, false, false);
        emit P2pSsvProxyFactory__BeaconSet(address(beacon));
        factory.setBeacon(address(beacon));

        assertEq(factory.getBeacon(), address(beacon));

        P2pUpgradeableBeacon badBeacon = new P2pUpgradeableBeacon(address(mockEthDepositor), owner);
        vm.expectRevert(abi.encodeWithSelector(P2pSsvProxyFactory__NotP2pSsvProxy.selector, address(mockEthDepositor)));
        factory.setBeacon(address(badBeacon));
    }

    function test_beaconUpgrade() public {
        factory.setBeacon(address(beacon));

        address proxy1 = factory.createP2pSsvProxy(address(mockFeeDistributor));
        assertEq(P2pSsvProxy(payable(proxy1)).getClient(), client);

        P2pSsvProxy newImpl = new P2pSsvProxy();
        beacon.upgradeTo(address(newImpl));

        assertEq(P2pSsvProxy(payable(proxy1)).getClient(), client);
        assertEq(P2pSsvProxy(payable(proxy1)).getFactory(), address(factory));
    }

    // ═══════════════════════════════════════════
    // H. ERC165 Backward Compatibility
    // ═══════════════════════════════════════════

    function test_supportsInterface() public {
        address proxy = _deployProxyViaClone();

        bytes4 proxyV1Id = type(IP2pSsvProxy).interfaceId
            ^ IP2pSsvProxy.bulkRegisterValidatorsEth.selector
            ^ IP2pSsvProxy.depositToSsvEth.selector
            ^ IP2pSsvProxy.reactivateEth.selector
            ^ IP2pSsvProxy.migrateClusterToETH.selector
            ^ IP2pSsvProxy.withdrawEthToOwner.selector
            ^ IP2pSsvProxy.setP2pSsvProxyFactory.selector;
        bytes4 proxyCurrentId = type(IP2pSsvProxy).interfaceId;

        assertTrue(P2pSsvProxy(payable(proxy)).supportsInterface(proxyV1Id));
        assertTrue(P2pSsvProxy(payable(proxy)).supportsInterface(proxyCurrentId));
        assertFalse(P2pSsvProxy(payable(proxy)).supportsInterface(bytes4(0xffffffff)));

        bytes4 factoryV1Id = type(IP2pSsvProxyFactory).interfaceId
            ^ IP2pSsvProxyFactory.registerValidatorsEth.selector
            ^ IP2pSsvProxyFactory.depositToSsvEth.selector
            ^ IP2pSsvProxyFactory.migrateClusterToETH.selector
            ^ IP2pSsvProxyFactory.setBeacon.selector
            ^ IP2pSsvProxyFactory.getBeacon.selector
            ^ IP2pSsvProxyFactory.predictP2pSsvProxyAddressBeacon.selector;
        bytes4 factoryCurrentId = type(IP2pSsvProxyFactory).interfaceId;
        assertTrue(factory.supportsInterface(factoryV1Id));
        assertTrue(factory.supportsInterface(factoryCurrentId));
        assertTrue(factory.supportsInterface(type(ISSVWhitelistingContract).interfaceId));
        assertFalse(factory.supportsInterface(bytes4(0xffffffff)));
    }

    receive() external payable {}
}
