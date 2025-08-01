# @version 0.4.1

"""
@title USDaf Flash Zapper
@license MIT
@author asymmetry.finance
@notice Leverages up and down USDaf positions using a flash loan
"""

from ethereum.ercs import IERC20

from interfaces import IWrapper
from interfaces import IExchange
from interfaces import IERC3156FlashLender
from interfaces import ITroveNFT
from interfaces import IBorrowerOperations
from interfaces import IAddressesRegistry


# ============================================================================================
# Constants
# ============================================================================================


# ERC3156
FLASHLOAN_CALLBACK_SUCCESS: constant(bytes32) = keccak256("ERC3156FlashBorrower.onFlashLoan")
MAX_FLASHLOAN_CALLBACK_DATA_SIZE: constant(uint256) = 10**5

# Selector
SELECTOR_SIZE: constant(uint256) = 4

# Open trove
ENCODED_OPEN_TROVE_ARGS_SIZE: constant(uint256) = 288
OPEN_TROVE_CALLDATA_SIZE: constant(uint256) = (ENCODED_OPEN_TROVE_ARGS_SIZE + SELECTOR_SIZE)

# Lever up
ENCODED_LEVER_UP_ARGS_SIZE: constant(uint256) = 128
LEVER_UP_CALLDATA_SIZE: constant(uint256) = (ENCODED_LEVER_UP_ARGS_SIZE + SELECTOR_SIZE)

# Lever down
ENCODED_LEVER_DOWN_ARGS_SIZE: constant(uint256) = 160
LEVER_DOWN_CALLDATA_SIZE: constant(uint256) = (ENCODED_LEVER_DOWN_ARGS_SIZE + SELECTOR_SIZE)

# WETH gas compensation needed for opening a trove
ETH_GAS_COMPENSATION: constant(uint256) = as_wei_value(0.0375, "ether")

# Decimals difference between the collateral token and the wrapped version
DECIMALS_DIFF: constant(uint256) = 10

# Token addresses
USDAF: public(constant(IERC20)) = IERC20(0x9Cf12ccd6020b6888e4D4C4e4c7AcA33c1eB91f8)
CRVUSD: public(constant(IERC20)) = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E)
WETH: public(constant(IERC20)) = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)

# Flashloan provider (crvUSD FlashLender)
FLASH_LENDER: public(constant(IERC3156FlashLender)) = IERC3156FlashLender(0x26dE7861e213A5351F6ED767d00e0839930e9eE1)

# Trove addresses
UNWRAPPED_COLLATERAL_TOKEN: public(immutable(IERC20))
COLLATERAL_TOKEN: public(immutable(IERC20))
TROVE_NFT: public(immutable(ITroveNFT))
BORROWER_OPERATIONS: public(immutable(IBorrowerOperations))


# ============================================================================================
# Storage
# ============================================================================================


# Exchanges
usdaf_exchange: public(IExchange)
collateral_exchange: public(IExchange)


# ============================================================================================
# Constructor
# ============================================================================================


@deploy
def __init__(
    usdaf_exchange: address,
    collateral_exchange: address,
    addresses_registry: address,
    unwrapped_collateral_token: address,
):
    """
    @notice Initialize the contract
    @param usdaf_exchange Address of the crvUSD/USDaf exchange contract
    @param collateral_exchange Address of the crvUSD/collateral exchange contract
    @param addresses_registry Address of the AddressesRegistry contract
    """
    # Set collateral branch addresses
    _addresses_registry: IAddressesRegistry = IAddressesRegistry(addresses_registry)
    COLLATERAL_TOKEN = IERC20(staticcall _addresses_registry.collToken())
    TROVE_NFT = ITroveNFT(staticcall _addresses_registry.troveNFT())
    BORROWER_OPERATIONS = IBorrowerOperations(staticcall _addresses_registry.borrowerOperations())

    # Set unwrapped collateral token if needed
    if unwrapped_collateral_token != empty(address):
        UNWRAPPED_COLLATERAL_TOKEN = IERC20(unwrapped_collateral_token)
        assert staticcall IWrapper(COLLATERAL_TOKEN.address).underlying() == unwrapped_collateral_token, "!wrapper"
        extcall UNWRAPPED_COLLATERAL_TOKEN.approve(
            COLLATERAL_TOKEN.address, max_value(uint256), default_return_value=True
        )

    self.set_exchange(IExchange(usdaf_exchange), False)
    self.set_exchange(IExchange(collateral_exchange), True)

    # Approve spending to the borrower operations
    extcall WETH.approve(BORROWER_OPERATIONS.address, max_value(uint256), default_return_value=True)
    extcall COLLATERAL_TOKEN.approve(BORROWER_OPERATIONS.address, max_value(uint256), default_return_value=True)


# ============================================================================================
# Open leveraged
# ============================================================================================


@external
def open_leveraged_trove(
    owner: address,
    owner_index: uint256,
    initial_collateral_amount: uint256,
    flash_loan_amount: uint256,
    usdaf_amount: uint256,
    upper_hint: uint256,
    lower_hint: uint256,
    annual_interest_rate: uint256,
    max_upfront_fee: uint256,
):
    """
    @notice Opens a leveraged trove using a flash loan
    @dev Adds this contract as add/receive manager to be able to fully adjust trove
    @param owner Address of the trove owner
    @param owner_index Index of the trove owner in the trove index
    @param initial_collateral_amount Amount of collateral to pull from the user, will be added to the trove
    @param flash_loan_amount Amount of crvUSD to flash loan, will be swapped for collateral
    @param usdaf_amount Amount of USDaf to mint
    @param upper_hint Upper hint for the trove
    @param lower_hint Lower hint for the trove
    @param annual_interest_rate Annual interest rate for the trove
    @param max_upfront_fee Maximum upfront fee to pay for the operation
    """
    # Pull initial collateral and wrap if needed
    collateral_amount: uint256 = initial_collateral_amount
    if UNWRAPPED_COLLATERAL_TOKEN == empty(IERC20):
        extcall COLLATERAL_TOKEN.transferFrom(msg.sender, self, collateral_amount, default_return_value=True)
    else:
        extcall UNWRAPPED_COLLATERAL_TOKEN.transferFrom(msg.sender, self, collateral_amount, default_return_value=True)
        extcall IWrapper(COLLATERAL_TOKEN.address).depositFor(self, collateral_amount, default_return_value=True)
        collateral_amount *= 10**DECIMALS_DIFF

    extcall WETH.transferFrom(msg.sender, self, ETH_GAS_COMPENSATION, default_return_value=True)

    # Cache crvUSD balance before
    before: uint256 = staticcall CRVUSD.balanceOf(self)

    # Prepare calldata for the flash loan
    selector: Bytes[SELECTOR_SIZE] = method_id("on_open_leveraged_trove()")
    encoded_args: Bytes[ENCODED_OPEN_TROVE_ARGS_SIZE] = abi_encode(
        owner,
        owner_index,
        collateral_amount,
        flash_loan_amount,
        usdaf_amount,
        upper_hint,
        lower_hint,
        annual_interest_rate,
        max_upfront_fee,
    )
    data: Bytes[OPEN_TROVE_CALLDATA_SIZE] = concat(selector, encoded_args)

    # Request flash loan
    extcall FLASH_LENDER.flashLoan(self, CRVUSD.address, flash_loan_amount, data)

    # Return leftover crvUSD to the user
    self.return_leftovers(before)


def on_open_leveraged_trove(
    owner: address,
    owner_index: uint256,
    initial_collateral_amount: uint256,
    flash_loan_amount: uint256,
    usdaf_amount: uint256,
    upper_hint: uint256,
    lower_hint: uint256,
    annual_interest_rate: uint256,
    max_upfront_fee: uint256,
):
    """
    @notice Internal function to handle opening a leveraged trove. Called by the flash loan provider
    @dev No need to worry about sandwich, the flash loan provider will revert if the amount returned is not enough
    @param owner Address of the trove owner
    @param owner_index Index of the trove owner in the trove index
    @param initial_collateral_amount Amount of collateral that was pulled from the user
    @param flash_loan_amount Amount of crvUSD to flash loan, will be swapped for collateral
    @param usdaf_amount Amount of USDaf to mint
    @param upper_hint Upper hint for the trove
    @param lower_hint Lower hint for the trove
    @param annual_interest_rate Annual interest rate for the trove
    @param max_upfront_fee Maximum upfront fee to pay for the operation
    """
    # crvUSD --> collateral
    collateral_amount: uint256 = (self.swap(flash_loan_amount, True, True) + initial_collateral_amount)

    # Open trove
    extcall BORROWER_OPERATIONS.openTrove(
        owner,
        owner_index,
        collateral_amount,
        usdaf_amount,
        upper_hint,
        lower_hint,
        annual_interest_rate,
        max_upfront_fee,
        self,  # addManager
        self,  # removeManager
        self,  # receiver
    )

    # USDaf --> crvUSD
    self.swap(usdaf_amount, False, False)


# ============================================================================================
# Lever up
# ============================================================================================


@external
def lever_up_trove(
    trove_id: uint256,
    flash_loan_amount: uint256,
    usdaf_amount: uint256,
    max_upfront_fee: uint256,
):
    """
    @notice Leverages up a trove using a flash loan
    @dev The zapper must be the remove manager and receiver of the trove and the caller must be the owner of it
    @dev Returns leftover crvUSD to the caller
    @param trove_id ID of the trove to leverage up
    @param flash_loan_amount Amount of crvUSD to borrow, will be swapped for collateral
    @param usdaf_amount Amount of USDaf debt to add to the trove
    @param max_upfront_fee Maximum upfront fee to pay for the operation
    """
    # Validate caller and zapper privileges
    self.check_caller_is_owner(trove_id)
    self.check_zapper_is_remove_manager_and_receiver(trove_id)

    # Cache crvUSD balance before
    before: uint256 = staticcall CRVUSD.balanceOf(self)

    # Prepare calldata for the flash loan
    selector: Bytes[SELECTOR_SIZE] = method_id("on_lever_up_trove()")
    encoded_args: Bytes[ENCODED_LEVER_UP_ARGS_SIZE] = abi_encode(
        trove_id, flash_loan_amount, usdaf_amount, max_upfront_fee
    )
    data: Bytes[LEVER_UP_CALLDATA_SIZE] = concat(selector, encoded_args)

    # Request flash loan
    extcall FLASH_LENDER.flashLoan(self, CRVUSD.address, flash_loan_amount, data)

    # Return leftover crvUSD to the user
    self.return_leftovers(before)


def on_lever_up_trove(
    trove_id: uint256,
    flash_loan_amount: uint256,
    usdaf_amount: uint256,
    max_upfront_fee: uint256,
):
    """
    @notice Internal function to handle leveraging up a trove. Called by the flash loan provider
    @dev No need to worry about sandwich, the flash loan provider will revert if the amount returned is not enough
    @param trove_id ID of the trove to leverage up
    @param flash_loan_amount Amount of crvUSD to borrow
    @param usdaf_amount Amount of USDaf to add to the trove
    @param max_upfront_fee Maximum upfront fee to pay for the operation
    """
    # crvUSD --> collateral
    collateral_amount: uint256 = self.swap(flash_loan_amount, True, True)

    # Increase trove collateral and debt
    extcall BORROWER_OPERATIONS.adjustTrove(trove_id, collateral_amount, True, usdaf_amount, True, max_upfront_fee)

    # USDaf --> crvUSD
    self.swap(usdaf_amount, False, False)


# ============================================================================================
# Lever down
# ============================================================================================


@external
def lever_down_trove(
    trove_id: uint256,
    flash_loan_amount: uint256,
    min_usdaf_amount: uint256,
    collateral_amount: uint256,
):
    """
    @notice Leverages down a trove using a flash loan
    @dev The zapper must be the remove manager and receiver of the trove and the caller must be the owner of it
    @param trove_id ID of the trove to leverage down
    @param flash_loan_amount Amount of crvUSD to borrow, will be swapped for USDaf
    @param min_usdaf_amount Minimum amount of USDaf to receive from the swap
    @param collateral_amount Amount of collateral to remove from the trove
    """
    # Validate caller and zapper privileges
    self.check_caller_is_owner(trove_id)
    self.check_zapper_is_remove_manager_and_receiver(trove_id)

    # Cache crvUSD balance before
    before: uint256 = staticcall CRVUSD.balanceOf(self)

    # Prepare calldata for the flash loan
    selector: Bytes[SELECTOR_SIZE] = method_id("on_lever_down_trove()")
    encoded_args: Bytes[ENCODED_LEVER_DOWN_ARGS_SIZE] = abi_encode(
        trove_id, flash_loan_amount, min_usdaf_amount, collateral_amount, msg.sender
    )
    data: Bytes[LEVER_DOWN_CALLDATA_SIZE] = concat(selector, encoded_args)

    # Request flash loan
    extcall FLASH_LENDER.flashLoan(self, CRVUSD.address, flash_loan_amount, data)

    # Return leftover crvUSD to the user
    self.return_leftovers(before)


def on_lever_down_trove(
    trove_id: uint256,
    flash_loan_amount: uint256,
    min_usdaf_amount: uint256,
    collateral_amount: uint256,
    user: address,
):
    """
    @notice Internal function to handle leveraging down a trove. Called by the flash loan provider
    @dev Need to make sure we don't pay more than we want to free the collateral_amount
    @dev Don't need to worry about the second swap, as the flash loan provider will revert if the amount returned is not enough
    @param trove_id ID of the trove to leverage down
    @param flash_loan_amount Amount of crvUSD to borrow
    @param min_usdaf_amount Minimum amount of USDaf to receive from the swap
    @param collateral_amount Amount of collateral to remove from the trove
    @dev user Address of the user to transfer leftover USDaf to
    """
    # Cache USDaf balance before
    before: uint256 = staticcall USDAF.balanceOf(self)

    # crvUSD --> USDaf
    usdaf_amount: uint256 = self.swap(flash_loan_amount, False, True, min_usdaf_amount)

    # Decrease trove collateral and debt
    extcall BORROWER_OPERATIONS.adjustTrove(trove_id, collateral_amount, False, usdaf_amount, False, 0)

    # Collateral --> crvUSD
    self.swap(collateral_amount, True, False)

    # Send leftover USDaf back to the user
    after: uint256 = staticcall USDAF.balanceOf(self)
    if after > before:
        extcall USDAF.transfer(user, after - before, default_return_value=True)


# ============================================================================================
# On flashloan
# ============================================================================================


@external
def onFlashLoan(
    initiator: address,
    token: address,
    amount: uint256,
    fee: uint256,
    data: Bytes[MAX_FLASHLOAN_CALLBACK_DATA_SIZE],
) -> bytes32:
    """
    @notice ERC-3156 Flash loan callback.
    """
    assert msg.sender == FLASH_LENDER.address, "!caller"
    assert initiator == self, "!initiator"
    assert token == CRVUSD.address, "!token"
    assert len(data) > 4, "!data"
    assert staticcall CRVUSD.balanceOf(self) >= amount, "!amount"
    assert fee == 0, "!fee"

    # Decode the calldata and call the appropriate function
    selector: Bytes[SELECTOR_SIZE] = slice(data, 0, SELECTOR_SIZE)
    if selector == method_id("on_lever_up_trove()"):
        trove_id: uint256 = empty(uint256)
        flash_loan_amount: uint256 = empty(uint256)
        usdaf_amount: uint256 = empty(uint256)
        max_upfront_fee: uint256 = empty(uint256)
        (trove_id, flash_loan_amount, usdaf_amount, max_upfront_fee) = abi_decode(
            slice(data, SELECTOR_SIZE, ENCODED_LEVER_UP_ARGS_SIZE), (uint256, uint256, uint256, uint256)
        )
        self.on_lever_up_trove(trove_id, flash_loan_amount, usdaf_amount, max_upfront_fee)
    elif selector == method_id("on_lever_down_trove()"):
        trove_id: uint256 = empty(uint256)
        flash_loan_amount: uint256 = empty(uint256)
        min_usdaf_amount: uint256 = empty(uint256)
        collateral_amount: uint256 = empty(uint256)
        user: address = empty(address)
        (trove_id, flash_loan_amount, min_usdaf_amount, collateral_amount, user) = abi_decode(
            slice(data, SELECTOR_SIZE, ENCODED_LEVER_DOWN_ARGS_SIZE), (uint256, uint256, uint256, uint256, address)
        )
        self.on_lever_down_trove(trove_id, flash_loan_amount, min_usdaf_amount, collateral_amount, user)
    elif selector == method_id("on_open_leveraged_trove()"):
        owner: address = empty(address)
        owner_index: uint256 = empty(uint256)
        initial_collateral_amount: uint256 = empty(uint256)
        flash_loan_amount: uint256 = empty(uint256)
        usdaf_amount: uint256 = empty(uint256)
        upper_hint: uint256 = empty(uint256)
        lower_hint: uint256 = empty(uint256)
        annual_interest_rate: uint256 = empty(uint256)
        max_upfront_fee: uint256 = empty(uint256)

        (
            owner,
            owner_index,
            initial_collateral_amount,
            flash_loan_amount,
            usdaf_amount,
            upper_hint,
            lower_hint,
            annual_interest_rate,
            max_upfront_fee,
        ) = abi_decode(
            slice(data, SELECTOR_SIZE, ENCODED_OPEN_TROVE_ARGS_SIZE),
            (address, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256),
        )

        self.on_open_leveraged_trove(
            owner,
            owner_index,
            initial_collateral_amount,
            flash_loan_amount,
            usdaf_amount,
            upper_hint,
            lower_hint,
            annual_interest_rate,
            max_upfront_fee,
        )
    else:
        raise "!selector"

    extcall CRVUSD.transfer(FLASH_LENDER.address, amount, default_return_value=True)

    return FLASHLOAN_CALLBACK_SUCCESS


# ============================================================================================
# Internal view functions
# ============================================================================================


@view
def check_caller_is_owner(trove_id: uint256):
    """
    @notice Internal view function that checks if the caller is the owner of the trove
    @param trove_id ID of the trove
    """
    assert msg.sender == staticcall TROVE_NFT.ownerOf(trove_id), "caller != owner"


@view
def check_zapper_is_remove_manager_and_receiver(trove_id: uint256):
    """
    @notice Internal view function that checks if the zapper has the necessary privileges to act on a trove
    @param trove_id ID of the trove
    """
    manager: address = empty(address)
    receiver: address = empty(address)
    (manager, receiver) = staticcall BORROWER_OPERATIONS.removeManagerReceiverOf(trove_id)
    assert manager == self, "zapper != manager"
    assert receiver == self, "zapper != receiver"


# ============================================================================================
# Internal mutated functions
# ============================================================================================


def set_exchange(exchange: IExchange, is_collateral: bool):
    """
    @notice Internal function that sets the address of the exchange contract
    @param exchange Address of the exchange contract
    @param is_collateral True for the crvUSD/collateral exchange, False for the crvUSD/USDaf exchange
    """
    # Chcek that the primary token is crvUSD
    assert (staticcall exchange.TOKEN() == CRVUSD.address), "!token"

    # Check that the paired token is either the collateral token or USDaf
    paired_with: IERC20 = IERC20(staticcall exchange.PAIRED_WITH())
    if is_collateral:
        assert (paired_with.address == COLLATERAL_TOKEN.address), "!collateral"
        self.collateral_exchange = exchange
    else:
        assert (paired_with.address == USDAF.address), "!usdaf"
        self.usdaf_exchange = exchange

    extcall CRVUSD.approve(exchange.address, max_value(uint256), default_return_value=True)
    extcall paired_with.approve(exchange.address, max_value(uint256), default_return_value=True)


def swap(amount: uint256, is_collateral: bool, from_crvusd: bool, min_out: uint256 = 0) -> uint256:
    """
    @notice Internal function that swaps between crvUSD and USDaf or the collateral token
    @param amount Amount of tokens to swap
    @param is_collateral True for the crvUSD/collateral exchange, False for the crvUSD/USDaf exchange
    @param from_crvusd True if swapping from crvUSD, False otherwise
    @param min_out Minimum amount of tokens to receive from the swap. Defaults to 0
    @return Amount of tokens received
    """
    return (
        extcall self.collateral_exchange.swap(amount, min_out, from_crvusd)
        if is_collateral
        else extcall self.usdaf_exchange.swap(amount, min_out, from_crvusd)
    )


def return_leftovers(before: uint256):
    """
    @notice Internal function that transfers back any leftover crvUSD to the user
    @param before The crvUSD balance at the beginning of the operation
    """
    after: uint256 = staticcall CRVUSD.balanceOf(self)
    if after > before:
        extcall CRVUSD.transfer(msg.sender, after - before, default_return_value=True)
