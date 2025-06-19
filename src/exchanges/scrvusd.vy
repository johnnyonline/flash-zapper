# @version 0.4.1

"""
@title crvUSD <--> scrvUSD
@license MIT
@author asymmetry.finance
@notice Swaps crvUSD for scrvUSD and vice versa
"""

from ethereum.ercs import IERC20
from ethereum.ercs import IERC4626

from ..interfaces import IExchange

from ..periphery import ownable_2step as ownable
from ..periphery import sweep


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


# Token addresses
CRVUSD: constant(IERC20) = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E)
SCRVUSD: constant(IERC4626) = IERC4626(0x0655977FEb2f289A4aB78af67BAB0d17aAb84367)


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
    self._max_approve(CRVUSD, SCRVUSD.address)


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
    return SCRVUSD.address


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
    extcall CRVUSD.transferFrom(msg.sender, self, amount, default_return_value=True)
    amount_out: uint256 = extcall SCRVUSD.deposit(amount, msg.sender)
    assert amount_out >= min_amount, "slippage rekt you"
    return amount_out


def _swap_to(amount: uint256, min_amount: uint256) -> uint256:
    """
    @notice Swaps from collateral to USDaf
    @param amount Amount of collateral to swap
    @param min_amount Minimum amount of USDaf to receive
    @return Amount of USDaf received
    """
    amount_out: uint256 = extcall SCRVUSD.redeem(amount, msg.sender, msg.sender)
    assert amount_out >= min_amount, "slippage rekt you"
    return amount_out


def _max_approve(token: IERC20, spender: address):
    extcall token.approve(spender, max_value(uint256), default_return_value=True)
