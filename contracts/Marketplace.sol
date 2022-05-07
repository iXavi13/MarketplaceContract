//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./SafeERC20B.sol";

contract Turtlesea is Ownable, ReentrancyGuard {
    using SafeERC20B for IERC20B;

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant INTERFACE_ID_ERC1155 = 0xd9b67a26;
    uint256 public constant BASIS_POINTS = 10000;

    address public paymentToken;

    uint256 public fee;
    address public feeReceipient;

    bool public marketActive;

    struct Listing {
        uint256 quantity;
        uint256 pricePerItem;
        uint256 expirationDate;
        uint256 blockNumber;
    }

    //  _collectionAddress => _tokenId => _owner
    mapping(address => mapping(uint256 => mapping(address => Listing))) public listings;

    event UpdateFee(uint256 fee);
    event UpdateFeeRecipient(address feeRecipient);
    event UpdatePaymentToken(address paymentToken);

    event ItemListed(
        address seller,
        address nftAddress,
        uint256 tokenId,
        uint256 quantity,
        uint256 pricePerItem,
        uint256 expirationDate
    );

    event ItemUpdated(
        address seller,
        address nftAddress,
        uint256 tokenId,
        uint256 quantity,
        uint256 pricePerItem,
        uint256 expirationDate
    );

    event ItemSold(
        address seller,
        address buyer,
        address nftAddress,
        uint256 tokenId,
        uint256 quantity,
        uint256 pricePerItem
    );

    event ItemCanceled(address seller, address nftAddress, uint256 tokenId);

    modifier isListed(
        address _collectionAddress,
        uint256 _tokenId,
        address _owner
    ) {
        Listing memory listing = listings[_collectionAddress][_tokenId][_owner];
        require(listing.quantity > 0, "not listed item");
        _;
    }

    modifier validListing(
        address _collectionAddress,
        uint256 _tokenId,
        address _owner
    ) {
        Listing memory listedItem = listings[_collectionAddress][_tokenId][_owner];
        if (IERC165(_collectionAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_collectionAddress);
            require(nft.ownerOf(_tokenId) == _owner, "not owning item");
        } else if (IERC165(_collectionAddress).supportsInterface(INTERFACE_ID_ERC1155)) {
            IERC1155 nft = IERC1155(_collectionAddress);
            require(nft.balanceOf(_owner, _tokenId) >= listedItem.quantity, "not owning item");
        } else {
            revert("invalid nft address");
        }
        require(listedItem.expirationDate >= block.timestamp, "listing expired");
        _;
    }

    constructor() {
        setPaymentToken(0xCB5df23bfe0367f340Ce6dfa84e6Db949D5Fb4F5); 
    }

    function createListing(
        address _collectionAddress,
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _pricePerItem,
        uint256 _expirationDate
    ) external onlyOwner {
        require(marketActive, "Market is not live");
        require(listings[_collectionAddress][_tokenId][_msgSender()].quantity == 0, "already listed");
        if (_expirationDate == 0) _expirationDate = type(uint256).max;
        require(_expirationDate > block.timestamp, "invalid expiration time");
        require(_quantity > 0, "nothing to list");

        if (IERC165(_collectionAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_collectionAddress);
            require(nft.ownerOf(_tokenId) == _msgSender(), "not owning item");
            require(_quantity == 1, "ERC721 is not fungible");
            require(nft.isApprovedForAll(_msgSender(), address(this)), "item not approved");
        } else if (IERC165(_collectionAddress).supportsInterface(INTERFACE_ID_ERC1155)) {
            IERC1155 nft = IERC1155(_collectionAddress);
            require(nft.balanceOf(_msgSender(), _tokenId) >= _quantity, "must hold enough nfts");
            require(nft.isApprovedForAll(_msgSender(), address(this)), "item not approved");
        } else {
            revert("invalid nft address");
        }

        listings[_collectionAddress][_tokenId][_msgSender()] = Listing(
            _quantity,
            _pricePerItem,
            _expirationDate,
            block.number
        );

        emit ItemListed(
            _msgSender(),
            _collectionAddress,
            _tokenId,
            _quantity,
            _pricePerItem,
            _expirationDate
        );
    }

    function updateListing(
        address _collectionAddress,
        uint256 _tokenId,
        uint256 _newQuantity,
        uint256 _newPricePerItem,
        uint256 _newExpirationDate
    ) external nonReentrant isListed(_collectionAddress, _tokenId, _msgSender()) {
        require(_newExpirationDate > block.timestamp, "invalid expiration time");

        Listing storage listedItem = listings[_collectionAddress][_tokenId][_msgSender()];
        if (IERC165(_collectionAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_collectionAddress);
            require(nft.ownerOf(_tokenId) == _msgSender(), "not owning item");
        } else if (IERC165(_collectionAddress).supportsInterface(INTERFACE_ID_ERC1155)) {
            IERC1155 nft = IERC1155(_collectionAddress);
            require(nft.balanceOf(_msgSender(), _tokenId) >= _newQuantity, "must hold enough nfts");
        } else {
            revert("invalid nft address");
        }

        //Check if message sender is origin and owner of token

        listedItem.quantity = _newQuantity;
        listedItem.pricePerItem = _newPricePerItem;
        listedItem.expirationDate = _newExpirationDate;
        listedItem.blockNumber = block.number;

        emit ItemUpdated(
            _msgSender(),
            _collectionAddress,
            _tokenId,
            _newQuantity,
            _newPricePerItem,
            _newExpirationDate
        );
    }

    function cancelListing(address _collectionAddress, uint256 _tokenId)
        external
        nonReentrant
        isListed(_collectionAddress, _tokenId, _msgSender())
    {
        _cancelListing(_collectionAddress, _tokenId, _msgSender());
    }

    function _cancelListing(
        address _collectionAddress,
        uint256 _tokenId,
        address _owner
    ) internal {
        Listing memory listedItem = listings[_collectionAddress][_tokenId][_owner];
        if (IERC165(_collectionAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_collectionAddress);
            require(nft.ownerOf(_tokenId) == _owner, "not owning item");
        } else if (IERC165(_collectionAddress).supportsInterface(INTERFACE_ID_ERC1155)) {
            IERC1155 nft = IERC1155(_collectionAddress);
            require(nft.balanceOf(_msgSender(), _tokenId) >= listedItem.quantity, "not owning item");
        } else {
            revert("invalid nft address");
        }

        delete (listings[_collectionAddress][_tokenId][_owner]);
        emit ItemCanceled(_owner, _collectionAddress, _tokenId);
    }

    function buyItem(
        address _collectionAddress,
        uint256 _tokenId,
        address _owner,
        uint256 _quantity
    )
        external
        nonReentrant
        isListed(_collectionAddress, _tokenId, _owner)
        validListing(_collectionAddress, _tokenId, _owner)
    {
        require(marketActive, "Market is not live");
        require(_quantity > 0, "Cannot buy 0");
        require(_msgSender() != _owner, "Cannot buy your own item");

        Listing memory listedItem = listings[_collectionAddress][_tokenId][_owner];
        require(listedItem.quantity >= _quantity, "not enough quantity");
        require(listedItem.blockNumber < block.number, "Cannot buy in same block the listing is set");

        // Transfer NFT to buyer
        if (IERC165(_collectionAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721(_collectionAddress).safeTransferFrom(_owner, _msgSender(), _tokenId);
        } else {
            IERC1155(_collectionAddress).safeTransferFrom(_owner, _msgSender(), _tokenId, _quantity, bytes(""));
        }

        if (listedItem.quantity == _quantity) {
            delete (listings[_collectionAddress][_tokenId][_owner]);
        } else {
            listings[_collectionAddress][_tokenId][_owner].quantity -= _quantity;
        }

        emit ItemSold(
            _owner,
            _msgSender(),
            _collectionAddress,
            _tokenId,
            _quantity,
            listedItem.pricePerItem
        );

        //BytPriceDictionary(transactionDictionary).reportSale(_collectionAddress, _tokenId, paymentToken, listedItem.pricePerItem);
        _buyItem(listedItem.pricePerItem, _quantity);
    }

    function _buyItem(
        uint256 _pricePerItem,
        uint256 _quantity
    ) internal {
        uint256 totalPrice = _pricePerItem * _quantity;
        IERC20B(paymentToken).safeBurnFrom(_msgSender(), totalPrice);
    }

    // Admin Functions

    function setMarketActive() external onlyOwner {
        marketActive = !marketActive;
    }

    function setPaymentToken(address _paymentToken) public onlyOwner {
        paymentToken = _paymentToken;
        emit UpdatePaymentToken(_paymentToken);
    }
}
