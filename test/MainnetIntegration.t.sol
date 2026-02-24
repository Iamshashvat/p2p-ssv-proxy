// SPDX-FileCopyrightText: 2024 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import "../src/interfaces/ssv/ISSVClusters.sol";
import "../src/interfaces/ssv/ISSVOperators.sol";

import "../src/p2pSsvProxyFactory/P2pSsvProxyFactory.sol";
import "../src/p2pSsvProxy/P2pSsvProxy.sol";
import "../src/access/OwnableBase.sol";
import "../src/structs/P2pStructs.sol";

import "../src/mocks/IChangeOperator.sol";
import "../src/mocks/IMockSsvNetwork.sol";
import "../src/mocks/IMockSsvNetworkViews.sol";

contract MainnetIntegration is Test {
    address public constant ssvOwner = 0xb35096b074fdb9bBac63E3AdaE0Bbde512B2E6b6;
    address public constant ssvNetworkAddress = 0xDD9BC35aE942eF0cFa76930954a156B3fF30a4E1;
    IMockSsvNetworkViews public constant ssvNetworkViews = IMockSsvNetworkViews(0xafE830B6Ee262ba11cce5F32fDCd760FFE6a66e4);

    address public constant owner = 0x588ede4403DF0082C5ab245b35F0f79EB2d8033a;
    address public constant operator = 0x11491A091A64E7e8E4837fe728e380BDd42b8834;
    address public constant nobody = address(42);

    IERC20 public constant ssvToken = IERC20(0x9D65fF81a3c488d585bBfb0Bfe3c7707c7917f54);
    P2pSsvProxyFactory public p2pSsvProxyFactory;
    address payable public constant client = payable(address(0x62a90760c7ce5CBaDbb64188ad075e9A52518D41));
    address public constant withdrawalCredentialsAddress = 0x548D1cA3470Cf9Daa1Ea6b4eF82A382cc3e24c4f;
    bytes32 public constant withdrawalCredentials = 0x010000000000000000000000548D1cA3470Cf9Daa1Ea6b4eF82A382cc3e24c4f;
    bytes32 public constant withdrawalCredentials_02 = 0x020000000000000000000000548D1cA3470Cf9Daa1Ea6b4eF82A382cc3e24c4f;

    IP2pOrgUnlimitedEthDepositor public constant p2pOrgUnlimitedEthDepositor = IP2pOrgUnlimitedEthDepositor(0xf6deA2834281d1a2e9E5ae6297F287475C907270);
    IFeeDistributorFactory public constant feeDistributorFactory = IFeeDistributorFactory(0x825C85a124a8134D2f599AE65B7E8D0635E84247);
    address public constant referenceFeeDistributor = 0x98b2eFF7e900d741d5c90dab4E708DaEb2a063e1;
    address public referenceP2pSsvProxy;
    ISSVNetworkCore.Cluster public clusterAfter1stRegistation;

    FeeRecipient public clientConfig;
    FeeRecipient public referrerConfig;
    address public proxyAddress;

    uint64[] public operatorIds;
    address[] allowedSsvOperatorOwners;

    bytes[] validatorPubKeys;
    bytes[] validatorPubKeys_42eth;
    bytes[] validatorSharesData;

    uint112 public constant SsvPerEthExchangeRateDividedByWei = 7539000000000000;
    uint112 public constant MaxSsvTokenAmountPerValidator = 30 ether;
    uint40 constant TIMEOUT = 1 days;
    uint96 constant MIN_ACTIVATION_BALANCE = 32 ether;

    event ValidatorAdded(address indexed owner, uint64[] operatorIds, bytes publicKey, bytes shares, ISSVNetworkCore.Cluster cluster);

    event ValidatorRemoved(address indexed owner, uint64[] operatorIds, bytes publicKey, ISSVNetworkCore.Cluster cluster);

    event ClusterLiquidated(address indexed owner, uint64[] operatorIds, ISSVNetworkCore.Cluster cluster);

    event ClusterReactivated(address indexed owner, uint64[] operatorIds, ISSVNetworkCore.Cluster cluster);

    event ClusterWithdrawn(address indexed owner, uint64[] operatorIds, uint256 value, ISSVNetworkCore.Cluster cluster);

    event ClusterDeposited(address indexed owner, uint64[] operatorIds, uint256 value, ISSVNetworkCore.Cluster cluster);

    event FeeRecipientAddressUpdated(address indexed owner, address recipientAddress);

    event ValidatorExited(address indexed owner, uint64[] operatorIds, bytes publicKey);

    error P2pOrgUnlimitedEthDepositor__Eip7251NotEnabledYet();

    function setUp() public {
        vm.createSelectFork("mainnet", 20106698);

        vm.startPrank(owner);

        p2pSsvProxyFactory = new P2pSsvProxyFactory(
            address(p2pOrgUnlimitedEthDepositor),
            address(feeDistributorFactory),
            referenceFeeDistributor
        );
        referenceP2pSsvProxy = address(new P2pSsvProxy());
        p2pSsvProxyFactory.setReferenceP2pSsvProxy(referenceP2pSsvProxy);

        operatorIds = new uint64[](4);
        operatorIds[0] = 145;
        operatorIds[1] = 474;
        operatorIds[2] = 506;
        operatorIds[3] = 512;

        allowedSsvOperatorOwners = new address[](4);
        allowedSsvOperatorOwners[0] = 0x09b7f5408d8a389e6beDfA3a6B43b328d6b3249d;
        allowedSsvOperatorOwners[1] = 0x3719A494cCf9C05d7d3b4c30D138d9ae2021F452;
        allowedSsvOperatorOwners[2] = 0xabB21CEC50038fe9F5Efa191760C9D38d758Af8d;
        allowedSsvOperatorOwners[3] = 0x448132eb4832bAE2C65da4A09b6f34D520007A71;

        p2pSsvProxyFactory.setAllowedSsvOperatorOwners(allowedSsvOperatorOwners);

        IChangeOperator(address(feeDistributorFactory)).changeOperator(address(p2pSsvProxyFactory));

        p2pSsvProxyFactory.setSsvOperatorIds([operatorIds[0],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], allowedSsvOperatorOwners[0]);
        p2pSsvProxyFactory.setSsvOperatorIds([operatorIds[1],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], allowedSsvOperatorOwners[1]);
        p2pSsvProxyFactory.setSsvOperatorIds([operatorIds[2],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], allowedSsvOperatorOwners[2]);
        p2pSsvProxyFactory.setSsvOperatorIds([operatorIds[3],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], allowedSsvOperatorOwners[3]);

        p2pSsvProxyFactory.setSsvPerEthExchangeRateDividedByWei(SsvPerEthExchangeRateDividedByWei);
        p2pSsvProxyFactory.setMaxSsvTokenAmountPerValidator(MaxSsvTokenAmountPerValidator);

        vm.stopPrank();

        deal(address(ssvToken), address(p2pSsvProxyFactory), 50000 ether);

        clientConfig = FeeRecipient({
            recipient: client,
            basisPoints: 9500
        });
        referrerConfig = FeeRecipient({
            recipient: payable(address(0)),
            basisPoints: 0
        });

        proxyAddress = predictProxyAddress();

        clusterAfter1stRegistation = ISSVNetworkCore.Cluster({
            validatorCount: 5,
            networkFeeIndex: 73961461734,
            index: 80552263144,
            active: true,
            balance: 53460049500000000000
        });

        validatorPubKeys = new bytes[](7);
        validatorPubKeys[0] = bytes(hex'8ae430787d3cb55093dba32d4f5e7736c48d494121dc6ed5520182490b977af7ddc0ecc586296fc315f9553dd07c5486');
        validatorPubKeys[1] = bytes(hex'b87798a82ca43743b7b726bdad694c8c9b76b68023bde42cf97a0e4d0da7e3604d4b436b9db44ef5e56106626d95ef68');
        validatorPubKeys[2] = bytes(hex'a3e789d3b378c42a3c963ef549b739ca55d1cdc7211aa22ebf382e4e847ea23f12c5a5131aa835afe5743432b02df806');
        validatorPubKeys[3] = bytes(hex'8171e4c04ea01ab1a84746527e33fdc739ad118946ba3f1cee356f3b35e9642304a7efffd1e4db4aa556ce333687ea11');
        validatorPubKeys[4] = bytes(hex'95dc732567172754d9a1764b0ce4aefba1c25d82983d964bafd26e8776c8b8197695b569b00321fa581eb70d528bca57');
        validatorPubKeys[5] = bytes(hex'92269be7b88c417f46aafd18943783990df0952c9858bd3147815e31f48d1be5f559387b696231f98fcc5ca2b3ff354e');
        validatorPubKeys[6] = bytes(hex'a413b93c25f77d27c5edab2b131d06bc90215c3eb2761309fdac35b0c76e12dccf45788a7ca0228b591cafb8626ab01a');

        validatorPubKeys_42eth = new bytes[](7);
        validatorPubKeys_42eth[0] = bytes(hex'a9ff619fbfedc3178cd401526b8320590903f8278c00ab1bf791b836cce92f2afa7c884dca2684a0a835a588e8661fa7');
        validatorPubKeys_42eth[1] = bytes(hex'ab7fa41fbf3e05cc29028140a2a56909f35e6f83766799182d6fa80e85a133907387455ecff841358392c4bfaa5c8329');
        validatorPubKeys_42eth[2] = bytes(hex'b88a4490baabd8d0e23ea0cc3ac81f95986272f0a355a2d180d85b67dfc99a749b69eae4138505aa4bc06b24cbde9fa0');
        validatorPubKeys_42eth[3] = bytes(hex'99f25ba85bc78d39e0ea79185fb75b19b51751fb01dd961ec31e15378b050ed6b8d896e2a7c3bb2cd789aef82674a90f');
        validatorPubKeys_42eth[4] = bytes(hex'833ac26a630899fd5e2e1f0aef225072eab71ae346a8968d79f091a6ecf33ffeba0d2221419fe2674b15f79e68fc6f52');
        validatorPubKeys_42eth[5] = bytes(hex'8d6984fdade19e2a3bd64bbb83f280dd4701366ecdf47ef49e3c57ef0838327102c9e3af37f87be33b92a278b4a7ee04');
        validatorPubKeys_42eth[6] = bytes(hex'944a91ae380a0ece1a41a9cf22729d4af45373308400b2b178f56eaa9322d55b85bd97bd4d82aec8fb8b0fe4152a0ab0');

        validatorSharesData = new bytes[](7);
        validatorSharesData[0] = bytes(hex'9714c5518407c3efb9cd40325ec39ca98fa10eb77012d47ce70a0518d2655d59d87df84fd84f8a063d0738bfd1ce002116d110e43ce18c70490fc561fca546bc6097030e5e533fd1c9002cd6785f7427d5b483d77f13189e71241e44e1b84d9b8e62a349a1fc9e6257aac8e2ad30073409a6345a9c002a4c7f2e27db41560bd735eed89ad073229a4dd9355dee558bd5a70ac0e7396e526205cb47014514f475065bb5b6e8ffb214f2a6da2ae4b7198ce069a6cc4fc9852d973c94fb3f0dfd63850649abef689d3dce185fae59232ba953fa3b6b3306782ed0a877a8c1e4979c62e1f0dee8ef2dcf237cd5df5340b951a4c32a3e2783ccdbb8b277c452fdbc2b186370c42631fe80b8cd115c48a2ce9f27c6791c03d48716673d6a3293ef989840a01829d5e504e22e16559516c6c6f4386d6fccdf83b0b1e10abcff06a5c964d87a616731ad7d543b6cfd3dcaeb4795ac50cbc1115d4d17c77d7119ab817a4952cf4aad389dace806e9fd7568c365ea96c02a9256e843846e96a070291d387f41e4a056d22c5b9286a0124e4330be9581818954b41a45a107f84e55f4f0e2799afd57517681db4fd7bd8bc4cedd4cbd19f1b2648fc34774396d7ec836cce3de792cffa21472fd806d331227ec21411ae4cb5a47558d383804cedabfce4e7ef49218255a1688ac8e2ef5aa0f43782655aa6002002a19d28ef90930d374006b3b9f44f09ae999223488e735551bf76e684e61966bf32e6dcbc6b3fa056a79692660af6f21ac806613e9a8586bf381b858598c30862d88b7f50a7805caf7b8c54ad5c08f8a2ca2f12e0de97b9c8c3dea41f61b90917b5cd0fe9a5fd7e6b367605aced36e6febac6900c05247a5d7a8df947458d75e8ec5cc907b86143b0574161fd2cd0fb7e3493cd5647a058820795b9fb236931e6efc89352b6e18c4fd3b61f73c5a80da892e20b5a28fe2cda5d48792c43c38ae3e51d6ad4141424019b54e4cb265e313fb737eb3c26796cee15f43ca3e19bffd7acec585e4190eba707f4bb187ff48ea0a3fa5392d182cc51f64cf1081e58948c030ec96cc688e00a84f1afd343b95c0a741c980655c02b6ffb049429d577e66204affac29e01d0ef9f6fd7047885814a84d8caa50af6fd9d5ccc10e31e0709dd9d66d84283a45ba6de07ebc96e66a04e5d7ed0714a0b3f2a3edaef9c73b9d24951f783e70b29073c49c4f5d099c5bdd10277eeacf765e3f3704e6812353fb263564aefb090f60598ea233273c977ffce4d9d4a047583d9bb076bc1d714eab9dda1e127c73938ec86c170466d454b2f7137b24e766955d2fa161257fc5f81f6c2ee5dc76d46f55f1d4a5fdf3c7f08d8fb5534c5bc50e5951abd272dcdf6ea32bba502872c1b15ff23254616b54b010975967526518c974bb00c2c161f89108178a50681548701e92f4e34b710a0ca914b9ed7f0b2c331a9e05bdcfd0cf6a8991b3cbdb24f9a2bf2fecda942098028196e59ed734f6cef9d1bfb5cf1d34bffb49f889f5a2a37072d2f847f34399dbd1084cea125e4bdad9357bde121927a795b3363c88a3163a231dd1be2e2f20515023f4933f0b450a6d78eeb3f7ae51c0be790a2247bc24de986277e5d88692e7dcd2ffad8d3d7c9e430e0a7b543b4359fa12d4bacd1c87c19628cd1a5d004e06c251ccd389ad781b35f125b79fb8a5406fbccb101c4baded43dc9bd67c0b91d0dae3f7b8014f6798eddb459159ec2c2794c73b82b548268f73728ca7c666c377ac756fa47d4f8cb6756081fd75ffa1c530a8808d34345750eec6bc3e91372cd266220bf6cf306b7f18372e842cac2f21eb1c8170697339418ac26823752a');
        validatorSharesData[1] = bytes(hex'88c88288862cf952bf388be0ca28646dc25ce1db6ddea6a57fd474c7ea249a80d077e813b4680c9249d48d20d37a3d8e035495f045c49d39fc5869b5e5363724a2b49a6c8d3dec824b28f6dbd40a0ece2287ff4cb670ed2d6f6b8bc7dd868c19b3cee94970c09e9cf302d5cb691ac2cfb049f4b24d85232ef7ca048e387761e3407e1507f9503f9ee8bb59cce50cd1228ab8a52ba343d6c84b18da712abb236f6b4861495c63f5204728f13db8afa6cd25059c3559450f3fd5940a0ae0f5c8d3a855bfdc2683e8acb0df3ed8ed3b161c033d2df8340073e377166fbbd5903cceebc23ae5eee25e800e7d12073e335fbda709991559fd8b41528da8a6249256a416defbf37406003757e83b71845b872d24acb22193b736eca3e169ddbc853d938fe15077e84f28067bfb9ed970c33e33910ad93196336735cede9dc4d310bf0d6792318bbe3832f9636ecff3bfe72ef2bc1f23fabf3c420336a4fc65bf690696a9e56bba1ceab4f2e3debcd8384f5558ea25b3c78900d6d3f2da23649f635245e2d0ec6fb69c15068fe0580dd92b472796caaf00a8108ef91c630db1220c0680f229d25a35444d1f42442a563ac77c4b837104355425d5fdb894a2009f0f89987cff9ec8e8ad72537668ba0f9d13d916852ded2cc8ac3d0da3e15b73cef302802917c593b6d0c231a1dd95e9e44d502f65423c7511d3ec3a54904dd83e27a7f331877ca0b4e8a7ed6b8355ae66a829ab890aa0e8ba7244e9e2a840451f6442b04f89a615285d718f82fa56ff1e69f85befac2d7226ef55c9ef42d9552cf4d832f5e7299ed0390db1937294e47d8f437f4eeaf33c22c66f202941378f75f34a49f5fce3d6b0aa4f7c90bb9276b4aa2a6733c015eee5cf0c3e13ff85782e7312157b22f57950bfff2a7b24b7f3436b2489b4a9c426c4abc3cb0c906618fc3781a6b9882f62e8e60f1e16b35d2c7abe71e6f07a18358c2ab722e35c7ddf7e6bac0301d2d89cb56fdca4b320b6772aead25b9e7bb79bea7baa76bf15d88e09cc95f6a585b0147abb9dea0ff50aea5a3ae76053c888adb06339bc39ff1a36dcdbb59436807ce9cb3c0bab96109960342d72c377f2f88dfe7399d8878e39d8b8b85bd76d7bbff63f359f645f97915e34ebeef91277e26e357a243c3bda1623b3ab7df30446575cdca20d9798e760a9ef418221e9188f5c047d59f59e529fd3f8ebc91666ea669d1b7b9efabc88a0e77cbbcbe0116c1ba3c76c5c5b3b3709f10ad888f59ecf8ae961bb9c0b90c938c5c5decea67a68f19cde29eb6048a0d366c9a476528fad29d8874700e760ac3768bc3ad9ff043b5e8e3617895b5d91394a2567c9104c9aeb385a0b0d61c08f9e9b1de0d19cb0a894b433bc7cf7475d370e2da6e5dae6fca2ee9850a2e4670876675d3c8064a6ec58c92d571c10d169e37d0ac6a311dc77d06b9dff30b881660cbfd976a6e2f3a6a8b6b0391b44d53f1068a571674bda28d81b4117e8399cd721e5eb08ffcde1e3b3614be5f94102a9a967b9add0c70dc85ea34fa7b3bed18b7ab3cc1f04f22a9030af7a185363b04daf79f347cf9355e61e5ba3fd3883091c9c4cfaab449691f15b8008b4a594aba31ac8147184f2b967c8d609e1116d3e1ab346512c9a3b06afd386e1bbdc28c75a8f8e407a4c3332ce39f817e8b8629e2fad9500488f930aa7cef618953185bf8135eb22af9f53fab4f84769fc0a0a77a07b4ecd5f04f01d7da83e1a420349fc624806b8fd8a9fc8878e1405a03e00b120b9e0646b300b02342e87bec6483b5ad1187f52bd1eeb8c49585a8bb921d8c8f9e925ebe57fcf88e45bdb17fde57b8f3c4cd7830c1246');
        validatorSharesData[2] = bytes(hex'a2a18b09f6fec70a0420eb0f4bf0ce4e67ca71fa4bf0e670f86382b75764a8cb7f9822ca77abe70e4c4c89b314414b430f8699423388e9a9598625a2b42a8798e32b4e2b699c4ff600d0ad8ed270f7091f667ec68a4b8150fdb04d12d172633396f17f960c32c2fcb212aeddeb0c009c089e3508012997558502863711528e127f178b41ee577fe84f40e6f2bb143a6ca0f1cdbf347077f4258d76e8558ccbd0ab0e281cd8c37ac17d998cce3f460549a02e2f8145fea73ea918bf05005213d2b25c47a693177f37228334ccb128055cae565820cc0005a07611fe153a6d00414ab3ba04773cdf5d82d7387dcfc51f818b2f46d918e2ccf6e4097e8aed740e6f309266c834f087b28803cc28e85d313c1dc31d26d6568a9597b59385cd30af883eec0beb97b855faf65e4803806e4e99da33569a40100f8f694811b7be11dc159394f3585ea2d9f46157f77c6ee99512c7dc0997f6e6b6ba6f5d7dbbc01df11bcc159965bc0b7cb9e9db810d7bb379b48fe0a9de97c8b31f59b91e07a9081b77a96b6413bf924d99c934d49dcf4997b032c4e165de282d8d87faf2d69862d3ba5bd023f8b8138deea323a1d6cc96944868d22de1581d7b94eb9dfc395d9864f38d8a9b6639dcbde8daaf7aa4008eced053d9f7ce496a7ab42b4f01117060b8c2d88a93edbaace8440979c48699675bd16f5a2e4fb460ceef732b712df4ac77a5bbcd381dee943b248cbcfc031483ee6aecf8e05f10cc226ece24e32e29396d33be3c0fedc83c6081df718dfdd1c675885cd766ae9e9b83e6d0144fa4c7e9543190bbef40b79cdf64187dad7eb4d4703387dcc0fcade19d08249aa1836048c3365c8e8840730edf6fd5cdb9aa6795e21ee4bd3db14437f0684fc37845fcaf057b906ca159800280d86f676c0d93c18d4a9e218bf8208dea8bbf73e55aedeb5023955214cadc9defa31273b1b6552a6f67ca158f19d0a601e9a460adfce9daaa0f95aceef528350faec40ec3e7273a0a4067bdf59dd4efb043442507384efa152ad93b6b227bc7ae7bfddbdbcb285702f675d12b640464d7c8b145332d937fadacadc0f99cfde42fab292fc0b9e7195c2067551c1dfda3b860cad2237013807b9c9225fe6cec423ccaceefcfff7d37e38f20f7b01e3a05cdeece442c8e652d048bdb7cc3a861399d0baee2aea828a0a62594a66bc3b2333bbfff2b39c4fa75890da043578b38bc8b83c93e7a0039638de70324af24869afc2a6cf850f5361074af30f20d8f155637417831a17545cf3dd157752d82ee355740c7f3a4e64330940383ad9ab513d700db4533f66cbdc8ec4b5e8e2767896884f271cd7a9c2e3bbb2b44a9ae359af341f6d0d7861ad25421d8ee97a7f3ded73f5b209e4a1be311189b7d753f85c572368803a5c3e8a56ec63f60087c807e93d1d25b6f8a11544f144acbc390de3342871ed9d1fd81ae9af2758ecc0ed3960a91bdfd448cd22e7e6fd099027813c70259180e9f69ddb0e3c41ac620649a7e7956787692322f532b6b2a408d7f458b2707e9e438812741a0e9ef2932e5ed53c90bea818aa27f804db695396e8ffcbcb80bdf7976d479377cffdb96c9416e6f175375bb216d0b610b589a3fa006285b16ec8a8bf2dcc509b1ea4e8f1c9c65747562a2f6b5e51eca50715bb1b80bd8ac195056f4ab8c477ebe71879687cff3fdb4af2790f39e3485b8ecac2fb5513a38af334c6aaab492af0474f6e23b61a90210a069b878388ba2d2dcb56f994cca24463f13eb269cd9d491ba086e878667a9625ce4884ffea357f32fbf59c1e7e329527b01335bece92a3fd40eb4ce766a96a9aacfb843171c41a38de7');
        validatorSharesData[3] = bytes(hex'826ef6f296151043e5d5de4265e6e86e109b728d6abb189bfa5e684400f88d9635661dc0502f7d55e6ee677c87118c960842e878ca7516161ba83ad183377dd5856531107269469c569d0a57cbcd36f33fae0728495f3fd4c785e4f64f750057927f743f74aa12c6fe14fbc5a91320d6376a878e543df7c30f5de4cfe409a38bd0a02a5acfec724530b40801075d48f1affa0e49d7fd97cbef355996f17a39fa33423be846e481afa1d50a614a3e0784a6aea1bcf17d967f2d3d29eb16b76a36b21e5f0360e014a6463499ff8d084e9aa744b3e5d2127a460877115535268c9d48ebf89e681cc5b40a36d8d505eb026581bab7607c5f2581ebb2ec1f8926b19867f89398942bcab9bbe29f6c2ec07c889d29b09d078265be23a6449180b9a9efa09aa67f1690a7b2f058614b45b5a9a019ec96a3cedfcb3935e89e49e7e99c360d669b8c51cb8c38f640456ab61b055484ebca56239698f2d72c918506f64dd9b14fa05160b1d514faa52ecf6450edd46b5bb74df3841c1c26faa6ba1d26954e0904406cdd59d80efb5cde3f427d6517093dc0e0571ab64e7f8b0ffa63a8f42c4481e3f3f2078cffe5272563d3032edd56fd9c65dc9882a2b5d0c22eb26926a78b5fefb5773a36bcce6cd5968c8b14370bc948ecb2f213db444cd4a538dc1b6362189c35e579fb607fe295f5b0db20c8ae166a7c5a03f01a43b023ef45982affa61f1ef8d0a9a64c4baf65440abe9c9f606fe47941f8f5cec6167b735c23fb98ba7c9192abf09287a4daebffd2fb47fb580e490adc0fd3a9cab727269863ca70221e6341079a68d20a9ac07b9f4911e1e8ce5bb8a8ba75e8f78809da3b0b515c0e78b2916d748b3a033c4d66382438bbbaca6583a555943ce6a35d3f8a69c1e44b74a51889b8974ef5ff9994650def6f5d2f6cdd25e8dbbc58ddd3d196a0cc199ccfc4e2d1f8590e4e2f4f122b1769b9719258ad4a363056e7b33e19dfdc1aa49300b6c39e118a1a9510837c84fc613fcc87531367c9a126df32ed0d553224da32ebac2acc14408dda707933810276c68260df4bcfd21cdedbc0016085120f685366898a32bf60154fd8a2a0188d86b7b6cf5fa0d51b4e02aa51d350a537b7b80fb67b9d5632b62ddf786293410030af18d9b6693bf74f2054c895752f4608d9b24fd12435149c79a6ef6a54b2a6417e3c136426e842037a01e65501336cfc40562bf034763e5c0a0ac0f8aec2f3cd0c1db9f011cc09b956bf8d9d07e312f529e13a47a0bc8a4c9cc4df154cf71180007848ca9267074c7903c1c065f07549b92dbf38b72526c73695161598e0ae6e4330b5cd482020cc7201054e4bdc07a19cc0b657164d23af04d5c9455a5cbb12815ca2d581185256da83911fa3a4dbc851b371002d0d9731c713fad9c56e9ab03a8b3753983d1e42cb4fc328e7f96635d3bbca00fe5eeee7ef7eb800635c3f5a03699c2d753c5a59c9fc7f75a9db7951efe19843b92a5582b3914a5b6016c284c440dbe99cfd6014fa2322940cc196b024ca4a3cfd4fdaba15b3f9e288d6e982b747ea613cb9eaccc40b625153c85bc4563af397876fa86ba571422cf6dcae9239e14e2f542ab25e5567cbfc68a189921fd84148204ae20e20718bcdf9802ecbc51af430b25730caf747dfae7934af27e4091a33fe425659f36b8aa54fc56a36b3391aedf230d040e73fa8f9608a6d72d9a72c81c9407a6142b444477427e36e28754e6abfc27c5db0b5adf08360a6d0ad43eea9450b8c33723aecd4c8513f7e6e84c532a7567a1003f1f7b680e8a484fd7b5ee1c1ac45eb4f22cdfb607467a3f4ff49d5b8e1e3c1ec4b34c24e9d0a7b09');
        validatorSharesData[4] = bytes(hex'a9aee828686da28649403ffc4e6b832e6101461b7bd162e9227576c8055f63a20a47aa76e85778af4f5ad49d073ab0901075bc5a954758fd0f426def03b27f66f7eab914cf0be83fa6836354681f602d2122443cfb7894559c9980ff4da281c883fe2f0a48d237b71604cd97ebcd2d82c0bb38311dc978bde7567ae9891df2a5138a1cbefcc5febaf29c58fabc4e4c3380240e87e15bed70f4a66f795163aab9d8600f08dca619d530194ac7163702718570a5e7611490d45b07c569a117f469ab8195e1a94bddb74fc9a94e50b9115e5351be3e6b362d1a662c20bc52ef2ba8371b5df0c460fd0887aa462a41bdc558a0ae92f534ea3ef55ee22a59b66dbb07e1f937b96e635e92271ac8615031e05e5a37f6a3c51cd9e3fb194b572a06abab86c492ca5c4ed7fdfc5c1e0df1099e9ef0bccfef9339d77b2c0d23097e81319c3534546045aaf8c345b435aaadb4f000b565fab9e18f6aa7c0d368fb47ea4c5a7da81154c171577e9baba130690e9e082b32e593f76d34513827f4be1e0acbfcb23ab20cabcb990b4392de0ab735ba0e266887ddf1f6e4926036be5e61d76a6786dfc0d5997294f816161d0938f7e1ea44ca0cecf043c9bb9738aa64518590c84bc06bc6680d8aa5a684aa29628cdcdfc36bb451f9508679cae7f2fc2e0882e4b68fccc90e31c1c3ffc712b20c0b097c125b91511cabb49f59fff86150ed6013d5ef19f3fde42c8acdeef51adc79c31cc7cd56cd5dda395bb1514331a2517ea35a55d9b51190a83d6bed720b5a8ba0ed07a4b32f5a44fe87425d6f9a9b98939d258b932ae502a994edbe5cac2c074e61f624cfa50d8854ed67f2dbaf71561977365dd4793bd4f95d6fc795faab13ade0a7c77141fac38ad3e288cc0bee4bbdf3737b7e254732bca1936bac02b6c7c9ecbb88df420a27cdd6bc28764c158c4b11b1ee3b619a318f9258598412f6065dcb246fea89566f564a37e136da70097a72536035e3cbbe75a0be4097abae62b05ffae73efc9fc3020509166edd0b286a5903911c8d837eb8bfe26a43092e07653ee01b54b6555f3d782aa5ce204f221775f0bb9163609e584f45e9bc9199e007a29d4f6413278f6b4255441c70f5f5f0073aaa1561ceab21aea7c17be2bcc124ffe54ab0eaef60db6e00f18d042cf6b9e959909cd3f29f7ced195db75243c5083e77d69f1bec9b8850efb4c15475bbcdc5d7f685ce805270385f4e58552dcf20d742d5cb287772143b1cccbe15f14500c72fd0d33d83f6b73cf8452c741768c7aed34384fa5e504617b58f354c4da7ac1960571878e365210e05e23ee9ba0829c27e8aaf49d24ac8d0ef104109b4ee7d5f2467de5d003a20607a3f590e13d5d6c22b9053a2c1cc613d7349cd6f99d756a88af95f75329867f9601559c57c2e55c2fca06c6cf936aa811683a72f82c98fb573dd1019b750f118e66fcee1fceeb68bb93528dfadd44b69e30d596e863efd65b08d28c3659a44e2aceecc7f0a20ee4fcd63c620a4d35f234b9c771c61027631b834b9dfc7e3628386b8ba7edeb5b0c20ebdda972324f994b2a5c7b2a8cccad761f6e7c6859a98192f32cb5fc240c51db24dfbff0e77fe97d52450405b6656602853bb43a2ddd7f5bbafa70d72045589b79f8575430054bf1cd29a8d3dc4d603b6b626fee39d1299c439ae388622399cc488a82df7fdfcbf54dae087877c1a813c5b8cbac5f55ce340871116ad9bb1d6dda3925e2e53b5e951aed96119325aa40babb844f71275ee08f1b1d635991a36b1bf5424cbbd092111c58788c7ffe046844a5871ec238a9087da2c9dceda8865651f3b91e44ca8cf26c1ed5ef0698490');
        validatorSharesData[5] = bytes(hex'97c1234209ecc63e907ad559a5193f8a17407caa089a721368b3b15a7ac56eb3413f3dd8de41607602348aa2081458260f5304ff30058e3556e2ac9fcdd28ca00b68b9afede51c193a59b47b25f19b5d5fd740f1bee56c7211b0332044cde0f0a40be54b20467d47866076b6eacbb41e5de0d217d1da09c74c5620004ed67a350d2589e1d2ea38c18aec55be0e27d4fbaf7a63a811c9d9bd1200f20a9dcd6ebb9ee0758c2c91069c4fc2e366e52fa0839db1fb9aeff05da2c2696e3efca3e75bacf1610d3fadbceb22b94686582f12a081125c86d840f8200b598e566e95e761fb3d924b990de6db5df929a869d308b1b0eab56138beb3a9cbe6e0d2c9bed730c40cee1a724ab7b238bc0f4128b9385b39568704c6ced503af40a00050a775da57a8cb23e29fd63b93cfdf0113af3c144fb3eabc27126016d0437749a17bc70967513814a987d93304e8747fdfdfe834ef75d0d62964f6e8bd9253184521e0d8e2849e3f856166a32e486b2c2d46f55a570619774858f23b7274fa99b56035ed56d9f3b9422956140a766e461bc5e2bc1ebf4ce3c290ab78f157a595ebe8f45e7c1ffd3df99bf7ba9e666b743174c4243287036c5c622edf19b4b1926f6e753b0eab8fc678db637903ec8cda7270aab39227c984b6cd9ba9cb2d8c79b35bcd5a4d5852dbba6a7b6eef20ff21594eddd506a5302545b711a84660904227dc882bcb9a28ae277da0712f6098e327dec373d0bd8782f9b3ee92ef4890c3f725ead77da085a3620b7199c4047fd417190c5d3ef73721d659b3a249c0b8d22c0fcb40b0594afbaf382ea25abb70c16ecc3173f1d22e1a0187066da7c9b24e20ce976628aa95570940ae7efd9ebdc7c1b6e2557a389107755e92116bce7edbac102378479b35cdf755f6daef4d9b738ec03675f738590f9f770f8ad2a5fdcfcc417542a084c5b5bbf19e919b547ce5359f3ad0d145ba421c8ad85163a8bc0eb4c7e98e982ee9f2dde3ef640d64c8c3895f8e580fc9a91416b843ec0f5dc2213960a8890c56af5b23f8cb02f116cd599cc6ba0efb023381047b7af2d765cecc2a8d4b46ac2b8a3ec302add152471fb684873399539dcb94e20c70beefc09566c86053c952ff3050731f039b21a0a40536fda7e2c68cab8bf40994bed6e306cd8e0a0b270862ffea6c92a1bf909733f36239237444bc5b56fc9e3e7b19769c794d34b6ace6e348b784212881f0f895c7f755903e4d1bdbce9a6a3d65caf6bbf899ec3053c3acdb231373a99e97d4dd0a78ab083a1373de6a4fefa7c1b2bc2015ad8eeefec8d671bf09846fea05936bc69adb6f4b52ceff7a100f85b0d01bf2fc001fdb492b5c12aaa5e9e8c32bda8d06fa2519d8059e1890e429088327142af945e7bd27ed82ea8ef14e956c0b803af18c489b6ab95ca81bf21d75a14be49a40fb95e9c7d505a21003a7747b963412635f45b95298a9d6a515216152a820887cb18114cc0108192f5673568f1781904d63c9ae03d27f5c212768f0fd6a831756bc56ccfe75df151159333e5a115b7c1439d489be7033c370a07393fa120c6bc614f9ed871711c65bb4617a2bc0a88b5af6d49d1b341e1ca5fc85d7b02622f60d08ef8736a97369f65642f54efd268017e17f3bc60fe458495b84477976853ff220903e8ce80f34d88990121394c22ff96a73b5792da507f97e5c4b801cb85c068fe45da43c551eda03eb76585c2fada4b758bb8a4edf5a518fe952712d2337ca7a2e4ca0e1b40ad77e931e95067f2cbfb215f87a21d26529131ea17551b649f81418c4a53bd8e3ecdef08ace9440937bfe8d2b2f628f4efbaa2eef245caa26bd2665cf83');
        validatorSharesData[6] = bytes(hex'acbb370c42c326f9cfca5904af936088305076f85a84c5c00c5c66a02c88377d05f012726e723e43acf0595fcfd5960d13c79309d552807f42809e00154b13531207991ddc37e892fa48d0d29ef3918840d44d3f8dfb3f3418e77592142fecf9adafcc7bfc0968f7dd74205cd54bd31e9c4111f71307c7da31f86bbc8e2f0f88f2ac403238f79a4733f6568f64815b15804908045038f43144d79408b764c71781f6091028dd0639ff74c49f7cfd2d36e427d2a917fd755ee308b967ec0ea90189f4794417df2da6ba6e37521018bbb1b022fd475da2c0f12e1f5dff1419dd4d11fff7e8d1c69e5cc7197dbe877f4b64b92bd144136eb09e6fcdcf836aa49687d29bcb8f2950f130f27e002570b68bbc7d8244762c5c66a36e6f67511cf74ddd32059bacbd17a8275863db176d7a9523a5e47f0d369c3fa91c31aaf60e4c8054fa0bdc7aada44bd3ee9087b9668d8ddf9acea624643a800d985fa6da590f71aa47b03758c8e63a350ffaeb36636f1ef3b0b7606bc944952edd99dc13ab2a899f300da9ab30cc9de7252a91c5822874c0c6ab510d32323a475ba19505121e68dd9cf018fea72c313b350264595f1c412823b62396f693eb662672f0fa8ac4b0cda432649838751d3e8626ddf007359c83d6b6779ab27fc4c4214f509dd350209cfcec81959de52d5f20379c52e4ad465e26358ae854196b57a724df54728c148307b1ce99325555c3dd981b9c8cfae510db924d68045cc88920d67c9cb231bd266e0356dce03c42efb87fbd5ccd667c732afff450b949dec75640085dc7ff309c9a90c3b3bfaa0dcb967b5d7efc10953fe6f24af9bd5a30b2c6fdd12dd8b76f197f698aa34cb3779b90471dfbef97642ec8508d1be3ee9c067e8ae61ea461af642b0b2508498d2718cdc4aace45f76d693273bc5bc469b0a2624e1f71dee3a777efb4e43a6d6c37ad242b25454a7b37cefdf8d7093b5aa2fc10f54a83925292c37796867343995bab2dd6b3a661b83624b45e2101222e5057bb7907fbe52ec39fbf66d1f14c176344fd5d8bd26c56b8440bdaa97d4b963ad1e02584b9d3199aa6f02f8062ba72d301f4d0eb4b2a8385682eee94aea5dd2be779512d229c0d0fef7d4f9dfa1fd82b98d25b09ab3f4623f54acf62b105f954b8507fde3c35b0589ed0a4b530c0ac6411a4104b93847c40bd06d9354c582d2407192b19d6eda61573343317c290519fc6fa699682884eb95215fd580c0dc82e8007d29b42248e5b6cce9ce0b4396d38cf23b8b39a23a36f49ae9aad146d9a650bec7c92ecca13a00debcdd611c3bcd06640b8c9982af47fc8a2894a00ac5c22343b0aa4c04ef65036680a8fa24d6ad164a0a86b032961c4f4ca7bd77b5674a48ddf167380e71537dcf250f86d43512675275ec69c64bea43d2b2f94e1cb9990f669595ba2594a805a447b0fe1f7a166d87a6198890cb6074008baebc09e99523399c069ef7b22ed5e6f156c5c219acaae2ad1c6046f9ca920660fc6172c2447ad4f05cfbe2579f39e8ceab11598eb7d0cd4ee5cd7c4c1506634aa169029dfc7fd235465dae70bcb09cfd7a8b28bd8f29a0c238867c81f35c5cfaaf33b58f61532782adc6db3e46ed8d89959bba349c911e243ae3d3599e9583a9083c99e20522180b7d1aa7c8e0053a09c9896c1e58634682583c456cf1c0cb59f1b515019dc2255f54bf65ad319e143a94aadcefd63dc6a1c49dc37e33e5a0e223df27414a2ccc224eddff93b18eb71450764000d8dbc9470570cf61bd3666432d86664f0b44d2d9b0cacbeac92b6b5482506a5b1718b9d4358efe22e66b00fbc9e34202c002d16be66c741303e3f');
    }

    function getSnapshot(uint64 operatorId) private view returns(bytes32 snapshot) {
        uint256 p = uint256(keccak256("ssv.network.storage.main")) + 5;
        bytes32 slot1 = bytes32(uint256(keccak256(abi.encode(uint256(operatorId), p))) + 2);
        snapshot = vm.load(ssvNetworkAddress, slot1);
    }

    function getSsvSlot0() private view returns(bytes32 ssvSlot0) {
        bytes32 slot = bytes32(uint256(keccak256("ssv.network.storage.protocol")) - 1);
        ssvSlot0 = vm.load(ssvNetworkAddress, slot);
    }

    function getOperatorFee(uint64 operatorId) private view returns(uint256) {
        return ssvNetworkViews.getOperatorFee(operatorId);
    }

    function setSsvOperator(SsvOperator[] memory ssvOperators, uint256 index) private view {
        ssvOperators[index].owner = allowedSsvOperatorOwners[index];
        ssvOperators[index].id = operatorIds[index];
        ssvOperators[index].snapshot = getSnapshot(operatorIds[index]);
        ssvOperators[index].fee = getOperatorFee(operatorIds[index]);
    }

    function getUpdatedSsvOperators() private view returns(SsvOperator[] memory ssvOperators) {
        ssvOperators = new SsvOperator[](4);
        setSsvOperator(ssvOperators, 0);
        setSsvOperator(ssvOperators, 1);
        setSsvOperator(ssvOperators, 2);
        setSsvOperator(ssvOperators, 3);
    }

    function getSsvValidators1() private view returns(SsvValidator[] memory ssvValidators) {
        ssvValidators = new SsvValidator[](5);
        for (uint256 i = 0; i < 5; i++) {
            ssvValidators[i].pubkey = validatorPubKeys[i];
            ssvValidators[i].sharesData = validatorSharesData[i];
        }
    }

    function getSsvValidators2() private view returns(SsvValidator[] memory ssvValidators) {
        ssvValidators = new SsvValidator[](2);
        ssvValidators[0].pubkey = validatorPubKeys[5];
        ssvValidators[0].sharesData = validatorSharesData[5];

        ssvValidators[1].pubkey = validatorPubKeys[6];
        ssvValidators[1].sharesData = validatorSharesData[6];
    }

    function getCluster1() private pure returns(ISSVNetworkCore.Cluster memory cluster) {
        cluster = ISSVNetworkCore.Cluster({
            validatorCount: 0,
            networkFeeIndex: 0,
            index: 0,
            active: true,
            balance: 0
        });
    }

    function getTokenAmount1() private pure returns(uint256 tokenAmount) {
        tokenAmount = 53460049500000000000;
    }

    function getSsvPayload1() private view returns(SsvPayload memory) {
        SsvOperator[] memory ssvOperators = getUpdatedSsvOperators();
        SsvValidator[] memory ssvValidators = getSsvValidators1();
        ISSVNetworkCore.Cluster memory cluster = getCluster1();
        uint256 tokenAmount = getTokenAmount1();

        return SsvPayload({
            ssvOperators:ssvOperators,
            ssvValidators:ssvValidators,
            cluster:cluster,
            tokenAmount:tokenAmount,
            ssvSlot0: getSsvSlot0()
        });
    }

    function getSsvPayload1WithDuplicateOperatorOwner() private view returns(SsvPayload memory) {
        SsvOperator[] memory ssvOperators = getUpdatedSsvOperators();

        ssvOperators[3] = ssvOperators[2];

        SsvValidator[] memory ssvValidators = getSsvValidators1();
        ISSVNetworkCore.Cluster memory cluster = getCluster1();
        uint256 tokenAmount = getTokenAmount1();

        return SsvPayload({
            ssvOperators:ssvOperators,
            ssvValidators:ssvValidators,
            cluster:cluster,
            tokenAmount:tokenAmount,
            ssvSlot0: getSsvSlot0()
        });
    }

    function getDepositData1() private pure returns(DepositData memory) {
        bytes[] memory signatures = new bytes[](5);
        signatures[0] = bytes(hex'b30e5adc7e414df9895082fc262142f4f238e768f76937a79c34dfae4417a44c9271d81118a97d933d033c7fa52f91f00cf52c016dd493eccfc694ab708e9c33b289da7c4c4d2d1357b89340bbaf7256b50cf69e6c8a18db37dc24eafe5b7c26');
        signatures[1] = bytes(hex'a4407a0a3675c31807d029b71916120880f3500c5373c2c0ab604bd7fcd1c4548aebf3f7ac3a1d8d3935dc68b088c2a1195456f2e52244cfa07657aa53e28a77d54b5399a5dfca1246b2292d1bdcbfb523e5423304fc88ca587d3f986e660f2b');
        signatures[2] = bytes(hex'aad460f178be421f88a28293f27e4eba3b72e4be18d0803dcba581de735c950f4bfcfc431f6e8bf8e46a8bb7bae303ab12bba13862d66256807f08960677ab018d352849e7e580c99b05ffcb1ff7ec7a9d09bdd055a69d16ea80c533a4e5f0a2');
        signatures[3] = bytes(hex'93a3bd7abe123e171b41e5dcdd3ba7d040e3d1d69e41ed3cf67c1215fcca14b2ffb6bd603021bed758a7d67aa323c264180c92b13d063e12f6d6911ebc24e932566c01c87dacea02f1571369680b5645ec10a9b44fe51cc147aa775837dd91b2');
        signatures[4] = bytes(hex'b624037a0899714bb07d0673caefdec5a16535900f72d9d457994600434b19917437fbd67c7e4ff17860bdbf7b57657a09eb2cae3bb1fbf59a3bf25e8aa2b27ba066b41b1122fe5741523fe62a6682906e4ecd3c2da281452eb38fbbf0d66083');

        bytes32[] memory depositDataRoots = new bytes32[](5);
        depositDataRoots[0] = bytes32(hex'b91266d5b4e92690874f3815ea7b7b8bf0d72f6fb9819c7a4c6b5151bf15ce88');
        depositDataRoots[1] = bytes32(hex'3f751c3138d9da913371cd993991e3392eadebb815563bac82583bc357b73292');
        depositDataRoots[2] = bytes32(hex'89d95e435cb1535044ff888a3bcbf49ba4a950667def6dff3032e6a9e0655efd');
        depositDataRoots[3] = bytes32(hex'2db2efe5d6e8bdf6e95cc61c21b5b0295fa77ee0589dacbf830e7f68cfe9db8f');
        depositDataRoots[4] = bytes32(hex'2b86e89e1cdace0d21853457ac6b958a348c0ac6e94b2ae5d8c85873e8ec684d');

        return DepositData({
            signatures: signatures,
            depositDataRoots: depositDataRoots
        });
    }

    function getDepositData1_42eth() private pure returns(DepositData memory) {
        bytes[] memory signatures = new bytes[](5);
        signatures[0] = bytes(hex'83a932e672d9f3fcda1cf2c8ef81cbcef7c42e0426aa20e29b1bb1e25759a43e7f10c4cc929f52b3ce89189422328d1d1135b83a7fed90fcacfea9652dbfd0761a0dd321a51a9410f154e23694889729eadc231eff468a71fab1c18cdf674fe9');
        signatures[1] = bytes(hex'b361c7e742c5e062326802273bfafe2b82a7075ce21fb47c112ff666f1d62bf3dd049da381f938ab169aa07c3667faf30462ed43274366141fabf5bb1f8db6d7b6c44f4fde1921aff3718cfc51b04d2cad3005ac47f00885859fe1752e7c4888');
        signatures[2] = bytes(hex'80cc25f6a497e4309edf7e775b6fdaa6a8ce67f612e8f473e7278df01bd1fb5af849bda10542eb7be59004335c5fcade104ae246d5427e1518a4469e1385beac2f05800d3240ab708ea12a38ded8d988d857c05f96865680554fbf31d1d48acd');
        signatures[3] = bytes(hex'8eabe180045a15d7b0d6a0616817e0c2148efd5aa3361fed48a9e00a8e805e0ad90485b304da16db48188c450a32ade20fd9383bd52b3d875ef9b4da38bf1e527107cf5658c720710190553e3ec6325d4c6d67390f1d25dd8b3d60f2d7b52411');
        signatures[4] = bytes(hex'8eaa489d1bcf80620350387e9dd66ba1d0e5ede46ceede000ceff3284b1f3a39d99a178ed339ebd564a3fd7dcf8d367216893251f6960c0c65cbdc9f198e2f48b938e546e39df4cba7cc11776814d4e0100e130b8446050ed04e87d473d42149');

        bytes32[] memory depositDataRoots = new bytes32[](5);
        depositDataRoots[0] = bytes32(hex'1dbe9ba0be5e6abb34bc39473898a61ba71c5f239dcc9dd303bc513b8a87044f');
        depositDataRoots[1] = bytes32(hex'abbb84072feb98b7f9645d7fda29a021a725e0faf3b9aa50d5cd8d5c701be95d');
        depositDataRoots[2] = bytes32(hex'0919b7daea390d11b9d8854004777b36ea966c45e6db63269eade3e8441c99b9');
        depositDataRoots[3] = bytes32(hex'5cb3442c055cf4481efd3ea7b4af7a4c1c8626c1c4cfdd4f032837c5a3e57f10');
        depositDataRoots[4] = bytes32(hex'f633c7a69984f42e8e5b6d60d21e2c0246ef61a752ba4f582028a8875d331928');

        return DepositData({
            signatures: signatures,
            depositDataRoots: depositDataRoots
        });
    }

    function getDepositData1DifferentLength() private pure returns(DepositData memory) {
        bytes[] memory signatures = new bytes[](4);
        signatures[0] = bytes(hex'b30e5adc7e414df9895082fc262142f4f238e768f76937a79c34dfae4417a44c9271d81118a97d933d033c7fa52f91f00cf52c016dd493eccfc694ab708e9c33b289da7c4c4d2d1357b89340bbaf7256b50cf69e6c8a18db37dc24eafe5b7c26');
        signatures[1] = bytes(hex'a4407a0a3675c31807d029b71916120880f3500c5373c2c0ab604bd7fcd1c4548aebf3f7ac3a1d8d3935dc68b088c2a1195456f2e52244cfa07657aa53e28a77d54b5399a5dfca1246b2292d1bdcbfb523e5423304fc88ca587d3f986e660f2b');
        signatures[2] = bytes(hex'aad460f178be421f88a28293f27e4eba3b72e4be18d0803dcba581de735c950f4bfcfc431f6e8bf8e46a8bb7bae303ab12bba13862d66256807f08960677ab018d352849e7e580c99b05ffcb1ff7ec7a9d09bdd055a69d16ea80c533a4e5f0a2');
        signatures[3] = bytes(hex'93a3bd7abe123e171b41e5dcdd3ba7d040e3d1d69e41ed3cf67c1215fcca14b2ffb6bd603021bed758a7d67aa323c264180c92b13d063e12f6d6911ebc24e932566c01c87dacea02f1571369680b5645ec10a9b44fe51cc147aa775837dd91b2');

        bytes32[] memory depositDataRoots = new bytes32[](5);
        depositDataRoots[0] = bytes32(hex'b91266d5b4e92690874f3815ea7b7b8bf0d72f6fb9819c7a4c6b5151bf15ce88');
        depositDataRoots[1] = bytes32(hex'3f751c3138d9da913371cd993991e3392eadebb815563bac82583bc357b73292');
        depositDataRoots[2] = bytes32(hex'89d95e435cb1535044ff888a3bcbf49ba4a950667def6dff3032e6a9e0655efd');
        depositDataRoots[3] = bytes32(hex'2db2efe5d6e8bdf6e95cc61c21b5b0295fa77ee0589dacbf830e7f68cfe9db8f');
        depositDataRoots[4] = bytes32(hex'2b86e89e1cdace0d21853457ac6b958a348c0ac6e94b2ae5d8c85873e8ec684d');

        return DepositData({
            signatures: signatures,
            depositDataRoots: depositDataRoots
        });
    }

    function getSsvPayload2() private view returns(SsvPayload memory) {
        SsvOperator[] memory ssvOperators = getUpdatedSsvOperators();
        SsvValidator[] memory ssvValidators = getSsvValidators2();

        return SsvPayload({
            ssvOperators:ssvOperators,
            ssvValidators:ssvValidators,
            cluster:clusterAfter1stRegistation,
            tokenAmount:getTokenAmount1(),
            ssvSlot0: getSsvSlot0()
        });
    }

    function getDepositData2() private pure returns(DepositData memory) {
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = bytes(hex'8c00eea680eadac2f426cd3809ab3177ab4b25c3f97dd80fc4ba0c055ff8d60e73381de456cf8b8184d9af2a15bb318a144cd0b0c261f462b58e61bea15e1fb9ff67058950ac0eb2e430feca3915c2c49d36b83beb3f7ca23141b5ebd5cf12f0');
        signatures[1] = bytes(hex'8a28e64df753ed8e4785db087e4c6b7476ab4d11d711674b2d6398fb82dde8417e7b5db8ccf4383e891da8bdc167982f17dc7712a3b27c6b57d90b08af884486d743ffd904575561a29960f6ee47cda70a606b461b8dc475d191bcbab2af8662');

        bytes32[] memory depositDataRoots = new bytes32[](2);
        depositDataRoots[0] = bytes32(hex'20187410c9727808d2eafe0bea417c04c65917236ed424f21c8daa1f2b494f98');
        depositDataRoots[1] = bytes32(hex'8c75013ba6f48bd1c635c25d8e6e1f3ca04a8f30ae77d91dc53f49df518de687');

        return DepositData({
            signatures: signatures,
            depositDataRoots: depositDataRoots
        });
    }

    function getDepositData2_42eth() private pure returns(DepositData memory) {
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = bytes(hex'8cc040fb9e11bac6cfd3c646221e8402630852bc0f652942b6571d287f15bebc1e35c00ac7da4089ab24c4de9bdf534e0776b968a0509af20fd7625cf4b9649de1f47f2d715e9dcac9b53a964458c2e61e9fd721eece94c2cc89e9eee59f1b7e');
        signatures[1] = bytes(hex'969decd4696ee36493dceb1365fe6a8bf5046226c3f6a8e687e31322536676db95666af806fd3b275fcaf5ec7c9f5046106d8766c52928f07974d1e975451e34b82928514817e1487de7a71f4c20ee1bdc247993e4c10391c2bea28267e1ec3c');

        bytes32[] memory depositDataRoots = new bytes32[](2);
        depositDataRoots[0] = bytes32(hex'5217680bead75f1753bd0f38a82b8c70bfa6e60e3fcb5b32c2acd7848cba614d');
        depositDataRoots[1] = bytes32(hex'5cb1ddaae83d0d789542e77277df8f52e081464e632999b5869c1b33663b7c64');

        return DepositData({
            signatures: signatures,
            depositDataRoots: depositDataRoots
        });
    }

    function predictProxyAddress() private view returns(address) {
        address feeDistributor = feeDistributorFactory.predictFeeDistributorAddress(referenceFeeDistributor, clientConfig, referrerConfig);
        return p2pSsvProxyFactory.predictP2pSsvProxyAddress(feeDistributor);
    }

    function test_depositEthAndRegisterValidators_Mainnet_Deprecated() public {
        console.log("test_depositEthAndRegisterValidators_Mainnet_Deprecated started");

        vm.deal(client, 1000 ether);
        vm.startPrank(client);

        DepositData memory depositData1 = getDepositData1();
        SsvPayload memory ssvPayload1 = getSsvPayload1();

        vm.expectRevert(P2pSsvProxyFactory__DeprecatedFunction.selector);
        p2pSsvProxyFactory.depositEthAndRegisterValidators{value: 160 ether}(
            depositData1,
            withdrawalCredentialsAddress,
            ssvPayload1,
            clientConfig,
            referrerConfig
        );

        vm.stopPrank();

        console.log("test_depositEthAndRegisterValidators_Mainnet_Deprecated finished");
    }

    function test_depositEthAndRegisterValidators_via_bulkRegisterValidators_Deprecated() public {
        console.log("test_depositEthAndRegisterValidators_via_bulkRegisterValidators_Deprecated started");

        vm.deal(client, 1000 ether);
        vm.startPrank(client);

        DepositData memory depositData1 = getDepositData1();

        bytes[] memory pubKeys1 = new bytes[](5);
        bytes[] memory sharesData1 = new bytes[](5);
        for (uint256 i = 0; i < 5; i++) {
            pubKeys1[i] = validatorPubKeys[i];
            sharesData1[i] = validatorSharesData[i];
        }

        vm.expectRevert(P2pSsvProxyFactory__DeprecatedFunction.selector);
        p2pSsvProxyFactory.depositEthAndRegisterValidators{value: 160 ether}(
            depositData1,
            withdrawalCredentialsAddress,

            allowedSsvOperatorOwners,
            operatorIds,
            pubKeys1,
            sharesData1,
            getTokenAmount1(),
            getCluster1(),

            clientConfig,
            referrerConfig
        );

        vm.stopPrank();

        console.log("test_depositEthAndRegisterValidators_via_bulkRegisterValidators_Deprecated finished");
    }

    function registerValidators() private {
        vm.startPrank(owner);
        p2pSsvProxyFactory.setSsvPerEthExchangeRateDividedByWei(SsvPerEthExchangeRateDividedByWei);
        vm.stopPrank();

        SsvPayload memory ssvPayload1 = getSsvPayload1();

        uint256 neededEth = p2pSsvProxyFactory.getNeededAmountOfEtherToCoverSsvFees(ssvPayload1.tokenAmount);

        vm.deal(nobody, 1000 ether);
        vm.startPrank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pSsvProxyFactory__CallerNeitherOperatorNorOwnerNorClient.selector, nobody));
        p2pSsvProxyFactory.registerValidators{value: neededEth}(
            ssvPayload1,
            clientConfig,
            referrerConfig
        );
        vm.stopPrank();

        vm.deal(client, 1000 ether);
        vm.startPrank(client);
        p2pSsvProxyFactory.registerValidators{value: neededEth}(
            ssvPayload1,
            clientConfig,
            referrerConfig
        );
        vm.stopPrank();
    }

    function registerValidators_via_bulkRegisterValidators() private {
        vm.startPrank(owner);
        p2pSsvProxyFactory.setSsvPerEthExchangeRateDividedByWei(SsvPerEthExchangeRateDividedByWei);
        vm.stopPrank();

        bytes[] memory pubKeys1 = new bytes[](5);
        bytes[] memory sharesData1 = new bytes[](5);
        for (uint256 i = 0; i < 5; i++) {
            pubKeys1[i] = validatorPubKeys[i];
            sharesData1[i] = validatorSharesData[i];
        }

        vm.deal(client, 1000 ether);
        vm.startPrank(client);

        uint256 neededEth = p2pSsvProxyFactory.getNeededAmountOfEtherToCoverSsvFees(getTokenAmount1());

        p2pSsvProxyFactory.registerValidators{value: neededEth}(
            allowedSsvOperatorOwners,
            operatorIds,
            pubKeys1,
            sharesData1,
            getTokenAmount1(),
            getCluster1(),

            clientConfig,
            referrerConfig
        );

        vm.stopPrank();
    }

    function test_viewFunctions() public {
        console.log("test_viewFunctions started");

        vm.startPrank(owner);
        p2pSsvProxyFactory.setSsvPerEthExchangeRateDividedByWei(SsvPerEthExchangeRateDividedByWei);
        vm.stopPrank();

        SsvPayload memory ssvPayload1 = getSsvPayload1();

        uint256 neededEth = p2pSsvProxyFactory.getNeededAmountOfEtherToCoverSsvFees(ssvPayload1.tokenAmount);

        address proxy1 = predictProxyAddress();
        address feeDistributor = feeDistributorFactory.predictFeeDistributorAddress(referenceFeeDistributor, clientConfig, referrerConfig);

        vm.deal(client, 1000 ether);
        vm.startPrank(client);

        vm.expectEmit();
        emit FeeRecipientAddressUpdated(
            proxy1,
            feeDistributor
        );
        p2pSsvProxyFactory.registerValidators{value: neededEth}(
            ssvPayload1,
            clientConfig,
            referrerConfig
        );
        vm.stopPrank();

        {
        address clientFromProxy = P2pSsvProxy(payable(proxy1)).getClient();
        assertEq(clientFromProxy, client);

        address factoryFromProxy = P2pSsvProxy(payable(proxy1)).getFactory();
        assertEq(factoryFromProxy, address(p2pSsvProxyFactory));

        address feeDistributorFromProxy = P2pSsvProxy(payable(proxy1)).getFeeDistributor();
        assertEq(feeDistributorFromProxy, feeDistributor);

        address ownerFromProxy = P2pSsvProxy(payable(proxy1)).owner();
        assertEq(ownerFromProxy, owner);
        }

        vm.startPrank(owner);
        p2pSsvProxyFactory.changeOperator(operator);
        vm.stopPrank();

        {
        address operatorFromProxy = P2pSsvProxy(payable(proxy1)).operator();
        assertEq(operatorFromProxy, operator);

        address operatorFromFactory = p2pSsvProxyFactory.operator();
        assertEq(operatorFromFactory, operator);

        address ownerFromFactory = p2pSsvProxyFactory.owner();
        assertEq(ownerFromFactory, owner);

        address[] memory allClientP2pSsvProxies = p2pSsvProxyFactory.getAllClientP2pSsvProxies(client);
        assertEq(allClientP2pSsvProxies[0], proxy1);

        uint64[MAX_ALLOWED_SSV_OPERATOR_IDS] memory ids = p2pSsvProxyFactory.getAllowedSsvOperatorIds(ssvPayload1.ssvOperators[1].owner);
        assertEq(ids[0], ssvPayload1.ssvOperators[1].id);

        address[] memory ssvOperatorOwners = p2pSsvProxyFactory.getAllowedSsvOperatorOwners();
        assertEq(ssvOperatorOwners[1], ssvPayload1.ssvOperators[1].owner);

        address[] memory allProxies = p2pSsvProxyFactory.getAllP2pSsvProxies();
        assertEq(allProxies[0], proxy1);
        }

        {
            address feeDistributorFactoryFromP2pSsvProxyFactory = p2pSsvProxyFactory.getFeeDistributorFactory();
            assertEq(feeDistributorFactoryFromP2pSsvProxyFactory, address(feeDistributorFactory));

            uint256 neededAmountOfEtherToCoverSsvFees = p2pSsvProxyFactory.getNeededAmountOfEtherToCoverSsvFees(ssvPayload1.tokenAmount);
            assertEq(neededAmountOfEtherToCoverSsvFees, (ssvPayload1.tokenAmount * SsvPerEthExchangeRateDividedByWei) / 10**18);

            address referenceFeeDistributorFromFactory = p2pSsvProxyFactory.getReferenceFeeDistributor();
            assertEq(referenceFeeDistributorFromFactory, referenceFeeDistributor);

            address referenceP2pSsvProxyFromFactory = p2pSsvProxyFactory.getReferenceP2pSsvProxy();
            assertEq(referenceP2pSsvProxyFromFactory, referenceP2pSsvProxy);

            uint256 ssvPerEthExchangeRateDividedByWeiFromFactory = p2pSsvProxyFactory.getSsvPerEthExchangeRateDividedByWei();
            assertEq(ssvPerEthExchangeRateDividedByWeiFromFactory, SsvPerEthExchangeRateDividedByWei);

            bytes4[] memory selectors = new bytes4[](1);
            selectors[0] = ISSVClusters.withdraw.selector;

            bool isOperatorSelectorAllowedFromFactoryBefore = p2pSsvProxyFactory.isOperatorSelectorAllowed(selectors[0]);
            assertEq(isOperatorSelectorAllowedFromFactoryBefore, false);

            vm.startPrank(owner);
            p2pSsvProxyFactory.setAllowedSelectorsForOperator(selectors);
            vm.stopPrank();

            bool isOperatorSelectorAllowedFromFactoryAfter = p2pSsvProxyFactory.isOperatorSelectorAllowed(selectors[0]);
            assertEq(isOperatorSelectorAllowedFromFactoryAfter, true);

            bool isClientSelectorAllowedFromFactoryBefore = p2pSsvProxyFactory.isClientSelectorAllowed(selectors[0]);
            assertEq(isClientSelectorAllowedFromFactoryBefore, false);

            vm.startPrank(owner);
            p2pSsvProxyFactory.setAllowedSelectorsForClient(selectors);
            vm.stopPrank();

            bool isClientSelectorAllowedFromFactoryAfter = p2pSsvProxyFactory.isClientSelectorAllowed(selectors[0]);
            assertEq(isClientSelectorAllowedFromFactoryAfter, true);

            vm.startPrank(owner);
            p2pSsvProxyFactory.removeAllowedSelectorsForClient(selectors);
            vm.stopPrank();

            isClientSelectorAllowedFromFactoryAfter = p2pSsvProxyFactory.isClientSelectorAllowed(selectors[0]);
            assertEq(isClientSelectorAllowedFromFactoryAfter, false);
        }

        {
            address feeDistributorFactory_ = p2pSsvProxyFactory.getFeeDistributorFactory();
            address referenceFeeDistributor_ = p2pSsvProxyFactory.getReferenceFeeDistributor();
            address feeDistributorInstance = IFeeDistributorFactory(feeDistributorFactory_).predictFeeDistributorAddress(
                referenceFeeDistributor_,
                clientConfig,
                referrerConfig
            );

            address proxy_1 = p2pSsvProxyFactory.predictP2pSsvProxyAddress(feeDistributorInstance);
            address proxy_2 = p2pSsvProxyFactory.predictP2pSsvProxyAddress(
                referenceFeeDistributor_,
                clientConfig,
                referrerConfig
            );
            address proxy_3 = p2pSsvProxyFactory.predictP2pSsvProxyAddress(
                clientConfig,
                referrerConfig
            );
            address proxy_4 = p2pSsvProxyFactory.predictP2pSsvProxyAddress(
                clientConfig
            );

            assertEq(proxy_1, proxy_2);
            assertEq(proxy_1, proxy_3);
            assertEq(proxy_1, proxy_4);
        }

        console.log("test_viewFunctions finsihed");
    }

    function test_setFeeRecipientAddress() public {
        console.log("test_setFeeRecipientAddress started");

        vm.startPrank(owner);
        p2pSsvProxyFactory.setSsvPerEthExchangeRateDividedByWei(SsvPerEthExchangeRateDividedByWei);
        vm.stopPrank();

        SsvPayload memory ssvPayload1 = getSsvPayload1();

        uint256 neededEth = p2pSsvProxyFactory.getNeededAmountOfEtherToCoverSsvFees(ssvPayload1.tokenAmount);

        address proxy1 = predictProxyAddress();
        address feeDistributor = feeDistributorFactory.predictFeeDistributorAddress(referenceFeeDistributor, clientConfig, referrerConfig);

        vm.deal(client, 1000 ether);
        vm.startPrank(client);

        vm.expectEmit();
        emit FeeRecipientAddressUpdated(
            proxy1,
            feeDistributor
        );
        p2pSsvProxyFactory.registerValidators{value: neededEth}(
            ssvPayload1,
            clientConfig,
            referrerConfig
        );
        vm.stopPrank();

        vm.startPrank(owner);

        vm.expectEmit();
        emit FeeRecipientAddressUpdated(
            proxy1,
            client
        );
        P2pSsvProxy(payable(proxy1)).setFeeRecipientAddress(client);
        vm.stopPrank();

        console.log("test_setFeeRecipientAddress finsihed");
    }

    function test_settersAndRemovers() public {
        console.log("test_settersAndRemovers started");

        vm.startPrank(owner);
        p2pSsvProxyFactory.setSsvPerEthExchangeRateDividedByWei(SsvPerEthExchangeRateDividedByWei);
        vm.stopPrank();

        SsvPayload memory ssvPayload1 = getSsvPayload1();

        uint256 neededEth = p2pSsvProxyFactory.getNeededAmountOfEtherToCoverSsvFees(ssvPayload1.tokenAmount);

        address feeDistributor = 0x98b2eFF7e900d741d5c90dab4E708DaEb2a063e1;
        address proxy1 = p2pSsvProxyFactory.predictP2pSsvProxyAddress(feeDistributor);
        assertEq(proxy1.code.length, 0);

        vm.startPrank(owner);
        p2pSsvProxyFactory.createP2pSsvProxy(feeDistributor);
        vm.stopPrank();

        assertNotEq(proxy1.code.length, 0);

        vm.deal(client, 1000 ether);
        vm.startPrank(client);
        p2pSsvProxyFactory.registerValidators{value: neededEth}(
            ssvPayload1,
            clientConfig,
            referrerConfig
        );
        vm.stopPrank();

        address[] memory ssvOperatorOwners = new address[](2);
        ssvOperatorOwners[0] = 0x8D174A0a34A244C4E2B6568f373dA136a2ffafc8;
        ssvOperatorOwners[1] = 0xf2659Cc196829c6676B1E0E1a71A8797ceC6778A;

        vm.startPrank(owner);
        p2pSsvProxyFactory.setAllowedSsvOperatorOwners(ssvOperatorOwners);
        p2pSsvProxyFactory.setSsvOperatorIds([uint64(0), 0, 0, 0, 0, 0, 40, 0, 0, 0, 0, 0, 0, 0, 0, 0,0,0,0,0,0,0,0,0], ssvOperatorOwners[0]);
        p2pSsvProxyFactory.setSsvOperatorIds([uint64(0), 0, 44, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,0,0,0,0,0,0,0,0], ssvOperatorOwners[1]);
        vm.stopPrank();

        vm.startPrank(ssvOperatorOwners[0]);
        p2pSsvProxyFactory.setSsvOperatorIds([uint64(37), 38, 39, 40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,0,0,0,0,0,0,0,0]);
        vm.stopPrank();

        vm.startPrank(ssvOperatorOwners[1]);
        p2pSsvProxyFactory.setSsvOperatorIds([uint64(45), 0, 44, 0, 43, 0, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0,0,0,0,0,0,0,0,0]);
        p2pSsvProxyFactory.clearSsvOperatorIds();
        p2pSsvProxyFactory.clearSsvOperatorIds();
        vm.stopPrank();

        vm.startPrank(owner);
        p2pSsvProxyFactory.removeAllowedSsvOperatorOwners(ssvOperatorOwners);
        vm.stopPrank();

        vm.startPrank(ssvOperatorOwners[1]);
        vm.expectRevert(abi.encodeWithSelector(P2pSsvProxyFactory__NotAllowedSsvOperatorOwner.selector, ssvOperatorOwners[1]));
        p2pSsvProxyFactory.setSsvOperatorIds([uint64(45), 0, 44, 0, 43, 0, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0,0,0,0,0,0,0,0,0]);
        vm.stopPrank();

        console.log("test_settersAndRemovers finsihed");
    }

    function test_removeValidators() public {
        console.log("test_removeValidators started");

        vm.startPrank(owner);
        p2pSsvProxyFactory.setSsvPerEthExchangeRateDividedByWei(SsvPerEthExchangeRateDividedByWei);
        vm.stopPrank();

        SsvPayload memory ssvPayload1 = getSsvPayload1();

        uint256 neededEth = p2pSsvProxyFactory.getNeededAmountOfEtherToCoverSsvFees(ssvPayload1.tokenAmount);

        vm.deal(client, 1000 ether);
        vm.startPrank(client);
        address proxy1 = p2pSsvProxyFactory.registerValidators{value: neededEth}(
            ssvPayload1,
            clientConfig,
            referrerConfig
        );
        vm.stopPrank();

        bytes[] memory _pubkeys = new bytes[](2);
        _pubkeys[0] = ssvPayload1.ssvValidators[1].pubkey;
        _pubkeys[1] = ssvPayload1.ssvValidators[3].pubkey;
        uint64[] memory _operatorIds = new uint64[](4);
        _operatorIds[0] = ssvPayload1.ssvOperators[0].id;
        _operatorIds[1] = ssvPayload1.ssvOperators[1].id;
        _operatorIds[2] = ssvPayload1.ssvOperators[2].id;
        _operatorIds[3] = ssvPayload1.ssvOperators[3].id;
        ISSVNetwork.Cluster[] memory _clusters = new ISSVNetwork.Cluster[](2);
        _clusters[0] = clusterAfter1stRegistation;
        _clusters[1] = clusterAfter1stRegistation;
        _clusters[1].validatorCount = 4;

        ISSVNetwork.Cluster memory clusterAfterRemoval = clusterAfter1stRegistation;
        clusterAfterRemoval.validatorCount = 3;

        vm.startPrank(owner);

        vm.expectEmit();
        emit ValidatorRemoved(
            proxy1,
            _operatorIds,
            ssvPayload1.ssvValidators[3].pubkey,
            clusterAfterRemoval
        );

        P2pSsvProxy(payable(proxy1)).removeValidators(_pubkeys, _operatorIds, _clusters);
        vm.stopPrank();

        console.log("test_removeValidators finsihed");
    }

    function test_liquidateAndReactivate() public {
        console.log("test_liquidateAndReactivate started");

        vm.startPrank(owner);
        p2pSsvProxyFactory.setSsvPerEthExchangeRateDividedByWei(SsvPerEthExchangeRateDividedByWei);
        vm.stopPrank();

        SsvPayload memory ssvPayload1 = getSsvPayload1();

        uint256 neededEth = p2pSsvProxyFactory.getNeededAmountOfEtherToCoverSsvFees(ssvPayload1.tokenAmount);

        vm.deal(client, 1000 ether);
        vm.startPrank(client);
        address proxy1 = p2pSsvProxyFactory.registerValidators{value: neededEth}(
            ssvPayload1,
            clientConfig,
            referrerConfig
        );
        vm.stopPrank();

        uint64[] memory _operatorIds = new uint64[](4);
        _operatorIds[0] = ssvPayload1.ssvOperators[0].id;
        _operatorIds[1] = ssvPayload1.ssvOperators[1].id;
        _operatorIds[2] = ssvPayload1.ssvOperators[2].id;
        _operatorIds[3] = ssvPayload1.ssvOperators[3].id;
        ISSVNetwork.Cluster[] memory _clusters = new ISSVNetwork.Cluster[](1);
        _clusters[0] = clusterAfter1stRegistation;

        ISSVNetworkCore.Cluster memory clusterAfterLiquidation = ISSVNetworkCore.Cluster({
            validatorCount: 5,
            networkFeeIndex: 0,
            index: 0,
            active: false,
            balance: 0
        });

        uint256 ssvTokenBalanceBefore = ssvToken.balanceOf(proxy1);

        vm.startPrank(owner);

        vm.expectEmit();
        emit ClusterLiquidated(
            proxy1,
            _operatorIds,
            clusterAfterLiquidation
        );

        P2pSsvProxy(payable(proxy1)).liquidate(_operatorIds, _clusters);
        vm.stopPrank();

        uint256 ssvTokenBalanceAfter = ssvToken.balanceOf(proxy1);

        assertEq(ssvTokenBalanceAfter - ssvTokenBalanceBefore, ssvPayload1.tokenAmount);

        uint256 ssvOwnerTokenBalanceBefore = ssvToken.balanceOf(owner);

        vm.expectRevert(abi.encodeWithSelector(OwnableBase__CallerNotOwner.selector, address(this), owner));
        P2pSsvProxy(payable(proxy1)).withdrawSSVTokens(owner, ssvPayload1.tokenAmount);

        vm.startPrank(owner);
        P2pSsvProxy(payable(proxy1)).withdrawSSVTokens(owner, ssvPayload1.tokenAmount);
        vm.stopPrank();

        uint256 ssvOwnerTokenBalanceAfter = ssvToken.balanceOf(owner);

        assertEq(ssvOwnerTokenBalanceAfter - ssvOwnerTokenBalanceBefore, ssvPayload1.tokenAmount);

        vm.startPrank(owner);

        ssvToken.transfer(proxy1, ssvPayload1.tokenAmount);
        _clusters[0] = clusterAfterLiquidation;

        vm.expectEmit();
        emit ClusterReactivated(
            proxy1,
            _operatorIds,
            clusterAfter1stRegistation
        );

        P2pSsvProxy(payable(proxy1)).reactivate(ssvPayload1.tokenAmount, _operatorIds, _clusters);
        vm.stopPrank();

        _clusters[0] = clusterAfter1stRegistation;
        deal(address(ssvToken), address(this), 50000 ether);

        ssvToken.transfer(proxy1, 42 ether);

        ISSVNetworkCore.Cluster memory clusterAfterDeposit = clusterAfter1stRegistation;
        clusterAfterDeposit.balance += 42 ether;

        vm.expectEmit();
        emit ClusterDeposited(
            proxy1,
            _operatorIds,
            42 ether,
            clusterAfterDeposit
        );

        P2pSsvProxy(payable(proxy1)).depositToSSV(42 ether, _operatorIds, _clusters);

        console.log("test_liquidateAndReactivate finsihed");
    }

    function test_registerValidators() public {
        console.log("test_registerValidators started");

        registerValidators();

        console.log("test_registerValidators finsihed");
    }

    function test_registerValidators_via_bulkRegisterValidators() public {
        console.log("test_registerValidators_via_bulkRegisterValidators started");

        registerValidators_via_bulkRegisterValidators();

        console.log("test_registerValidators_via_bulkRegisterValidators finsihed");
    }

    function test_DuplicateOperatorOwner() public {
        console.log("test_DuplicateOperatorOwner started");

        vm.startPrank(owner);
        p2pSsvProxyFactory.setSsvPerEthExchangeRateDividedByWei(SsvPerEthExchangeRateDividedByWei);
        vm.stopPrank();

        SsvPayload memory ssvPayload1 = getSsvPayload1WithDuplicateOperatorOwner();

        vm.deal(client, 1000 ether);
        vm.startPrank(client);

        uint256 neededEth = p2pSsvProxyFactory.getNeededAmountOfEtherToCoverSsvFees(ssvPayload1.tokenAmount);

        // SSV Network rejects duplicate operator IDs.
        vm.expectRevert(ISSVNetworkCore.OperatorsListNotUnique.selector);
        p2pSsvProxyFactory.registerValidators{value: neededEth}(
            ssvPayload1,
            clientConfig,
            referrerConfig
        );

        vm.stopPrank();

        console.log("test_DuplicateOperatorOwner finished");
    }

    function test_NewClientSelectors() public {
        console.log("test_NewClientSelectors started");

        registerValidators();

        bytes memory callData = abi.encodeCall(ISSVClusters.withdraw, (operatorIds, 42, clusterAfter1stRegistation));

        vm.startPrank(client);
        (bool success1, bytes memory data1) = proxyAddress.call(callData);
        vm.stopPrank();

        assertFalse(success1);
        assertEq(data1, abi.encodeWithSelector(P2pSsvProxy__SelectorNotAllowed.selector, client, ISSVClusters.withdraw.selector));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ISSVClusters.withdraw.selector;

        vm.startPrank(owner);
        p2pSsvProxyFactory.setAllowedSelectorsForClient(selectors);
        vm.stopPrank();

        vm.startPrank(client);
        (bool success2, bytes memory data2) = proxyAddress.call(callData);
        vm.stopPrank();

        assertTrue(success2);
        assertEq(data2, bytes(''));

        console.log("test_NewClientSelectors finished");
    }

    function test_NewOperatorSelectors() public {
        console.log("test_NewOperatorSelectors started");

        registerValidators();

        vm.startPrank(owner);
        p2pSsvProxyFactory.changeOperator(operator);
        vm.stopPrank();

        bytes memory callData = abi.encodeCall(ISSVClusters.withdraw, (operatorIds, 42, clusterAfter1stRegistation));

        vm.startPrank(operator);
        (bool success1, bytes memory data1) = proxyAddress.call(callData);
        vm.stopPrank();

        assertFalse(success1);
        assertEq(data1, abi.encodeWithSelector(P2pSsvProxy__SelectorNotAllowed.selector, operator, ISSVClusters.withdraw.selector));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ISSVClusters.withdraw.selector;

        vm.startPrank(owner);
        p2pSsvProxyFactory.setAllowedSelectorsForOperator(selectors);
        vm.stopPrank();

        vm.startPrank(operator);
        (bool success2, bytes memory data2) = proxyAddress.call(callData);
        vm.stopPrank();

        assertTrue(success2);
        assertEq(data2, bytes(''));

        vm.startPrank(owner);
        p2pSsvProxyFactory.removeAllowedSelectorsForOperator(selectors);
        vm.stopPrank();

        vm.startPrank(operator);
        (bool success3, bytes memory data3) = proxyAddress.call(callData);
        vm.stopPrank();

        assertFalse(success3);
        assertEq(data3, abi.encodeWithSelector(P2pSsvProxy__SelectorNotAllowed.selector, operator, ISSVClusters.withdraw.selector));

        console.log("test_NewOperatorSelectors finished");
    }

    function test_NewOwnerSelectors() public {
        console.log("test_NewOwnerSelectors started");

        registerValidators();

        bytes memory callData = abi.encodeCall(ISSVClusters.withdraw, (operatorIds, 42, clusterAfter1stRegistation));

        vm.startPrank(owner);
        (bool success1, bytes memory data1) = proxyAddress.call(callData);
        vm.stopPrank();

        assertTrue(success1);
        assertEq(data1, bytes(''));

        console.log("test_NewOwnerSelectors finished");
    }

    function test_WithdrawSsvTokens() public {
        console.log("test_WithdrawSsvTokens started");

        registerValidators();

        ISSVNetworkCore.Cluster[] memory clusters = new ISSVNetworkCore.Cluster[](1);
        clusters[0] = clusterAfter1stRegistation;

        uint256 proxyBalanceBefore = ssvToken.balanceOf(proxyAddress);

        uint256 tokenAmount = 42;

        vm.startPrank(owner);
        P2pSsvProxy(payable(proxyAddress)).withdrawFromSSV(tokenAmount, operatorIds, clusters);
        vm.stopPrank();

        uint256 proxyBalanceAfter = ssvToken.balanceOf(proxyAddress);

        assertEq(proxyBalanceAfter - proxyBalanceBefore, tokenAmount);

        uint256 ownerBalanceBefore = ssvToken.balanceOf(owner);

        vm.startPrank(owner);
        P2pSsvProxy(payable(proxyAddress)).withdrawSSVTokens(owner, tokenAmount);
        vm.stopPrank();

        uint256 ownerBalanceAfter = ssvToken.balanceOf(owner);

        assertEq(ownerBalanceAfter - ownerBalanceBefore, tokenAmount);

        console.log("test_WithdrawSsvTokens finished");
    }

    function test_DepositToSSV() public {
        console.log("test_DepositToSSV started");

        registerValidators();

        uint256 factoryBalanceBefore = ssvToken.balanceOf(address(p2pSsvProxyFactory));

        uint256 tokenAmount = 42;

        ISSVNetworkCore.Cluster memory clusterAfterDeposit = ISSVNetworkCore.Cluster({
            validatorCount: clusterAfter1stRegistation.validatorCount,
            networkFeeIndex: clusterAfter1stRegistation.networkFeeIndex,
            index: clusterAfter1stRegistation.index,
            active: true,
            balance: clusterAfter1stRegistation.balance + tokenAmount
        });

        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSelector(
            OwnableBase__CallerNotOwner.selector, operator, owner
        ));
        p2pSsvProxyFactory.depositToSSV(proxyAddress, tokenAmount, operatorIds, clusterAfter1stRegistation);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectEmit();
        emit ClusterDeposited(
            proxyAddress,
            operatorIds,
            tokenAmount,
            clusterAfterDeposit
        );
        p2pSsvProxyFactory.depositToSSV(proxyAddress, tokenAmount, operatorIds, clusterAfter1stRegistation);
        vm.stopPrank();

        uint256 factoryBalanceAfter = ssvToken.balanceOf(address(p2pSsvProxyFactory));
        assertEq(factoryBalanceBefore - factoryBalanceAfter, tokenAmount);

        console.log("test_DepositToSSV finished");
    }

    function test_bulkExitValidator() public {
        console.log("test_bulkExitValidator started");

        vm.startPrank(owner);
        p2pSsvProxyFactory.changeOperator(operator);
        vm.stopPrank();

        vm.startPrank(owner);
        p2pSsvProxyFactory.setSsvPerEthExchangeRateDividedByWei(SsvPerEthExchangeRateDividedByWei);
        vm.stopPrank();

        SsvPayload memory ssvPayload1 = getSsvPayload1();

        uint256 neededEth = p2pSsvProxyFactory.getNeededAmountOfEtherToCoverSsvFees(ssvPayload1.tokenAmount);

        vm.deal(client, 1000 ether);
        vm.startPrank(client);
        address proxy1 = p2pSsvProxyFactory.registerValidators{value: neededEth}(
            ssvPayload1,
            clientConfig,
            referrerConfig
        );
        vm.stopPrank();

        bytes[] memory _pubkeys = new bytes[](2);
        _pubkeys[0] = ssvPayload1.ssvValidators[1].pubkey;
        _pubkeys[1] = ssvPayload1.ssvValidators[3].pubkey;
        uint64[] memory _operatorIds = new uint64[](4);
        _operatorIds[0] = ssvPayload1.ssvOperators[0].id;
        _operatorIds[1] = ssvPayload1.ssvOperators[1].id;
        _operatorIds[2] = ssvPayload1.ssvOperators[2].id;
        _operatorIds[3] = ssvPayload1.ssvOperators[3].id;
        ISSVNetwork.Cluster[] memory _clusters = new ISSVNetwork.Cluster[](2);
        _clusters[0] = clusterAfter1stRegistation;
        _clusters[1] = clusterAfter1stRegistation;
        _clusters[1].validatorCount = 4;

        vm.startPrank(owner);

        vm.expectEmit();
        emit ValidatorExited(
            proxy1,
            _operatorIds,
            ssvPayload1.ssvValidators[1].pubkey
        );

        P2pSsvProxy(payable(proxy1)).bulkExitValidator(_pubkeys, _operatorIds);
        vm.stopPrank();

        vm.startPrank(operator);

        vm.expectEmit();
        emit ValidatorExited(
            proxy1,
            _operatorIds,
            ssvPayload1.ssvValidators[1].pubkey
        );

        P2pSsvProxy(payable(proxy1)).bulkExitValidator(_pubkeys, _operatorIds);
        vm.stopPrank();

        vm.startPrank(client);

        vm.expectEmit();
        emit ValidatorExited(
            proxy1,
            _operatorIds,
            ssvPayload1.ssvValidators[1].pubkey
        );

        vm.expectEmit();
        emit ValidatorExited(
            proxy1,
            _operatorIds,
            ssvPayload1.ssvValidators[3].pubkey
        );

        P2pSsvProxy(payable(proxy1)).bulkExitValidator(_pubkeys, _operatorIds);
        vm.stopPrank();

        vm.startPrank(nobody);

        vm.expectRevert(abi.encodeWithSelector(P2pSsvProxy__CallerNeitherOperatorNorOwnerNorClient.selector, nobody));

        P2pSsvProxy(payable(proxy1)).bulkExitValidator(_pubkeys, _operatorIds);
        vm.stopPrank();

        console.log("test_bulkExitValidator finsihed");
    }

    function test_withdrawAllSSVTokensToFactory() public {
        console.log("test_withdrawAllSSVTokensToFactory started");

        vm.startPrank(owner);
        p2pSsvProxyFactory.changeOperator(operator);
        vm.stopPrank();

        registerValidators();

        ISSVNetworkCore.Cluster[] memory clusters = new ISSVNetworkCore.Cluster[](1);
        clusters[0] = clusterAfter1stRegistation;

        uint256 proxyBalanceBefore = ssvToken.balanceOf(proxyAddress);

        uint256 tokenAmount = 42;

        vm.startPrank(owner);
        P2pSsvProxy(payable(proxyAddress)).withdrawFromSSV(tokenAmount, operatorIds, clusters);
        vm.stopPrank();

        uint256 proxyBalanceAfter = ssvToken.balanceOf(proxyAddress);

        assertEq(proxyBalanceAfter - proxyBalanceBefore, tokenAmount);

        vm.startPrank(nobody);

        vm.expectRevert(abi.encodeWithSelector(P2pSsvProxy__CallerNeitherOperatorNorOwner.selector, nobody, operator, owner));

        P2pSsvProxy(payable(proxyAddress)).withdrawAllSSVTokensToFactory();
        vm.stopPrank();

        uint256 factoryBalanceBefore = ssvToken.balanceOf(address(p2pSsvProxyFactory));

        vm.startPrank(owner);
        P2pSsvProxy(payable(proxyAddress)).withdrawAllSSVTokensToFactory();
        vm.stopPrank();

        uint256 factoryBalanceAfter = ssvToken.balanceOf(address(p2pSsvProxyFactory));

        assertEq(factoryBalanceAfter - factoryBalanceBefore, tokenAmount);

        console.log("test_withdrawAllSSVTokensToFactory finished");
    }

    function test_withdrawFromSSVToFactory() public {
        console.log("test_withdrawFromSSVToFactory started");

        vm.startPrank(owner);
        p2pSsvProxyFactory.changeOperator(operator);
        vm.stopPrank();

        registerValidators();

        ISSVNetworkCore.Cluster[] memory clusters = new ISSVNetworkCore.Cluster[](1);
        clusters[0] = clusterAfter1stRegistation;

        uint256 tokenAmount = 42;

        vm.startPrank(nobody);

        vm.expectRevert(abi.encodeWithSelector(P2pSsvProxy__CallerNeitherOperatorNorOwner.selector, nobody, operator, owner));

        P2pSsvProxy(payable(proxyAddress)).withdrawFromSSVToFactory(tokenAmount, operatorIds, clusters);
        vm.stopPrank();

        uint256 factoryBalanceBefore = ssvToken.balanceOf(address(p2pSsvProxyFactory));

        vm.startPrank(operator);
        P2pSsvProxy(payable(proxyAddress)).withdrawFromSSVToFactory(tokenAmount, operatorIds, clusters);
        vm.stopPrank();

        uint256 factoryBalanceAfter = ssvToken.balanceOf(address(p2pSsvProxyFactory));

        assertEq(factoryBalanceAfter - factoryBalanceBefore, tokenAmount);

        console.log("test_withdrawFromSSVToFactory finished");
    }

    function test_registerValidators_Whitelisted() public {
        console.log("test_registerValidators_Whitelisted started");

        address feeDistributorFactory_ = p2pSsvProxyFactory.getFeeDistributorFactory();
        address referenceFeeDistributor_ = p2pSsvProxyFactory.getReferenceFeeDistributor();
        address feeDistributorInstance_ = IFeeDistributorFactory(feeDistributorFactory_).predictFeeDistributorAddress(
            referenceFeeDistributor_,
            clientConfig,
            referrerConfig
        );
        address proxy_ = p2pSsvProxyFactory.predictP2pSsvProxyAddress(feeDistributorInstance_);

        for (uint256 i = 0; i < allowedSsvOperatorOwners.length; i++) {
            vm.startPrank(allowedSsvOperatorOwners[i]);

            ISSVOperators(ssvNetworkAddress).reduceOperatorFee(operatorIds[i], 0);
            ISSVOperators(ssvNetworkAddress).setOperatorWhitelist(operatorIds[i], proxy_);

            vm.stopPrank();
        }

        vm.startPrank(owner);
        p2pSsvProxyFactory.setSsvPerEthExchangeRateDividedByWei(SsvPerEthExchangeRateDividedByWei);
        vm.stopPrank();

        bytes[] memory pubKeys1 = new bytes[](5);
        bytes[] memory sharesData1 = new bytes[](5);
        for (uint256 i = 0; i < 5; i++) {
            pubKeys1[i] = validatorPubKeys[i];
            sharesData1[i] = validatorSharesData[i];
        }

        uint256 amount = 1.6e18;

        uint256 neededEth = p2pSsvProxyFactory.getNeededAmountOfEtherToCoverSsvFees(amount);

        vm.deal(nobody, 1000 ether);
        vm.startPrank(nobody);

        vm.expectRevert(abi.encodeWithSelector(P2pSsvProxyFactory__CallerNeitherOperatorNorOwnerNorClient.selector, nobody));
        p2pSsvProxyFactory.registerValidators{value: neededEth}(
            allowedSsvOperatorOwners,
            operatorIds,
            pubKeys1,
            sharesData1,
            amount,
            getCluster1(),

            clientConfig,
            referrerConfig
        );

        vm.stopPrank();

        vm.deal(client, 1000 ether);
        vm.startPrank(client);

        p2pSsvProxyFactory.registerValidators{value: neededEth}(
            allowedSsvOperatorOwners,
            operatorIds,
            pubKeys1,
            sharesData1,
            amount,
            getCluster1(),

            clientConfig,
            referrerConfig
        );

        vm.stopPrank();

        bool isWhitelisted = p2pSsvProxyFactory.isWhitelisted(proxy_, 42);
        assertTrue(isWhitelisted);

        console.log("test_registerValidators_Whitelisted finished");
    }

    function test_makeBeaconDepositsAndRegisterValidators() public {
        console.log("test_makeBeaconDepositsAndRegisterValidators started");

        uint256 nonDepositable = 13 ether;
        uint256 clientDeposit = 7 * 32 ether + nonDepositable;

        FeeRecipient memory clientConfig1 = FeeRecipient({
            recipient: payable(withdrawalCredentialsAddress),
            basisPoints: 9500
        });

        vm.startPrank(owner);
        p2pSsvProxyFactory.changeOperator(operator);
        vm.stopPrank();

        vm.deal(client, 100000 ether);
        vm.startPrank(client);
        (,address feeDistributorInstance,) = p2pSsvProxyFactory.addEth{value: clientDeposit}(
            withdrawalCredentials,
            MIN_ACTIVATION_BALANCE,
            clientConfig1,
            referrerConfig,
            ""
        );
        vm.stopPrank();

        DepositData memory depositData1 = getDepositData1();
        bytes[] memory pubKeys1 = new bytes[](5);
        bytes[] memory sharesData1 = new bytes[](5);
        for (uint256 i = 0; i < 5; i++) {
            pubKeys1[i] = validatorPubKeys[i];
            sharesData1[i] = validatorSharesData[i];
        }
        DepositData memory depositData2 = getDepositData2();
        bytes[] memory pubKeys2 = new bytes[](2);
        bytes[] memory sharesData2 = new bytes[](2);
        for (uint256 i = 0; i < 2; i++) {
            pubKeys2[i] = validatorPubKeys[i + 5];
            sharesData2[i] = validatorSharesData[i + 5];
        }

        vm.startPrank(operator);
        p2pSsvProxyFactory.makeBeaconDepositsAndRegisterValidators(
            withdrawalCredentials,
            MIN_ACTIVATION_BALANCE,
            feeDistributorInstance,

            depositData1,

            operatorIds,
            pubKeys1,
            sharesData1,
            getTokenAmount1(),
            getCluster1()
        );
        p2pSsvProxyFactory.makeBeaconDepositsAndRegisterValidators(
            withdrawalCredentials,
            MIN_ACTIVATION_BALANCE,
            feeDistributorInstance,

            depositData2,

            operatorIds,
            pubKeys2,
            sharesData2,
            getTokenAmount1(),
            clusterAfter1stRegistation
        );
        vm.stopPrank();

        vm.warp(block.timestamp + TIMEOUT + 1);

        uint256 balanceBefore = withdrawalCredentialsAddress.balance;

        vm.startPrank(withdrawalCredentialsAddress);
        p2pOrgUnlimitedEthDepositor.refund(
            withdrawalCredentials,
            MIN_ACTIVATION_BALANCE,
            feeDistributorInstance
        );
        vm.stopPrank();

        uint256 balanceAfter = withdrawalCredentialsAddress.balance;

        assertEqUint(balanceAfter - balanceBefore, nonDepositable);

        console.log("test_makeBeaconDepositsAndRegisterValidators finished");
    }

    function test_makeBeaconDepositsAndRegisterValidators_higherMEB() public {
        console.log("test_makeBeaconDepositsAndRegisterValidators_higherMEB started");

        uint96 depositAmount = 42 ether;
        uint256 nonDepositable = 13 ether;
        uint256 clientDeposit = 7 * depositAmount + nonDepositable;

        FeeRecipient memory clientConfig1 = FeeRecipient({
            recipient: payable(withdrawalCredentialsAddress),
            basisPoints: 9500
        });

        vm.startPrank(owner);
        p2pSsvProxyFactory.changeOperator(operator);
        vm.stopPrank();

        vm.deal(client, 100000 ether);
        vm.startPrank(client);
        vm.expectRevert(P2pOrgUnlimitedEthDepositor__Eip7251NotEnabledYet.selector);
        p2pSsvProxyFactory.addEth{value: clientDeposit}(
            withdrawalCredentials_02,
            depositAmount,
            clientConfig1,
            referrerConfig,
            ""
        );
        vm.stopPrank();

        vm.startPrank(owner);
        p2pOrgUnlimitedEthDepositor.enableEip7251();
        vm.stopPrank();

        vm.startPrank(client);
        p2pSsvProxyFactory.addEth{value: clientDeposit}(
            withdrawalCredentials_02,
            depositAmount,
            clientConfig1,
            referrerConfig,
            ""
        );
        vm.stopPrank();

        address feeDistributorInstance = feeDistributorFactory.predictFeeDistributorAddress(referenceFeeDistributor, clientConfig1, referrerConfig);
        DepositData memory depositData1 = getDepositData1_42eth();
        bytes[] memory pubKeys1 = new bytes[](5);
        bytes[] memory sharesData1 = new bytes[](5);
        for (uint256 i = 0; i < 5; i++) {
            pubKeys1[i] = validatorPubKeys_42eth[i];
            sharesData1[i] = validatorSharesData[i];
        }
        DepositData memory depositData2 = getDepositData2_42eth();
        bytes[] memory pubKeys2 = new bytes[](2);
        bytes[] memory sharesData2 = new bytes[](2);
        for (uint256 i = 0; i < 2; i++) {
            pubKeys2[i] = validatorPubKeys_42eth[i + 5];
            sharesData2[i] = validatorSharesData[i + 5];
        }

        vm.startPrank(operator);
        p2pSsvProxyFactory.makeBeaconDepositsAndRegisterValidators(
            withdrawalCredentials_02,
            depositAmount,
            feeDistributorInstance,

            depositData1,

            operatorIds,
            pubKeys1,
            sharesData1,
            getTokenAmount1(),
            getCluster1()
        );
        p2pSsvProxyFactory.makeBeaconDepositsAndRegisterValidators(
            withdrawalCredentials_02,
            depositAmount,
            feeDistributorInstance,

            depositData2,

            operatorIds,
            pubKeys2,
            sharesData2,
            getTokenAmount1(),
            clusterAfter1stRegistation
        );
        vm.stopPrank();

        vm.warp(block.timestamp + TIMEOUT + 1);

        uint256 balanceBefore = withdrawalCredentialsAddress.balance;

        vm.startPrank(withdrawalCredentialsAddress);
        p2pOrgUnlimitedEthDepositor.refund(
            withdrawalCredentials_02,
            depositAmount,
            feeDistributorInstance
        );
        vm.stopPrank();

        uint256 balanceAfter = withdrawalCredentialsAddress.balance;

        assertEqUint(balanceAfter - balanceBefore, nonDepositable);

        console.log("test_makeBeaconDepositsAndRegisterValidators_higherMEB finished");
    }

    function test_callAnyContract() public {
        console.log("test_callAnyContract started");

        vm.startPrank(owner);
        P2pSsvProxy p2pSsvProxyInstance = P2pSsvProxy(payable(p2pSsvProxyFactory.createP2pSsvProxy(referenceFeeDistributor)));
        vm.stopPrank();

        deal(address(ssvToken), address(p2pSsvProxyInstance), 50 ether);
        uint256 amount = 42 ether;

        address ssvTokenAddress = address(ssvToken);
        bytes memory contractCalldata = abi.encodeWithSelector(
            IERC20.transfer.selector,
            owner,
            amount
        );

        vm.startPrank(nobody);
        vm.expectRevert(abi.encodeWithSelector(
            OwnableBase__CallerNotOwner.selector, nobody, owner
        ));
        p2pSsvProxyInstance.callAnyContract(ssvTokenAddress, contractCalldata);
        vm.stopPrank();

        uint256 ssvTokenBalanceBefore = ssvToken.balanceOf(owner);

        vm.startPrank(owner);
        p2pSsvProxyInstance.callAnyContract(ssvTokenAddress, contractCalldata);
        vm.stopPrank();

        uint256 ssvTokenBalanceAfter = ssvToken.balanceOf(owner);

        assertEq(ssvTokenBalanceAfter - ssvTokenBalanceBefore, amount);

        console.log("test_callAnyContract finished");
    }
}
