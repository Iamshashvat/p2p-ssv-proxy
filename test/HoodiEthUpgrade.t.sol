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
import "../src/access/OwnableBase.sol";
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

    struct MultiValidatorEthFixture {
        uint64[] ids;
        address[] owners;
        bytes[] pubkeys;
        bytes[] sharesData;
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
    uint256 public constant MULTI_ETH_REGISTER_VALUE = 10074069280000000;

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
        vm.createSelectFork("hoodi", 2262900);
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

    function _getMultiValidatorEthFixture() internal returns (MultiValidatorEthFixture memory f) {
        f.ids = new uint64[](4);
        f.ids[0] = 26;
        f.ids[1] = 36;
        f.ids[2] = 40;
        f.ids[3] = 41;

        f.owners = new address[](4);
        for (uint256 i = 0; i < 4; ++i) {
            (address opOwner,,,,,) = ISSVViews(SSV_VIEWS).getOperatorById(f.ids[i]);
            f.owners[i] = opOwner;
        }

        address[] memory uniqueOwners = new address[](2);
        uniqueOwners[0] = f.owners[0];
        uniqueOwners[1] = f.owners[1];
        factory.setAllowedSsvOperatorOwners(uniqueOwners);

        uint64[24] memory idsForOwner0;
        idsForOwner0[0] = 26;
        idsForOwner0[1] = 40;
        idsForOwner0[2] = 41;
        factory.setSsvOperatorIds(idsForOwner0, uniqueOwners[0]);

        uint64[24] memory idsForOwner1;
        idsForOwner1[0] = 36;
        factory.setSsvOperatorIds(idsForOwner1, uniqueOwners[1]);

        f.pubkeys = new bytes[](2);
        f.pubkeys[0] = hex"9736b1f94fa67402c25b6bb329dc4bbf23086113e77ab1c0ff811516cdc8b798ada7755b6b5f4661378b337d7f560d21";
        f.pubkeys[1] = hex"a14ba157c018e484226207edc4e6897ac40783311961727917d3d0182467a3f59e2f92d269add085db539899b6641249";

        f.sharesData = new bytes[](2);
        f.sharesData[0] = hex"86f07418967089326b59622ff8f20b457e5e28ebfa86f8bc061001a90ab5bd9fc9592914762bc44e57d626f1872dec4d0e1af1a5f4837a7c5ad13d906b97f91fa0ef7e0e35a447e76515c441026bfcf4d17d46b4dc107e8f3f9c2b435b6b12bb8f9333406056e795992d585dceffe85025f7127198f6196afae956bc7b1f4a971232e3e9f2f4f04c953d3d05f24684aa85664e5dbdf79491029a0357c7e56e2f7a47d01f8778fde57371dfd1d25e2cbbeeaed0488227b5b40e97ba03cb078dcdb184cc51df6d5637c963458393674f5d65af10b3f3f304621a03cffc5f88e9fec2e33b4ae511a8372fc0b5497a42200592aa85db280a77b1b8211356717562aef736034832913ee4935d0fa7ee7dd2c0d4d4bd11900890aabc5dcc0516a94f707720e978421ac4fd3f552ff88b5907ea9a148332639c685a1f7ac42b49f0326447b97244ce4e1a61b40437b92ef8fd1696be12dc2dc16fb62423a2cc7768bf266b532afa40f6799894a5239c62b66e1052102483168e8e864423cc9de06ca65db5db07840aef3b96a4c89b0ea8241ebac87367b986439202eb2bdc49114dcc1ad0c533e5c6c4b437e0c4028a620f5e3e15bd0410db237a78bf99e9bb76a41e18f1687616ab46fa98380523b4e18ba3930740f5d55971e292de8559966208296ea2d73c6835ca75d05a20db4125d8d5ab41dc09664e14b9131336a01c2f40b715ccfcc04e04c7ffa6a15d93de82db39dd9573ab0ecdf10772a0200f0abb83c2b3776496e2a3f93142ea738144fa93a45e2230e3e8cbb40a9c55d65060af040688eca55132210c0f27217ae23284feb5e619df35a8d3893e5a6d2cfbb443a87eee1dc72928b09ad322b43c4e460d89066a0ba15c19af0ab733223aee18c2e41bbf03674a6a11ddbf18b870a19109640336bc9b2be9b0ec95093a8dcbb8d0c196d49bc5a749218143bb0645ca37be8858b87083888688ce591ed3bfb1a1456c0f01b70385656953ff294640d123e1c23796eb1c401c19d24f0ee6ebfdd35642dffd0e83fa1033efb73c7b03cc978786592f55fa840a2bc2ef489fe972514269c96457bbf3f9f2d979d16cc64cd92aa714816aa711f1a919396349715758cb4997873edc705b18f8640369ca9ec087688e88d53a46abcab4871b8c5dab3b46f534407058bc3245daf24d52c1ef27f0f7ac3c1f628cbf7f7f94962e8648ffadd51bf60512a0d45294bdde53755bafbb4182dcc85753971e8249c713dac1a0c7a2fa55f2e97f558659a484337924437fb0c6ab76b8d2a7b188781bd8bf97c8b8cacfba70bb775378e07aa83ecc054c4270e956edf3977311f710297d44c5dbf2a3ad0b8bdbacace7d874999d8d1296a81ae22225c6c16485876f9a9f2dd97c90fb3128a2965ecee4a77cafe9e48bb0194f464b4dbf97f200f4b0dc30c2b9c7dc04b7588beb796ba323f0998d29c67cbcd25ef8ea9e3ac84c3d7392a5ebf231adae777e0843dc5904f4662f4f131cc751d2aefff92bb6c9f4a34028cd026f1fe1f53eb9728fd8f147ce44cf6f2c2001f5c9f4f0989112bc170828b33e1803aab5ebf33046f7cebe63be1e850642f5c3e75fecf48fed24bf42ff9aa7e4d90826b6b47cf09dcce3b561bd3665daa85667981f0b8e83c17864b8e1a21575c8fd62aa9ce90b63a0f17bb3649b03d28aa1d25492598031ed5f19293d40d10f4d77e5080f6fbc57f8e7ab4d0437a972b74485dcf79aa824039411acbf7342ee1d4302126d6b797c232db547926008801b34267d8b877044687f33b73b99fc597b0096c406d48218c832ce01e76ff63bdb0996d2050a7175e14d956380f14acf9ae15be920f12f";
        f.sharesData[1] = hex"8de7a4cda0061036544e46c6663b10dc9041da347cda2f898156d35f6904fe6aafe730f9a9d812b9d7b71c050a5d36b705478d593ab5ff6b04d6e04a724f3db54d73697796b50c9c196fa2a7a83d5673d94479f04e622f31a09f0384bb4c91a592b89b64ef56f224cfd800cd8e502693f2f1d365806d4f2852edd8ef65818196cac465dcb17b90697fc12996baa015f1b1bd6b34c06a2b3e9ea7d53b7057f1c288ae2027ff087c0ca546eb82befff5966bd554dc6dc51c074080ae79d919280fa430bceffa27037538a4f995e72fba25fdb0faa02758d3ff6434a433781e54b985e488df7d653dd9e36bd3fa28abaf53a8f51a8b71c694fc279b4c463e5a820d799ebef441b9e1456d49cc738ca79518882d35c95340dd394bc5e300b52d759540c4324ad64eb919feeda344ff29b1be06e2200c2f6a8478bdcf472c33662b338ab78c56be51968e205c656ffd439c9d56cc89e7995c42485ba84771f4c9a6f11e3d8e3d5d4a54cb8e6abf17de13bd40409e977ccea2b61cd83018bab97ec6d9097c3936c2a178fe485af9589f744077b09243dab9d9a469d8c2224a75a8779ab29b2a81867923799650337f1c163736812b621fe74423f37726456ac8bb2c546434db3da010ed344d77ea46e11c28723f4f8886b6a86e5c79ff4e49665d85f1b6dfd2e975a287dd8da1a823b26ba4a914b39dbc1cfbb1f10261f04033efb2a42b238dd2275e701f9201bd9e716b395adfd7a543e6740b22e64db0d4e2e7793d11ba42815c96da2b57066aaf3950f651e686383fe1c4f57948d7755bbcc1b67141f0b9bb43fa7a98799d18798018abd0b6069287dcfae5830f3aadef445e21d461917a1ef9c2c074aa49c448ec4f47cce60ab26a593cf463d7831bb3c30c760dbc93845b943402560fca4232a0225099f2cbc6bb9d21f792b1cd354f4bceff75af3e63f21703529bcd6752388fc3dc92eafece893a41ea4099d50820723a9739d6cbcba827725bc25e8d654fcc9ced4acbafaa50fa2663ce8198e46249b66d498d7d80e639c3987ea5335d6bcbf01fb9f8056ed026eadc060f8531e089ad9e5e92f4402af93f7236b83eaee60c89a57ef37df154419859ec641e08516bb6f83e50df63e283fc9d16c81fef774e231bb770872b5c64a7ec097ca0853cc325883c85c1a2dc73b21cdc7798a891373f3817cacf5c671b2d962aba117831ce6416c0d2bb09e82e31cefb9d29f6180bbcd0976888fd431b50de88423713e1bce59325926a97da8724b3ab0ffb3c9ee1f8587022bb0fd06543791734373e987eae1c6489d483131969e31364f77310918d1b4e830da2a5a86c65fca7ee2867e9609261c1371b29f0203a7a8ecdca539a84b4889795c4ef811c48f575949dff2115c549ffda187d3c523506af24d51b4ad608ba363cd3e642990313465e54648b4c8a20b639205b262f36e491629abcc468d5a5bc83a01ba3a3f3c79f3c1dee0edce46d36e3179f750a05c0b2eca3e4480984cde4908e748acc91eae401fc04cb0e02717c570417a0541047acffbd3701171ed51e73890701f8309f02abfd906a3b3f7dbe9cf2b3ea4990cb85048779a3f699e7bbba989d35e50676517cbd514e3d3a9dfe4329e30ea7d2d50da54d070e1f435191db6f2529ee82084ab54a549ec21ccc9ff912115e01a3522fa993705b2d7c7b3a5d9bd9a34dde218f197afd6b5391adaa6f81f5493fda953c574f131d1135366cb1bcdb50014209a27a29abd823825cf55b52ab0a9cf40e37c479a8ec932060f76d045537bd5f0b1d2a96be3e83be62e72dc2cbf722d0511f6d2a82c615816b3d19be070c61abbe79274364bb9acd29";

        f.registerValue = MULTI_ETH_REGISTER_VALUE;
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

    function _registerMultiValidatorEthFixture()
        internal
        returns (address proxy, uint64[] memory multiOperatorIds, ISSVNetworkCore.Cluster memory clusterAfterRegister)
    {
        MultiValidatorEthFixture memory f = _getMultiValidatorEthFixture();
        multiOperatorIds = f.ids;

        proxy = _deployProxyViaClone();
        vm.deal(address(factory), f.registerValue);
        vm.recordLogs();
        vm.prank(address(factory));
        P2pSsvProxy(payable(proxy)).bulkRegisterValidatorsEth{value: f.registerValue}(
            f.pubkeys,
            f.ids,
            f.sharesData,
            _getEmptyCluster()
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        clusterAfterRegister = _extractClusterFromValidatorAdded(logs, proxy);
    }

    function _registerMultiValidatorViaFactoryEthFixture()
        internal
        returns (address proxy, uint64[] memory multiOperatorIds, ISSVNetworkCore.Cluster memory clusterAfterRegister)
    {
        MultiValidatorEthFixture memory f = _getMultiValidatorEthFixture();
        multiOperatorIds = f.ids;

        FeeRecipient memory localClientConfig = FeeRecipient({ recipient: payable(address(this)), basisPoints: 9500 });
        FeeRecipient memory localReferrerConfig = FeeRecipient({ recipient: payable(address(0)), basisPoints: 0 });

        vm.recordLogs();
        proxy = factory.registerValidatorsEth{value: f.registerValue}(
            f.owners,
            f.ids,
            f.pubkeys,
            f.sharesData,
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
        vm.expectRevert(abi.encodeWithSelector(
            P2pSsvProxy__NotP2pSsvProxyFactoryCalled.selector, nobody, IP2pSsvProxyFactory(address(factory))
        ));
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
        vm.expectRevert(abi.encodeWithSelector(
            P2pSsvProxy__CallerNeitherOperatorNorOwner.selector, nobody, address(0), owner
        ));
        P2pSsvProxy(payable(proxy)).reactivateEth{value: 1 ether}(operatorIds, one);

        ISSVNetworkCore.Cluster[] memory empty = new ISSVNetworkCore.Cluster[](0);
        vm.expectRevert(P2pSsvProxy__AmountOfParametersError.selector);
        P2pSsvProxy(payable(proxy)).reactivateEth{value: 1 ether}(operatorIds, empty);
    }

    function test_migrateClusterToETH_proxy_onlyFactory() public {
        address proxy = _deployProxyViaClone();
        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(
            P2pSsvProxy__NotP2pSsvProxyFactoryCalled.selector, nobody, IP2pSsvProxyFactory(address(factory))
        ));
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
        vm.expectRevert(abi.encodeWithSelector(OwnableBase__CallerNotOwner.selector, nobody, owner));
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
        vm.expectRevert(abi.encodeWithSelector(
            P2pSsvProxy__CallerNeitherOperatorNorOwner.selector, nobody, address(0), owner
        ));
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

    /**********************************/
    /* Multi-Validator ETH Tests       */
    /**********************************/

    function test_bulkRegisterValidatorsEth_multipleValidators() public {
        (address proxy,, ISSVNetworkCore.Cluster memory clusterAfterRegister) = _registerMultiValidatorEthFixture();

        assertTrue(proxy != address(0));
        assertEq(clusterAfterRegister.validatorCount, 2);
        assertTrue(clusterAfterRegister.active);
    }

    function test_registerValidatorsEth_multipleValidators() public {
        (address proxy,, ISSVNetworkCore.Cluster memory clusterAfterRegister) = _registerMultiValidatorViaFactoryEthFixture();

        assertTrue(proxy != address(0));
        assertEq(clusterAfterRegister.validatorCount, 2);
        assertTrue(clusterAfterRegister.active);
        assertEq(P2pSsvProxy(payable(proxy)).getFactory(), address(factory));
    }

    function test_depositToSsvEth_afterMultiValidatorRegistration() public {
        (address proxy, uint64[] memory multiOpIds, ISSVNetworkCore.Cluster memory clusterAfterRegister) =
            _registerMultiValidatorEthFixture();

        ISSVNetworkCore.Cluster[] memory clusters = _singleClusterArray(clusterAfterRegister);

        vm.recordLogs();
        P2pSsvProxy(payable(proxy)).depositToSsvEth{value: ETH_DEPOSIT_VALUE}(multiOpIds, clusters);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        ISSVNetworkCore.Cluster memory clusterAfterDeposit = _extractClusterFromDeposited(logs, proxy);

        assertEq(clusterAfterDeposit.validatorCount, 2);
        assertTrue(clusterAfterDeposit.balance > clusterAfterRegister.balance);
    }

    receive() external payable {}
}
