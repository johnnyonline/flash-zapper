# @version 0.4.1

"""
@title Ownable 2-step
@license MIT
@author yearn.finance, asymmetry.finance
@notice ownable_2step.vy is a two-step ownable contract that allows for a two-step transfer of ownership
"""


# ============================================================================================
# Events
# ============================================================================================


event PendingOwnershipTransfer:
    old_owner: address
    new_owner: address


event OwnershipTransferred:
    old_owner: address
    new_owner: address


# ============================================================================================
# Storage
# ============================================================================================


owner: public(address)
pending_owner: public(address)


# ============================================================================================
# Constructor
# ============================================================================================


@deploy
def __init__(owner: address):
    """
    @notice Initialize the contract
    @dev Sets the deployer as the initial owner
    @param owner The address of the initial owner
    """
    assert owner != empty(address), "!owner"
    self._transfer_ownership(owner)


# ============================================================================================
# Owner functions
# ============================================================================================


@external
def transfer_ownership(new_owner: address):
    """
    @notice Starts the ownership transfer of the contract to a new account
    @dev Only callable by the current `owner`
    @dev Replaces the pending transfer if there is one
    @param new_owner The address of the new owner
    """
    self._check_owner()
    self.pending_owner = new_owner
    log PendingOwnershipTransfer(old_owner=self.owner, new_owner=new_owner)


@external
def accept_ownership():
    """
    @notice The new owner accepts the ownership transfer
    @dev Only callable by the current `pending_owner`
    """
    assert self.pending_owner == msg.sender, "!new owner"
    self._transfer_ownership(msg.sender)


# ============================================================================================
# Internal functions
# ============================================================================================


def _check_owner():
    assert msg.sender == self.owner, "!owner"


def _transfer_ownership(new_owner: address):
    self.pending_owner = empty(address)
    old_owner: address = self.owner
    self.owner = new_owner
    log OwnershipTransferred(old_owner=old_owner, new_owner=new_owner)
