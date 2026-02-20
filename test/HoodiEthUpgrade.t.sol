// SPDX-FileCopyrightText: 2024 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import "../src/p2pSsvProxyFactory/P2pSsvProxyFactory.sol";
import "../src/p2pSsvProxy/P2pSsvProxy.sol";
import "../src/proxy/P2pUpgradeableBeacon.sol";
import "../src/interfaces/p2p/IFeeDistributor.sol";
import "../src/interfaces/ssv/ISSVViews.sol";
import "../src/structs/P2pStructs.sol";
import "../src/mocks/IChangeOperator.sol";

contract HoodiEthUpgrade is Test {
    struct EthOperatorFixture {
        uint64[] ids;
        address[] owners;
    }

    struct EthValidatorFixture {
        bytes pubkey;
        bytes sharesData;
        uint256 registerValue;
    }

    address public constant SSV_NETWORK = 0x58410Bef803ECd7E63B23664C586A6DB72DAf59c;
    address public constant SSV_VIEWS = 0x5AdDb3f1529C5ec70D77400499eE4bbF328368fe;
    address public constant FEE_DISTRIBUTOR_FACTORY = 0xBc869f68ce5FEB21fa152d628098A49b60830b3f;
    address public constant P2P_ORG_UNLIMITED_ETH_DEPOSITOR = 0xc18c3aBE6456CFbc654Eb30D864692659562214B;
    address public constant REFERENCE_FEE_DISTRIBUTOR = 0xB20b9Eb263F0361d9aE28CC1Dd382E6b1B9383Cf;

    address public owner;
    address public operator;
    address public nobody;
    address payable public client;

    P2pSsvProxyFactory public factory;
    P2pSsvProxy public referenceProxy;
    P2pUpgradeableBeacon public beacon;

    FeeRecipient public clientConfig;
    FeeRecipient public referrerConfig;

    address[] public allowedOperatorOwners;
    uint64[] public operatorIds;
    address[] public ethOperatorOwners;
    uint64[] public ethOperatorIds;

    bytes public ethValidatorPubkey;
    bytes public ethValidatorSharesData;
    uint256 public constant ETH_REGISTER_VALUE = 56657822608000000;
    uint256 public constant ETH_DEPOSIT_VALUE = 0.001 ether;

    event P2pSsvProxy__EthReceived(address indexed _sender, uint256 _amount);
    event P2pSsvProxy__SuccessfullyCalledViaFallback(address indexed _caller, bytes4 indexed _selector);
    event P2pSsvProxy__P2pSsvProxyFactorySet(address indexed _oldFactory, address indexed _newFactory);
    event P2pSsvProxy__Initialized(address indexed _feeDistributor);
    event P2pSsvProxyFactory__ClusterMigrationInitiated(address indexed _proxy, uint256 _ethDeposited);
    event P2pSsvProxyFactory__BeaconSet(address indexed _beacon);

    bytes32 private constant VALIDATOR_ADDED_TOPIC =
        keccak256("ValidatorAdded(address,uint64[],bytes,bytes,(uint32,uint64,uint64,bool,uint256))");
    bytes32 private constant CLUSTER_DEPOSITED_TOPIC =
        keccak256("ClusterDeposited(address,uint64[],uint256,(uint32,uint64,uint64,bool,uint256))");
    bytes32 private constant CLUSTER_LIQUIDATED_TOPIC =
        keccak256("ClusterLiquidated(address,uint64[],(uint32,uint64,uint64,bool,uint256))");
    bytes32 private constant CLUSTER_REACTIVATED_TOPIC =
        keccak256("ClusterReactivated(address,uint64[],(uint32,uint64,uint64,bool,uint256))");

    function setUp() public {
        vm.createSelectFork("hoodi");
        _initCoreActorsAndFactory();
        _authorizeLocalFactoryInFeeDistributorFactory();
        _initLegacyTestDefaults();
        _initDefaultConfig();
        _initEthOperatorFixtures();
        _initEthValidatorFixtures();
        _initFunding();
    }

    function _initCoreActorsAndFactory() internal {
        owner = address(this);
        operator = address(0xB0B);
        nobody = address(0xdead);
        client = payable(IFeeDistributor(REFERENCE_FEE_DISTRIBUTOR).client());

        factory = new P2pSsvProxyFactory(
            P2P_ORG_UNLIMITED_ETH_DEPOSITOR,
            FEE_DISTRIBUTOR_FACTORY,
            REFERENCE_FEE_DISTRIBUTOR
        );

        referenceProxy = new P2pSsvProxy();
        factory.setReferenceP2pSsvProxy(address(referenceProxy));
        beacon = new P2pUpgradeableBeacon(address(referenceProxy), owner);
    }

    function _authorizeLocalFactoryInFeeDistributorFactory() internal {
        address fdFactoryOwner = IFeeDistributorFactory(FEE_DISTRIBUTOR_FACTORY).owner();
        vm.prank(fdFactoryOwner);
        IChangeOperator(FEE_DISTRIBUTOR_FACTORY).changeOperator(address(factory));
    }

    function _initLegacyTestDefaults() internal {
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
    }

    function _initDefaultConfig() internal {
        clientConfig = FeeRecipient({ recipient: client, basisPoints: 9500 });
        referrerConfig = FeeRecipient({ recipient: payable(address(0)), basisPoints: 0 });

        factory.setSsvPerEthExchangeRateDividedByWei(7539000000000000);
        factory.setMaxSsvTokenAmountPerValidator(30 ether);
    }

    function _initEthOperatorFixtures() internal {
        EthOperatorFixture memory fixture = _getEthOperatorFixture();
        ethOperatorIds = fixture.ids;
        ethOperatorOwners = fixture.owners;
    }

    function _initEthValidatorFixtures() internal {
        EthValidatorFixture memory fixture = _getEthValidatorFixture();
        ethValidatorPubkey = fixture.pubkey;
        ethValidatorSharesData = fixture.sharesData;
    }

    function _initFunding() internal {
        vm.deal(address(this), 100 ether);
    }

    /**********************************/
    /* Fixture Builders               */
    /**********************************/

    function _getEthOperatorFixture() internal returns (EthOperatorFixture memory fixture) {
        fixture.ids = new uint64[](4);
        fixture.ids[0] = 51;
        fixture.ids[1] = 53;
        fixture.ids[2] = 56;
        fixture.ids[3] = 58;

        fixture.owners = new address[](4);
        uint256 operatorCount = fixture.ids.length;
        for (uint256 i = 0; i < operatorCount; ++i) {
            (address opOwner,,,,,) = ISSVViews(SSV_VIEWS).getOperatorById(fixture.ids[i]);
            fixture.owners[i] = opOwner;
        }

        factory.setAllowedSsvOperatorOwners(fixture.owners);
        for (uint256 i = 0; i < fixture.ids.length; ++i) {
            _allowSingleOperatorForOwner(fixture.ids[i], fixture.owners[i]);
        }
    }

    function _getEthValidatorFixture() internal pure returns (EthValidatorFixture memory fixture) {
        fixture.pubkey = hex"88d07a82f491c4cd983042575a9720d9a32706eab6029125a49157cb61620edcd711a4f7bc999ad742df51e26bb9c697";
        fixture.sharesData = hex"8e7674a12882267698f59a7207b5c96a1415d7654bdcef732e9fa2e6e6ce658debeeeb3a11bb6191c5bd33f43e472ec301005d808da99da921fcf8007a98b3f7b8a04696355bad8f934ebe610568fdef742158f5353d0939deb7f3ef5f8d0619a393be3322aa5e63d44bd06a6ce0b103ea76f12a91a0993f899d3018ef07adb3c1af1e651cf3d65bb08bf1a2c7b50b95847ab9627f9b21f2f469ff491b591d9cbe6e1ae1247bd0882a5bc5af40b0012b94c7d19575e78c85b67bfc2b9068bb7482fee2a8eca476e344aaece7d21cfb8e5f41d0da20b055ba34faf3cfed83fafee938635424b1cd38418b71458d2c27ccaaa792c800b825b477de3838f98557088f11a379131b277b1148a210591a6f35dd88d5db05907a96856682815f11e1ae9a2cd36246bbcc183c660867f641efb5c1c2262c2c70b0728b22f0309f7df524bad92335f4c4054d7d6f5274ca18c6c83acf2c6df2d0b4d962f076c0af93494379f77da7a77858ca339599c8c623e6ac68999a9bb73342ab8aff6379dc9a7daf57cb319aab7b30dd8ac8c9b5446e1a578da138c7288245cce7bef5b389eda02c879f347bf8c8285eb8b22b10ddecbe7f9e076bc40d6dd3a5feea8b1c5e0d33c105f452cfd42fad425e3c92e4c40c61ebe86ba6de33996aede5918074dd23ff6fdbbb01518f681d25c357b01e49a3d3a2e5f2c8d168e1893ca053f3c5a41d3969ec3d4847aa480e7edada98e543a4e37af14c7fd8d193dd49f9dbfeb8c64944a9a5f78e039efe803d10a7b3f7b9565897eb89e9b30dd518ae90ad897747e407ad0f9ff3cbd0e008f4db9249df2a87f69303774e2cf012594957c20d2b4d77d8028b650827dc0356bcea190a7ddb78dfc78907471d645f962d17e7c324010b688ff56592e9872ecf0f403a4b531e363ba9e7beaf2cf0fb27b1f87e28fc83a5ee12833cd626e5d5eec3caf8504120b5bb20bd7aed5b571cd1a9102930a660816a850dbc5d73ed30455ead46a72a165944ee66ed73b5219e2ef0ef3e970d80033df5f1979c61eef9f72597a4adb6b3bdfea9047654ea7893b803a68d2957a948b48022a768062c035d19734c76a36d00593dbe97854e46279b6320470ebdd551e3ab3ded8267c3935b5862118fb461710858b0cbec250976f600935b242d4eece1de8802b1bb489bce882c373d3e74ec89464a34ffdd1b29f73b781432cffaf9d4746d07c539eae9e968b8c2d87bce65516ab0400ef897b1d685bb32510f5ae4d5edee3967512cfcf2a6f7ac33b11f970d5c1c76e12febfb98a812547002fc2c728a80a06ba907132f246e909ecba0c7e8ceba94109bcd535b31cadeee39be95ee51de82dff9d41d6d9fd34b954c858397ea9e1f0bb833426e7516d527af2dab57aefd53423ec3d03a89ac5933c448129a3f9562e3dcccdc8ae40b3e6a892b760fef977964b9d0b029ff7654946416e126550bcc37c784dfdbcb5dd103f5bf442a5c8aae23f8fc36a60452d9cdc4546b30769f0228174e71795de52de46e5b3e7766b125ddff456fac5b6dc28318d7f6f5f347f7c62fe3ef69be2b77e846dd5d1c5c8b2b4ddbe003b8fe35bf820389dc13ee869a4386e5169bad17ff36192b14a6a11ecba171949202c5099706d6e429f6e0d9f33e66c1da58e2f17676f5d3c2564687d657c629baf53803594ea916fa996647dc3ec689368a62b37df94da520abecf429a4fa6708c3acc7262ea121c96207e6e51443f6ce8094512069b58a8fc478a7d28f0f470dde6dd91cfacaeaf3119f0e919a89e72e5d6a3ed03bb77a5f0c28d029d0477bdd2deae6255537d19eba0f161f7f224883a4a68fd605c6db3e27d1";
        fixture.registerValue = ETH_REGISTER_VALUE;
    }

    /**********************************/
    /* Generic Test Helpers           */
    /**********************************/

    function _getEmptyCluster() internal pure returns (ISSVNetworkCore.Cluster memory) {
        return ISSVNetworkCore.Cluster({
            validatorCount: 0,
            networkFeeIndex: 0,
            index: 0,
            active: true,
            balance: 0
        });
    }

    function _buildSingleValidatorData() internal pure returns (bytes[] memory pubkeys, bytes[] memory sharesData) {
        pubkeys = new bytes[](1);
        pubkeys[0] = hex"aabbcc";
        sharesData = new bytes[](1);
        sharesData[0] = hex"ddeeff";
    }

    function _deployProxyViaClone() internal returns (address proxy) {
        proxy = factory.createP2pSsvProxy(REFERENCE_FEE_DISTRIBUTOR);
    }

    function _deployProxyViaBeacon() internal returns (address proxy) {
        factory.setBeacon(address(beacon));
        proxy = factory.createP2pSsvProxy(REFERENCE_FEE_DISTRIBUTOR);
    }

    function _allowSingleOperatorForOwner(uint64 operatorId, address operatorOwner) internal {
        uint64[24] memory ids;
        ids[0] = operatorId;
        factory.setSsvOperatorIds(ids, operatorOwner);
    }

    function _singleClusterArray(
        ISSVNetworkCore.Cluster memory cluster
    ) internal pure returns (ISSVNetworkCore.Cluster[] memory clusters) {
        clusters = new ISSVNetworkCore.Cluster[](1);
        clusters[0] = cluster;
    }

    function _registerSingleValidatorEthFixture()
        internal
        returns (address proxy, ISSVNetworkCore.Cluster memory clusterAfterRegister)
    {
        bytes[] memory pubkeys = new bytes[](1);
        EthValidatorFixture memory fixture = _getEthValidatorFixture();
        pubkeys[0] = fixture.pubkey;
        bytes[] memory sharesData = new bytes[](1);
        sharesData[0] = fixture.sharesData;

        proxy = _deployProxyViaClone();
        vm.deal(address(factory), fixture.registerValue);
        vm.recordLogs();
        vm.prank(address(factory));
        P2pSsvProxy(payable(proxy)).bulkRegisterValidatorsEth{value: fixture.registerValue}(
            pubkeys,
            ethOperatorIds,
            sharesData,
            _getEmptyCluster()
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        clusterAfterRegister = _extractClusterFromValidatorAdded(logs, proxy);
    }

    function _registerSingleValidatorViaFactoryEthFixture()
        internal
        returns (address proxy, ISSVNetworkCore.Cluster memory clusterAfterRegister)
    {
        bytes[] memory pubkeys = new bytes[](1);
        EthValidatorFixture memory fixture = _getEthValidatorFixture();
        pubkeys[0] = fixture.pubkey;
        bytes[] memory sharesData = new bytes[](1);
        sharesData[0] = fixture.sharesData;

        FeeRecipient memory localClientConfig = FeeRecipient({ recipient: payable(address(this)), basisPoints: 9500 });
        FeeRecipient memory localReferrerConfig = FeeRecipient({ recipient: payable(address(0)), basisPoints: 0 });

        vm.recordLogs();
        proxy = factory.registerValidatorsEth{value: fixture.registerValue}(
            ethOperatorOwners,
            ethOperatorIds,
            pubkeys,
            sharesData,
            _getEmptyCluster(),
            localClientConfig,
            localReferrerConfig
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        clusterAfterRegister = _extractClusterFromValidatorAdded(logs, proxy);
    }

    /**********************************/
    /* Log-Based Cluster Decoders     */
    /**********************************/

    function _extractClusterFromValidatorAdded(
        Vm.Log[] memory logs,
        address expectedOwner
    ) internal pure returns (ISSVNetworkCore.Cluster memory cluster) {
        bytes32 ownerTopic = bytes32(uint256(uint160(expectedOwner)));
        for (uint256 i = logs.length; i > 0; --i) {
            Vm.Log memory log = logs[i - 1];
            if (
                log.emitter == SSV_NETWORK &&
                log.topics.length > 1 &&
                log.topics[0] == VALIDATOR_ADDED_TOPIC &&
                log.topics[1] == ownerTopic
            ) {
                (,,, cluster) = abi.decode(log.data, (uint64[], bytes, bytes, ISSVNetworkCore.Cluster));
                return cluster;
            }
        }
        revert("validator added not found");
    }

    function _extractClusterFromDeposited(
        Vm.Log[] memory logs,
        address expectedOwner
    ) internal pure returns (ISSVNetworkCore.Cluster memory cluster) {
        bytes32 ownerTopic = bytes32(uint256(uint160(expectedOwner)));
        for (uint256 i = logs.length; i > 0; --i) {
            Vm.Log memory log = logs[i - 1];
            if (
                log.emitter == SSV_NETWORK &&
                log.topics.length > 1 &&
                log.topics[0] == CLUSTER_DEPOSITED_TOPIC &&
                log.topics[1] == ownerTopic
            ) {
                (,, cluster) = abi.decode(log.data, (uint64[], uint256, ISSVNetworkCore.Cluster));
                return cluster;
            }
        }
        revert("cluster deposited not found");
    }

    function _extractClusterFromLiquidated(
        Vm.Log[] memory logs,
        address expectedOwner
    ) internal pure returns (ISSVNetworkCore.Cluster memory cluster) {
        bytes32 ownerTopic = bytes32(uint256(uint160(expectedOwner)));
        for (uint256 i = logs.length; i > 0; --i) {
            Vm.Log memory log = logs[i - 1];
            if (
                log.emitter == SSV_NETWORK &&
                log.topics.length > 1 &&
                log.topics[0] == CLUSTER_LIQUIDATED_TOPIC &&
                log.topics[1] == ownerTopic
            ) {
                (, cluster) = abi.decode(log.data, (uint64[], ISSVNetworkCore.Cluster));
                return cluster;
            }
        }
        revert("cluster liquidated not found");
    }

    function _extractClusterFromReactivated(
        Vm.Log[] memory logs,
        address expectedOwner
    ) internal pure returns (ISSVNetworkCore.Cluster memory cluster) {
        bytes32 ownerTopic = bytes32(uint256(uint160(expectedOwner)));
        for (uint256 i = logs.length; i > 0; --i) {
            Vm.Log memory log = logs[i - 1];
            if (
                log.emitter == SSV_NETWORK &&
                log.topics.length > 1 &&
                log.topics[0] == CLUSTER_REACTIVATED_TOPIC &&
                log.topics[1] == ownerTopic
            ) {
                (, cluster) = abi.decode(log.data, (uint64[], ISSVNetworkCore.Cluster));
                return cluster;
            }
        }
        revert("cluster reactivated not found");
    }

    function test_beaconProxyDeployment() public {
        address proxy = _deployProxyViaBeacon();

        assertTrue(proxy != address(0));
        assertEq(P2pSsvProxy(payable(proxy)).getFactory(), address(factory));
        assertEq(P2pSsvProxy(payable(proxy)).getClient(), client);
        assertEq(P2pSsvProxy(payable(proxy)).getFeeDistributor(), REFERENCE_FEE_DISTRIBUTOR);
        assertTrue(factory.isWhitelisted(proxy, 0));
    }

    function test_beaconProxyAddressPrediction() public {
        factory.setBeacon(address(beacon));
        address predicted = factory.predictP2pSsvProxyAddressBeacon(REFERENCE_FEE_DISTRIBUTOR);
        address actual = factory.createP2pSsvProxy(REFERENCE_FEE_DISTRIBUTOR);
        assertEq(predicted, actual);
    }

    function test_cloneFallbackWhenNoBeacon() public {
        address proxy = _deployProxyViaClone();
        assertTrue(proxy != address(0));
        vm.expectRevert(P2pSsvProxyFactory__BeaconNotSet.selector);
        factory.predictP2pSsvProxyAddressBeacon(REFERENCE_FEE_DISTRIBUTOR);
    }

    function test_bulkRegisterValidatorsEth_onlyFactory() public {
        address proxy = _deployProxyViaClone();
        (bytes[] memory pubkeys, bytes[] memory sharesData) = _buildSingleValidatorData();
        vm.prank(nobody);
        vm.expectRevert();
        P2pSsvProxy(payable(proxy)).bulkRegisterValidatorsEth{value: 1 ether}(
            pubkeys, operatorIds, sharesData, _getEmptyCluster()
        );
    }

    function test_bulkRegisterValidatorsEth_success() public {
        (address proxy, ISSVNetworkCore.Cluster memory clusterAfterRegister) = _registerSingleValidatorEthFixture();
        assertTrue(proxy != address(0));
        assertEq(clusterAfterRegister.validatorCount, 1);
        assertTrue(clusterAfterRegister.active);
    }

    function test_depositToSsvEth_success() public {
        (address proxy, ISSVNetworkCore.Cluster memory clusterAfterRegister) = _registerSingleValidatorEthFixture();
        ISSVNetworkCore.Cluster[] memory clusters = _singleClusterArray(clusterAfterRegister);

        vm.recordLogs();
        P2pSsvProxy(payable(proxy)).depositToSsvEth{value: ETH_DEPOSIT_VALUE}(ethOperatorIds, clusters);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        ISSVNetworkCore.Cluster memory clusterAfterDeposit = _extractClusterFromDeposited(logs, proxy);

        assertEq(clusterAfterDeposit.validatorCount, clusterAfterRegister.validatorCount);
        assertTrue(clusterAfterDeposit.balance > clusterAfterRegister.balance);
    }

    function test_reactivateEth_success() public {
        (address proxy, ISSVNetworkCore.Cluster memory clusterAfterRegister) = _registerSingleValidatorEthFixture();

        // Move far enough so the cluster can be liquidated in a deterministic way on fork.
        vm.roll(block.number + 2_000_000);
        vm.warp(block.timestamp + 365 days);

        vm.recordLogs();
        P2pSsvProxy(payable(proxy)).liquidate(ethOperatorIds, _singleClusterArray(clusterAfterRegister));
        Vm.Log[] memory liqLogs = vm.getRecordedLogs();
        ISSVNetworkCore.Cluster memory clusterAfterLiquidate = _extractClusterFromLiquidated(liqLogs, proxy);
        assertFalse(clusterAfterLiquidate.active);

        vm.recordLogs();
        P2pSsvProxy(payable(proxy)).reactivateEth{value: ETH_DEPOSIT_VALUE}(
            ethOperatorIds, _singleClusterArray(clusterAfterLiquidate)
        );
        Vm.Log[] memory reactLogs = vm.getRecordedLogs();
        ISSVNetworkCore.Cluster memory clusterAfterReactivate = _extractClusterFromReactivated(reactLogs, proxy);
        assertTrue(clusterAfterReactivate.active);
    }

    function test_depositToSsvEth_zeroClustersReverts() public {
        address proxy = _deployProxyViaClone();
        ISSVNetworkCore.Cluster[] memory empty = new ISSVNetworkCore.Cluster[](0);
        vm.expectRevert(P2pSsvProxy__AmountOfParametersError.selector);
        P2pSsvProxy(payable(proxy)).depositToSsvEth{value: 1 ether}(operatorIds, empty);
    }

    function test_reactivateEth_accessAndZeroClustersReverts() public {
        address proxy = _deployProxyViaClone();

        ISSVNetworkCore.Cluster[] memory one = new ISSVNetworkCore.Cluster[](1);
        one[0] = _getEmptyCluster();
        vm.prank(nobody);
        vm.expectRevert();
        P2pSsvProxy(payable(proxy)).reactivateEth{value: 1 ether}(operatorIds, one);

        ISSVNetworkCore.Cluster[] memory empty = new ISSVNetworkCore.Cluster[](0);
        vm.expectRevert(P2pSsvProxy__AmountOfParametersError.selector);
        P2pSsvProxy(payable(proxy)).reactivateEth{value: 1 ether}(operatorIds, empty);
    }

    function test_migrateClusterToETH_proxy_onlyFactory() public {
        address proxy = _deployProxyViaClone();
        vm.prank(nobody);
        vm.expectRevert();
        P2pSsvProxy(payable(proxy)).migrateClusterToETH{value: 1 ether}(operatorIds, _getEmptyCluster());
    }

    function test_registerValidatorsEth_revertsOnNotAllowedOwner() public {
        address[] memory notAllowedOwners = new address[](1);
        notAllowedOwners[0] = address(0xBAD);
        uint64[] memory singleOperatorId = new uint64[](1);
        singleOperatorId[0] = 1;
        (bytes[] memory pubkeys, bytes[] memory sharesData) = _buildSingleValidatorData();

        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(P2pSsvProxyFactory__SsvOperatorNotAllowed.selector, address(0xBAD), uint64(1))
        );
        factory.registerValidatorsEth(
            notAllowedOwners,
            singleOperatorId,
            pubkeys,
            sharesData,
            _getEmptyCluster(),
            clientConfig,
            referrerConfig
        );
    }

    function test_registerValidatorsEth_success() public {
        (address proxy, ISSVNetworkCore.Cluster memory clusterAfterRegister) = _registerSingleValidatorViaFactoryEthFixture();
        assertTrue(proxy != address(0));
        assertEq(clusterAfterRegister.validatorCount, 1);
        assertTrue(clusterAfterRegister.active);
        assertEq(P2pSsvProxy(payable(proxy)).getFactory(), address(factory));
    }

    function test_depositToSsvEth_factory_onlyOwner() public {
        vm.prank(nobody);
        vm.expectRevert();
        factory.depositToSsvEth{value: 1 ether}(address(0x123), operatorIds, _getEmptyCluster());
    }

    function test_depositToSsvEth_factory_success() public {
        (address proxy, ISSVNetworkCore.Cluster memory clusterAfterRegister) = _registerSingleValidatorViaFactoryEthFixture();
        vm.recordLogs();
        factory.depositToSsvEth{value: ETH_DEPOSIT_VALUE}(proxy, ethOperatorIds, clusterAfterRegister);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        ISSVNetworkCore.Cluster memory clusterAfterDeposit = _extractClusterFromDeposited(logs, proxy);
        assertEq(clusterAfterDeposit.validatorCount, clusterAfterRegister.validatorCount);
        assertTrue(clusterAfterDeposit.balance > clusterAfterRegister.balance);
    }

    function test_migrateClusterToETH_factory_notDeployedProxyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(P2pSsvProxyFactory__NotDeployedP2pSsvProxy.selector, address(0x999)));
        factory.migrateClusterToETH{value: 1 ether}(address(0x999), operatorIds, _getEmptyCluster());
    }

    function test_deprecatedDepositEthAndRegisterValidators_reverts() public {
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = hex"1234";
        bytes32[] memory roots = new bytes32[](1);
        roots[0] = bytes32(uint256(1));
        DepositData memory depositData = DepositData({ signatures: signatures, depositDataRoots: roots });
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

    function test_proxyReceivesEth() public {
        address proxy = _deployProxyViaClone();
        vm.deal(address(this), 2 ether);
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
        P2pSsvProxy(payable(proxy)).withdrawEthToOwner();
        assertEq(proxy.balance, 0);
        assertEq(owner.balance - ownerBalBefore, 2 ether);

        vm.deal(proxy, 1 ether);
        vm.prank(nobody);
        vm.expectRevert();
        P2pSsvProxy(payable(proxy)).withdrawEthToOwner();
    }

    function test_payableFallback_revertsWhenSelectorNotAllowlistedForOperator() public {
        address proxy = _deployProxyViaClone();
        factory.changeOperator(operator);
        bytes4[] memory allowedSelectors = new bytes4[](1);
        allowedSelectors[0] = bytes4(keccak256("allowedOnly()"));
        factory.setAllowedSelectorsForOperator(allowedSelectors);

        bytes4 selector = bytes4(keccak256("forbiddenSelector()"));
        vm.prank(operator);
        (bool success, bytes memory data) = proxy.call(abi.encodeWithSelector(selector));
        assertFalse(success);
        assertEq(data, abi.encodeWithSelector(P2pSsvProxy__SelectorNotAllowed.selector, operator, selector));
    }

    function test_payableFallback_emitsSuccessEvent_withGetVersion() public {
        address proxy = _deployProxyViaClone();
        bytes4 selector = ISSVViews.getVersion.selector;
        vm.expectEmit(true, true, false, false, proxy);
        emit P2pSsvProxy__SuccessfullyCalledViaFallback(owner, selector);
        (bool success, bytes memory data) = proxy.call(abi.encodeWithSelector(selector));
        assertTrue(success);
        string memory version = abi.decode(data, (string));
        assertTrue(bytes(version).length > 0);
    }

    function test_setP2pSsvProxyFactory() public {
        address proxy = _deployProxyViaClone();

        P2pSsvProxyFactory factory2 = new P2pSsvProxyFactory(
            P2P_ORG_UNLIMITED_ETH_DEPOSITOR,
            FEE_DISTRIBUTOR_FACTORY,
            REFERENCE_FEE_DISTRIBUTOR
        );
        factory2.setReferenceP2pSsvProxy(address(referenceProxy));

        vm.expectEmit(true, true, false, false, proxy);
        emit P2pSsvProxy__P2pSsvProxyFactorySet(address(factory), address(factory2));
        P2pSsvProxy(payable(proxy)).setP2pSsvProxyFactory(address(factory2));
        assertEq(P2pSsvProxy(payable(proxy)).getFactory(), address(factory2));
    }

    function test_setP2pSsvProxyFactory_accessControl() public {
        address proxy = _deployProxyViaClone();
        P2pSsvProxyFactory factory2 = new P2pSsvProxyFactory(
            P2P_ORG_UNLIMITED_ETH_DEPOSITOR,
            FEE_DISTRIBUTOR_FACTORY,
            REFERENCE_FEE_DISTRIBUTOR
        );
        factory2.setReferenceP2pSsvProxy(address(referenceProxy));

        vm.prank(nobody);
        vm.expectRevert();
        P2pSsvProxy(payable(proxy)).setP2pSsvProxyFactory(address(factory2));

        vm.expectRevert(abi.encodeWithSelector(P2pSsvProxy__NotP2pSsvProxyFactory.selector, nobody));
        P2pSsvProxy(payable(proxy)).setP2pSsvProxyFactory(nobody);
    }

    function test_initializeCannotBeCalledTwice() public {
        address proxy = _deployProxyViaClone();
        vm.prank(address(factory));
        vm.expectRevert(P2pSsvProxy__AlreadyInitialized.selector);
        P2pSsvProxy(payable(proxy)).initialize(REFERENCE_FEE_DISTRIBUTOR);
    }

    function test_setBeacon() public {
        vm.expectEmit(true, false, false, false);
        emit P2pSsvProxyFactory__BeaconSet(address(beacon));
        factory.setBeacon(address(beacon));
        assertEq(factory.getBeacon(), address(beacon));

        P2pUpgradeableBeacon badBeacon = new P2pUpgradeableBeacon(P2P_ORG_UNLIMITED_ETH_DEPOSITOR, owner);
        vm.expectRevert(abi.encodeWithSelector(P2pSsvProxyFactory__NotP2pSsvProxy.selector, P2P_ORG_UNLIMITED_ETH_DEPOSITOR));
        factory.setBeacon(address(badBeacon));
    }

    function test_beaconUpgrade() public {
        factory.setBeacon(address(beacon));
        address proxy = factory.createP2pSsvProxy(REFERENCE_FEE_DISTRIBUTOR);
        assertEq(P2pSsvProxy(payable(proxy)).getFactory(), address(factory));

        P2pSsvProxy newImpl = new P2pSsvProxy();
        beacon.upgradeTo(address(newImpl));

        assertEq(P2pSsvProxy(payable(proxy)).getFactory(), address(factory));
        assertEq(P2pSsvProxy(payable(proxy)).getClient(), client);
    }

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

    function test_hoodiSsvNetworkIsReachable() public view {
        string memory version = ISSVViews(SSV_VIEWS).getVersion();
        assertTrue(bytes(version).length > 0);
    }

    receive() external payable {}
}
