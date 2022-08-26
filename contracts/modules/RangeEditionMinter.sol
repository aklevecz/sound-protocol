// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.16;

import { IERC165 } from "openzeppelin/utils/introspection/IERC165.sol";
import { IRangeEditionMinter, EditionMintData, MintInfo } from "./interfaces/IRangeEditionMinter.sol";
import { BaseMinter } from "./BaseMinter.sol";
import { IMinterModule } from "@core/interfaces/IMinterModule.sol";

/*
 * @title RangeEditionMinter
 * @notice Module for range edition mints of Sound editions.
 * @author Sound.xyz
 */
contract RangeEditionMinter is IRangeEditionMinter, BaseMinter {
    /**
     * @dev Edition mint data
     * edition => mintId => EditionMintData
     */
    mapping(address => mapping(uint256 => EditionMintData)) internal _editionMintData;
    /**
     * @dev Number of tokens minted by each buyer address, used to mitigate buyers minting more than maxMintablePerAccount.
     * This is a weak mitigation since buyers can still buy from multiple addresses, but creates more friction than balanceOf.
     * edition => mintId => buyer => mintedTallies
     */
    mapping(address => mapping(uint256 => mapping(address => uint256))) public mintedTallies;

    // ================================
    // MODIFIERS
    // ================================

    /**
     * @dev Restricts the start time to be less than the end time.
     */
    modifier onlyValidRangeTimes(
        uint32 startTime,
        uint32 closingTime,
        uint32 endTime
    ) virtual {
        if (!(startTime < closingTime && closingTime < endTime)) revert InvalidTimeRange();
        _;
    }

    // ================================
    // WRITE FUNCTIONS
    // ================================

    /// @inheritdoc IRangeEditionMinter
    function createEditionMint(
        address edition,
        uint256 price_,
        uint32 startTime,
        uint32 closingTime,
        uint32 endTime,
        uint32 maxMintableLower,
        uint32 maxMintableUpper,
        uint32 maxMintablePerAccount_
    ) public returns (uint256 mintId) {
        if (!(startTime < closingTime && closingTime < endTime)) revert InvalidTimeRange();
        if (!(maxMintableLower < maxMintableUpper)) revert InvalidMaxMintableRange(maxMintableLower, maxMintableUpper);

        mintId = _createEditionMint(edition, startTime, endTime);

        EditionMintData storage data = _editionMintData[edition][mintId];
        data.price = price_;
        data.closingTime = closingTime;
        data.maxMintableLower = maxMintableLower;
        data.maxMintableUpper = maxMintableUpper;
        data.maxMintablePerAccount = maxMintablePerAccount_;

        // prettier-ignore
        emit RangeEditionMintCreated(
            edition,
            mintId,
            price_,
            startTime,
            closingTime,
            endTime,
            maxMintableLower,
            maxMintableUpper,
            maxMintablePerAccount_
        );
    }

    /// @inheritdoc IRangeEditionMinter
    function mint(
        address edition,
        uint256 mintId,
        uint32 quantity,
        address affiliate
    ) public payable {
        EditionMintData storage data = _editionMintData[edition][mintId];

        uint32 _maxMintable = _getMaxMintable(data);

        // Increase `totalMinted` by `quantity`.
        // Require that the increased value does not exceed `maxMintable`.
        uint32 nextTotalMinted = data.totalMinted + quantity;
        _requireNotSoldOut(nextTotalMinted, _maxMintable);
        data.totalMinted = nextTotalMinted;

        uint256 userMintedBalance = mintedTallies[edition][mintId][msg.sender];
        // If the maximum allowed per account is set (i.e. is different to 0)
        // check the required additional quantity does not exceed the set maximum
        if ((userMintedBalance + quantity) > data.maxMintablePerAccount) revert ExceedsMaxPerAccount();

        mintedTallies[edition][mintId][msg.sender] += quantity;

        _mint(edition, mintId, quantity, affiliate);
    }

    /// @inheritdoc IRangeEditionMinter
    function setTimeRange(
        address edition,
        uint256 mintId,
        uint32 startTime,
        uint32 closingTime,
        uint32 endTime
    ) public onlyEditionOwnerOrAdmin(edition) {
        // Set closingTime first, as its stored value gets validated later in the execution.
        EditionMintData storage data = _editionMintData[edition][mintId];
        data.closingTime = closingTime;

        // This calls _beforeSetTimeRange, which does the closingTime validation.
        _setTimeRange(edition, mintId, startTime, endTime);

        emit ClosingTimeSet(edition, mintId, closingTime);
    }

    /// @inheritdoc IRangeEditionMinter
    function setMaxMintableRange(
        address edition,
        uint256 mintId,
        uint32 maxMintableLower,
        uint32 maxMintableUpper
    ) public onlyEditionOwnerOrAdmin(edition) {
        EditionMintData storage data = _editionMintData[edition][mintId];
        data.maxMintableLower = maxMintableLower;
        data.maxMintableUpper = maxMintableUpper;

        if (!(data.maxMintableLower < data.maxMintableUpper))
            revert InvalidMaxMintableRange(data.maxMintableLower, data.maxMintableUpper);

        emit MaxMintableRangeSet(edition, mintId, maxMintableLower, maxMintableUpper);
    }

    // ================================
    // VIEW FUNCTIONS
    // ================================

    /**
     * @dev Returns the `EditionMintData` for `edition.
     * @param edition Address of the song edition contract we are minting for.
     */
    function editionMintData(address edition, uint256 mintId) public view returns (EditionMintData memory) {
        return _editionMintData[edition][mintId];
    }

    function mintInfo(address edition, uint256 mintId) public view returns (MintInfo memory) {
        BaseData memory baseData = super.baseMintData(edition, mintId);
        EditionMintData storage mintData = _editionMintData[edition][mintId];

        uint32 _maxMintable = _getMaxMintable(mintData);

        MintInfo memory combinedMintData = MintInfo(
            baseData.startTime,
            baseData.endTime,
            baseData.mintPaused,
            mintData.price,
            _maxMintable,
            mintData.maxMintablePerAccount,
            mintData.totalMinted,
            mintData.closingTime
        );

        return combinedMintData;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, BaseMinter) returns (bool) {
        return BaseMinter.supportsInterface(interfaceId) || interfaceId == type(IRangeEditionMinter).interfaceId;
    }

    // ================================
    // INTERNAL FUNCTIONS
    // ================================

    /// @inheritdoc BaseMinter
    function _beforeSetTimeRange(
        address edition,
        uint256 mintId,
        uint32 startTime,
        uint32 endTime
    ) internal view override {
        uint32 closingTime = _editionMintData[edition][mintId].closingTime;
        if (!(startTime < closingTime && closingTime < endTime)) revert InvalidTimeRange();
    }

    /**
     * @dev Gets the current maximum mintable quantity.
     */
    function _getMaxMintable(EditionMintData storage data) internal view returns (uint32) {
        uint32 _maxMintable;
        if (block.timestamp < data.closingTime) {
            _maxMintable = data.maxMintableUpper;
        } else {
            _maxMintable = data.maxMintableLower;
        }
        return _maxMintable;
    }

    function _baseTotalPrice(
        address edition,
        uint256 mintId,
        address, /* minter */
        uint32 quantity
    ) internal view virtual override returns (uint256) {
        return _editionMintData[edition][mintId].price * quantity;
    }
}
