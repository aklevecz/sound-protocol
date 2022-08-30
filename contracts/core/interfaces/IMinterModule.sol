// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import { IERC165 } from "openzeppelin/utils/introspection/IERC165.sol";

/**
 * @title IMinterModule
 * @notice The interface for Sound protocol minter modules.
 */
interface IMinterModule is IERC165 {
    // ================================
    // STRUCTS
    // ================================

    struct BaseData {
        uint32 startTime;
        uint32 endTime;
        uint16 affiliateFeeBPS;
        bool mintPaused;
    }

    // ================================
    // EVENTS
    // ================================

    /**
     * @dev Emitted when the mint instance for an `edition` is created.
     * @param edition The edition address.
     * @param mintId The mint ID, to distinguish beteen multiple mints for the same edition.
     * @param startTime The start time of the mint.
     * @param endTime The end time of the mint.
     * @param affiliateFeeBPS The affiliate fee in basis points.
     */
    event MintConfigCreated(
        address indexed edition,
        address indexed creator,
        uint128 mintId,
        uint32 startTime,
        uint32 endTime,
        uint16 affiliateFeeBPS
    );

    /**
     * @dev Emitted when the `paused` status of `edition` is updated.
     * @param edition The edition address.
     * @param mintId The mint ID, to distinguish beteen multiple mints for the same edition.
     * @param paused The new paused status.
     */
    event MintPausedSet(address indexed edition, uint128 mintId, bool paused);

    /**
     * @dev Emitted when the `paused` status of `edition` is updated.
     * @param edition The edition address.
     * @param mintId The mint ID, to distinguish beteen multiple mints for the same edition.
     * @param startTime The start time of the mint.
     * @param endTime The end time of the mint.
     */
    event TimeRangeSet(address indexed edition, uint128 indexed mintId, uint32 startTime, uint32 endTime);

    /**
     * @notice Emitted when the `affiliateFeeBPS` is updated.
     */
    event AffiliateFeeSet(address indexed edition, uint128 indexed mintId, uint16 feeBPS);

    // ================================
    // ERRORS
    // ================================

    /**
     * @dev The Ether value paid is below the value required.
     * @param paid The amount sent to the contract.
     * @param required The amount required to mint.
     */
    error Underpaid(uint256 paid, uint256 required);

    /**
     * @dev The number minted has exceeded the max mintable amount.
     * @param maxMintable The total maximum mintable number of tokens.
     */
    error MaxMintableReached(uint32 maxMintable);

    /**
     * @dev The mint is not opened.
     * @param blockTimestamp The current block timestamp.
     * @param startTime The start time of the mint.
     * @param endTime The end time of the mint.
     */
    error MintNotOpen(uint256 blockTimestamp, uint32 startTime, uint32 endTime);

    /**
     * @dev The mint is paused.
     */
    error MintPaused();

    /**
     * @dev The `startTime` is not less than the `endTime`.
     */
    error InvalidTimeRange();

    /**
     * @dev Unauthorized caller
     */
    error Unauthorized();

    /**
     * @dev The affiliate fee numerator must not exceed `MAX_BPS`.
     */
    error InvalidAffiliateFeeBPS();

    /**
     * @dev Fee registry cannot be the zero address.
     */
    error FeeRegistryIsZeroAddress();

    // ================================
    // WRITE FUNCTIONS
    // ================================

    /**
     * @dev Sets the paused status for (`edition`, `mintId`).
     * Calling conditions:
     * - The caller must be the edition's owner or an admin.
     */
    function setEditionMintPaused(
        address edition,
        uint128 mintId,
        bool paused
    ) external;

    /**
     * @dev Sets the time range for an edition mint.
     * @param edition The edition address.
     * @param mintId The mint ID, to distinguish beteen multiple mints for the same edition.
     * @param startTime The start time of the mint.
     * @param endTime The end time of the mint.
     * Calling conditions:
     * - The caller must be the edition's owner or an admin.
     */
    function setTimeRange(
        address edition,
        uint128 mintId,
        uint32 startTime,
        uint32 endTime
    ) external;

    /**
     * @dev Sets the affiliate fee for (`edition`, `mintId`).
     * Calling conditions:
     * - The caller must be the edition's owner or an admin.
     */
    function setAffiliateFee(
        address edition,
        uint128 mintId,
        uint16 affiliateFeeBPS
    ) external;

    /**
     * @dev Withdraws all the accrued fees for `affiliate`.
     */
    function withdrawForAffiliate(address affiliate) external;

    /**
     * @dev Withdraws all the accrued fees for the platform.
     */
    function withdrawForPlatform() external;

    // ================================
    // VIEW FUNCTIONS
    // ================================

    /**
     * @dev Returns the total fees accrued for `affiliate`.
     */
    function affiliateFeesAccrued(address affiliate) external view returns (uint128);

    /**
     * @dev Returns the total fees accrued for the platform.
     */
    function platformFeesAccrued() external view returns (uint128);

    /**
     * @dev Returns whether `affiliate` is affiliated for (`edition`, `mintId`).
     */
    function isAffiliated(
        address edition,
        uint128 mintId,
        address affiliate
    ) external view returns (bool);

    /**
     * @dev Returns the total price for `quantity` tokens for (`edition`, `mintId`).
     */
    function totalPrice(
        address edition,
        uint128 mintId,
        address minter,
        uint32 quantity
    ) external view returns (uint128);

    /**
     * @dev Returns the next mint ID.
     * A mint ID is assigned sequentially starting from (0, 1, 2, ...),
     * and is shared amongst all editions connected to the minter contract.
     */
    function nextMintId() external view returns (uint128);

    /**
     * Returns child minter interface ID
     * @return interfaceId The child minter interface ID.
     */
    function moduleInterfaceId() external view returns (bytes4);
}
