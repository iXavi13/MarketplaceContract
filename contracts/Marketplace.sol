//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

//SOLU - 0xCB5df23bfe0367f340Ce6dfa84e6Db949D5Fb4F5
//NFT - 0x444C43d656B72C26ba7898aAB84C6dCB429CAe11

contract RosieMagicMarket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant INTERFACE_ID_ERC1155 = 0xd9b67a26;
    uint256 public constant BASIS_POINTS = 10000;

    address public paymentToken;

    uint256 public fee;
    address public feeReceipient;

    struct Listing {
        uint256 quantity;
        uint256 pricePerItem;
        uint256 expirationDate;
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
        setFee(750);
        setFeeRecipient(0x693065F2e132E9A8B70AA4D43120EAef7f8f2685);
        setPaymentToken(0xCB5df23bfe0367f340Ce6dfa84e6Db949D5Fb4F5); 
    }

    function createListing(
        address _collectionAddress,
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _pricePerItem,
        uint256 _expirationDate
    ) external {
        require(listings[_collectionAddress][_tokenId][_msgSender()].quantity == 0, "already listed");
        if (_expirationDate == 0) _expirationDate = type(uint256).max;
        require(_expirationDate > block.timestamp, "invalid expiration time");
        require(_quantity > 0, "nothing to list");

        if (IERC165(_collectionAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_collectionAddress);
            require(nft.ownerOf(_tokenId) == _msgSender(), "not owning item");
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
            _expirationDate
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
        require(_quantity > 0, "Cannot buy 0");
        require(_msgSender() != _owner, "Cannot buy your own item");

        Listing memory listedItem = listings[_collectionAddress][_tokenId][_owner];
        require(listedItem.quantity >= _quantity, "not enough quantity");

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
        _buyItem(listedItem.pricePerItem, _quantity, _owner);
    }

    function _buyItem(
        uint256 _pricePerItem,
        uint256 _quantity,
        address _owner
    ) internal {
        uint256 totalPrice = _pricePerItem * _quantity;
        uint256 feeAmount = totalPrice * fee / BASIS_POINTS;
        IERC20(paymentToken).safeTransferFrom(_msgSender(), feeReceipient, feeAmount);
        IERC20(paymentToken).safeTransferFrom(_msgSender(), _owner, totalPrice - feeAmount);
    }

    // admin

    function setFee(uint256 _fee) public onlyOwner {
        require(_fee < BASIS_POINTS, "max fee");
        fee = _fee;
        emit UpdateFee(_fee);
    }

    function setFeeRecipient(address _feeRecipient) public onlyOwner {
        feeReceipient = _feeRecipient;
        emit UpdateFeeRecipient(_feeRecipient);
    }

    function setPaymentToken(address _paymentToken) public onlyOwner {
        paymentToken = _paymentToken;
        emit UpdatePaymentToken(_paymentToken);
    }
}
