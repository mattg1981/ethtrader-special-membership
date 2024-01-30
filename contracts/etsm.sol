// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract NFTV14 is ERC721, ERC721URIStorage, ERC721Burnable, AccessControl {
    uint256 private _nextTokenId = 1;
    uint256 public _pricePerDay = 0.0001 ether;
    //address public _multisigAddress = 0x439ceE4cC4EcBD75DC08D9a17E92bDdCc11CDb8C;
    address public _multisigAddress = 0xa8C8c9e18C763805c91bcB720B2320aDe16a0BBf;

    bytes32 public constant PRICE_CHANGER_ROLE = keccak256("PRICE_CHANGER_ROLE");
    bytes32 public constant FREE_MINTER_ROLE = keccak256("FREE_MINTER_ROLE");

    string public _baseUrl;

    mapping(uint256 => uint256) _tokenExpiration;
    mapping(address => uint256[]) _nftOwners;

    event UpdateMeta(address indexed subscriber, address purchaser, uint256 tokenId, uint256 expirationDate);
    event PriceChanged(address changedBy, uint256 price);

    constructor() ERC721("NFT v14", "NFT14") {
        _baseUrl = "https://raw.githubusercontent.com/mattg1981/ethtrader-special-membership/main/meta/";

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PRICE_CHANGER_ROLE, msg.sender);
        _grantRole(FREE_MINTER_ROLE, msg.sender);

        emit PriceChanged(msg.sender, _pricePerDay);
    }

    function setMultisigAddress(address multisig)
    public
    onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _multisigAddress = multisig;
    }

    // Pricing

    function setPricePerDayInWei(uint256 newPrice)
    public
    onlyRole(PRICE_CHANGER_ROLE)
    {
         _pricePerDay = newPrice;
        emit PriceChanged(msg.sender, _pricePerDay);
    }


    function getPriceForDaysInWei(uint numDays)
    public
    view
    returns (uint256)
    {
          return _pricePerDay * numDays;
    }



    // NFT --------------------------------------------

    function setBaseUrl(string calldata baseUrl)
    public
    onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _baseUrl = baseUrl;
    }

    function tokenURI(uint256 tokenId)
    override(ERC721, ERC721URIStorage)
    public
    view
    returns (string memory)
    {
        _requireOwned(tokenId);
        return string.concat(_baseUrl, Strings.toString(tokenId), ".json");
    }

    function safeMint(uint256 numDays)
    public
    payable
    {
        safeMintFor(msg.sender, numDays);
    }

    function safeMintFor(address to, uint256 numDays)
    public
    payable
    {
        require (
            msg.value >=  _pricePerDay * numDays,
            string.concat("Not enough ETH included in the transaction; needed amount: ", Strings.toString(_pricePerDay * numDays))
        );

        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);

        // send msg.value to the multisig
        payable(_multisigAddress).transfer(msg.value);

        uint256 expiration = block.timestamp + (numDays * 1 days);
        _tokenExpiration[tokenId] = expiration;

        _nftOwners[to].push(tokenId);

        emit UpdateMeta(to, msg.sender, tokenId, expiration);
    }

    function safeMintFree(address to, uint256 numDays)
    public
    onlyRole(FREE_MINTER_ROLE)
    {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);

        uint256 expiration = block.timestamp + (numDays * 1 days);
        _tokenExpiration[tokenId] = expiration;

        _nftOwners[to].push(tokenId);

        emit UpdateMeta(to, msg.sender, tokenId, expiration);
    }

    function transferFrom(address from, address to, uint256 tokenId)
    override(ERC721, IERC721)
    public
    {
        super.transferFrom(from, to, tokenId);
        removeTokenFromOwner(tokenId, from);
        _nftOwners[to].push(tokenId);
    }

    function removeTokenFromOwner(uint256 tokenId, address from)
    private
    {
        if (balanceOf(from) > 1) {
            for (uint256 i = 0; i < _nftOwners[from].length; i++) {
                if (_nftOwners[from][i] == tokenId) {
                    // replace the current index with the last item in array
                    // which will be popped off
                    _nftOwners[from][i] = _nftOwners[from][_nftOwners[from].length - 1];
                }
            }
        }

            _nftOwners[from].pop();
    }

    function burn(uint256 tokenId)
    override
    public
    virtual
    {
        address prevOwner = ownerOf(tokenId);
        super.burn(tokenId);
        removeTokenFromOwner(tokenId, prevOwner);
    }

    // Special Membership --------------------------------------------

    function getExpirationDateForTokenId(uint256 tokenId)
    public
    view
    returns (uint256)
    {
       return _tokenExpiration[tokenId];
    }

    function extendMembership(uint256 tokenId, uint256 numDays)
    public
    payable
    returns (uint256)
    {
        require (
            msg.value >=  _pricePerDay * numDays,
            string.concat("Not enough ETH included in the transaction; needed amount: ", Strings.toString(_pricePerDay * numDays))
        );

        // send msg.value to the multisig
        payable(_multisigAddress).transfer(msg.value);

        return extend(tokenId, numDays);
    }

    function extendMembershipFree(uint256 tokenId, uint256 numDays)
    public
    onlyRole(FREE_MINTER_ROLE)
    returns (uint256)
    {
        return extend(tokenId, numDays);
    }

    function extend(uint256 tokenId, uint256 numDays)
    private
    returns (uint256)
    {
        uint256 newExpiration = 0;

        if (_tokenExpiration[tokenId] < block.timestamp)
            newExpiration = block.timestamp + (numDays * 1 days);
        else
            newExpiration = _tokenExpiration[tokenId] + (numDays * 1 days);

        _tokenExpiration[tokenId] = newExpiration ;

        // two emits
        //   - MetadataUpdate is an ERC-4906 standard that markets such as
        //     OpenSea use to flag metadata updates
        //   - UpdateMeta is our custom event with additional information used
        //     to build the metadata.json file
        emit UpdateMeta(ownerOf(tokenId), msg.sender, tokenId, newExpiration);
        emit MetadataUpdate(tokenId);
        return newExpiration;
    }

    function extendMembershipByAddress(address subscriber, uint256 numDays)
    public
    payable
    returns (uint256)
    {
        require (
            msg.value >=  _pricePerDay * numDays,
            string.concat("Not enough ETH included in the transaction; needed amount: ", Strings.toString(_pricePerDay * numDays))
        );

        // send msg.value to the multisig
        payable(_multisigAddress).transfer(msg.value);

        return extendByAddress(subscriber, numDays);
    }

    function extendMembershipByAddressFree(address subscriber, uint256 numDays)
    public
    onlyRole(FREE_MINTER_ROLE)
    returns (uint256)
    {
        return extendByAddress(subscriber, numDays);
    }

    function extendByAddress(address subscriber, uint256 numDays)
    private
    returns (uint256)
    {
        uint256 newExpiration = 0;

        if (_nftOwners[subscriber].length == 0) {
            revert('Address has no NFTs, user safeMintFor() instead');
        }

        uint256 maxVal = 0;
        uint256 tokenId = 0;
        for (uint256 i = 0; i < _nftOwners[subscriber].length; i++) {
            if (_tokenExpiration[_nftOwners[subscriber][i]] > maxVal) {
                maxVal = _tokenExpiration[_nftOwners[subscriber][i]];
                tokenId = _nftOwners[subscriber][i];
            }
        }

        if (_tokenExpiration[tokenId] < block.timestamp)
            newExpiration = block.timestamp + (numDays * 1 days);
        else
            newExpiration = _tokenExpiration[tokenId] + (numDays * 1 days);

        _tokenExpiration[tokenId] = newExpiration ;

        // two emits
        //   - MetadataUpdate is an ERC-4906 standard that markets such as
        //     OpenSea use to flag metadata updates
        //   - UpdateMeta is our custom event with additional information used
        //     to build the metadata.json file
        emit UpdateMeta(ownerOf(tokenId), msg.sender, tokenId, newExpiration);
        emit MetadataUpdate(tokenId);
        return newExpiration;
    }

    function getTokenIdsForAddress(address nftOwner)
    public
    view
    returns (uint256[] memory)
    {
        return _nftOwners[nftOwner];
    }

    function hasValidMembership(address nftOwner)
    public
    view
    returns (bool)
    {
        return getExpirationDateForAddress(nftOwner) > block.timestamp;
    }

    function getExpirationDateForAddress(address nftOwner)
    public
    view
    returns (uint256)
    {
        uint256 maxVal = 0;

        if (_nftOwners[nftOwner].length == 0) {
            return 0;
        }

        for (uint256 i = 0; i < _nftOwners[nftOwner].length; i++) {
            if (_tokenExpiration[_nftOwners[nftOwner][i]] > maxVal) {
                maxVal = _tokenExpiration[_nftOwners[nftOwner][i]];
            }
        }

        return maxVal;
    }

    // OpenZeppelin Required ------------------------------------

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}