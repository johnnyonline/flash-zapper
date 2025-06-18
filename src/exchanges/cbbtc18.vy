# @version 0.4.1

"""
@title cbBTC18 <--> USDaf
@license MIT
@author asymmetry.finance
@notice Swaps cbBTC18 for USDaf and vice versa
"""

from ethereum.ercs import IERC20

from ..interfaces import IExchange
from ..interfaces import IWrapper

from ..periphery import ownable_2step as ownable
from ..periphery import sweep
from ..periphery import curve_stableswap_swapper as curve_stableswap
from ..periphery import curve_tricrypto_swapper as curve_tricrypto


# ============================================================================================
# Modules
# ============================================================================================


initializes: ownable
exports: (
    ownable.owner,
    ownable.pending_owner,
    ownable.transfer_ownership,
    ownable.accept_ownership,
)

initializes: sweep[ownable := ownable]
exports: sweep.sweep_token


# ============================================================================================
# Interfaces
# ============================================================================================


implements: IExchange


# ============================================================================================
# Constants
# ============================================================================================


# Difference between the wrapped and underlying collateral
DECIMALS_DIFF: constant(uint256) = 10

# USDaf/USDC Curve StableNG Pool
USDC_INDEX_USDAF_USDC_CURVE_POOL: constant(uint256) = 1
USDAF_INDEX_USDAF_USDC_CURVE_POOL: constant(uint256) = 0
USDAF_USDC_CURVE_POOL: constant(address) = 0x95591348FE9718bE8bfa3afcC9b017D9Ec18A7fa

# USDC/WBTC/WETH Curve Tricrypto Pool
USDC_INDEX_TRICRYPTO: constant(uint256) = 0
WBTC_INDEX_TRICRYPTO: constant(uint256) = 1
TRICRYPTO_POOL: constant(address) = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B

# cbBTC/WBTC Curve Pool
CBBTC_INDEX_CBBTC_WBTC_CURVE_POOL: constant(uint256) = 0
WBTC_INDEX_CBBTC_WBTC_CURVE_POOL: constant(uint256) = 1
CBBTC_WBTC_CURVE_POOL: constant(address) = 0x839d6bDeDFF886404A6d7a788ef241e4e28F4802

# Token addresses
USDAF: constant(IERC20) = IERC20(0x85E30b8b263bC64d94b827ed450F2EdFEE8579dA)
USDC: constant(IERC20) = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
WBTC: constant(IERC20) = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599)
CBBTC: constant(IERC20) = IERC20(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf)
CBBTC18: constant(IWrapper) = IWrapper(0x7fd713FE57FCD0A7636C152Faba6bDC2D3B27d15)


# ============================================================================================
# Constructor
# ============================================================================================


@deploy
def __init__(owner: address):
    """
    @notice Initialize the contract
    @param owner Address of the owner
    """
    ownable.__init__(owner)

    self._max_approve(USDAF, USDAF_USDC_CURVE_POOL)
    self._max_approve(USDC, USDAF_USDC_CURVE_POOL)
    self._max_approve(USDC, TRICRYPTO_POOL)
    self._max_approve(WBTC, TRICRYPTO_POOL)
    self._max_approve(WBTC, CBBTC_WBTC_CURVE_POOL)
    self._max_approve(CBBTC, CBBTC_WBTC_CURVE_POOL)
    self._max_approve(CBBTC, CBBTC18.address)


# ============================================================================================
# View functions
# ============================================================================================


@external
@view
def BORROW_TOKEN() -> address:
    """
    @notice Returns the address of the borrow token
    @return Address of the borrow token
    """
    return USDAF.address


@external
@view
def COLLATERAL_TOKEN() -> address:
    """
    @notice Returns the address of the collateral token
    @return Address of the collateral token
    """
    return CBBTC18.address


# ============================================================================================
# Mutative functions
# ============================================================================================


@external
def swap(amount: uint256, min_amount: uint256, from_af: bool) -> uint256:
    """
    @notice Swaps between USDaf and collateral
    @param amount Amount of tokens to swap
    @param min_amount Minimum amount of tokens to receive
    @param from_af True if swapping from USDaf to collateral, False if swapping from collateral to USDaf
    @return Amount of tokens received
    """
    return (self._swap_from(amount, min_amount) if from_af else self._swap_to(amount, min_amount))


# ============================================================================================
# Internal functions
# ============================================================================================


def _swap_from(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from USDaf to collateral
    @param amount Amount of USDaf to swap
    @param min_amount Minimum amount of collateral to receive
    @return Amount of collateral received
    """
    # Pull USDaf
    extcall USDAF.transferFrom(msg.sender, self, amount, default_return_value=True)

    # USDaf --> USDC
    amount_out: uint256 = curve_stableswap.swap_underlying(
        USDAF_INDEX_USDAF_USDC_CURVE_POOL,
        USDC_INDEX_USDAF_USDC_CURVE_POOL,
        amount,
        USDAF_USDC_CURVE_POOL,
        self,
    )

    # USDC --> WBTC
    amount_out = curve_tricrypto.swap(USDC_INDEX_TRICRYPTO, WBTC_INDEX_TRICRYPTO, amount_out, TRICRYPTO_POOL)

    # WBTC --> cbBTC
    amount_out = curve_stableswap.swap(
        WBTC_INDEX_CBBTC_WBTC_CURVE_POOL,
        CBBTC_INDEX_CBBTC_WBTC_CURVE_POOL,
        amount_out,
        CBBTC_WBTC_CURVE_POOL,
        self,
    )

    # cbBTC --> cbBTC18
    extcall CBBTC18.depositFor(msg.sender, amount_out)
    amount_out *= 10**DECIMALS_DIFF

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def _swap_to(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from collateral to USDaf
    @param amount Amount of collateral to swap
    @param min_amount Minimum amount of USDaf to receive
    @return Amount of USDaf received
    """
    # Pull cbBTC18
    extcall IERC20(CBBTC18.address).transferFrom(msg.sender, self, amount, default_return_value=True)

    # cbBTC18 --> cbBTC
    extcall CBBTC18.withdrawTo(self, amount)
    amount_out: uint256 = amount // 10**DECIMALS_DIFF

    # cbBTC --> WBTC
    amount_out = curve_stableswap.swap(
        CBBTC_INDEX_CBBTC_WBTC_CURVE_POOL,
        WBTC_INDEX_CBBTC_WBTC_CURVE_POOL,
        amount_out,
        CBBTC_WBTC_CURVE_POOL,
        self,
    )

    # WBTC --> USDC
    amount_out = curve_tricrypto.swap(WBTC_INDEX_TRICRYPTO, USDC_INDEX_TRICRYPTO, amount_out, TRICRYPTO_POOL)

    # USDC --> USDaf
    amount_out = curve_stableswap.swap_underlying(
        USDC_INDEX_USDAF_USDC_CURVE_POOL,
        USDAF_INDEX_USDAF_USDC_CURVE_POOL,
        amount_out,
        USDAF_USDC_CURVE_POOL,
        msg.sender,
    )

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def _max_approve(token: IERC20, spender: address):
    extcall token.approve(spender, max_value(uint256), default_return_value=True)
