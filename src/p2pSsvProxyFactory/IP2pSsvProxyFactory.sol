// SPDX-FileCopyrightText: 2024 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "../structs/P2pStructs.sol";
import "../constants/P2pConstants.sol";
import "../interfaces/ssv/ISSVNetwork.sol";
import "../interfaces/ssv/external/ISSVWhitelistingContract.sol";
import "../access/IOwnableWithOperator.sol";

/// @dev External interface of P2pSsvProxyFactory
interface IP2pSsvProxyFactory is ISSVWhitelistingContract, IOwnableWithOperator, IERC165 {

    /// @notice Emits when batch registration of validator with SSV is completed
    /// @param _proxy address of P2pSsvProxy that was used for registration and became the cluster owner
    event P2pSsvProxyFactory__RegistrationCompleted(
        address indexed _proxy
    );

    /// @notice Emits when a new P2pSsvProxy instance was deployed and initialized
    /// @param _p2pSsvProxy newly deployed P2pSsvProxy instance address
    /// @param _client client address
    /// @param _feeDistributor FeeDistributor instance address
    event P2pSsvProxyFactory__P2pSsvProxyCreated(
        address indexed _p2pSsvProxy,
        address indexed _client,
        address indexed _feeDistributor
    );

    /// @notice Emits when a new reference FeeDistributor has been set
    /// @param _referenceFeeDistributor new reference FeeDistributor address
    event P2pSsvProxyFactory__ReferenceFeeDistributorSet(
        address indexed _referenceFeeDistributor
    );

    /// @notice Emits when a new value for ssvPerEthExchangeRateDividedByWei has been set
    /// @param _ssvPerEthExchangeRateDividedByWei new value for ssvPerEthExchangeRateDividedByWei
    event P2pSsvProxyFactory__SsvPerEthExchangeRateDividedByWeiSet(
        uint112 _ssvPerEthExchangeRateDividedByWei
    );

    /// @notice Emits when a new value for maximum amount of SSV tokens per validator has been set
    /// @param _maxSsvTokenAmountPerValidator new value for maximum amount of SSV tokens per validator
    event P2pSsvProxyFactory__MaxSsvTokenAmountPerValidatorSet(
        uint112 _maxSsvTokenAmountPerValidator
    );

    /// @notice Emits when a new reference P2pSsvProxy has been set
    /// @param _referenceP2pSsvProxy new reference P2pSsvProxy address
    event P2pSsvProxyFactory__ReferenceP2pSsvProxySet(
        address indexed _referenceP2pSsvProxy
    );

    /// @notice Emits when new selectors were allowed for clients
    /// @param _selectors newly allowed selectors
    event P2pSsvProxyFactory__AllowedSelectorsForClientSet(
        bytes4[] _selectors
    );

    /// @notice Emits when selectors were disallowed for clients
    /// @param _selectors disallowed selectors
    event P2pSsvProxyFactory__AllowedSelectorsForClientRemoved(
        bytes4[] _selectors
    );

    /// @notice Emits when new selectors were allowed for operator
    /// @param _selectors newly allowed selectors
    event P2pSsvProxyFactory__AllowedSelectorsForOperatorSet(
        bytes4[] _selectors
    );

    /// @notice Emits when selectors were disallowed for operator
    /// @param _selectors disallowed selectors
    event P2pSsvProxyFactory__AllowedSelectorsForOperatorRemoved(
        bytes4[] _selectors
    );

    /// @notice Emits when new SSV operator owner addresses have been allowed
    /// @param _allowedSsvOperatorOwners newly allowed SSV operator owner addresses
    event P2pSsvProxyFactory__AllowedSsvOperatorOwnersSet(
        address[] _allowedSsvOperatorOwners
    );

    /// @notice Emits when some SSV operator owner addresses have been removed from the allowlist
    /// @param _allowedSsvOperatorOwners disallowed SSV operator owner addresses
    event P2pSsvProxyFactory__AllowedSsvOperatorOwnersRemoved(
        address[] _allowedSsvOperatorOwners
    );

    /// @notice Emits when new SSV operator IDs have been set to the given SSV operator owner
    /// @param _ssvOperatorOwner SSV operator owner
    event P2pSsvProxyFactory__SsvOperatorIdsSet(
        address indexed _ssvOperatorOwner,
        uint64[MAX_ALLOWED_SSV_OPERATOR_IDS] _operatorIds
    );

    /// @notice Emits when operator IDs list has been cleared for the given SSV operator owner
    /// @param _ssvOperatorOwner SSV operator owner
    event P2pSsvProxyFactory__SsvOperatorIdsCleared(
        address indexed _ssvOperatorOwner
    );

    /// @notice Emits when client deposited their ETH for SSV staking
    /// @param _depositId ID of client deposit (derived from ETH2 WithdrawalCredentials, ETH amount per validator in wei, fee distributor instance address)
    /// @param _sender address who sent ETH
    /// @param _p2pSsvProxy address of the client instance of P2pSsvProxy
    /// @param _feeDistributorInstance address of the client instance of FeeDistributor
    /// @param _ethAmountInWei amount of deposited ETH in wei
    event P2pSsvProxyFactory__EthForSsvStakingDeposited(
        bytes32 indexed _depositId,
        address indexed _sender,
        address indexed _p2pSsvProxy,
        address _feeDistributorInstance,
        uint256 _ethAmountInWei
    );

    /// @notice Set Exchange rate between SSV and ETH set by P2P.
    /// @dev (If 1 SSV = 0.007539 ETH, it should be 0.007539 * 10^18 = 7539000000000000).
    /// @param _ssvPerEthExchangeRateDividedByWei Exchange rate
    function setSsvPerEthExchangeRateDividedByWei(uint112 _ssvPerEthExchangeRateDividedByWei) external;

    /// @notice Set Maximum amount of SSV tokens per validator that is allowed for client to deposit during `depositEthAndRegisterValidators`
    /// @param _maxSsvTokenAmountPerValidator Maximum amount of SSV tokens per validator
    function setMaxSsvTokenAmountPerValidator(uint112 _maxSsvTokenAmountPerValidator) external;

    /// @notice Set template to be used for new P2pSsvProxy instances
    /// @param _referenceP2pSsvProxy template to be used for new P2pSsvProxy instances
    function setReferenceP2pSsvProxy(address _referenceP2pSsvProxy) external;

    /// @notice Allow selectors (function signatures) for clients to call on SSVNetwork via P2pSsvProxy
    /// @param _selectors selectors (function signatures) to allow for clients
    function setAllowedSelectorsForClient(bytes4[] calldata _selectors) external;

    /// @notice Disallow selectors (function signatures) for clients to call on SSVNetwork via P2pSsvProxy
    /// @param _selectors selectors (function signatures) to disallow for clients
    function removeAllowedSelectorsForClient(bytes4[] calldata _selectors) external;

    /// @notice Allow selectors (function signatures) for P2P operator to call on SSVNetwork via P2pSsvProxy
    /// @param _selectors selectors (function signatures) to allow for P2P operator
    function setAllowedSelectorsForOperator(bytes4[] calldata _selectors) external;

    /// @notice Disallow selectors (function signatures) for P2P operator to call on SSVNetwork via P2pSsvProxy
    /// @param _selectors selectors (function signatures) to disallow for P2P operator
    function removeAllowedSelectorsForOperator(bytes4[] calldata _selectors) external;

    /// @notice Set template to be used for new FeeDistributor instances
    /// @param _referenceFeeDistributor template to be used for new FeeDistributor instances
    function setReferenceFeeDistributor(
        address _referenceFeeDistributor
    ) external;

    /// @notice Allow addresses of SSV operator owners (both P2P and partners)
    /// @param _allowedSsvOperatorOwners addresses of SSV operator owners to allow
    function setAllowedSsvOperatorOwners(
        address[] calldata _allowedSsvOperatorOwners
    ) external;

    /// @notice Disallow addresses of SSV operator owners (both P2P and partners)
    /// @param _allowedSsvOperatorOwnersToRemove addresses of SSV operator owners to disallow
    function removeAllowedSsvOperatorOwners(
        address[] calldata _allowedSsvOperatorOwnersToRemove
    ) external;

    /// @notice Set own SSV operator IDs list
    /// @dev To be called by SSV operator owner
    /// @param _operatorIds SSV operator IDs list
    function setSsvOperatorIds(
        uint64[MAX_ALLOWED_SSV_OPERATOR_IDS] calldata _operatorIds
    ) external;

    /// @notice Set SSV operator IDs list for a SSV operator owner
    /// @dev To be called by P2P
    /// @param _operatorIds SSV operator IDs list
    /// @param _ssvOperatorOwner SSV operator owner
    function setSsvOperatorIds(
        uint64[MAX_ALLOWED_SSV_OPERATOR_IDS] calldata _operatorIds,
        address _ssvOperatorOwner
    ) external;

    /// @notice Clear own SSV operator IDs list
    /// @dev To be called by SSV operator owner
    function clearSsvOperatorIds() external;

    /// @notice Clear SSV operator IDs list for a SSV operator owner
    /// @dev To be called by P2P
    /// @param _ssvOperatorOwner SSV operator owner
    function clearSsvOperatorIds(
        address _ssvOperatorOwner
    ) external;

    /// @notice Computes the address of a P2pSsvProxy created by `_createP2pSsvProxy` function
    /// @dev P2pSsvProxy instances are guaranteed to have the same address if _feeDistributorInstance is the same
    /// @param _feeDistributorInstance The address of FeeDistributor instance
    /// @return address client P2pSsvProxy instance that will be or has been deployed
    function predictP2pSsvProxyAddress(
        address _feeDistributorInstance
    ) external view returns (address);

    /// @notice Computes the address of a P2pSsvProxy created by `_createP2pSsvProxy` function
    /// @param _referenceFeeDistributor The address of the reference implementation of FeeDistributor used as the basis for clones
    /// @param _clientConfig address and basis points (percent * 100) of the client
    /// @param _referrerConfig address and basis points (percent * 100) of the referrer.
    /// @return address client P2pSsvProxy instance that will be or has been deployed
    function predictP2pSsvProxyAddress(
        address _referenceFeeDistributor,
        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    ) external view returns (address);

    /// @notice Computes the address of a P2pSsvProxy for the default referenceFeeDistributor
    /// @param _clientConfig address and basis points (percent * 100) of the client
    /// @param _referrerConfig address and basis points (percent * 100) of the referrer.
    /// @return address client P2pSsvProxy instance that will be or has been deployed
    function predictP2pSsvProxyAddress(
        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    ) external view returns (address);

    /// @notice Computes the address of a P2pSsvProxy for the default referenceFeeDistributor and referrerConfig
    /// @param _clientConfig address and basis points (percent * 100) of the client
    /// @return address client P2pSsvProxy instance that will be or has been deployed
    function predictP2pSsvProxyAddress(
        FeeRecipient calldata _clientConfig
    ) external view returns (address);

    /// @notice Deploy P2pSsvProxy instance if not deployed before
    /// @param _feeDistributorInstance The address of FeeDistributor instance
    /// @return p2pSsvProxyInstance client P2pSsvProxy instance that has been deployed
    function createP2pSsvProxy(
        address _feeDistributorInstance
    ) external returns(address p2pSsvProxyInstance);

    /// @notice DEPRECATED. Always reverts. Use registerValidatorsEth for ETH-native registration.
    function depositEthAndRegisterValidators(
        DepositData calldata _depositData,
        address _withdrawalCredentialsAddress,

        SsvPayload calldata _ssvPayload,

        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    ) external payable returns (address p2pSsvProxy);

    /// @notice DEPRECATED. Always reverts. Use registerValidatorsEth for ETH-native registration.
    function depositEthAndRegisterValidators(
        DepositData calldata _depositData,
        address _withdrawalCredentialsAddress,

        address[] calldata _operatorOwners,
        uint64[] calldata _operatorIds,
        bytes[] calldata _publicKeys,
        bytes[] calldata _sharesData,
        uint256 _amount,
        ISSVNetwork.Cluster calldata _cluster,

        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    ) external payable returns (address p2pSsvProxy);

    /// @notice Deposit unlimited amount of ETH for SSV staking
    /// @dev Callable by clients
    /// @param _eth2WithdrawalCredentials ETH2 withdrawal credentials
    /// @param _ethAmountPerValidatorInWei amount of ETH to deposit per 1 validator (should be >= 32 and <= 2048)
    /// @param _clientConfig address and basis points (percent * 100) of the client
    /// @param _referrerConfig address and basis points (percent * 100) of the referrer.
    /// @param _extraData any other data to pass to the event listener
    /// @return depositId ID of client deposit (derived from ETH2 WithdrawalCredentials, ETH amount per validator in wei, fee distributor instance address)
    /// @return feeDistributorInstance client FeeDistributor instance
    /// @return p2pSsvProxy client P2pSsvProxy instance that became the SSV cluster owner
    function addEth(
        bytes32 _eth2WithdrawalCredentials,
        uint96 _ethAmountPerValidatorInWei,
        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig,
        bytes calldata _extraData
    )
    external
    payable
    returns (
        bytes32 depositId,
        address feeDistributorInstance,
        address p2pSsvProxy
    );

    /// @notice Register validators with SSV (up to 60, calldata size is the limit) without ETH deposits
    /// @param _ssvPayload a stuct with data necessary for SSV registration (see `SsvPayload` struct for details)
    /// @param _clientConfig address and basis points (percent * 100) of the client (for FeeDistributor)
    /// @param _referrerConfig address and basis points (percent * 100) of the referrer (for FeeDistributor)
    /// @return p2pSsvProxy client P2pSsvProxy instance that became the SSV cluster owner
    function registerValidators(
        SsvPayload calldata _ssvPayload,
        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    ) external payable returns (address p2pSsvProxy);

    /// @notice Register validators with SSV (up to 60, calldata size is the limit) without ETH deposits
    /// @param _operatorOwners SSV operator owner addresses
    /// @param _operatorIds SSV operator IDs
    /// @param _publicKeys validator public keys
    /// @param _sharesData encrypted shares related to the validator
    /// @param _amount amount of ERC-20 SSV tokens to deposit into the cluster
    /// @param _cluster SSV cluster
    /// @param _clientConfig address and basis points (percent * 100) of the client (for FeeDistributor)
    /// @param _referrerConfig address and basis points (percent * 100) of the referrer (for FeeDistributor)
    /// @return p2pSsvProxy client P2pSsvProxy instance that became the SSV cluster owner
    function registerValidators(
        address[] calldata _operatorOwners,
        uint64[] calldata _operatorIds,
        bytes[] calldata _publicKeys,
        bytes[] calldata _sharesData,
        uint256 _amount,
        ISSVNetwork.Cluster calldata _cluster,

        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    ) external payable returns (address p2pSsvProxy);

    /// @notice Send ETH to ETH2 DepositContract on behalf of the client and register validators with SSV (up to 60, calldata size is the limit)
    /// @dev Callable by P2P only.
    /// @param _eth2WithdrawalCredentials ETH2 withdrawal credentials
    /// @param _ethAmountPerValidatorInWei amount of ETH to deposit per 1 validator (should be >= 32 and <= 2048)
    /// @param _feeDistributorInstance user FeeDistributor instance that determines the terms of staking service
    /// @param _depositData signatures and depositDataRoots from Beacon deposit data
    /// @param _operatorIds SSV operator IDs
    /// @param _publicKeys validator public keys
    /// @param _sharesData encrypted shares related to the validator
    /// @param _amount amount of ERC-20 SSV tokens to deposit into the cluster
    /// @param _cluster SSV cluster
    /// @return p2pSsvProxy client P2pSsvProxy instance that became the SSV cluster owner
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
    ) external returns (address p2pSsvProxy);

    /// @notice Deposit SSV tokens from P2pSsvProxyFactory to SSV cluster
    /// @dev Can only be called by P2pSsvProxyFactory owner
    /// @param _clusterOwner SSV cluster owner (usually, P2pSsvProxy instance)
    /// @param _tokenAmount SSV token amount to be deposited
    /// @param _operatorIds SSV operator IDs
    /// @param _cluster SSV cluster
    function depositToSSV(
        address _clusterOwner,
        uint256 _tokenAmount,
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster calldata _cluster
    ) external;

    /**********************************/
    /* ETH-Native Methods (V2)        */
    /**********************************/

    /// @notice Emits when ETH-native batch registration of validators with SSV is completed
    /// @param _proxy address of P2pSsvProxy used for registration
    /// @param _ethToSsv amount of ETH forwarded to SSV for cluster funding
    event P2pSsvProxyFactory__EthRegistrationCompleted(
        address indexed _proxy,
        uint256 _ethToSsv
    );

    /// @notice Emits when a cluster migration to ETH has been initiated via the factory
    /// @param _proxy address of P2pSsvProxy whose cluster is being migrated
    /// @param _ethDeposited amount of ETH deposited for the migrated cluster
    event P2pSsvProxyFactory__ClusterMigrationInitiated(
        address indexed _proxy,
        uint256 _ethDeposited
    );

    /// @notice Register validators with SSV using ETH payments (no beacon deposit)
    /// @dev msg.value is forwarded to SSV as cluster funding. No SSV token transfer.
    /// @param _operatorOwners SSV operator owner addresses
    /// @param _operatorIds SSV operator IDs
    /// @param _publicKeys validator public keys
    /// @param _sharesData encrypted shares related to the validators
    /// @param _cluster SSV cluster
    /// @param _clientConfig address and basis points (percent * 100) of the client (for FeeDistributor)
    /// @param _referrerConfig address and basis points (percent * 100) of the referrer (for FeeDistributor)
    /// @return p2pSsvProxy client P2pSsvProxy instance that became the SSV cluster owner
    function registerValidatorsEth(
        address[] calldata _operatorOwners,
        uint64[] calldata _operatorIds,
        bytes[] calldata _publicKeys,
        bytes[] calldata _sharesData,
        ISSVNetwork.Cluster calldata _cluster,

        FeeRecipient calldata _clientConfig,
        FeeRecipient calldata _referrerConfig
    ) external payable returns (address p2pSsvProxy);

    /// @notice Deposit ETH from P2pSsvProxyFactory directly to an SSV cluster
    /// @dev msg.value is forwarded to SSV as the deposit amount
    /// @param _clusterOwner SSV cluster owner (usually, P2pSsvProxy instance)
    /// @param _operatorIds SSV operator IDs
    /// @param _cluster SSV cluster
    function depositToSsvEth(
        address _clusterOwner,
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster calldata _cluster
    ) external payable;

    /// @notice Initiate migration of a P2pSsvProxy cluster from SSV to ETH payments
    /// @dev msg.value is forwarded as the ETH deposit for the migrated cluster.
    /// SSV tokens refunded by SSV remain in the proxy and should be swept separately.
    /// @param _p2pSsvProxy address of the P2pSsvProxy whose cluster is being migrated
    /// @param _operatorIds SSV operator IDs
    /// @param _cluster SSV cluster to migrate
    function migrateClusterToETH(
        address _p2pSsvProxy,
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster calldata _cluster
    ) external payable;

    /**********************************/
    /* Beacon Proxy Management        */
    /**********************************/

    /// @notice Emits when the beacon address for new proxy deployments is set
    /// @param _beacon the new beacon address
    event P2pSsvProxyFactory__BeaconSet(address indexed _beacon);

    /// @notice Set the UpgradeableBeacon address for new proxy deployments
    /// @dev When set, new proxies are deployed as BeaconProxy instances. When unset, clone path is used.
    /// @param _beacon The UpgradeableBeacon address (its implementation must support IP2pSsvProxy)
    function setBeacon(address _beacon) external;

    /// @notice Returns the current beacon address (zero if not set)
    /// @return beacon address
    function getBeacon() external view returns (address);

    /// @notice Predict the address of a BeaconProxy-based P2pSsvProxy instance
    /// @param _feeDistributorInstance The address of FeeDistributor instance
    /// @return address the predicted proxy address
    function predictP2pSsvProxyAddressBeacon(
        address _feeDistributorInstance
    ) external view returns (address);

    /// @notice Returns the FeeDistributorFactory address
    /// @return FeeDistributorFactory address
    function getFeeDistributorFactory() external view returns (address);

    /// @notice A list of addresses of the deployed client P2pSsvProxy instances by client address
    /// @param _client client address
    /// @return A list of addresses of the deployed client P2pSsvProxy instances
    function getAllClientP2pSsvProxies(
        address _client
    ) external view returns (address[] memory);

    /// @notice Returns a list of all ever deployed client P2pSsvProxy instances
    /// @return a list of all ever deployed client P2pSsvProxy instances
    function getAllP2pSsvProxies() external view returns (address[] memory);

    /// @notice Returns if a certain selector (function signature) is allowed for clients to call on SSVNetwork via P2pSsvProxy
    /// @return True if allowed
    function isClientSelectorAllowed(bytes4 _selector) external view returns (bool);

    /// @notice Returns if a certain selector (function signature) is allowed for a P2P operator to call on SSVNetwork via P2pSsvProxy
    /// @param _selector selector (function signature)
    /// @return True if allowed
    function isOperatorSelectorAllowed(bytes4 _selector) external view returns (bool);

    /// @notice Returns SSV operator IDs list by operator owner address
    /// @param _ssvOperatorOwner operator owner address
    /// @return SSV operator IDs list
    function getAllowedSsvOperatorIds(address _ssvOperatorOwner) external view returns (uint64[MAX_ALLOWED_SSV_OPERATOR_IDS] memory);

    /// @notice Returns a set of addresses of SSV operator owners (both P2P and partners)
    /// @return a set of addresses of SSV operator owners (both P2P and partners)
    function getAllowedSsvOperatorOwners() external view returns (address[] memory);

    /// @notice Returns a template set by P2P to be used for new FeeDistributor instances
    /// @return a template set by P2P to be used for new FeeDistributor instances
    function getReferenceFeeDistributor() external view returns (address);

    /// @notice Returns a template set by P2P to be used for new P2pSsvProxy instances
    /// @return a template set by P2P to be used for new P2pSsvProxy instances
    function getReferenceP2pSsvProxy() external view returns (address);

    /// @notice Returns exchange rate between SSV and ETH set by P2P
    /// @dev (If 1 SSV = 0.007539 ETH, it should be 0.007539 * 10^18 = 7539000000000000).
    /// Only used during validator registration without ETH deposits to cover SSV token costs with client ETH.
    /// SSV tokens exchanged with this rate cannot be withdrawn by the client.
    /// P2P is willing to tolarate potential discrepancies with the market exchange rate for the sake of simplicity.
    /// The client agrees to this rate when calls `registerValidators` function.
    /// @return exchange rate between SSV and ETH set by P2P
    function getSsvPerEthExchangeRateDividedByWei() external view returns (uint112);

    /// @notice Returns the maximum amount of SSV tokens per validator that is allowed for client to deposit during `depositEthAndRegisterValidators`
    /// @return maximum amount of SSV tokens per validator
    function getMaxSsvTokenAmountPerValidator() external view returns (uint112);

    /// @notice Returns needed amount of ETH to cover SSV fees by SSV token amount
    /// @param _tokenAmount SSV token amount
    /// @return needed amount of ETH to cover SSV fees
    function getNeededAmountOfEtherToCoverSsvFees(uint256 _tokenAmount) external view returns (uint256);
}
