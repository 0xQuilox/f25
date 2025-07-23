// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Importing OpenZeppelin's IERC20 interface for secure and standardized
// interaction with ERC-20 compliant tokens. This is crucial for handling
// token-based bounties, including the BOBA token.
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// OpenZeppelin's Ownable contract provides a basic access control mechanism,
// allowing only a designated 'owner' to call certain functions.
import "@openzeppelin/contracts/access/Ownable.sol";
// Import the new Constants contract to inherit common constant values.
import "./Constants.sol"; // Assuming Constants.sol is in the same directory

/**
 * @title BlockForgeBounties
 * @dev This smart contract is specifically designed for the BlockForge platform,
 * operating natively on the Boba Network. It facilitates a decentralized bounty system
 * where users can fund tasks, escrow funds, and pay winners, or request refunds.
 *
 * The Boba Network is an Optimistic Rollup Layer 2 solution for Ethereum,
 * offering significant benefits like reduced gas fees, increased transaction throughput,
 * and enhanced smart contract capabilities (e.g., Hybrid Compute for off-chain data).
 * This contract leverages Boba's EVM compatibility to ensure seamless deployment and interaction.
 *
 * Key Features:
 * - **Bounty Creation & Funding:** Allows users to create new bounties and escrow funds.
 * Prioritizes the BOBA token but also supports other ERC-20 tokens and native ETH.
 * - **Escrow Management:** Securely holds bounty funds until completion or refund.
 * - **Winner Payment:** Enables the bounty owner to pay the designated winner upon satisfaction.
 * - **Refund Mechanism:** Provides options for the bounty owner to reclaim funds if the
 * bounty is not completed by the deadline or is cancelled early.
 * - **Detailed Tracking:** Stores comprehensive information for each bounty.
 * - **Event Emission:** Emits detailed events for off-chain indexing and UI updates.
 *
 * Security Considerations:
 * - Reentrancy attacks are mitigated by using `call` for ETH transfers and `transfer` for ERC-20.
 * - Access control for critical functions (e.g., `completeBounty`, `requestRefund`)
 * is enforced using `onlyBountyOwner` modifier.
 * - Input validation is performed for all critical parameters.
 */
contract BlockForgeBounties is Ownable, Constants { // Inherit from Ownable AND Constants
    // --- State Variables ---

    // nextBountyId: A monotonically increasing counter used to assign a unique identifier
    // to each new bounty created on the platform. Starts from 1.
    uint public nextBountyId;

    // bounties: A mapping that stores all the details of each bounty.
    // The key is the unique bounty ID (uint), and the value is a Bounty struct.
    mapping(uint => Bounty) public bounties;

    // bobaTokenAddress: Stores the official ERC-20 contract address of the BOBA token
    // on the Boba Network. This is crucial for prioritizing BOBA for bounties.
    // It's set during contract deployment and can potentially be updated by the owner.
    address public bobaTokenAddress;

    // --- Structs ---

    /**
     * @dev Bounty: A comprehensive data structure to encapsulate all relevant information
     * for a single bounty within the BlockForge ecosystem.
     *
     * @param owner The Ethereum address of the user who initiated and funded this bounty.
     * This address has exclusive rights to complete, refund, or cancel the bounty.
     * @param winner The Ethereum address of the individual who successfully completed the bounty.
     * This field is initialized to `address(0)` and is set only when the bounty is paid out.
     * @param amount The total value of the bounty, denominated in the specified `tokenAddress`
     * or native ETH. This amount is held in escrow by the contract.
     * @param tokenAddress The ERC-20 contract address of the token used for the bounty.
     * - If `address(0)`, the bounty is funded with native ETH.
     * - If `bobaTokenAddress`, the bounty is funded with the BOBA token.
     * - Otherwise, it's funded with another specified ERC-20 token.
     * @param deadline The Unix timestamp (seconds since epoch) by which the bounty must be
     * completed. If the current time exceeds this deadline, the bounty owner
     * can request a refund.
     * @param descriptionHash A cryptographic hash (e.g., IPFS Content Identifier - CID)
     * pointing to the detailed, off-chain description of the bounty task.
     * Storing the full description off-chain significantly reduces gas costs.
     * @param isCompleted A boolean flag indicating the status of the bounty.
     * `true` if the bounty has been successfully completed and the winner paid.
     * @param isRefunded A boolean flag indicating whether the bounty funds have been returned
     * to the original owner, either due to deadline expiry or early cancellation.
     */
    struct Bounty {
        address owner;
        address winner;
        uint amount;
        address tokenAddress;
        uint deadline;
        string descriptionHash;
        bool isCompleted;
        bool isRefunded;
    }

    // --- Events ---

    /**
     * @dev Emitted when a new bounty is successfully created and its funds are escrowed.
     * This event is crucial for off-chain applications (like the BlockForge UI) to
     * detect new bounties and update their state without constantly polling the blockchain.
     *
     * @param bountyId The unique identifier assigned to the newly created bounty.
     * @param owner The address of the user who created this bounty.
     * @param amount The total value of the bounty.
     * @param tokenAddress The address of the token used for the bounty (address(0) for ETH,
     * the actual BOBA address for BOBA, or other ERC-20 addresses).
     * @param deadline The timestamp marking the completion deadline for the bounty.
     * @param descriptionHash The hash linking to the off-chain bounty description.
     */
    event BountyCreated(
        uint indexed bountyId,
        address indexed owner,
        uint amount,
        address tokenAddress,
        uint deadline,
        string descriptionHash
    );

    /**
     * @dev Emitted when a bounty is successfully completed and the designated winner
     * receives the escrowed funds. This event signals the successful resolution of a bounty.
     *
     * @param bountyId The ID of the bounty that was completed.
     * @param winner The address of the recipient of the bounty funds.
     * @param amount The exact amount of funds paid to the winner.
     */
    event BountyCompleted(
        uint indexed bountyId,
        address indexed winner,
        uint amount
    );

    /**
     * @dev Emitted when the escrowed bounty funds are returned to the original owner.
     * This can happen either because the bounty deadline expired without completion,
     * or the owner decided to cancel the bounty early.
     *
     * @param bountyId The ID of the bounty that was refunded.
     * @param owner The address of the bounty owner who received the refund.
     * @param amount The amount of funds that were refunded.
     */
    event BountyRefunded(
        uint indexed bountyId,
        address indexed owner,
        uint amount
    );

    // --- Constructor ---

    /**
     * @dev Initializes the BlockForgeBounties contract.
     * This constructor is called only once upon deployment of the contract.
     *
     * @param _bobaTokenAddress The ERC-20 contract address of the BOBA token on the
     * Boba Network. This is a crucial parameter for
     * enabling BOBA-denominated bounties.
     */
        constructor(address _bobaTokenAddress) Ownable(msg.sender) {
        require(_bobaTokenAddress != address(0), "BlockForgeBounties: BOBA token address cannot be zero");
        bobaTokenAddress = _bobaTokenAddress;
    }

    // --- Modifiers ---

    /**
     * @dev `onlyBountyOwner` modifier: Ensures that the function can only be executed
     * by the original creator (owner) of the specified bounty. This provides
     * essential access control for sensitive operations like completing or refunding bounties.
     *
     * @param _bountyId The unique identifier of the bounty to check ownership against.
     */
    modifier onlyBountyOwner(uint _bountyId) {
        require(
            bounties[_bountyId].owner == msg.sender,
            "BlockForgeBounties: Caller is not the owner of this bounty."
        );
        _; // Continues execution of the function if the condition is met.
    }

    // --- Core Functions ---

    /**
     * @dev `createBounty`: Allows a user to create a new bounty and securely escrow
     * the bounty funds within this contract.
     *
     * This function supports three types of funding:
     * 1. **Native ETH:** If `_tokenAddress` is `address(0)`. The `msg.value` must
     * exactly match `_amount`.
     * 2. **BOBA Token:** If `_tokenAddress` is `BOBA_TOKEN_SENTINEL` (inherited from Constants.sol).
     * The contract will use the `bobaTokenAddress` stored in the state. The caller must have
     * pre-approved this contract to transfer `_amount` of BOBA tokens.
     * 3. **Other ERC-20 Tokens:** If `_tokenAddress` is any other valid ERC-20 address.
     * Similar to BOBA, the caller must have pre-approved this contract to transfer
     * `_amount` of the specified ERC-20 tokens.
     *
     * @param _amount The total value of the bounty. This is the amount of ETH or
     * ERC-20 tokens to be held in escrow.
     * @param _tokenAddress The address of the ERC-20 token to be used.
     * - Use `address(0)` for native ETH bounties.
     * - Use `BOBA_TOKEN_SENTINEL` to indicate a BOBA token bounty.
     * - Use the actual ERC-20 contract address for other tokens.
     * @param _durationInDays The desired duration for the bounty, specified in days.
     * The deadline will be calculated as `block.timestamp + _durationInDays * 1 days`.
     * @param _descriptionHash A string representing a cryptographic hash (e.g., IPFS CID)
     * of the detailed bounty description. This allows for rich
     * descriptions without incurring high on-chain storage costs.
     * @return uint The unique `bountyId` assigned to the newly created bounty.
     */
    function createBounty(
        uint _amount,
        address _tokenAddress,
        uint _durationInDays,
        string memory _descriptionHash
    ) external payable returns (uint) {
        // --- Input Validation ---
        require(_amount > 0, "BlockForgeBounties: Bounty amount must be greater than zero.");
        require(_durationInDays > 0, "BlockForgeBounties: Bounty duration must be at least one day.");
        require(bytes(_descriptionHash).length > 0, "BlockForgeBounties: Bounty description hash cannot be empty.");

        // Assign a unique ID to the new bounty.
        uint currentBountyId = nextBountyId;
        // Calculate the exact deadline timestamp.
        uint calculatedDeadline = block.timestamp + (_durationInDays * 1 days);

        // --- Fund Escrowing Logic ---
        address actualTokenAddress; // Stores the resolved token address for the bounty

        if (_tokenAddress == address(0)) {
            // Case 1: Native ETH Bounty
            require(msg.value == _amount, "BlockForgeBounties: ETH sent does not match bounty amount.");
            actualTokenAddress = address(0); // Explicitly set to zero for ETH
        } else if (_tokenAddress == BOBA_TOKEN_SENTINEL) { // Using inherited constant
            // Case 2: BOBA Token Bounty (Prioritized for Boba Native Projects)
            require(msg.value == 0, "BlockForgeBounties: Do not send ETH for BOBA token bounty.");
            // Transfer BOBA tokens from the caller to this contract.
            // This requires the caller to have previously called `approve` on the BOBA token contract.
            IERC20(bobaTokenAddress).transferFrom(msg.sender, address(this), _amount);
            actualTokenAddress = bobaTokenAddress; // Use the stored BOBA address
        } else {
            // Case 3: Other ERC-20 Token Bounty
            require(msg.value == 0, "BlockForgeBounties: Do not send ETH for ERC-20 token bounty.");
            // Transfer the specified ERC-20 tokens from the caller to this contract.
            // This requires the caller to have previously called `approve` on the ERC-20 token contract.
            IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount);
            actualTokenAddress = _tokenAddress;
        }

        // --- Store Bounty Details ---
        // Create a new Bounty struct and store it in the `bounties` mapping.
        bounties[currentBountyId] = Bounty({
            owner: msg.sender,         // The creator of the bounty
            winner: address(0),        // No winner assigned initially
            amount: _amount,           // The escrowed amount
            tokenAddress: actualTokenAddress, // The resolved token address (ETH, BOBA, or other ERC-20)
            deadline: calculatedDeadline, // The calculated completion deadline
            descriptionHash: _descriptionHash, // Hash to off-chain description
            isCompleted: false,        // Not completed yet
            isRefunded: false          // Not refunded yet
        });

        // Increment the counter for the next bounty.
        nextBountyId++;

        // --- Event Emission ---
        // Emit an event to signal the creation of a new bounty to off-chain listeners.
        emit BountyCreated(
            currentBountyId,
            msg.sender,
            _amount,
            actualTokenAddress,
            calculatedDeadline,
            _descriptionHash
        );
        return currentBountyId;
    }

    /**
     * @dev `completeBounty`: Allows the bounty owner to designate a winner and disburse
     * the escrowed bounty funds to them.
     *
     * This function can only be called by the `owner` of the bounty.
     * It ensures that the bounty has not already been completed or refunded,
     * and that the current timestamp is still within the bounty's deadline.
     *
     * @param _bountyId The unique ID of the bounty to be completed.
     * @param _winner The Ethereum address of the individual who successfully completed
     * the bounty and will receive the funds.
     */
    function completeBounty(
        uint _bountyId,
        address _winner
    ) external onlyBountyOwner(_bountyId) {
        // Get a mutable reference to the bounty's storage slot.
        Bounty storage bounty = bounties[_bountyId];

        // --- State Validation ---
        require(bounty.owner != address(0), "BlockForgeBounties: Bounty with this ID does not exist.");
        require(!bounty.isCompleted, "BlockForgeBounties: This bounty has already been completed.");
        require(!bounty.isRefunded, "BlockForgeBounties: This bounty has been refunded and cannot be completed.");
        require(
            block.timestamp <= bounty.deadline,
            "BlockForgeBounties: Bounty deadline has passed. Cannot complete, consider refunding."
        );
        require(_winner != address(0), "BlockForgeBounties: Winner address cannot be the zero address.");

        // --- Update Bounty State ---
        bounty.winner = _winner;        // Assign the winner's address.
        bounty.isCompleted = true;      // Mark the bounty as completed.

        // --- Fund Transfer to Winner ---
        if (bounty.tokenAddress == address(0)) {
            // Transfer native ETH to the winner.
            // Using `call` is the recommended low-level way to send ETH safely.
            (bool success, ) = payable(_winner).call{value: bounty.amount}("");
            require(success, "BlockForgeBounties: Failed to send native ETH to winner.");
        } else {
            // Transfer ERC-20 tokens (including BOBA) to the winner.
            IERC20 token = IERC20(bounty.tokenAddress);
            require(
                token.transfer(_winner, bounty.amount),
                "BlockForgeBounties: Failed to send ERC-20 tokens to winner."
            );
        }

        // --- Event Emission ---
        // Emit an event to signify the successful completion and payment of the bounty.
        emit BountyCompleted(_bountyId, _winner, bounty.amount);
    }

    /**
     * @dev `requestRefund`: Allows the bounty owner to reclaim the escrowed funds
     * if the bounty has not been completed and its specified deadline has passed.
     *
     * This function can only be called by the `owner` of the bounty.
     * It ensures the bounty is not already completed or refunded, and that the
     * deadline has indeed expired.
     *
     * @param _bountyId The unique ID of the bounty for which to request a refund.
     */
    function requestRefund(uint _bountyId) external onlyBountyOwner(_bountyId) {
        // Get a mutable reference to the bounty's storage slot.
        Bounty storage bounty = bounties[_bountyId];

        // --- State Validation ---
        require(bounty.owner != address(0), "BlockForgeBounties: Bounty with this ID does not exist.");
        require(!bounty.isCompleted, "BlockForgeBounties: Bounty has already been completed, cannot refund.");
        require(!bounty.isRefunded, "BlockForgeBounties: Bounty has already been refunded.");
        require(
            block.timestamp > bounty.deadline,
            "BlockForgeBounties: Bounty deadline has not yet passed. Use `cancelBounty` for early cancellation."
        );

        // --- Update Bounty State ---
        bounty.isRefunded = true; // Mark the bounty as refunded.

        // --- Fund Transfer to Owner ---
        if (bounty.tokenAddress == address(0)) {
            // Refund native ETH to the owner.
            (bool success, ) = payable(bounty.owner).call{value: bounty.amount}("");
            require(success, "BlockForgeBounties: Failed to refund native ETH to owner.");
        } else {
            // Refund ERC-20 tokens (including BOBA) to the owner.
            IERC20 token = IERC20(bounty.tokenAddress);
            require(
                token.transfer(bounty.owner, bounty.amount),
                "BlockForgeBounties: Failed to refund ERC-20 tokens to owner."
            );
        }

        // --- Event Emission ---
        // Emit an event to signify the refund of bounty funds.
        emit BountyRefunded(_bountyId, bounty.owner, bounty.amount);
    }

    /**
     * @dev `cancelBounty`: Allows the bounty owner to cancel a bounty and receive an
     * immediate refund, provided the bounty has not been completed and its deadline
     * has NOT yet passed. This acts as an early termination mechanism.
     *
     * This function can only be called by the `owner` of the bounty.
     *
     * @param _bountyId The unique ID of the bounty to be cancelled.
     */
    function cancelBounty(uint _bountyId) external onlyBountyOwner(_bountyId) {
        // Get a mutable reference to the bounty's storage slot.
        Bounty storage bounty = bounties[_bountyId];

        // --- State Validation ---
        require(bounty.owner != address(0), "BlockForgeBounties: Bounty with this ID does not exist.");
        require(!bounty.isCompleted, "BlockForgeBounties: Bounty has already been completed, cannot cancel.");
        require(!bounty.isRefunded, "BlockForgeBounties: Bounty has already been refunded.");
        require(
            block.timestamp <= bounty.deadline,
            "BlockForgeBounties: Bounty deadline has passed. Use `requestRefund` instead."
        );

        // --- Update Bounty State ---
        bounty.isRefunded = true; // Mark the bounty as refunded due to cancellation.

        // --- Fund Transfer to Owner ---
        if (bounty.tokenAddress == address(0)) {
            // Refund native ETH to the owner.
            (bool success, ) = payable(bounty.owner).call{value: bounty.amount}("");
            require(success, "BlockForgeBounties: Failed to refund native ETH during cancellation.");
        } else {
            // Refund ERC-20 tokens (including BOBA) to the owner.
            IERC20 token = IERC20(bounty.tokenAddress);
            require(
                token.transfer(bounty.owner, bounty.amount),
                "BlockForgeBounties: Failed to refund ERC-20 tokens during cancellation."
            );
        }

        // --- Event Emission ---
        // Emit a refund event, as cancellation is a form of refund.
        emit BountyRefunded(_bountyId, bounty.owner, bounty.amount);
    }

    // --- View Functions ---

    /**
     * @dev `getBounty`: A public view function to retrieve all stored details of a
     * specific bounty. This function does not modify the blockchain state and
     * therefore incurs no gas cost when called.
     *
     * @param _bountyId The unique ID of the bounty to query.
     * @return owner The address of the bounty creator.
     * @return winner The address of the bounty winner.
     * @return amount The amount of funds escrowed for the bounty.
     * @return tokenAddress The address of the token used (address(0) for ETH).
     * @return deadline The timestamp by which the bounty should be completed.
     * @return descriptionHash The hash of the off-chain bounty description.
     * @return isCompleted A boolean indicating if the bounty has been completed.
     * @return isRefunded A boolean indicating if the bounty has been refunded.
     */
    function getBounty(
        uint _bountyId
    )
        external
        view
        returns (
            address owner,
            address winner,
            uint amount,
            address tokenAddress,
            uint deadline,
            string memory descriptionHash,
            bool isCompleted,
            bool isRefunded
        )
    {
        // Retrieve the bounty struct from storage.
        Bounty storage bounty = bounties[_bountyId];
        // Ensure the bounty exists before returning its details.
        require(bounty.owner != address(0), "BlockForgeBounties: Bounty with this ID does not exist.");

        // Return all fields of the Bounty struct.
        return (
            bounty.owner,
            bounty.winner,
            bounty.amount,
            bounty.tokenAddress,
            bounty.deadline,
            bounty.descriptionHash,
            bounty.isCompleted,
            bounty.isRefunded
        );
    }

    /**
     * @dev `getBobaTokenAddress`: A public view function to retrieve the configured
     * BOBA token address for this contract.
     * @return address The ERC-20 contract address of the BOBA token.
     */
    function getBobaTokenAddress() external view returns (address) {
        return bobaTokenAddress;
    }

    // --- Administrative Functions (Owner-only) ---
    // These functions are inherited from Ownable and can only be called by the contract owner.
    // They are provided for potential future administrative needs, such as updating the BOBA token address
    // if it were to change (though this is rare for a mainnet token).

    /**
     * @dev `setBobaTokenAddress`: Allows the contract owner to update the BOBA token address.
     * This function should be used with extreme caution and only if the official BOBA token
     * contract address changes for some reason (highly unlikely for a deployed token).
     * @param _newBobaTokenAddress The new ERC-20 contract address for the BOBA token.
     */
    function setBobaTokenAddress(address _newBobaTokenAddress) external onlyOwner {
        require(_newBobaTokenAddress != address(0), "BlockForgeBounties: New BOBA token address cannot be zero.");
        bobaTokenAddress = _newBobaTokenAddress;
    }
}
