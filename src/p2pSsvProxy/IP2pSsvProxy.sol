// SPDX-FileCopyrightText: 2024 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "../structs/P2pStructs.sol";
import "../access/IOwnableWithOperator.sol";
import "../interfaces/ssv/ISSVNetwork.sol";

/// @dev External interface of P2pSsvProxy declared to support ERC165 detection.
interface IP2pSsvProxy is IOwnableWithOperator, IERC165 {

    /// @notice Emits when P2pSsvProxy instance is initialized
    /// @param _feeDistributor FeeDistributor instance that determines the identity of this P2pSsvProxy instance
    event P2pSsvProxy__Initialized(
        address indexed _feeDistributor
    );

    /// @notice Emits when the function was called successfully on SSVNetwork via fallback
    /// @param _caller caller of P2pSsvProxy
    /// @param _selector selector of the function from SSVNetwork
    event P2pSsvProxy__SuccessfullyCalledViaFallback(
        address indexed _caller,
        bytes4 indexed _selector
    );

    /// @notice Emits when an arbitrary external contract has been called by owner via P2pSsvProxy
    /// @param _contract external contract address
    /// @param _selector selector of the called function
    event P2pSsvProxy__SuccessfullyCalledExternalContract(
        address indexed _contract,
        bytes4 indexed _selector
    );

    /// @notice Initialize the P2pSsvProxy instance
    /// @dev Should only be called by P2pSsvProxyFactory
    /// @param _feeDistributor FeeDistributor instance that determines the identity of this P2pSsvProxy instance
    function initialize(
        address _feeDistributor
    ) external;

    /// @notice Call an arbitrary external contract with P2pSsvProxy as a msg.sender
    /// @dev Should be called by owner only
    /// @dev This function can help e.g. in claiming airdrops
    /// @param _contract external contract address
    /// @param _calldata calldata for the external contract
    function callAnyContract(
        address _contract,
        bytes calldata _calldata
    ) external;

    /// @notice Register a batch of validators with SSV
    /// @dev Should be called by P2pSsvProxyFactory only
    /// @param _ssvPayload struct with the SSV data required for registration
    function registerValidators(
        SsvPayload calldata _ssvPayload
    ) external;

    /// @notice Registers new validators on the SSV Network
    /// @dev Should be called by P2pSsvProxyFactory only
    /// @param publicKeys The public keys of the new validators
    /// @param operatorIds Array of IDs of operators managing this validator
    /// @param sharesData Encrypted shares related to the new validators
    /// @param amount Amount of SSV tokens to be deposited
    /// @param cluster Cluster to be used with the new validator
    function bulkRegisterValidators(
        bytes[] calldata publicKeys,
        uint64[] calldata operatorIds,
        bytes[] calldata sharesData,
        uint256 amount,
        ISSVNetwork.Cluster calldata cluster
    ) external;

    /// @notice Remove a batch of validators from SSV
    /// @dev Can be called either by P2P or by the client
    /// @param _pubkeys validator pubkeys
    /// @param _operatorIds SSV operator IDs
    /// @param _clusters SSV clusters, each of which should correspond to pubkey and operator IDs
    function removeValidators(
        bytes[] calldata _pubkeys,
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster[] calldata _clusters
    ) external;

    /// @notice Liquidate SSV clusters
    /// @dev Should be called by P2P only.
    /// This function is just batching calls for convenience. It's always possible to call the same function on SSVNetwork via fallback
    /// @param _operatorIds SSV operator IDs
    /// @param _clusters SSV clusters
    function liquidate(
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster[] calldata _clusters
    ) external;

    /// @notice Reactivate SSV clusters
    /// @dev Should be called by P2P only
    /// This function is just batching calls for convenience. It's always possible to call the same function on SSVNetwork via fallback
    /// @param _tokenAmount SSV token amount to be deposited for reactivation
    /// @param _operatorIds SSV operator IDs
    /// @param _clusters SSV clusters
    function reactivate(
        uint256 _tokenAmount,
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster[] calldata _clusters
    ) external;

    /// @notice Deposit SSV tokens to SSV clusters
    /// @dev Can be called by anyone
    /// This function is just batching calls for convenience. It's possible to call the same function on SSVNetwork directly
    /// @param _tokenAmount SSV token amount to be deposited
    /// @param _operatorIds SSV operator IDs
    /// @param _clusters SSV clusters
    function depositToSSV(
        uint256 _tokenAmount,
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster[] calldata _clusters
    ) external;

    /// @notice Withdraw SSV tokens from SSV clusters to this contract
    /// @dev Should be called by P2P only
    /// This function is just batching calls for convenience. It's always possible to call the same function on SSVNetwork via fallback
    /// @param _tokenAmount SSV token amount to be withdrawn
    /// @param _operatorIds SSV operator IDs
    /// @param _clusters SSV clusters
    function withdrawFromSSV(
        uint256 _tokenAmount,
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster[] calldata _clusters
    ) external;

    /// @notice Withdraw SSV tokens from this contract to the given address
    /// @dev Should be called by P2P only
    /// @param _to destination address
    /// @param _amount SSV token amount to be withdrawn
    function withdrawSSVTokens(
        address _to,
        uint256 _amount
    ) external;

    /// @notice Withdraw all SSV tokens from this contract to P2pSsvProxyFactory
    /// @dev Should be called by P2P only
    function withdrawAllSSVTokensToFactory() external;

    /// @notice Withdraw SSV tokens from SSV clusters to P2pSsvProxyFactory
    /// @dev Should be called by P2P only
    /// @param _tokenAmount SSV token amount to be withdrawn
    /// @param _operatorIds SSV operator IDs
    /// @param _clusters SSV clusters
    function withdrawFromSSVToFactory(
        uint256 _tokenAmount,
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster[] calldata _clusters
    ) external;

    /// @notice Set a new fee recipient address for this contract (cluster owner)
    /// @dev Should be called by P2P only.
    /// Another FeeDistributor instance can become the fee recipient (e.g. if service percentages change).
    /// Client address itself can become the fee recipient (e.g. if service percentage becomes zero due to some promo).
    /// It's fine for P2P to determine the fee recipient since P2P is paying SSV tokens and EL rewards are a way to compansate for them.
    /// Other operators are compansated via SSV tokens paid by P2P.
    /// @param _feeRecipientAddress fee recipient address to set
    function setFeeRecipientAddress(
        address _feeRecipientAddress
    ) external;

    /// @notice Fires the exit event for a set of validators
    /// @param publicKeys The public keys of the validators to be exited
    /// @param operatorIds Array of IDs of operators managing the validators
    function bulkExitValidator(bytes[] calldata publicKeys, uint64[] calldata operatorIds) external;

    /**********************************/
    /* ETH-Native Methods (V2)        */
    /**********************************/

    /// @notice Emits when ETH is received by the proxy (e.g. from SSV withdraw/liquidate on ETH clusters)
    /// @param _sender address that sent the ETH
    /// @param _amount amount of ETH received
    event P2pSsvProxy__EthReceived(
        address indexed _sender,
        uint256 _amount
    );

    /// @notice Registers new validators on the SSV Network using ETH payments
    /// @dev Should be called by P2pSsvProxyFactory only. msg.value is forwarded to SSV as the cluster deposit.
    /// @param publicKeys The public keys of the new validators
    /// @param operatorIds Array of IDs of operators managing this validator
    /// @param sharesData Encrypted shares related to the new validators
    /// @param cluster Cluster to be used with the new validators
    function bulkRegisterValidatorsEth(
        bytes[] calldata publicKeys,
        uint64[] calldata operatorIds,
        bytes[] calldata sharesData,
        ISSVNetwork.Cluster calldata cluster
    ) external payable;

    /// @notice Deposit ETH to SSV clusters
    /// @dev Can be called by anyone. msg.value is split evenly across clusters (remainder to last).
    /// @param _operatorIds SSV operator IDs
    /// @param _clusters SSV clusters
    function depositToSsvEth(
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster[] calldata _clusters
    ) external payable;

    /// @notice Reactivate SSV clusters using ETH payment
    /// @dev Should be called by P2P only. msg.value is split evenly across clusters (remainder to last).
    /// @param _operatorIds SSV operator IDs
    /// @param _clusters SSV clusters
    function reactivateEth(
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster[] calldata _clusters
    ) external payable;

    /// @notice Migrate an SSV-payment cluster to ETH payments
    /// @dev Should be called by P2P only. msg.value is forwarded as the ETH deposit for the migrated cluster.
    /// SSV tokens refunded by SSV remain in the proxy and should be swept via withdrawAllSSVTokensToFactory.
    /// @param _operatorIds SSV operator IDs
    /// @param _cluster SSV cluster to migrate
    function migrateClusterToETH(
        uint64[] calldata _operatorIds,
        ISSVNetwork.Cluster calldata _cluster
    ) external payable;

    /// @notice Withdraw all ETH from this contract to the owner
    /// @dev Should be called by P2P only
    function withdrawEthToOwner() external;

    /// @notice Emits when the P2pSsvProxyFactory address is updated
    /// @param _oldFactory previous factory address
    /// @param _newFactory new factory address
    event P2pSsvProxy__P2pSsvProxyFactorySet(
        address indexed _oldFactory,
        address indexed _newFactory
    );

    /// @notice Update the P2pSsvProxyFactory address for this proxy
    /// @dev Should be called by owner only. Changes the trust boundary for admin/operator resolution.
    /// @param _newFactory new P2pSsvProxyFactory address (must support IP2pSsvProxyFactory interface)
    function setP2pSsvProxyFactory(address _newFactory) external;

    /// @notice Returns the client address
    /// @return address client address
    function getClient() external view returns (address);

    /// @notice Returns the factory address
    /// @return address factory address
    function getFactory() external view returns (address);

    /// @notice Returns the address of FeeDistributor instance accociated with this contract
    /// @return FeeDistributor instance address
    function getFeeDistributor() external view returns (address);
}
