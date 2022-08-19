// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.16;

import "chiru-labs/ERC721A-Upgradeable/extensions/ERC721AQueryableUpgradeable.sol";
import "chiru-labs/ERC721A-Upgradeable/extensions/ERC721ABurnableUpgradeable.sol";
import "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "solady/utils/SafeTransferLib.sol";
import "../interfaces/ISoundEditionV1.sol";
import "../interfaces/IMetadataModule.sol";
import "openzeppelin-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

/*
                 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒
               ▒███████████████████████████████████████████████████████████
               ▒███████████████████████████████████████████████████████████
 ▒▓▓▓▓▓▓▓▓▓▓▓▓▓████████████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████████████████████████████▓▒▒▒▒▒▒▒▒▒▒▒▒▒
 █████████████████████████████▓              ████████████████████████████████████████████
 █████████████████████████████▓              ████████████████████████████████████████████
 █████████████████████████████▓               ▒▒▒▒▒▒▒▒▒▒▒▒▒██████████████████████████████
 █████████████████████████████▓                            ▒█████████████████████████████
 █████████████████████████████▓                             ▒████████████████████████████
 █████████████████████████████████████████████████████████▓
 ███████████████████████████████████████████████████████████
 ███████████████████████████████████████████████████████████▒
                              ███████████████████████████████████████████████████████████▒
                              ▓██████████████████████████████████████████████████████████▒
                               ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓███████████████████████████████▒
 █████████████████████████████                             ▒█████████████████████████████▒
 ██████████████████████████████                            ▒█████████████████████████████▒
 ██████████████████████████████▓▒▒▒▒▒▒▒▒▒▒▒▒▒              ▒█████████████████████████████▒
 ████████████████████████████████████████████▒             ▒█████████████████████████████▒
 ████████████████████████████████████████████▒             ▒█████████████████████████████▒
 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒███████████████████████████████▓▓▓▓▓▓▓▓▓▓▓▓▓███████████████▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒
               ▓██████████████████████████████████████████████████████████▒
               ▓██████████████████████████████████████████████████████████
*/

/**
 * @title SoundEditionV1
 * @author Sound.xyz
 */
contract SoundEditionV1 is
    ISoundEditionV1,
    ERC721AQueryableUpgradeable,
    ERC721ABurnableUpgradeable,
    OwnableUpgradeable,
    AccessControlEnumerableUpgradeable
{
    // ================================
    // CONSTANTS
    // ================================
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint16 internal constant MAX_BPS = 10_000;
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    // ================================
    // STORAGE
    // ================================

    IMetadataModule public metadataModule;
    string public baseURI;
    string public contractURI;
    bool public isMetadataFrozen;
    address public fundingRecipient;
    uint16 public royaltyBPS;
    uint32 public editionMaxMintable;
    uint32 public randomnessLockedAfterMinted;
    uint32 public randomnessLockedTimestamp;
    bytes32 public mintRandomness;

    // ================================
    // EVENTS
    // ================================

    event MetadataModuleSet(IMetadataModule metadataModule);
    event BaseURISet(string baseURI);
    event ContractURISet(string contractURI);
    event MetadataFrozen(IMetadataModule metadataModule, string baseURI, string contractURI);
    event FundingRecipientSet(address fundingRecipient);
    event RoyaltySet(uint16 royaltyBPS);
    event EditionMaxMintableSet(uint32 newMax);

    // ================================
    // ERRORS
    // ================================

    error MetadataIsFrozen();
    error InvalidRoyaltyBPS();
    error InvalidRandomnessLock();
    error Unauthorized();
    error EditionMaxMintableReached();
    error InvalidAmount();
    error InvalidFundingRecipient();
    error MaximumHasAlreadyBeenReached();

    // ================================
    // PUBLIC & EXTERNAL WRITABLE FUNCTIONS
    // ================================

    /// @inheritdoc ISoundEditionV1
    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        IMetadataModule metadataModule_,
        string memory baseURI_,
        string memory contractURI_,
        address fundingRecipient_,
        uint16 royaltyBPS_,
        uint32 editionMaxMintable_,
        uint32 randomnessLockedAfterMinted_,
        uint32 randomnessLockedTimestamp_
    ) public initializerERC721A initializer onlyValidRoyaltyBPS(royaltyBPS_) {
        __ERC721A_init(name, symbol);
        __ERC721AQueryable_init();
        __Ownable_init();

        metadataModule = metadataModule_;
        baseURI = baseURI_;
        contractURI = contractURI_;

        if (fundingRecipient_ == address(0)) revert InvalidFundingRecipient();
        fundingRecipient = fundingRecipient_;

        royaltyBPS = royaltyBPS_;
        editionMaxMintable = editionMaxMintable_ > 0 ? editionMaxMintable_ : type(uint32).max;
        randomnessLockedAfterMinted = randomnessLockedAfterMinted_;
        randomnessLockedTimestamp = randomnessLockedTimestamp_;

        __AccessControl_init();

        // Set ownership to owner
        transferOwnership(owner);

        // Give owner the DEFAULT_ADMIN_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, owner);

        emit EditionMaxMintableSet(editionMaxMintable);
    }

    /// @inheritdoc ISoundEditionV1
    function mint(address to, uint256 quantity) public payable {
        address caller = _msgSender();
        // Only allow calls if caller has minter role, admin role, or is the owner.
        if (!hasRole(MINTER_ROLE, caller) && !hasRole(ADMIN_ROLE, caller) && caller != owner()) revert Unauthorized();
        // Check if max supply has been reached.
        if (_totalMinted() + quantity > editionMaxMintable) revert EditionMaxMintableReached();
        // Mint the tokens.
        _mint(to, quantity);
        // Set randomness
        if (_totalMinted() <= randomnessLockedAfterMinted && block.timestamp <= randomnessLockedTimestamp) {
            mintRandomness = blockhash(block.number - 1);
        }
    }

    /// @inheritdoc ISoundEditionV1
    function withdrawETH() external {
        SafeTransferLib.safeTransferETH(fundingRecipient, address(this).balance);
    }

    /// @inheritdoc ISoundEditionV1
    function withdrawERC20(address[] calldata tokens) external {
        for (uint256 i; i < tokens.length; ++i) {
            SafeTransferLib.safeTransfer(tokens[i], fundingRecipient, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }

    /// @inheritdoc ISoundEditionV1
    function setMetadataModule(IMetadataModule metadataModule_) external onlyOwnerOrAdmin {
        if (isMetadataFrozen) revert MetadataIsFrozen();
        metadataModule = metadataModule_;

        emit MetadataModuleSet(metadataModule_);
    }

    /// @inheritdoc ISoundEditionV1
    function setBaseURI(string memory baseURI_) external onlyOwnerOrAdmin {
        if (isMetadataFrozen) revert MetadataIsFrozen();
        baseURI = baseURI_;

        emit BaseURISet(baseURI_);
    }

    /// @inheritdoc ISoundEditionV1
    function setContractURI(string memory contractURI_) external onlyOwnerOrAdmin {
        if (isMetadataFrozen) revert MetadataIsFrozen();
        contractURI = contractURI_;

        emit ContractURISet(contractURI_);
    }

    /// @inheritdoc ISoundEditionV1
    function freezeMetadata() external onlyOwnerOrAdmin {
        if (isMetadataFrozen) revert MetadataIsFrozen();

        isMetadataFrozen = true;
        emit MetadataFrozen(metadataModule, baseURI, contractURI);
    }

    /// @inheritdoc ISoundEditionV1
    function setFundingRecipient(address fundingRecipient_) external onlyOwnerOrAdmin {
        if (fundingRecipient_ == address(0)) revert InvalidFundingRecipient();
        fundingRecipient = fundingRecipient_;
        emit FundingRecipientSet(fundingRecipient_);
    }

    /// @inheritdoc ISoundEditionV1
    function setRoyalty(uint16 royaltyBPS_) external onlyOwnerOrAdmin onlyValidRoyaltyBPS(royaltyBPS_) {
        royaltyBPS = royaltyBPS_;
        emit RoyaltySet(royaltyBPS_);
    }

    function reduceEditionMaxMintable(uint32 newMax) external onlyOwnerOrAdmin {
        if (_totalMinted() == editionMaxMintable) {
            revert MaximumHasAlreadyBeenReached();
        }

        // Only allow reducing below current max.
        if (newMax >= editionMaxMintable) {
            revert InvalidAmount();
        }

        // If attempting to set below current total minted, set it to current total.
        // Otherwise, set it to the provided value.
        if (newMax < _totalMinted()) {
            editionMaxMintable = uint32(_totalMinted());
        } else {
            editionMaxMintable = newMax;
        }

        emit EditionMaxMintableSet(editionMaxMintable);
    }

    /// @inheritdoc ISoundEditionV1
    function setMintRandomnessLock(uint32 randomnessLockedAfterMinted_) external onlyOwnerOrAdmin {
        if (randomnessLockedAfterMinted_ < _totalMinted()) revert InvalidRandomnessLock();

        randomnessLockedAfterMinted = randomnessLockedAfterMinted_;
    }

    /// @inheritdoc ISoundEditionV1
    function setRandomnessLockedTimestamp(uint32 randomnessLockedTimestamp_) external onlyOwnerOrAdmin {
        randomnessLockedTimestamp = randomnessLockedTimestamp_;
    }

    // ================================
    // MODIFIERS
    // ================================

    modifier onlyOwnerOrAdmin() {
        if (_msgSender() != owner() && !hasRole(ADMIN_ROLE, _msgSender())) revert Unauthorized();
        _;
    }

    modifier onlyValidRoyaltyBPS(uint16 royalty) {
        if (royalty > MAX_BPS) revert InvalidRoyaltyBPS();
        _;
    }

    // ================================
    // VIEW FUNCTIONS
    // ================================

    /// @inheritdoc ISoundEditionV1
    function totalMinted() external view returns (uint256) {
        return _totalMinted();
    }

    /// @inheritdoc IERC721AUpgradeable
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721AUpgradeable, IERC721AUpgradeable)
        returns (string memory)
    {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        if (address(metadataModule) != address(0)) {
            return metadataModule.tokenURI(tokenId);
        }

        string memory baseURI_ = baseURI;
        return bytes(baseURI_).length != 0 ? string.concat(baseURI_, _toString(tokenId)) : "";
    }

    /// @inheritdoc ISoundEditionV1
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ISoundEditionV1, ERC721AUpgradeable, IERC721AUpgradeable, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return
            ERC721AUpgradeable.supportsInterface(interfaceId) ||
            AccessControlEnumerableUpgradeable.supportsInterface(interfaceId) ||
            interfaceId == _INTERFACE_ID_ERC2981;
    }

    /// @inheritdoc IERC2981Upgradeable
    function royaltyInfo(
        uint256, // tokenId
        uint256 salePrice
    ) external view override(IERC2981Upgradeable) returns (address fundingRecipient_, uint256 royaltyAmount) {
        fundingRecipient_ = fundingRecipient;
        royaltyAmount = (salePrice * royaltyBPS) / MAX_BPS;
    }

    /// @inheritdoc ERC721AUpgradeable
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    /// @inheritdoc ISoundEditionV1
    function getMembersOfRole(bytes32 role) external view returns (address[] memory members) {
        uint256 count = getRoleMemberCount(role);

        members = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            members[i] = getRoleMember(role, i);
        }
    }

    // ================================
    // FALLBACK FUNCTIONS
    // ================================

    /**
     * @dev receive secondary royalties
     */
    receive() external payable {}
}
