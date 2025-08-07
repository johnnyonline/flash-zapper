# @version 0.4.1

"""
@title crvUSD <--> WBTC18
@license MIT
@author asymmetry.finance
@notice Swaps crvUSD for WBTC18 and vice versa
"""

from ethereum.ercs import IERC20

from ..interfaces import IExchange
from ..interfaces import IWrapper

from ..periphery import curve_tricrypto_swapper as curve_tricrypto
from ..periphery import curve_stableswap_swapper as curve_stableswap


# ============================================================================================
# Interfaces
# ============================================================================================


implements: IExchange


# ============================================================================================
# Constants
# ============================================================================================

# Difference between the wrapped and underlying collateral
DECIMALS_DIFF: constant(uint256) = 10

# TricryptoLLAMA Pool
CRVUSD_INDEX_TRICRYPTO: constant(uint256) = 0
TBTC_INDEX_TRICRYPTO: constant(uint256) = 1
TRICRYPTO_POOL: constant(address) = 0x2889302a794dA87fBF1D6Db415C1492194663D13

# tBTC/WBTC Curve Stable Pool
TBTC_INDEX_TBTC_WBTC_CURVE_POOL: constant(uint256) = 1
WBTC_INDEX_TBTC_WBTC_CURVE_POOL: constant(uint256) = 0
TBTC_WBTC_CURVE_POOL: constant(address) = 0xB7ECB2AA52AA64a717180E030241bC75Cd946726

# Token addresses
CRVUSD: constant(IERC20) = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E)
TBTC: constant(IERC20) = IERC20(0x18084fbA666a33d37592fA2633fD49a74DD93a88)
WBTC: constant(IERC20) = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599)
WBTC18: constant(IWrapper) = IWrapper(0xe065Bc161b90C9C4Bba2de7F1E194b70A3267c47)


# ============================================================================================
# Constructor
# ============================================================================================


@deploy
def __init__():
    """
    @notice Initialize the contract
    """
    self._max_approve(CRVUSD, TRICRYPTO_POOL)
    self._max_approve(TBTC, TRICRYPTO_POOL)
    self._max_approve(WBTC, TBTC_WBTC_CURVE_POOL)
    self._max_approve(TBTC, TBTC_WBTC_CURVE_POOL)
    self._max_approve(WBTC, WBTC18.address)


# ============================================================================================
# View functions
# ============================================================================================


@external
@view
def TOKEN() -> address:
    """
    @notice Returns the address of the token
    @return Address of the token
    """
    return CRVUSD.address


@external
@view
def PAIRED_WITH() -> address:
    """
    @notice Returns the address of the paired with token
    @return Address of the paired token
    """
    return WBTC18.address


# ============================================================================================
# Mutative functions
# ============================================================================================


@external
def swap(amount: uint256, min_amount: uint256, from_token: bool) -> uint256:
    """
    @notice Swaps between crvUSD and the paired token
    @param amount Amount of tokens to swap
    @param min_amount Minimum amount of tokens to receive
    @param from_token If true, swap from crvUSD to the paired token, otherwise swap from the paired token to crvUSD
    @return Amount of tokens received
    """
    return (self.swap_from(amount, min_amount) if from_token else self.swap_to(amount, min_amount))


# ============================================================================================
# Internal functions
# ============================================================================================


def swap_from(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from token to collateral
    @param amount Amount of token to swap
    @param min_amount Minimum amount of collateral to receive
    @return Amount of collateral received
    """
    # Pull crvUSD
    extcall CRVUSD.transferFrom(msg.sender, self, amount, default_return_value=True)

    # crvUSD --> tBTC
    amount_out: uint256 = curve_tricrypto.swap(
        CRVUSD_INDEX_TRICRYPTO,
        TBTC_INDEX_TRICRYPTO,
        amount,
        TRICRYPTO_POOL,
        self,
    )

    # tBTC --> WBTC
    amount_out = curve_stableswap.swap(
        TBTC_INDEX_TBTC_WBTC_CURVE_POOL,
        WBTC_INDEX_TBTC_WBTC_CURVE_POOL,
        amount_out,
        TBTC_WBTC_CURVE_POOL,
        self,
    )

    # WBTC --> WBTC18
    extcall WBTC18.depositFor(msg.sender, amount_out)
    amount_out *= 10**DECIMALS_DIFF

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def swap_to(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from collateral to token
    @param amount Amount of collateral to swap
    @param min_amount Minimum amount of token to receive
    @return Amount of token received
    """
    # Pull WBTC18
    extcall IERC20(WBTC18.address).transferFrom(msg.sender, self, amount, default_return_value=True)

    # WBTC18 --> WBTC
    before: uint256 = staticcall IERC20(WBTC.address).balanceOf(self)
    extcall WBTC18.withdrawTo(self, amount)
    amount_out: uint256 = staticcall IERC20(WBTC.address).balanceOf(self) - before

    # WBTC --> tBTC
    amount_out = curve_stableswap.swap(
        WBTC_INDEX_TBTC_WBTC_CURVE_POOL,
        TBTC_INDEX_TBTC_WBTC_CURVE_POOL,
        amount_out,
        TBTC_WBTC_CURVE_POOL,
        self,
    )

    # tBTC --> crvUSD
    amount_out = curve_tricrypto.swap(
        TBTC_INDEX_TRICRYPTO,
        CRVUSD_INDEX_TRICRYPTO,
        amount_out,
        TRICRYPTO_POOL,
        msg.sender,
    )

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def _max_approve(token: IERC20, spender: address):
    extcall token.approve(spender, max_value(uint256), default_return_value=True)
