// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/Base64Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract LineaMiniSanto is Initializable, ERC721Upgradeable, ERC2981Upgradeable, ERC721EnumerableUpgradeable, PausableUpgradeable, AccessControlUpgradeable, ERC721BurnableUpgradeable, ReentrancyGuardUpgradeable {
    using ECDSAUpgradeable for bytes32;
    using StringsUpgradeable for uint256;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    enum Status {
        WhiteListSale,
        PublicSale,
        FreeSale
    }

    uint256 public openSupply;
    string private baseURI;
    string private baseExtension;
    uint256 public saleEthPrice;

    uint8 public phase;
    uint256 public saleStartTime;
    uint256 public saleEndTime;

    mapping(Status => uint256) public mintMax;
    mapping(Status => uint256) public mintCount;
    mapping(Status => uint256) public mintPerMax;
    mapping(uint256 => uint8) public features;

    mapping(address => mapping(uint8 => uint256)) public amountMintedPerFree;
    mapping(address => mapping(uint8 => uint256)) public amountMintedPerPublic;

    CountersUpgradeable.Counter private _tokenIdCounter;
    address private signer;
    mapping(bytes32 => bool) public executed;

    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");
    bytes32 public constant SERVER_ROLE = keccak256("SERVER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _startId,
        uint256 _startTime,
        address _signer,
        string memory _uri,
        string memory _ext
    ) initializer public {
         __ERC721_init(_name, _symbol);
        __ERC721Enumerable_init();
        __Pausable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __ERC721Burnable_init();

        __ERC2981_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        signer = _signer;
        _tokenIdCounter._value = _startId;
        _setDefaultRoyalty(_msgSender(), 500);
        _grantRole(SERVER_ROLE, signer);
        
        setPhase(1);
        setBaseURI(_uri);
        setBaseExtension(_ext);
        setSaleStartTime(_startTime);
        setSaleEndTime(_startTime + 24 hours);
        setMintPerMax(Status.FreeSale, 1);
    }

    modifier _notContract() {
        uint256 size;
        address addr = _msgSender();
        assembly {
            size := extcodesize(addr)
        }
        require(size == 0, "Contract is not allowed");
        require(_msgSender() == tx.origin, "Proxy contract is not allowed");
        _;
    }

    modifier _saleBetweenPeriod(uint256 _startTime, uint256 _endTime) {
        require(currentTime() >= _startTime, "Sale has not started yet");
        require(currentTime() < _endTime, "Sale is finished");
        _;
    }

    function mint(uint256 amount)
        public
        payable
        whenNotPaused
        _notContract
        _saleBetweenPeriod(saleStartTime, saleEndTime)
        nonReentrant
    {
        Status _current = Status.FreeSale;
        require(amountMintedPerFree[_msgSender()][phase] + amount <= mintPerMax[_current], "Minted reached the limit");

        mintCount[_current] += amount;
        amountMintedPerFree[_msgSender()][phase] += amount;
        _mintBatch(_msgSender(), amount, 0);
    }

    function claim(
        bytes memory signature,
        address addr,
        uint8 feature,
        uint256 amount,
        uint deadline
    ) nonReentrant _notContract public {
        require(deadline >= block.timestamp, "TownStory: Deadline Passed");
        bytes32 txHash = keccak256(abi.encode(addr, feature, amount, deadline, _msgSender()));

        require(!executed[txHash], "TownStory: Tx Executed");
        require(verify(txHash, signature), "TownStory: Unauthorised");
        executed[txHash] = true;

        _mintBatch(addr, amount, feature);
    }

    function _mintBatch(address _to, uint256 _amount, uint8 _feature) internal {
        for (uint256 i = 0; i < _amount; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            features[tokenId] = _feature;
            _safeMint(_to, tokenId);
        }
    }

    function rewardClaim(address[] memory addrs, uint256 amount, uint8 feature) public onlyRole(SERVER_ROLE) {
        for (uint256 i = 0; i < addrs.length; i++) {
            _mintBatch(addrs[i], amount, feature);
        }
    }

    function listOfBalances(address addr) public view returns (uint256[] memory, uint8[] memory) {
        uint256 balance = balanceOf(addr);
        uint256[] memory _balances = new uint256[](balance);
        uint8[] memory _features = new uint8[](balance);
        
        for (uint256 i = 0; i < balance; i++) {
            uint256 _tokenId = tokenOfOwnerByIndex(addr, i);
            _balances[i] = _tokenId;
            _features[i] = features[_tokenId];
        }

        return (_balances, _features);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        string memory base = _baseURI();

        string memory _name = "Linea Mini Santo";
        string memory _description = "Linea Mini Santo is a Linea Exclusive NFT in Town Story Galaxy, which is the most popular crypto social farming game on Linea. It contains a commemorative profile image and a special title!";
        bytes memory _uri = abi.encodePacked(base, "mini", baseExtension);

        if (features[tokenId] == 1) {
            _name = "Linea Premium Santo";
            _description = "Linea Premium Mini Santo is a mini OG Pass of Town Story Galaxy, which is the most popular crypto social farming game on Linea. This OG Pass grants you various privileges and bountiful rewards in the game!";
            _uri = abi.encodePacked(base, "premium", baseExtension);
        }

        bytes memory _attributes = abi.encodePacked(
            '"attributes":[',
                    '{"trait_type":"SIGNATURE SERIES","value":"', _name, '"}',
                ']'
        );

        string memory data = Base64Upgradeable.encode(abi.encodePacked(
            '{',
                '"name":"', _name, ' #', tokenId.toString(), '",',
                '"description":"', _description, '",',
                '"image":"', _uri, '",',
                _attributes,
            '}'
        ));

        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                data
            )
        );
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory _uri) public onlyRole(DEFAULT_ADMIN_ROLE) {
        baseURI = _uri;
    }

    function setSaleEthPrice(uint256 price) public onlyRole(DEFAULT_ADMIN_ROLE) {
        saleEthPrice = price;
    }

    function setSaleStartTime(uint256 startTime) public onlyRole(DEFAULT_ADMIN_ROLE) {
        saleStartTime = startTime;
    }

    function setSaleEndTime(uint256 endTime) public onlyRole(DEFAULT_ADMIN_ROLE) {
        saleEndTime = endTime;
    }

    function setBaseExtension(string memory _baseExtension) public onlyRole(DEFAULT_ADMIN_ROLE) {
        baseExtension = _baseExtension;
    }

    function setPhase(uint8 _phase) public onlyRole(DEFAULT_ADMIN_ROLE) {
        phase = _phase;
    }

    function setOpenSupply(uint256 _openSupply) public onlyRole(DEFAULT_ADMIN_ROLE) {
        openSupply = _openSupply;
    }

    function setMintMax(Status _status, uint256 _max) public onlyRole(DEFAULT_ADMIN_ROLE) {
        mintMax[_status] = _max;
    }

    function setMintPerMax(Status _status, uint256 _max) public onlyRole(DEFAULT_ADMIN_ROLE) {
        mintPerMax[_status] = _max;
    }

    function transferSigner(address _signer) public onlyRole(DEFAULT_ADMIN_ROLE) {
        signer = _signer;
    }
    
    function setDefaultRoyalty(address _receiver, uint96 _feeNumerator) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDefaultRoyalty(_receiver, _feeNumerator);
    }

    function deleteDefaultRoyalty() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _deleteDefaultRoyalty();
    }

    function setTokenRoyalty(
        uint256 _tokenId,
        address _receiver,
        uint96 _feeNumerator
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTokenRoyalty(_tokenId, _receiver, _feeNumerator);
    }

    function resetTokenRoyalty(uint256 _tokenId) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _resetTokenRoyalty(_tokenId);
    }

    function currentTime() private view returns (uint256) {
        return block.timestamp;
    }

    function verify(bytes32 hash, bytes memory signature) private view returns (bool) {
        bytes32 ethSignedHash = hash.toEthSignedMessageHash();
        return ethSignedHash.recover(signature) == signer;
    }

    function withdraw() public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint balance = address(this).balance;
        payable(_msgSender()).transfer(balance);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        whenNotPaused
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId) internal override(ERC721Upgradeable) {
        super._burn(tokenId);
        _resetTokenRoyalty(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC2981Upgradeable, ERC721EnumerableUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}