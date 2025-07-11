# @version 0.4.1

"""
@title CurveTricryptoOptimizedWETH Swapper
@license MIT
@author asymmetry.finance
@notice curve_tricrypto_swapper.vy swaps tokens on a Curve TricryptoOptimizedWETH pool
"""

from ..interfaces import ICurveTricrypto


# ============================================================================================
# Internal functions
# ============================================================================================


def swap(
    from_index: uint256,
    to_index: uint256,
    amount_in: uint256,
    pool: address,
    receiver: address,
) -> uint256:
    """
    @notice Swaps tokens on a Curve StableNG pool
    @param from_index Index of the token to swap from
    @param to_index Index of the token to swap to
    @param amount_in Amount of the token to swap
    @param pool Address of the Curve StableNG pool
    @param receiver Address that will receive the swapped tokens
    @return Amount of the token received after the swap
    """
    return extcall ICurveTricrypto(pool).exchange(
        from_index,
        to_index,
        amount_in,
        0,  # min_amount_out
        False,  # use_eth
        receiver,
    )
