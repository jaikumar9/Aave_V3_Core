// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {VersionedInitializable} from '../libraries/aave-upgradeability/VersionedInitializable.sol';
import {Errors} from '../libraries/helpers/Errors.sol';
import {ReserveConfiguration} from '../libraries/configuration/ReserveConfiguration.sol';
import {PoolLogic} from '../libraries/logic/PoolLogic.sol';
import {ReserveLogic} from '../libraries/logic/ReserveLogic.sol';  // this lib we are using in this contract 
import {EModeLogic} from '../libraries/logic/EModeLogic.sol';
import {SupplyLogic} from '../libraries/logic/SupplyLogic.sol';
import {FlashLoanLogic} from '../libraries/logic/FlashLoanLogic.sol';
import {BorrowLogic} from '../libraries/logic/BorrowLogic.sol';
import {LiquidationLogic} from '../libraries/logic/LiquidationLogic.sol';
import {DataTypes} from '../libraries/types/DataTypes.sol';
import {BridgeLogic} from '../libraries/logic/BridgeLogic.sol';
import {IERC20WithPermit} from '../../interfaces/IERC20WithPermit.sol';
import {IPoolAddressesProvider} from '../../interfaces/IPoolAddressesProvider.sol';
import {IPool} from '../../interfaces/IPool.sol';
import {IACLManager} from '../../interfaces/IACLManager.sol';
import {PoolStorage} from './PoolStorage.sol';


/**
 * @title Pool contract
 * @author Aave
 * @notice Main point of interaction with an Aave protocol's market
 * - Users can:
 *   # Supply
 *   # Withdraw
 *   # Borrow
 *   # Repay
 *   # Swap their loans between variable and stable rate
 *   # Enable/disable their supplied assets as collateral rebalance stable rate borrow positions
 *   # Liquidate positions
 *   # Execute Flash Loans
 * @dev To be covered by a proxy contract, owned by the PoolAddressesProvider of the specific market
 * @dev All admin functions are callable by the PoolConfigurator contract defined also in the
 *   PoolAddressesProvider
 */


contract Pool is VersionedInitializable, PoolStorage, IPool  {
  using ReserveLogic for DataTypes.ReserveData;

  uint256 public constant POOL_REVISION = 0x1;
  IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;

/**
   * @dev Only pool configurator can call functions marked by this modifier.
   */
   
   modifier onlyPoolConfigurator() {
    _onlyPoolConfigurator();
    _;
  }

   /**
   * @dev Only pool admin can call functions marked by this modifier.
   */
  modifier onlyPoolAdmin() {
    _onlyPoolAdmin();
    _;
  }
  
/**
   * @dev Only bridge can call functions marked by this modifier.
   */
  modifier onlyBridge() {
    _onlyBridge();
    _;
  }


  function _onlyPoolConfigurator() internal view virtual {
    require(
      ADDRESSES_PROVIDER.getPoolConfigurator() == msg.sender,
      Errors.CALLER_NOT_POOL_CONFIGURATOR
    );
  }
  
  function _onlyPoolAdmin() internal view virtual {
    require(
      IACLManager(ADDRESSES_PROVIDER.getACLManager()).isPoolAdmin(msg.sender),
      Errors.CALLER_NOT_POOL_ADMIN
    );
  }

  function _onlyBridge() internal view virtual {
    require(
      IACLManager(ADDRESSES_PROVIDER.getACLManager()).isBridge(msg.sender),
      Errors.CALLER_NOT_BRIDGE
    );
  }

  function getRevision() internal pure virtual override returns (uint256) {
    return POOL_REVISION;
  }

  /**
   * @dev Constructor.
   * @param provider The address of the PoolAddressesProvider contract
   */

constructor(IPoolAddressesProvider provider) {
    ADDRESSES_PROVIDER = provider;
  }

/**
   * @notice Initializes the Pool.
   * @dev Function is invoked by the proxy contract when the Pool contract is added to the
   * PoolAddressesProvider of the market.
   * @dev Caching the address of the PoolAddressesProvider in order to reduce gas consumption on subsequent operations
   * @param provider The address of the PoolAddressesProvider
   */

  function initialize(IPoolAddressesProvider provider) external virtual initializer {
    require(provider == ADDRESSES_PROVIDER, Errors.INVALID_ADDRESSES_PROVIDER);
    _maxStableRateBorrowSizePercent = 0.25e4;
  }

/// @inheritdoc IPool
  function mintUnbacked(address asset,uint256 amount,address onBehalfOf,uint16 referralCode) external virtual override onlyBridge {
    BridgeLogic.executeMintUnbacked(_reserves,_reservesList,_usersConfig[onBehalfOf],asset,amount,onBehalfOf,referralCode
    );
  }

function backUnbacked(
    address asset,
    uint256 amount,
    uint256 fee
  ) external virtual override onlyBridge returns (uint256) {
    return
      BridgeLogic.executeBackUnbacked(_reserves[asset], asset, amount, fee, _bridgeProtocolFee);
  }

function supply(address asset,uint256 amount,address onBehalfOf,uint16 referralCode) public virtual override {
    SupplyLogic.executeSupply( _reserves,_reservesList, _usersConfig[onBehalfOf],
      DataTypes.ExecuteSupplyParams({asset: asset,amount: amount,onBehalfOf: onBehalfOf,referralCode: referralCode
      })
    );
  }

  function supplyWithPermit(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16 referralCode,
    uint256 deadline,
    uint8 permitV,
    bytes32 permitR,
    bytes32 permitS
  ) public virtual override {
    IERC20WithPermit(asset).permit(
      msg.sender,
      address(this),
      amount,
      deadline,
      permitV,
      permitR,
      permitS
    );
    SupplyLogic.executeSupply(
      _reserves,
      _reservesList,
      _usersConfig[onBehalfOf],
      DataTypes.ExecuteSupplyParams({
        asset: asset,
        amount: amount,
        onBehalfOf: onBehalfOf,
        referralCode: referralCode
      })
    );
  }

/// @inheritdoc IPool

  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) public virtual override returns (uint256) {
    return
      SupplyLogic.executeWithdraw(
        _reserves,
        _reservesList,
        _eModeCategories,
        _usersConfig[msg.sender],
        DataTypes.ExecuteWithdrawParams({
          asset: asset,
          amount: amount,
          to: to,
          reservesCount: _reservesCount,
          oracle: ADDRESSES_PROVIDER.getPriceOracle(),
          userEModeCategory: _usersEModeCategory[msg.sender]
        })
      );
  }



}