# @version 0.4.1

"""
@title crvUSD <--> ysyBOLD
@license MIT
@author asymmetry.finance
@notice Swaps crvUSD for ysyBOLD and vice versa
"""

from ethereum.ercs import IERC20
from ethereum.ercs import IERC4626

from ..interfaces import IExchange
from ..interfaces import IYearnBoldZapper

from ..periphery import curve_stableswap_swapper as curve_stableswap


# ============================================================================================
# Interfaces
# ============================================================================================


implements: IExchange


# ============================================================================================
# Constants
# ============================================================================================


# USDC/crvUSD Curve StableNG Pool
USDC_INDEX_USDC_CRVUSD_CURVE_POOL: constant(uint256) = 0
CRVUSD_INDEX_USDC_CRVUSD_CURVE_POOL: constant(uint256) = 1
USDC_CRVUSD_CURVE_POOL: constant(address) = 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E

# BOLD/USDC Curve StableNG Pool
BOLD_INDEX_BOLD_USDC_CURVE_POOL: constant(uint256) = 0
USDC_INDEX_BOLD_USDC_CURVE_POOL: constant(uint256) = 1
USDC_BOLD_CURVE_POOL: constant(address) = 0xEFc6516323FbD28e80B85A497B65A86243a54B3E

# Token addresses
USDC: constant(IERC20) = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
CRVUSD: constant(IERC20) = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E)
BOLD: constant(IERC20) = IERC20(0x6440f144b7e50D6a8439336510312d2F54beB01D)
YEARN_STAKED_BOLD: constant(IERC20) = IERC20(0x23346B04a7f55b8760E5860AA5A77383D63491cD)

# Yearn BOLD Zapper
YEARN_BOLD_ZAPPER: constant(IYearnBoldZapper) = IYearnBoldZapper(0xE7099092533A3FB693Bb123cD96B8e53b4d83C58)


# ============================================================================================
# Constructor
# ============================================================================================


@deploy
def __init__():
    """
    @notice Initialize the contract
    """
    self._max_approve(USDC, USDC_CRVUSD_CURVE_POOL)
    self._max_approve(CRVUSD, USDC_CRVUSD_CURVE_POOL)
    self._max_approve(BOLD, USDC_BOLD_CURVE_POOL)
    self._max_approve(USDC, USDC_BOLD_CURVE_POOL)
    self._max_approve(BOLD, YEARN_BOLD_ZAPPER.address)
    self._max_approve(YEARN_STAKED_BOLD, YEARN_BOLD_ZAPPER.address)


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
    return YEARN_STAKED_BOLD.address


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
    return (self._swap_from(amount, min_amount) if from_token else self._swap_to(amount, min_amount))


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
    # Pull crvUSD
    extcall CRVUSD.transferFrom(msg.sender, self, amount, default_return_value=True)

    # crvUSD --> USDC
    amount_out: uint256 = curve_stableswap.swap(
        CRVUSD_INDEX_USDC_CRVUSD_CURVE_POOL,
        USDC_INDEX_USDC_CRVUSD_CURVE_POOL,
        amount,
        USDC_CRVUSD_CURVE_POOL,
        self,
    )

    # USDC --> BOLD
    amount_out = curve_stableswap.swap(
        USDC_INDEX_BOLD_USDC_CURVE_POOL,
        BOLD_INDEX_BOLD_USDC_CURVE_POOL,
        amount_out,
        USDC_BOLD_CURVE_POOL,
        self,
    )

    # BOLD --> st-yBOLD
    amount_out = extcall YEARN_BOLD_ZAPPER.zapIn(amount_out, msg.sender)

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def _swap_to(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from collateral to USDaf
    @param amount Amount of collateral to swap
    @param min_amount Minimum amount of USDaf to receive
    @return Amount of USDaf received
    """
    # Pull st-yBOLD
    extcall YEARN_STAKED_BOLD.transferFrom(msg.sender, self, amount, default_return_value=True)

    # st-yBOLD --> BOLD
    extcall YEARN_BOLD_ZAPPER.zapOut(amount, self, 0)  # maxLoss is 0

    # BOLD --> USDC
    amount_out: uint256 = curve_stableswap.swap(
        BOLD_INDEX_BOLD_USDC_CURVE_POOL,
        USDC_INDEX_BOLD_USDC_CURVE_POOL,
        amount,
        USDC_BOLD_CURVE_POOL,
        self,
    )

    # USDC --> crvUSD
    amount_out = curve_stableswap.swap(
        USDC_INDEX_USDC_CRVUSD_CURVE_POOL,
        CRVUSD_INDEX_USDC_CRVUSD_CURVE_POOL,
        amount_out,
        USDC_CRVUSD_CURVE_POOL,
        msg.sender,
    )

    assert amount_out >= min_amount, "slippage rekt you"

    return amount_out


def _max_approve(token: IERC20, spender: address):
    extcall token.approve(spender, max_value(uint256), default_return_value=True)
