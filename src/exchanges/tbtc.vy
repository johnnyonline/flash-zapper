# @version 0.4.1

"""
@title crvUSD <--> tBTC
@license MIT
@author asymmetry.finance
@notice Swaps crvUSD for tBTC and vice versa
"""

from ethereum.ercs import IERC20

from ..interfaces import IExchange

from ..periphery import curve_tricrypto_swapper as curve_tricrypto


# ============================================================================================
# Interfaces
# ============================================================================================


implements: IExchange


# ============================================================================================
# Constants
# ============================================================================================


# TricryptoLLAMA Pool
CRVUSD_INDEX_TRICRYPTO: constant(uint256) = 0
TBTC_INDEX_TRICRYPTO: constant(uint256) = 1
TRICRYPTO_POOL: constant(address) = 0x2889302a794dA87fBF1D6Db415C1492194663D13

# Token addresses
CRVUSD: constant(IERC20) = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E)
TBTC: constant(IERC20) = IERC20(0x18084fbA666a33d37592fA2633fD49a74DD93a88)


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
    return TBTC.address


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
        msg.sender,
    )

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def swap_to(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from collateral to token
    @param amount Amount of collateral to swap
    @param min_amount Minimum amount of token to receive
    @return Amount of token received
    """
    # Pull tBTC
    extcall TBTC.transferFrom(msg.sender, self, amount, default_return_value=True)

    # tBTC --> crvUSD
    amount_out: uint256 = curve_tricrypto.swap(
        TBTC_INDEX_TRICRYPTO,
        CRVUSD_INDEX_TRICRYPTO,
        amount,
        TRICRYPTO_POOL,
        msg.sender,
    )

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def _max_approve(token: IERC20, spender: address):
    extcall token.approve(spender, max_value(uint256), default_return_value=True)
