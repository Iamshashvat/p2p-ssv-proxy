// SPDX-FileCopyrightText: 2024 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../@openzeppelin/contracts/proxy/Clones.sol";
import "../@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "../@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "../proxy/P2pBeaconProxy.sol";

import "../interfaces/p2p/IFeeDistributor.sol";
import "../interfaces/p2p/IFeeDistributorFactory.sol";
import "../interfaces/p2p/IP2pOrgUnlimitedEthDepositor.sol";
import "../interfaces/ssv/ISSVViews.sol";
import "../interfaces/ssv/ISSVNetworkEth.sol";

import "../assetRecovering/OwnableAssetRecoverer.sol";
import "../access/OwnableWithOperator.sol";
import "../p2pSsvProxy/P2pSsvProxy.sol";
import "../structs/P2pStructs.sol";
import "./IP2pSsvProxyFactory.sol";

/// @notice Passed address is not a valid P2pOrgUnlimitedEthDepositor
/// @param _passedAddress Passed address
error P2pSsvProxyFactory__NotP2pOrgUnlimitedEthDepositor(address _passedAddress);

/// @notice Passed address is not a valid FeeDistributorFactory
/// @param _passedAddress Passed address
error P2pSsvProxyFactory__NotFeeDistributorFactory(address _passedAddress);

/// @notice Passed address is not a valid FeeDistributor
/// @param _passedAddress Passed address
error P2pSsvProxyFactory__NotFeeDistributor(address _passedAddress);

/// @notice Passed address is not a valid P2pSsvProxy
/// @param _passedAddress Passed address
error P2pSsvProxyFactory__NotP2pSsvProxy(address _passedAddress);

/// @notice Caller in not an allowed SSV operator owner
/// @param _caller Caller address
error P2pSsvProxyFactory__NotAllowedSsvOperatorOwner(address _caller);

/// @notice Cannot add an already existing SSV operator owner address
/// @param _ssvOperatorOwner an already existing SSV operator owner address
error P2pSsvProxyFactory__SsvOperatorOwnerAlreadyExists(address _ssvOperatorOwner);

/// @notice Cannot remove a nonexisting SSV operator owner address
/// @param _ssvOperatorOwner a nonexisting SSV operator owner address
error P2pSsvProxyFactory__SsvOperatorOwnerDoesNotExist(address _ssvOperatorOwner);

/// @notice This SSV operator ID is not allowed. Check both the operator owner address and the ID for being allowed
/// @param _ssvOperatorOwner operator owner address
/// @param _ssvOperatorId operator ID
error P2pSsvProxyFactory__SsvOperatorNotAllowed(address _ssvOperatorOwner, uint64 _ssvOperatorId);

/// @notice SsvOperatorOwners and SsvOperatorIds arrays must have the same lengths
/// @param _ssvOperatorOwnersLength SsvOperatorOwners arrray Length
/// @param _ssvOperatorIdsLength SsvOperatorIds arrray Length
error P2pSsvProxyFactory__SsvOperatorOwnersAndIdsMustHaveTheSameLength(uint256 _ssvOperatorOwnersLength, uint256 _ssvOperatorIdsLength);

/// @notice All the SSV operator IDs must be unique
/// @param _ssvOperatorId duplicated operator ID
error P2pSsvProxyFactory__DuplicateIdsNotAllowed(uint64 _ssvOperatorId);

/// @notice ETH value passed with the transaction must be equal to the needed value
/// @param _needed needed ETH value
/// @param _paid actually sent ETH value
error P2pSsvProxyFactory__NotEnoughEtherPaidToCoverSsvFees(uint256 _needed, uint256 _paid);

/// @dev We assume, SSV won't either drop 7539x or soar higher than 100 ETH.
/// If it does, this contract won't be operational and another contract will have to be deployed.
error P2pSsvProxyFactory__SsvPerEthExchangeRateDividedByWeiOutOfRange();

/// @notice Maximum amount of SSV tokens per validator must be >= 10^12 and <= 10^24
error P2pSsvProxyFactory__MaxSsvTokenAmountPerValidatorOutOfRange();

/// @notice SSV per ETH exchange rate has not been set. Cannot register validators without it.
error P2pSsvProxyFactory__SsvPerEthExchangeRateDividedByWeiNotSet();

/// @notice Maximum amount of SSV tokens per validator has not been set. Cannot do depositEthAndRegisterValidators without it.
error P2pSsvProxyFactory__MaxSsvTokenAmountPerValidatorNotSet();

/// @notice Cannot use token amount per validator larger than Maximum amount of SSV tokens per validator.
error P2pSsvProxyFactory__MaxSsvTokenAmountPerValidatorExceeded();

/// @notice This SSV operator ID does not belong to the passed owner
/// @param _operatorId SSV operator ID
/// @param _passedOwner passed address for SSV operator owner
/// @param _actualOwner actual SSV operator owner address
error P2pSsvProxyFactory__SsvOperatorIdDoesNotBelongToOwner(
    uint64 _operatorId,
    address _passedOwner,
    address _actualOwner
);

/// @notice Should pass at least 1 selector
error P2pSsvProxyFactory__CannotSetZeroSelectors();

/// @notice Should pass at least 1 selector
error P2pSsvProxyFactory__CannotRemoveZeroSelectors();

/// @notice Should pass at least 1 SSV operator owner
error P2pSsvProxyFactory__CannotSetZeroAllowedSsvOperatorOwners();

/// @notice Should pass at least 1 SSV operator owner
error P2pSsvProxyFactory__CannotRemoveZeroAllowedSsvOperatorOwners();

/// @notice P2pSsvProxy should have already been deployed for the given FeeDistributor instance
/// @param _feeDistributorInstance client FeeDistributor instance
error P2pSsvProxyFactory__P2pSsvProxyDoesNotExist(
    address _feeDistributorInstance
);

/// @notice The caller was neither operator nor owner nor client
/// @param _caller address of the caller
error P2pSsvProxyFactory__CallerNeitherOperatorNorOwnerNorClient(address _caller);

/// @notice msg.value does not equal beacon collateral plus SSV ETH funding
/// @param _expected expected msg.value
/// @param _actual actual msg.value
error P2pSsvProxyFactory__InvalidEthValue(uint256 _expected, uint256 _actual);

/// @notice The given address is not a deployed P2pSsvProxy
/// @param _address the address that is not a deployed P2pSsvProxy
error P2pSsvProxyFactory__NotDeployedP2pSsvProxy(address _address);

/// @notice Beacon has not been set
error P2pSsvProxyFactory__BeaconNotSet();

/// @notice This function has been deprecated and is no longer operational
error P2pSsvProxyFactory__DeprecatedFunction();

/// @title Entry point for SSV validator registration
/// @dev Deploys P2pSsvProxy instances
contract P2pSsvProxyFactory is OwnableAssetRecoverer, OwnableWithOperator, ERC165, IP2pSsvProxyFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice SSVNetwork address
    ISSVNetwork private immutable i_ssvNetwork;

    /// @notice P2pOrgUnlimitedEthDepositor
    IP2pOrgUnlimitedEthDepositor private immutable i_p2pOrgUnlimitedEthDepositor;

    /// @notice FeeDistributorFactory
    IFeeDistributorFactory private immutable i_feeDistributorFactory;

    /// @notice SSV ERC-20 token
    IERC20 private immutable i_ssvToken;

    /// @notice SSVNetworkViews
    ISSVViews private immutable i_ssvViews;

    /// @notice Template set by P2P to be used for new FeeDistributor instances.
    /// @dev Can be changed by P2P at any time. It will only affect the new clusters.
    /// Existing clusters will keep their existing FeeDistributor instance.
    address private s_referenceFeeDistributor;

    /// @notice Template set by P2P to be used for new P2pSsvProxy instances.
    /// @dev Can be changed by P2P at any time. It will only affect the new clusters.
    /// Existing clusters will keep their existing P2pSsvProxy instance.
    P2pSsvProxy private s_referenceP2pSsvProxy;

    /// @notice a set of addresses of SSV operator owners (both P2P and partners).
    /// @dev Only P2P can add or remove addresses from the set.
    EnumerableSet.AddressSet private s_allowedSsvOperatorOwners;

    /// @notice a mapping of (operator owner address → SSV operator IDs list).
    /// @dev The list of allowed SSV operator IDs for each address is limited to 24 IDs.
    /// The operator owner can update only their list. P2P can update lists of any owners.
    mapping(address => uint64[MAX_ALLOWED_SSV_OPERATOR_IDS]) private s_allowedSsvOperatorIds;

    /// @notice a mapping of (client address → a list of addresses of the deployed client P2pSsvProxy instances).
    /// @dev Updated automatically during P2pSsvProxy instance deployment.
    mapping(address => address[]) private s_allClientP2pSsvProxies;

    /// @notice a mapping of (P2pSsvProxy instance address → hasBeenDeployed flag).
    /// @dev Updated automatically during P2pSsvProxy instance deployment.
    mapping(address => bool) private s_deployedP2pSsvProxies;

    /// @notice a list of all ever deployed client P2pSsvProxy instances.
    /// @dev Updated automatically during P2pSsvProxy instance deployment.
    address[] private s_allP2pSsvProxies;

    /// @notice a mapping to check if a certain selector (function signature) is allowed for clients to call on SSVNetwork via P2pSsvProxy.
    mapping(bytes4 => bool) private s_clientSelectors;

    /// @notice a mapping to check if a certain selector (function signature) is allowed for a P2P operator to call on SSVNetwork via P2pSsvProxy.
    mapping(bytes4 => bool) private s_operatorSelectors;

    /// @notice Exchange rate between SSV and ETH set by P2P.
    /// @dev (If 1 SSV = 0.007539 ETH, it should be 0.007539 * 10^18 = 7539000000000000).
    /// Only used during validator registration without ETH deposits to cover SSV token costs with client ETH.
    /// SSV tokens exchanged with this rate cannot be withdrawn by the client.
    /// P2P is willing to tolarate potential discrepancies with the market exchange rate for the sake of simplicity.
    /// The client agrees to this rate when calls `registerValidators` function.
    uint112 private s_ssvPerEthExchangeRateDividedByWei;

    /// @notice Maximum amount of SSV tokens per validator that is allowed for client to deposit during `depositEthAndRegisterValidators`
    uint112 private s_maxSsvTokenAmountPerValidator;

    /// @notice UpgradeableBeacon address for new beacon-based proxy deployments.
    /// @dev When set (non-zero), new proxy instances are deployed as P2pBeaconProxy via CREATE2.
    /// When unset (zero), the legacy clone path is used.
    address private s_beacon;

    /// @notice If the given _ssvOperatorOwner is not allowed, revert
    modifier onlyAllowedSsvOperatorOwner(address _ssvOperatorOwner) {
        bool isAllowed = s_allowedSsvOperatorOwners.contains(_ssvOperatorOwner);
        if (!isAllowed) {
            revert P2pSsvProxyFactory__NotAllowedSsvOperatorOwner(_ssvOperatorOwner);
        }
        _;
    }

    /// @notice If the msg.sender is not an allowed SSV operator owner, revert
    modifier onlySsvOperatorOwner() {
        bool isAllowed = s_allowedSsvOperatorOwners.contains(msg.sender);
        if (!isAllowed) {
            revert P2pSsvProxyFactory__NotAllowedSsvOperatorOwner(msg.sender);
        }
        _;
    }

    /// @notice Revert if one of the operator IDs is not allowed
    modifier onlyAllowedOperators(SsvOperator[] calldata _operators) {
        uint256 operatorCount = _operators.length;
        for (uint256 i = 0; i < operatorCount; ++i) {
            address currentOperatorOwner = _operators[i].owner;

            bool isAllowed;
            for (uint256 j = 0; j < MAX_ALLOWED_SSV_OPERATOR_IDS; ++j) {
                if (s_allowedSsvOperatorIds[currentOperatorOwner][j] == _operators[i].id) {
                    isAllowed = true;
                    break;
                }
            }
            if (!isAllowed) {
                revert P2pSsvProxyFactory__SsvOperatorNotAllowed(currentOperatorOwner, _operators[i].id);
            }
        }

        _;
    }

    /// @notice Revert if one of the operator IDs is not allowed
    modifier onlyAllowedOperatorsByOwner(address[] calldata _operatorOwners, uint64[] calldata _operatorIds) {
        uint256 ownersCount = _operatorOwners.length;
        uint256 idsCount = _operatorIds.length;
        if (ownersCount != idsCount) {
            revert P2pSsvProxyFactory__SsvOperatorOwnersAndIdsMustHaveTheSameLength(ownersCount, idsCount);
        }

        for (uint256 i = 0; i < ownersCount; ++i) {
            address currentOperatorOwner = _operatorOwners[i];

            bool isAllowed;
            for (uint256 j = 0; j < MAX_ALLOWED_SSV_OPERATOR_IDS; ++j) {
                if (s_allowedSsvOperatorIds[currentOperatorOwner][j] == _operatorIds[i]) {
                    isAllowed = true;
                    break;
                }
            }
            if (!isAllowed) {
                revert P2pSsvProxyFactory__SsvOperatorNotAllowed(currentOperatorOwner, _operatorIds[i]);
            }
        }

        _;
    }

    /// @notice If caller is neither operator nor owner nor client, nor _referrer, revert
    modifier onlyOperatorOrOwnerOrClientOrReferrer(address _client, address _referrer) {
        if (_client != msg.sender && _referrer != msg.sender) {
            address operator_ = operator();
            address owner_ = owner();

            if (operator_ != msg.sender && owner_ != msg.sender) {
                revert P2pSsvProxyFactory__CallerNeitherOperatorNorOwnerNorClient(msg.sender);
            }
        }
        _;
    }

    /// @dev Set values that are constant, common for all clients, known at the initial deploy time.
    /// @param _p2pOrgUnlimitedEthDepositor P2pOrgUnlimitedEthDepositor address
    /// @param _feeDistributorFactory FeeDistributorFactory address
    /// @param _referenceFeeDistributor reference FeeDistributor address
    constructor(
        address _p2pOrgUnlimitedEthDepositor,
        address _feeDistributorFactory,
        address _referenceFeeDistributor
    ) {
        if (!ERC165Checker.supportsInterface(_p2pOrgUnlimitedEthDepositor, type(IP2pOrgUnlimitedEthDepositor).interfaceId)) {
            revert P2pSsvProxyFactory__NotP2pOrgUnlimitedEthDepositor(_p2pOrgUnlimitedEthDepositor);
        }
        i_p2pOrgUnlimitedEthDepositor = IP2pOrgUnlimitedEthDepositor(_p2pOrgUnlimitedEthDepositor);

        if (!ERC165Checker.supportsInterface(_feeDistributorFactory, type(IFeeDistributorFactory).interfaceId)) {
            revert P2pSsvProxyFactory__NotFeeDistributorFactory(_feeDistributorFactory);
        }
        i_feeDistributorFactory = IFeeDistributorFactory(_feeDistributorFactory);

        if (!ERC165Checker.supportsInterface(_referenceFeeDistributor, type(IFeeDistributor).interfaceId)) {
            revert P2pSsvProxyFactory__NotFeeDistributor(_referenceFeeDistributor);
        }

        s_referenceFeeDistributor = _referenceFeeDistributor;
        emit P2pSsvProxyFactory__ReferenceFeeDistributorSet(_referenceFeeDistributor);

        i_ssvToken = (block.chainid == 1)
            ? IERC20(0x9D65fF81a3c488d585bBfb0Bfe3c7707c7917f54)    
            : IERC20(0x9F5d4Ec84fC4785788aB44F9de973cF34F7A038e);         // hoodi

        i_ssvViews = (block.chainid == 1)
            ? ISSVViews(0xafE830B6Ee262ba11cce5F32fDCd760FFE6a66e4)
            : ISSVViews(0x5AdDb3f1529C5ec70D77400499eE4bbF328368fe);       // hoodi

        i_ssvNetwork = (block.chainid == 1)
            ? ISSVNetwork(0xDD9BC35aE942eF0cFa76930954a156B3fF30a4E1)
            : ISSVNetwork(0x58410Bef803ECd7E63B23664C586A6DB72DAf59c);     // hoodi

        i_ssvToken.approve(address(i_ssvNetwork), type(uint256).max);
    }

    receive() external payable {}

    /// @inheritdoc IP2pSsvProxyFactory
    function setSsvPerEthExchangeRateDividedByWei(uint112 _ssvPerEthExchangeRateDividedByWei) external onlyOwner {
        if (_ssvPerEthExchangeRateDividedByWei < 10 ** 12 || _ssvPerEthExchangeRateDividedByWei > 10 ** 20) {
            revert P2pSsvProxyFactory__SsvPerEthExchangeRateDividedByWeiOutOfRange();
        }

        s_ssvPerEthExchangeRateDividedByWei = _ssvPerEthExchangeRateDividedByWei;
        emit P2pSsvProxyFactory__SsvPerEthExchangeRateDividedByWeiSet(_ssvPerEthExchangeRateDividedByWei);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function setMaxSsvTokenAmountPerValidator(uint112 _maxSsvTokenAmountPerValidator) external onlyOwner {
        if (_maxSsvTokenAmountPerValidator < 10 ** 12 || _maxSsvTokenAmountPerValidator > 10 ** 24) {
            revert P2pSsvProxyFactory__MaxSsvTokenAmountPerValidatorOutOfRange();
        }

        s_maxSsvTokenAmountPerValidator = _maxSsvTokenAmountPerValidator;
        emit P2pSsvProxyFactory__MaxSsvTokenAmountPerValidatorSet(_maxSsvTokenAmountPerValidator);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function setReferenceP2pSsvProxy(address _referenceP2pSsvProxy) external onlyOwner {
        if (!ERC165Checker.supportsInterface(_referenceP2pSsvProxy, type(IP2pSsvProxy).interfaceId)) {
            revert P2pSsvProxyFactory__NotP2pSsvProxy(_referenceP2pSsvProxy);
        }

        s_referenceP2pSsvProxy = P2pSsvProxy(payable(_referenceP2pSsvProxy));
        emit P2pSsvProxyFactory__ReferenceP2pSsvProxySet(_referenceP2pSsvProxy);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function setAllowedSelectorsForClient(bytes4[] calldata _selectors) external onlyOwner {
        uint256 count = _selectors.length;

        if (count == 0) {
            revert P2pSsvProxyFactory__CannotSetZeroSelectors();
        }

        for (uint256 i = 0; i < count; ++i) {
            s_clientSelectors[_selectors[i]] = true;
        }

        emit P2pSsvProxyFactory__AllowedSelectorsForClientSet(_selectors);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function removeAllowedSelectorsForClient(bytes4[] calldata _selectors) external onlyOwner {
        uint256 count = _selectors.length;

        if (count == 0) {
            revert P2pSsvProxyFactory__CannotRemoveZeroSelectors();
        }

        for (uint256 i = 0; i < count; ++i) {
            s_clientSelectors[_selectors[i]] = false;
        }

        emit P2pSsvProxyFactory__AllowedSelectorsForClientRemoved(_selectors);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function setAllowedSelectorsForOperator(bytes4[] calldata _selectors) external onlyOwner {
        uint256 count = _selectors.length;

        if (count == 0) {
            revert P2pSsvProxyFactory__CannotSetZeroSelectors();
        }

        for (uint256 i = 0; i < count; ++i) {
            s_operatorSelectors[_selectors[i]] = true;
        }

        emit P2pSsvProxyFactory__AllowedSelectorsForOperatorSet(_selectors);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function removeAllowedSelectorsForOperator(bytes4[] calldata _selectors) external onlyOwner {
        uint256 count = _selectors.length;

        if (count == 0) {
            revert P2pSsvProxyFactory__CannotRemoveZeroSelectors();
        }

        for (uint256 i = 0; i < count; ++i) {
            s_operatorSelectors[_selectors[i]] = false;
        }

        emit P2pSsvProxyFactory__AllowedSelectorsForOperatorRemoved(_selectors);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function setReferenceFeeDistributor(
        address _referenceFeeDistributor
    ) external onlyOperatorOrOwner {
        if (!ERC165Checker.supportsInterface(_referenceFeeDistributor, type(IFeeDistributor).interfaceId)) {
            revert P2pSsvProxyFactory__NotFeeDistributor(_referenceFeeDistributor);
        }

        s_referenceFeeDistributor = _referenceFeeDistributor;
        emit P2pSsvProxyFactory__ReferenceFeeDistributorSet(_referenceFeeDistributor);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function setAllowedSsvOperatorOwners(
        address[] calldata _allowedSsvOperatorOwners
    ) external onlyOperatorOrOwner {
        uint256 count = _allowedSsvOperatorOwners.length;

        if (count == 0) {
            revert P2pSsvProxyFactory__CannotSetZeroAllowedSsvOperatorOwners();
        }

        for (uint256 i = 0; i < count; ++i) {
            address allowedSsvOperatorOwner = _allowedSsvOperatorOwners[i];

            if (!s_allowedSsvOperatorOwners.add(allowedSsvOperatorOwner)) {
                revert P2pSsvProxyFactory__SsvOperatorOwnerAlreadyExists(allowedSsvOperatorOwner);
            }
        }

        emit P2pSsvProxyFactory__AllowedSsvOperatorOwnersSet(_allowedSsvOperatorOwners);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function removeAllowedSsvOperatorOwners(
        address[] calldata _allowedSsvOperatorOwnersToRemove
    ) external onlyOperatorOrOwner {
        uint256 count = _allowedSsvOperatorOwnersToRemove.length;

        if (count == 0) {
            revert P2pSsvProxyFactory__CannotRemoveZeroAllowedSsvOperatorOwners();
        }

        for (uint256 i = 0; i < count; ++i) {
            address allowedSsvOperatorOwnersToRemove = _allowedSsvOperatorOwnersToRemove[i];

            if (!s_allowedSsvOperatorOwners.remove(allowedSsvOperatorOwnersToRemove)) {
                revert P2pSsvProxyFactory__SsvOperatorOwnerDoesNotExist(allowedSsvOperatorOwnersToRemove);
            }
        }

        emit P2pSsvProxyFactory__AllowedSsvOperatorOwnersRemoved(_allowedSsvOperatorOwnersToRemove);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function setSsvOperatorIds(
        uint64[MAX_ALLOWED_SSV_OPERATOR_IDS] calldata _operatorIds
    ) external onlySsvOperatorOwner {
        _setSsvOperatorIds(_operatorIds, msg.sender);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function setSsvOperatorIds(
        uint64[MAX_ALLOWED_SSV_OPERATOR_IDS] calldata _operatorIds,
        address _ssvOperatorOwner
    ) external onlyOperatorOrOwner onlyAllowedSsvOperatorOwner(_ssvOperatorOwner) {
        _setSsvOperatorIds(_operatorIds, _ssvOperatorOwner);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function clearSsvOperatorIds() external onlySsvOperatorOwner {
        _clearSsvOperatorIds(msg.sender);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function clearSsvOperatorIds(
        address _ssvOperatorOwner
    ) external onlyOperatorOrOwner {
        _clearSsvOperatorIds(_ssvOperatorOwner);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function predictP2pSsvProxyAddress(
        address _feeDistributorInstance
    ) public view returns (address) {
        return Clones.predictDeterministicAddress(
            address(s_referenceP2pSsvProxy),
            bytes32(bytes20(_feeDistributorInstance))
        );
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function predictP2pSsvProxyAddress(
        address _referenceFeeDistributor,
        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    ) external view returns (address) {
        address feeDistributorInstance = i_feeDistributorFactory.predictFeeDistributorAddress(
            _referenceFeeDistributor,
            _clientConfig,
            _referrerConfig
        );
        return predictP2pSsvProxyAddress(feeDistributorInstance);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function predictP2pSsvProxyAddress(
        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    ) external view returns (address) {
        address feeDistributorInstance = i_feeDistributorFactory.predictFeeDistributorAddress(
            s_referenceFeeDistributor,
            _clientConfig,
            _referrerConfig
        );
        return predictP2pSsvProxyAddress(feeDistributorInstance);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function predictP2pSsvProxyAddress(
        FeeRecipient calldata _clientConfig
    ) external view returns (address) {
        address feeDistributorInstance = i_feeDistributorFactory.predictFeeDistributorAddress(
            s_referenceFeeDistributor,
            _clientConfig,
            FeeRecipient({
                recipient: payable(address(0)),
                basisPoints: 0
            })
        );
        return predictP2pSsvProxyAddress(feeDistributorInstance);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function createP2pSsvProxy(
        address _feeDistributorInstance
    ) external onlyOperatorOrOwner returns(address p2pSsvProxyInstance) {
        p2pSsvProxyInstance = _createP2pSsvProxyAuto(_feeDistributorInstance);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function depositEthAndRegisterValidators(
        DepositData calldata,
        address,

        SsvPayload calldata,

        FeeRecipient calldata,
        FeeRecipient calldata
    )
    external
    payable
    returns (address) {
        revert P2pSsvProxyFactory__DeprecatedFunction();
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function depositEthAndRegisterValidators(
        DepositData calldata,
        address,

        address[] calldata,
        uint64[] calldata,
        bytes[] calldata,
        bytes[] calldata,
        uint256,
        ISSVNetwork.Cluster calldata,

        FeeRecipient calldata,
        FeeRecipient calldata
    )
    external
    payable
    returns (address) {
        revert P2pSsvProxyFactory__DeprecatedFunction();
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function addEth(
        bytes32 _eth2WithdrawalCredentials,
        uint96 _ethAmountPerValidatorInWei,
        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig,
        bytes calldata _extraData
    )
    external
    payable
    returns (bytes32, address, address) {
        (bytes32 depositId, address feeDistributorInstance) = i_p2pOrgUnlimitedEthDepositor.addEth{value: msg.value}(
            _eth2WithdrawalCredentials,
            _ethAmountPerValidatorInWei,
            s_referenceFeeDistributor,
            _clientConfig,
            _referrerConfig,
            _extraData
        );

        address p2pSsvProxy = _createP2pSsvProxyAuto(feeDistributorInstance);

        emit P2pSsvProxyFactory__EthForSsvStakingDeposited(
            depositId,
            msg.sender,
            p2pSsvProxy,
            feeDistributorInstance,
            msg.value
        );

        return (depositId, feeDistributorInstance, p2pSsvProxy);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function registerValidators(
        SsvPayload calldata _ssvPayload,
        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    )
    external
    payable
    onlyOperatorOrOwnerOrClientOrReferrer(
        _clientConfig.recipient,
        _referrerConfig.recipient
    )
    returns (address p2pSsvProxy) {
        _checkEthValue(_ssvPayload.tokenAmount);

        p2pSsvProxy = _registerValidators(_ssvPayload, _clientConfig, _referrerConfig);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function registerValidators(
        address[] calldata _operatorOwners,
        uint64[] calldata _operatorIds,
        bytes[] calldata _publicKeys,
        bytes[] calldata _sharesData,
        uint256 _amount,
        ISSVNetwork.Cluster calldata _cluster,

        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    )
    external
    payable
    onlyOperatorOrOwnerOrClientOrReferrer(
        _clientConfig.recipient,
        _referrerConfig.recipient
    )
    returns (address p2pSsvProxy) {
        _checkEthValue(_amount);

        p2pSsvProxy = _registerValidators(
            _operatorOwners,
            _operatorIds,
            _publicKeys,
            _sharesData,
            _amount,
            _cluster,
            _clientConfig,
            _referrerConfig
        );
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function makeBeaconDepositsAndRegisterValidators(
        bytes32 _eth2WithdrawalCredentials,
        uint96 _ethAmountPerValidatorInWei,
        address _feeDistributorInstance,
        DepositData calldata _depositData,
        uint64[] calldata _operatorIds,
        bytes[] calldata _publicKeys,
        bytes[] calldata _sharesData,
        uint256 _amount,
        ISSVNetwork.Cluster calldata _cluster
    ) external onlyOperatorOrOwner returns (address p2pSsvProxy) {
        p2pSsvProxy = predictP2pSsvProxyAddress(_feeDistributorInstance);
        if (p2pSsvProxy.code.length == 0) {
            revert P2pSsvProxyFactory__P2pSsvProxyDoesNotExist(_feeDistributorInstance);
        }

        uint256 validatorCount = _publicKeys.length;
        _checkTokenAmount(_amount, validatorCount);

        // Lengths matching check for public keys, signatures, and deposit data roots
        // is done by P2pOrgUnlimitedEthDepositor

        i_p2pOrgUnlimitedEthDepositor.makeBeaconDeposit(
            _eth2WithdrawalCredentials,
            _ethAmountPerValidatorInWei,
            _feeDistributorInstance,
            _publicKeys,
            _depositData.signatures,
            _depositData.depositDataRoots
        );

        i_ssvToken.transfer(address(p2pSsvProxy), _amount);

        P2pSsvProxy(payable(p2pSsvProxy)).bulkRegisterValidators(
            _publicKeys,
            _operatorIds,
            _sharesData,
            _amount,
            _cluster
        );

        emit P2pSsvProxyFactory__RegistrationCompleted(p2pSsvProxy);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function depositToSSV(
        address _clusterOwner,
        uint256 _tokenAmount,
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster calldata _cluster
    ) external onlyOwner {
        i_ssvNetwork.deposit(_clusterOwner, _operatorIds, _tokenAmount, _cluster);
    }

    /**********************************/
    /* ETH-Native Methods (V2)        */
    /**********************************/

    /// @inheritdoc IP2pSsvProxyFactory
    function registerValidatorsEth(
        address[] calldata _operatorOwners,
        uint64[] calldata _operatorIds,
        bytes[] calldata _publicKeys,
        bytes[] calldata _sharesData,
        ISSVNetwork.Cluster calldata _cluster,

        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    )
    external
    payable
    onlyOperatorOrOwnerOrClientOrReferrer(
        _clientConfig.recipient,
        _referrerConfig.recipient
    )
    onlyAllowedOperatorsByOwner(_operatorOwners, _operatorIds)
    returns (address p2pSsvProxy) {
        address feeDistributorInstance = _createFeeDistributor(_clientConfig, _referrerConfig);
        p2pSsvProxy = _createP2pSsvProxyAuto(feeDistributorInstance);

        P2pSsvProxy(payable(p2pSsvProxy)).bulkRegisterValidatorsEth{value: msg.value}(
            _publicKeys,
            _operatorIds,
            _sharesData,
            _cluster
        );

        emit P2pSsvProxyFactory__EthRegistrationCompleted(p2pSsvProxy, msg.value);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function depositToSsvEth(
        address _clusterOwner,
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster calldata _cluster
    ) external payable onlyOwner {
        ISSVNetworkEth(address(i_ssvNetwork)).deposit{value: msg.value}(_clusterOwner, _operatorIds, _cluster);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function migrateClusterToETH(
        address _p2pSsvProxy,
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster calldata _cluster
    ) external payable onlyOperatorOrOwner {
        if (!s_deployedP2pSsvProxies[_p2pSsvProxy]) {
            revert P2pSsvProxyFactory__NotDeployedP2pSsvProxy(_p2pSsvProxy);
        }

        P2pSsvProxy(payable(_p2pSsvProxy)).migrateClusterToETH{value: msg.value}(
            _operatorIds,
            _cluster
        );

        emit P2pSsvProxyFactory__ClusterMigrationInitiated(_p2pSsvProxy, msg.value);
    }

    /**********************************/
    /* Beacon Proxy Management        */
    /**********************************/

    /// @inheritdoc IP2pSsvProxyFactory
    function setBeacon(address _beacon) external onlyOwner {
        address impl = IBeacon(_beacon).implementation();
        if (!ERC165Checker.supportsInterface(impl, type(IP2pSsvProxy).interfaceId)) {
            revert P2pSsvProxyFactory__NotP2pSsvProxy(impl);
        }
        s_beacon = _beacon;
        emit P2pSsvProxyFactory__BeaconSet(_beacon);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function getBeacon() external view returns (address) {
        return s_beacon;
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function predictP2pSsvProxyAddressBeacon(
        address _feeDistributorInstance
    ) public view returns (address) {
        address beacon_ = s_beacon;
        if (beacon_ == address(0)) {
            revert P2pSsvProxyFactory__BeaconNotSet();
        }

        bytes32 salt = bytes32(bytes20(_feeDistributorInstance));
        bytes memory initData = abi.encodeCall(P2pSsvProxy.initialize, (_feeDistributorInstance));
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(type(P2pBeaconProxy).creationCode, abi.encode(beacon_, initData))
        );
        return address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)
        ))));
    }

    /// @notice Deploy P2pSsvProxy instance via BeaconProxy if not deployed before
    /// @param _feeDistributorInstance The address of FeeDistributor instance
    /// @return p2pSsvProxyInstance client P2pSsvProxy instance that has been deployed
    function _createP2pSsvProxyBeacon(
        address _feeDistributorInstance
    ) private returns(address p2pSsvProxyInstance) {
        p2pSsvProxyInstance = predictP2pSsvProxyAddressBeacon(_feeDistributorInstance);
        if (p2pSsvProxyInstance.code.length == 0) {
            if (!ERC165Checker.supportsInterface(_feeDistributorInstance, type(IFeeDistributor).interfaceId)) {
                revert P2pSsvProxyFactory__NotFeeDistributor(_feeDistributorInstance);
            }

            bytes memory initData = abi.encodeCall(P2pSsvProxy.initialize, (_feeDistributorInstance));
            bytes32 salt = bytes32(bytes20(_feeDistributorInstance));
            p2pSsvProxyInstance = address(new P2pBeaconProxy{salt: salt}(s_beacon, initData));

            address client = IFeeDistributor(_feeDistributorInstance).client();

            s_allClientP2pSsvProxies[client].push(p2pSsvProxyInstance);
            s_allP2pSsvProxies.push(p2pSsvProxyInstance);
            s_deployedP2pSsvProxies[p2pSsvProxyInstance] = true;

            emit P2pSsvProxyFactory__P2pSsvProxyCreated(
                p2pSsvProxyInstance,
                client,
                _feeDistributorInstance
            );
        }
    }

    /// @notice Deploy P2pSsvProxy via beacon (if set) or via clone (legacy fallback)
    /// @param _feeDistributorInstance The address of FeeDistributor instance
    /// @return p2pSsvProxyInstance deployed proxy address
    function _createP2pSsvProxyAuto(
        address _feeDistributorInstance
    ) private returns(address p2pSsvProxyInstance) {
        if (s_beacon != address(0)) {
            return _createP2pSsvProxyBeacon(_feeDistributorInstance);
        }
        return _createP2pSsvProxy(_feeDistributorInstance);
    }

    function _checkTokenAmount(
        uint256 _tokenAmount,
        uint256 _validatorCount
    ) private view {
        uint112 maxSsvTokenAmountPerValidator = s_maxSsvTokenAmountPerValidator;

        if (maxSsvTokenAmountPerValidator == 0) {
            revert P2pSsvProxyFactory__MaxSsvTokenAmountPerValidatorNotSet();
        }

        if (_tokenAmount > maxSsvTokenAmountPerValidator * _validatorCount) {
            revert P2pSsvProxyFactory__MaxSsvTokenAmountPerValidatorExceeded();
        }
    }

    /// @notice Register validators with SSV (up to 60, calldata size is the limit)
    /// @dev Common logic for depositEthAndRegisterValidators and registerValidators functions
    /// @param _ssvPayload a stuct with data necessary for SSV registration (see `SsvPayload` struct for details)
    /// @param _clientConfig address and basis points (percent * 100) of the client (for FeeDistributor)
    /// @param _referrerConfig address and basis points (percent * 100) of the referrer (for FeeDistributor)
    /// @return p2pSsvProxy client P2pSsvProxy instance that became the SSV cluster owner
    function _registerValidators(
        SsvPayload calldata _ssvPayload,
        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    ) private onlyAllowedOperators(_ssvPayload.ssvOperators) returns (address p2pSsvProxy) {
        address feeDistributorInstance = _createFeeDistributor(_clientConfig, _referrerConfig);
        p2pSsvProxy = _createP2pSsvProxyAuto(feeDistributorInstance);

        i_ssvToken.transfer(address(p2pSsvProxy), _ssvPayload.tokenAmount);

        P2pSsvProxy(payable(p2pSsvProxy)).registerValidators(_ssvPayload);

        emit P2pSsvProxyFactory__RegistrationCompleted(p2pSsvProxy);
    }

    /// @notice Register validators with SSV
    /// @dev Common logic for depositEthAndRegisterValidators and registerValidators functions
    /// @param _operatorOwners SSV operator owner addresses
    /// @param _operatorIds SSV operator IDs
    /// @param _publicKeys validator public keys
    /// @param _sharesData encrypted shares related to the validator
    /// @param _amount amount of ERC-20 SSV tokens to deposit into the cluster
    /// @param _cluster SSV cluster
    /// @param _clientConfig address and basis points (percent * 100) of the client (for FeeDistributor)
    /// @param _referrerConfig address and basis points (percent * 100) of the referrer (for FeeDistributor)
    /// @return p2pSsvProxy client P2pSsvProxy instance that became the SSV cluster owner
    function _registerValidators(
        address[] calldata _operatorOwners,
        uint64[] calldata _operatorIds,

        bytes[] calldata _publicKeys,
        bytes[] calldata _sharesData,

        uint256 _amount,
        ISSVNetwork.Cluster calldata _cluster,

        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    ) private onlyAllowedOperatorsByOwner(_operatorOwners, _operatorIds) returns (address p2pSsvProxy) {
        address feeDistributorInstance = _createFeeDistributor(_clientConfig, _referrerConfig);
        p2pSsvProxy = _createP2pSsvProxyAuto(feeDistributorInstance);

        i_ssvToken.transfer(address(p2pSsvProxy), _amount);

        P2pSsvProxy(payable(p2pSsvProxy)).bulkRegisterValidators(
            _publicKeys,
            _operatorIds,
            _sharesData,
            _amount,
            _cluster
        );

        emit P2pSsvProxyFactory__RegistrationCompleted(p2pSsvProxy);
    }

    /// @notice Deploy P2pSsvProxy instance if not deployed before
    /// @param _feeDistributorInstance The address of FeeDistributor instance
    /// @return p2pSsvProxyInstance client P2pSsvProxy instance that has been deployed
    function _createP2pSsvProxy(
        address _feeDistributorInstance
    ) private returns(address p2pSsvProxyInstance) {
        p2pSsvProxyInstance = predictP2pSsvProxyAddress(_feeDistributorInstance);
        if (p2pSsvProxyInstance.code.length == 0) { // if p2pSsvProxyInstance doesn't exist, deploy it
            if (!ERC165Checker.supportsInterface(_feeDistributorInstance, type(IFeeDistributor).interfaceId)) {
                revert P2pSsvProxyFactory__NotFeeDistributor(_feeDistributorInstance);
            }

            // clone the reference implementation of P2pSsvProxy
            p2pSsvProxyInstance = Clones.cloneDeterministic(
                address(s_referenceP2pSsvProxy),
                bytes32(bytes20(_feeDistributorInstance))
            );

            // set the client address to the cloned P2pSsvProxy instance
            P2pSsvProxy(payable(p2pSsvProxyInstance)).initialize(_feeDistributorInstance);

            address client = IFeeDistributor(_feeDistributorInstance).client();

            // append new P2pSsvProxy address to all client P2pSsvProxies array
            s_allClientP2pSsvProxies[client].push(p2pSsvProxyInstance);

            // append new P2pSsvProxy address to all P2pSsvProxies array
            s_allP2pSsvProxies.push(p2pSsvProxyInstance);

            s_deployedP2pSsvProxies[p2pSsvProxyInstance] = true;

            // emit event with the address of the newly created instance for the external listener
            emit P2pSsvProxyFactory__P2pSsvProxyCreated(
                p2pSsvProxyInstance,
                client,
                _feeDistributorInstance
            );
        }
    }

    /// @notice Deploy FeeDistributor instance if not deployed before
    /// @param _clientConfig address and basis points (percent * 100) of the client (for FeeDistributor)
    /// @param _referrerConfig address and basis points (percent * 100) of the referrer (for FeeDistributor)
    /// @return feeDistributorInstance client FeeDistributor instance that has been deployed
    function _createFeeDistributor(
        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    ) private returns(address feeDistributorInstance) {
        address referenceFeeDistributor_ = s_referenceFeeDistributor;

        feeDistributorInstance = i_feeDistributorFactory.predictFeeDistributorAddress(
            referenceFeeDistributor_,
            _clientConfig,
            _referrerConfig
        );
        if (feeDistributorInstance.code.length == 0) {
            // if feeDistributorInstance doesn't exist, deploy it
            i_feeDistributorFactory.createFeeDistributor(
                referenceFeeDistributor_,
                _clientConfig,
                _referrerConfig
            );
        }
    }

    /// @notice Check ETH value for validator registrations without ETH deposits.
    /// @dev P2P cannot afford totally free validator registrations since they are paid with P2P's SSV tokens.
    /// It's OK for validator registrations with ETH deposits since we can be confident in the existense of EL rewards
    /// that will cover the SSV tokens cost in that case.
    /// If there are no ETH deposits, to prevent draining of SSV tokens from P2pSsvProxyFactory,
    /// the client pays for the used SSV tokens.
    /// The client will only need to pay once. Starting from the next month, P2P will be depositing SSV tokens to the clusters
    /// the same way as with ETH deposits.
    /// @param _tokenAmount amount of ERC-20 SSV tokens for validator registration
    function _checkEthValue(
        uint256 _tokenAmount
    ) private view {
        uint112 exchangeRate = s_ssvPerEthExchangeRateDividedByWei;
        if (exchangeRate == 0) {
            revert P2pSsvProxyFactory__SsvPerEthExchangeRateDividedByWeiNotSet();
        }

        uint256 ssvTokensValueInWei = (_tokenAmount * exchangeRate) / 10**18;
        if (msg.value != ssvTokensValueInWei) {
            revert P2pSsvProxyFactory__NotEnoughEtherPaidToCoverSsvFees(ssvTokensValueInWei, msg.value);
        }
    }

    /// @notice Set SSV operator IDs list for a SSV operator owner
    /// @param _operatorIds SSV operator IDs list
    /// @param _ssvOperatorOwner SSV operator owner
    function _setSsvOperatorIds(
        uint64[MAX_ALLOWED_SSV_OPERATOR_IDS] calldata _operatorIds,
        address _ssvOperatorOwner
    ) private {
        for (uint i = 0; i < _operatorIds.length; ++i) {
            uint64 id = _operatorIds[i];

            for (uint j = i + 1; j < _operatorIds.length; ++j) {
                if (id == _operatorIds[j] && id != 0) {
                    revert P2pSsvProxyFactory__DuplicateIdsNotAllowed(id);
                }
            }

            if (id != 0) {
                (address actualOwner,,,,,) = i_ssvViews.getOperatorById(id);
                if (actualOwner != _ssvOperatorOwner) {
                    revert P2pSsvProxyFactory__SsvOperatorIdDoesNotBelongToOwner(id, _ssvOperatorOwner, actualOwner);
                }
            }
        }

        s_allowedSsvOperatorIds[_ssvOperatorOwner] = _operatorIds;
        emit P2pSsvProxyFactory__SsvOperatorIdsSet(_ssvOperatorOwner, _operatorIds);
    }

    /// @notice Clear SSV operator IDs list for a SSV operator owner
    /// @param _ssvOperatorOwner SSV operator owner
    function _clearSsvOperatorIds(
        address _ssvOperatorOwner
    ) private {
        delete s_allowedSsvOperatorIds[_ssvOperatorOwner];
        emit P2pSsvProxyFactory__SsvOperatorIdsCleared(_ssvOperatorOwner);
    }

    /// @inheritdoc IOwnable
    function owner() public view override(Ownable, OwnableBase, IOwnable) returns (address) {
        return super.owner();
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function getFeeDistributorFactory() external view returns (address) {
        return address(i_feeDistributorFactory);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function getAllClientP2pSsvProxies(
        address _client
    ) external view returns (address[] memory) {
        return s_allClientP2pSsvProxies[_client];
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function getAllP2pSsvProxies() external view returns (address[] memory) {
        return s_allP2pSsvProxies;
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function isClientSelectorAllowed(bytes4 _selector) external view returns (bool) {
        return s_clientSelectors[_selector];
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function isOperatorSelectorAllowed(bytes4 _selector) external view returns (bool) {
        return s_operatorSelectors[_selector];
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function getAllowedSsvOperatorIds(address _ssvOperatorOwner) external view returns (uint64[MAX_ALLOWED_SSV_OPERATOR_IDS] memory) {
        return s_allowedSsvOperatorIds[_ssvOperatorOwner];
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function getAllowedSsvOperatorOwners() external view returns (address[] memory) {
        return s_allowedSsvOperatorOwners.values();
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function getReferenceFeeDistributor() external view returns (address) {
        return s_referenceFeeDistributor;
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function getReferenceP2pSsvProxy() external view returns (address) {
        return address(s_referenceP2pSsvProxy);
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function getSsvPerEthExchangeRateDividedByWei() external view returns (uint112) {
        return s_ssvPerEthExchangeRateDividedByWei;
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function getNeededAmountOfEtherToCoverSsvFees(uint256 _tokenAmount) external view returns (uint256) {
        return (_tokenAmount * s_ssvPerEthExchangeRateDividedByWei) / 10**18;
    }

    /// @inheritdoc IP2pSsvProxyFactory
    function getMaxSsvTokenAmountPerValidator() external view returns (uint112) {
        return s_maxSsvTokenAmountPerValidator;
    }

    /// @inheritdoc ISSVWhitelistingContract
    function isWhitelisted(address account, uint256) external view returns (bool) {
        return s_deployedP2pSsvProxies[account];
    }

    /// @dev V1 interfaceId (original deployed interface). Kept for backward compatibility.
    bytes4 private constant _IP2P_SSV_PROXY_FACTORY_V1_INTERFACE_ID = 0xd73c1ea2;

    /// @dev V2 interfaceId
    bytes4 private constant _IP2P_SSV_PROXY_FACTORY_V2_INTERFACE_ID = 0x86829d35;

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IP2pSsvProxyFactory).interfaceId ||
               interfaceId == _IP2P_SSV_PROXY_FACTORY_V2_INTERFACE_ID ||
               interfaceId == _IP2P_SSV_PROXY_FACTORY_V1_INTERFACE_ID ||
               interfaceId == type(ISSVWhitelistingContract).interfaceId ||
               super.supportsInterface(interfaceId);
    }
}
