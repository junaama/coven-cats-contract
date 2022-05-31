//SPDX-License-Identifier: MIT
//Contract based on [https://docs.openzeppelin.com/contracts/3.x/erc721](https://docs.openzeppelin.com/contracts/3.x/erc721)

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract CovenCats is
    ERC721Upgradeable,
    IERC2981,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using Counters for Counters.Counter;
    using Strings for uint256;

    Counters.Counter private tokenCounter;

    string private baseURI;
    bool private isOpenSeaProxyActive;

    uint256 public constant MAX_CATS_PER_PHASE = 3;
    uint256 public constant MAX_CATS = 9999;
    uint256 public constant MAX_GIFTED_CATS = 666;
    uint256 public numGiftedCats;

    enum SalePhase {
        PUBLIC,
        MEOWLIST,
        WITCH,
        OFF
    }
    SalePhase public salePhase;

    uint256 public constant PUBLIC_SALE_PRICE = 0.07 ether;
    bytes32 public meowlistSaleMerkleRoot;

    uint256 public constant WITCH_SALE_PRICE = 0.05 ether;
    bytes32 public witchSaleMerkleRoot;

    mapping(string => uint256) public mintCounts;

    // ============ ACCESS CONTROL/SANITY MODIFIERS ============

    modifier publicSaleActive() {
        require(salePhase == SalePhase.PUBLIC, "Public sale is not open");
        _;
    }

    modifier meowlistSaleActive() {
        require(salePhase == SalePhase.MEOWLIST, "MEOWLIST sale is not open");
        _;
    }

    modifier witchSaleActive() {
        require(salePhase == SalePhase.WITCH, "WITCH sale is not open");
        _;
    }

    modifier maxCatsPerPhase(uint256 numberOfTokens) {
        require(
            mintCounts[mintCountsIdentifier()] + numberOfTokens <=
                MAX_CATS_PER_PHASE,
            "Max cats to mint per phase is three"
        );
        _;
    }

    modifier canMintCats(uint256 numberOfTokens) {
        require(
            tokenCounter.current() + numberOfTokens <=
                MAX_CATS - MAX_GIFTED_CATS + numGiftedCats,
            "Not enough cats remaining to mint"
        );
        _;
    }

    modifier canGiftCats(uint256 num) {
        require(
            numGiftedCats + num <= MAX_GIFTED_CATS,
            "Not enough cats remaining to gift"
        );
        require(
            tokenCounter.current() + num <= MAX_CATS,
            "Not enough cats remaining to mint"
        );
        _;
    }

    modifier isCorrectPayment(uint256 price, uint256 numberOfTokens) {
        require(
            price * numberOfTokens == msg.value,
            "Incorrect ETH value sent"
        );
        _;
    }

    modifier isValidMerkleProof(bytes32[] calldata merkleProof, bytes32 root) {
        require(
            MerkleProof.verify(
                merkleProof,
                root,
                keccak256(abi.encodePacked(msg.sender))
            ),
            "Address does not exist in list"
        );
        _;
    }

    function initialize() public initializer {
        __ERC721_init_unchained("Coven Cats", "CAT");
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();

        isOpenSeaProxyActive = true;
        salePhase = SalePhase.OFF;
    }

    // ============ PUBLIC FUNCTIONS FOR MINTING ============

    function mint(uint256 numberOfTokens)
        external
        payable
        nonReentrant
        isCorrectPayment(PUBLIC_SALE_PRICE, numberOfTokens)
        publicSaleActive
        canMintCats(numberOfTokens)
        maxCatsPerPhase(numberOfTokens)
    {
        mintCounts[mintCountsIdentifier()] += numberOfTokens;
        for (uint256 i = 0; i < numberOfTokens; i++) {
            _safeMint(msg.sender, nextTokenId());
        }
    }

    function mintMeowlistSale(
        uint8 numberOfTokens,
        bytes32[] calldata merkleProof
    )
        external
        payable
        nonReentrant
        meowlistSaleActive
        canMintCats(numberOfTokens)
        maxCatsPerPhase(numberOfTokens)
        isCorrectPayment(PUBLIC_SALE_PRICE, numberOfTokens)
        isValidMerkleProof(merkleProof, meowlistSaleMerkleRoot)
    {
        mintCounts[mintCountsIdentifier()] += numberOfTokens;
        for (uint256 i = 0; i < numberOfTokens; i++) {
            _safeMint(msg.sender, nextTokenId());
        }
    }

    function mintWitchSale(uint8 numberOfTokens, bytes32[] calldata merkleProof)
        external
        payable
        nonReentrant
        witchSaleActive
        canMintCats(numberOfTokens)
        maxCatsPerPhase(numberOfTokens)
        isCorrectPayment(WITCH_SALE_PRICE, numberOfTokens)
        isValidMerkleProof(merkleProof, witchSaleMerkleRoot)
    {
        mintCounts[mintCountsIdentifier()] += numberOfTokens;
        for (uint256 i = 0; i < numberOfTokens; i++) {
            _safeMint(msg.sender, nextTokenId());
        }
    }

    // ============ PUBLIC READ-ONLY FUNCTIONS ============

    function getBaseURI() external view returns (string memory) {
        return baseURI;
    }

    function getLastTokenId() external view returns (uint256) {
        return tokenCounter.current();
    }

    // ============ OWNER-ONLY ADMIN FUNCTIONS ============

    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    // function to disable gasless listings for security in case
    // opensea ever shuts down or is compromised
    function setIsOpenSeaProxyActive(bool _isOpenSeaProxyActive)
        external
        onlyOwner
    {
        isOpenSeaProxyActive = _isOpenSeaProxyActive;
    }

    function setSalePhase(SalePhase newPhase) external onlyOwner {
        salePhase = newPhase;
    }

    function setMeowlistMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        meowlistSaleMerkleRoot = merkleRoot;
    }

    function setWitchListMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        witchSaleMerkleRoot = merkleRoot;
    }

    function reserveForGifting(uint256 numToReserve)
        external
        nonReentrant
        onlyOwner
        canGiftCats(numToReserve)
    {
        numGiftedCats += numToReserve;
        for (uint256 i = 0; i < numToReserve; i++) {
            _safeMint(msg.sender, nextTokenId());
        }
    }

    function giftCats(address[] calldata addresses)
        external
        nonReentrant
        onlyOwner
        canGiftCats(addresses.length)
    {
        uint256 numToGift = addresses.length;
        numGiftedCats += numToGift;

        for (uint256 i = 0; i < numToGift; i++) {
            _safeMint(addresses[i], nextTokenId());
        }
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    function withdrawTokens(IERC20 token) public onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
    }

    // ============ SUPPORTING FUNCTIONS ============

    function nextTokenId() private returns (uint256) {
        tokenCounter.increment();
        return tokenCounter.current();
    }

    function mintCountsIdentifier() private view returns (string memory) {
        return string(abi.encodePacked(msg.sender, "-", salePhase));
    }

    // ============ FUNCTION OVERRIDES ============

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Override isApprovedForAll to allowlist user's OpenSea proxy accounts to enable gas-less listings.
     */
    function isApprovedForAll(address owner, address operator)
        public
        view
        override
        returns (bool)
    {
        // Get a reference to OpenSea's proxy registry contract by instantiating
        // the contract using the already existing address.
        ProxyRegistry proxyRegistry = ProxyRegistry(
            0xa5409ec958C83C3f309868babACA7c86DCB077c1
        );
        if (
            isOpenSeaProxyActive &&
            address(proxyRegistry.proxies(owner)) == operator
        ) {
            return true;
        }

        return super.isApprovedForAll(owner, operator);
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), "Nonexistent token");

        return
            string(abi.encodePacked(baseURI, "/", tokenId.toString(), ".json"));
    }

    /**
     * @dev See {IERC165-royaltyInfo}.
     */
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        require(_exists(tokenId), "Nonexistent token");

        return (owner(), SafeMath.div(SafeMath.mul(salePrice, 75), 1000));
    }
}

// These contract definitions are used to create a reference to the OpenSea
// ProxyRegistry contract by using the registry's address (see isApprovedForAll).
contract OwnableDelegateProxy {

}

contract ProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
}
