# @version 0.4.1

"""
@title Sweep
@license MIT
@author asymmetry.finance
@notice sweep.vy sweeps tokens from the contract to the owner
"""

from ethereum.ercs import IERC20

import ownable_2step as ownable


# ============================================================================================
# Modules
# ============================================================================================


uses: ownable


# ============================================================================================
# Events
# ============================================================================================


event Sweep:
    token: address
    amount: uint256
    to: address


# ============================================================================================
# Owner functions
# ============================================================================================


@external
def sweep_token(token: address):
    """
    @notice Sweeps token from the contract
    @dev Only callable by the current `owner` and sweeps to the current `owner`
    @param token The address of the token to sweep. Address(0) for ETH
    """
    ownable._check_owner()

    amount: uint256 = 0
    to: address = ownable.owner
    if token == empty(address):
        amount = self.balance
        assert amount > 0, "!eth amount"
        raw_call(to, b"", value=amount)
    else:
        amount = staticcall IERC20(token).balanceOf(self)
        assert amount > 0, "!amount"
        assert extcall IERC20(token).transfer(to, amount, default_return_value=True)

    log Sweep(token=token, amount=amount, to=to)
