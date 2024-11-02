pragma solidity 0.4.24;

contract CrabData {
  modifier crabDataLength(uint256[] memory _crabData) {
    require(_crabData.length == 8);
    _;
  }

  struct CrabPartData {
    uint256 hp;
    uint256 dps;
    uint256 blockRate;
    uint256 resistanceBonus;
    uint256 hpBonus;
    uint256 dpsBonus;
    uint256 blockBonus;
    uint256 mutiplierBonus;
  }

  function arrayToCrabPartData(
    uint256[] _partData
  ) 
    internal 
    pure 
    crabDataLength(_partData) 
    returns (CrabPartData memory _parsedData) 
  {
    _parsedData = CrabPartData(
      _partData[0],   // hp
      _partData[1],   // dps
      _partData[2],   // block rate
      _partData[3],   // resistance bonus
      _partData[4],   // hp bonus
      _partData[5],   // dps bonus
      _partData[6],   // block bonus
      _partData[7]);  // multiplier bonus
  }

  function crabPartDataToArray(CrabPartData _crabPartData) internal pure returns (uint256[] memory _resultData) {
    _resultData = new uint256[](8);
    _resultData[0] = _crabPartData.hp;
    _resultData[1] = _crabPartData.dps;
    _resultData[2] = _crabPartData.blockRate;
    _resultData[3] = _crabPartData.resistanceBonus;
    _resultData[4] = _crabPartData.hpBonus;
    _resultData[5] = _crabPartData.dpsBonus;
    _resultData[6] = _crabPartData.blockBonus;
    _resultData[7] = _crabPartData.mutiplierBonus;
  }
}

contract GeneSurgeon {
  //0 - filler, 1 - body, 2 - leg, 3 - left claw, 4 - right claw
  uint256[] internal crabPartMultiplier = [0, 10**9, 10**6, 10**3, 1];

  function extractElementsFromGene(uint256 _gene) internal view returns (uint256[] memory _elements) {
    _elements = new uint256[](4);
    _elements[0] = _gene / crabPartMultiplier[1] / 100 % 10;
    _elements[1] = _gene / crabPartMultiplier[2] / 100 % 10;
    _elements[2] = _gene / crabPartMultiplier[3] / 100 % 10;
    _elements[3] = _gene / crabPartMultiplier[4] / 100 % 10;
  }

  function extractPartsFromGene(uint256 _gene) internal view returns (uint256[] memory _parts) {
    _parts = new uint256[](4);
    _parts[0] = _gene / crabPartMultiplier[1] % 100;
    _parts[1] = _gene / crabPartMultiplier[2] % 100;
    _parts[2] = _gene / crabPartMultiplier[3] % 100;
    _parts[3] = _gene / crabPartMultiplier[4] % 100;
  }
}

interface GenesisCrabInterface {
  function generateCrabGene(bool isPresale, bool hasLegendaryPart) external returns (uint256 _gene, uint256 _skin, uint256 _heartValue, uint256 _growthValue);
  function mutateCrabPart(uint256 _part, uint256 _existingPartGene, uint256 _legendaryPercentage) external view returns (uint256);
  function generateCrabHeart() external view returns (uint256, uint256);
}

contract Randomable {
  // Generates a random number base on last block hash
  function _generateRandom(bytes32 seed) view internal returns (bytes32) {
    return keccak256(abi.encodePacked(blockhash(block.number-1), seed));
  }

  function _generateRandomNumber(bytes32 seed, uint256 max) view internal returns (uint256) {
    return uint256(_generateRandom(seed)) % max;
  }
}

contract CryptantCrabStoreInterface {
  function createAddress(bytes32 key, address value) external returns (bool);
  function createAddresses(bytes32[] keys, address[] values) external returns (bool);
  function updateAddress(bytes32 key, address value) external returns (bool);
  function updateAddresses(bytes32[] keys, address[] values) external returns (bool);
  function removeAddress(bytes32 key) external returns (bool);
  function removeAddresses(bytes32[] keys) external returns (bool);
  function readAddress(bytes32 key) external view returns (address);
  function readAddresses(bytes32[] keys) external view returns (address[]);
  // Bool related functions
  function createBool(bytes32 key, bool value) external returns (bool);
  function createBools(bytes32[] keys, bool[] values) external returns (bool);
  function updateBool(bytes32 key, bool value) external returns (bool);
  function updateBools(bytes32[] keys, bool[] values) external returns (bool);
  function removeBool(bytes32 key) external returns (bool);
  function removeBools(bytes32[] keys) external returns (bool);
  function readBool(bytes32 key) external view returns (bool);
  function readBools(bytes32[] keys) external view returns (bool[]);
  // Bytes32 related functions
  function createBytes32(bytes32 key, bytes32 value) external returns (bool);
  function createBytes32s(bytes32[] keys, bytes32[] values) external returns (bool);
  function updateBytes32(bytes32 key, bytes32 value) external returns (bool);
  function updateBytes32s(bytes32[] keys, bytes32[] values) external returns (bool);
  function removeBytes32(bytes32 key) external returns (bool);
  function removeBytes32s(bytes32[] keys) external returns (bool);
  function readBytes32(bytes32 key) external view returns (bytes32);
  function readBytes32s(bytes32[] keys) external view returns (bytes32[]);
  // uint256 related functions
  function createUint256(bytes32 key, uint256 value) external returns (bool);
  function createUint256s(bytes32[] keys, uint256[] values) external returns (bool);
  function updateUint256(bytes32 key, uint256 value) external returns (bool);
  function updateUint256s(bytes32[] keys, uint256[] values) external returns (bool);
  function removeUint256(bytes32 key) external returns (bool);
  function removeUint256s(bytes32[] keys) external returns (bool);
  function readUint256(bytes32 key) external view returns (uint256);
  function readUint256s(bytes32[] keys) external view returns (uint256[]);
  // int256 related functions
  function createInt256(bytes32 key, int256 value) external returns (bool);
  function createInt256s(bytes32[] keys, int256[] values) external returns (bool);
  function updateInt256(bytes32 key, int256 value) external returns (bool);
  function updateInt256s(bytes32[] keys, int256[] values) external returns (bool);
  function removeInt256(bytes32 key) external returns (bool);
  function removeInt256s(bytes32[] keys) external returns (bool);
  function readInt256(bytes32 key) external view returns (int256);
  function readInt256s(bytes32[] keys) external view returns (int256[]);
  // internal functions
  function parseKey(bytes32 key) internal pure returns (bytes32);
  function parseKeys(bytes32[] _keys) internal pure returns (bytes32[]);
}

library AddressUtils {

  /**
   * Returns whether the target address is a contract
   * @dev This function will return false if invoked during the constructor of a contract,
   * as the code is not actually created until after the constructor finishes.
   * @param addr address to check
   * @return whether the target address is a contract
   */
  function isContract(address addr) internal view returns (bool) {
    uint256 size;
    // XXX Currently there is no better way to check if there is a contract in an address
    // than to check the size of the code at that address.
    // See https://ethereum.stackexchange.com/a/14016/36603
    // for more details about how this works.
    // TODO Check this again before the Serenity release, because all addresses will be
    // contracts then.
    // solium-disable-next-line security/no-inline-assembly
    assembly { size := extcodesize(addr) }
    return size > 0;
  }

}

interface ERC165 {

  /**
   * @notice Query if a contract implements an interface
   * @param _interfaceId The interface identifier, as specified in ERC-165
   * @dev Interface identification is specified in ERC-165. This function
   * uses less than 30,000 gas.
   */
  function supportsInterface(bytes4 _interfaceId)
    external
    view
    returns (bool);
}

contract SupportsInterfaceWithLookup is ERC165 {
  bytes4 public constant InterfaceId_ERC165 = 0x01ffc9a7;
  /**
   * 0x01ffc9a7 ===
   *   bytes4(keccak256('supportsInterface(bytes4)'))
   */

  /**
   * @dev a mapping of interface id to whether or not it's supported
   */
  mapping(bytes4 => bool) internal supportedInterfaces;

  /**
   * @dev A contract implementing SupportsInterfaceWithLookup
   * implement ERC165 itself
   */
  constructor()
    public
  {
    _registerInterface(InterfaceId_ERC165);
  }

  /**
   * @dev implement supportsInterface(bytes4) using a lookup table
   */
  function supportsInterface(bytes4 _interfaceId)
    external
    view
    returns (bool)
  {
    return supportedInterfaces[_interfaceId];
  }

  /**
   * @dev private method for registering an interface
   */
  function _registerInterface(bytes4 _interfaceId)
    internal
  {
    require(_interfaceId != 0xffffffff);
    supportedInterfaces[_interfaceId] = true;
  }
}

library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  */
  function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
    // Gas optimization: this is cheaper than asserting 'a' not being zero, but the
    // benefit is lost if 'b' is also tested.
    // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
    if (a == 0) {
      return 0;
    }

    c = a * b;
    assert(c / a == b);
    return c;
  }

  /**
  * @dev Integer division of two numbers, truncating the quotient.
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    // uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return a / b;
  }

  /**
  * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
    c = a + b;
    assert(c >= a);
    return c;
  }
}

contract Ownable {
  address public owner;


  event OwnershipRenounced(address indexed previousOwner);
  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );


  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  constructor() public {
    owner = msg.sender;
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  /**
   * @dev Allows the current owner to relinquish control of the contract.
   * @notice Renouncing to ownership will leave the contract without an owner.
   * It will not be possible to call the functions with the `onlyOwner`
   * modifier anymore.
   */
  function renounceOwnership() public onlyOwner {
    emit OwnershipRenounced(owner);
    owner = address(0);
  }

  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param _newOwner The address to transfer ownership to.
   */
  function transferOwnership(address _newOwner) public onlyOwner {
    _transferOwnership(_newOwner);
  }

  /**
   * @dev Transfers control of the contract to a newOwner.
   * @param _newOwner The address to transfer ownership to.
   */
  function _transferOwnership(address _newOwner) internal {
    require(_newOwner != address(0));
    emit OwnershipTransferred(owner, _newOwner);
    owner = _newOwner;
  }
}

contract CryptantCrabBase is Ownable {
  GenesisCrabInterface public genesisCrab;
  CryptantCrabNFT public cryptantCrabToken;
  CryptantCrabStoreInterface public cryptantCrabStorage;

  constructor(address _genesisCrabAddress, address _cryptantCrabTokenAddress, address _cryptantCrabStorageAddress) public {
    // constructor
    
    _setAddresses(_genesisCrabAddress, _cryptantCrabTokenAddress, _cryptantCrabStorageAddress);
  }

  function setAddresses(
    address _genesisCrabAddress, 
    address _cryptantCrabTokenAddress, 
    address _cryptantCrabStorageAddress
  ) 
  external onlyOwner {
    _setAddresses(_genesisCrabAddress, _cryptantCrabTokenAddress, _cryptantCrabStorageAddress);
  }

  function _setAddresses(
    address _genesisCrabAddress,
    address _cryptantCrabTokenAddress,
    address _cryptantCrabStorageAddress
  )
  internal 
  {
    if(_genesisCrabAddress != address(0)) {
      GenesisCrabInterface genesisCrabContract = GenesisCrabInterface(_genesisCrabAddress);
      genesisCrab = genesisCrabContract;
    }
    
    if(_cryptantCrabTokenAddress != address(0)) {
      CryptantCrabNFT cryptantCrabTokenContract = CryptantCrabNFT(_cryptantCrabTokenAddress);
      cryptantCrabToken = cryptantCrabTokenContract;
    }
    
    if(_cryptantCrabStorageAddress != address(0)) {
      CryptantCrabStoreInterface cryptantCrabStorageContract = CryptantCrabStoreInterface(_cryptantCrabStorageAddress);
      cryptantCrabStorage = cryptantCrabStorageContract;
    }
  }
}

contract CryptantCrabInformant is CryptantCrabBase{
  constructor
  (
    address _genesisCrabAddress, 
    address _cryptantCrabTokenAddress, 
    address _cryptantCrabStorageAddress
  ) 
  public 
  CryptantCrabBase
  (
    _genesisCrabAddress, 
    _cryptantCrabTokenAddress, 
    _cryptantCrabStorageAddress
  ) {
    // constructor

  }

  function _getCrabData(uint256 _tokenId) internal view returns 
  (
    uint256 _gene, 
    uint256 _level, 
    uint256 _exp, 
    uint256 _mutationCount,
    uint256 _trophyCount,
    uint256 _heartValue,
    uint256 _growthValue
  ) {
    require(cryptantCrabStorage != address(0));

    bytes32[] memory keys = new bytes32[](7);
    uint256[] memory values;

    keys[0] = keccak256(abi.encodePacked(_tokenId, "gene"));
    keys[1] = keccak256(abi.encodePacked(_tokenId, "level"));
    keys[2] = keccak256(abi.encodePacked(_tokenId, "exp"));
    keys[3] = keccak256(abi.encodePacked(_tokenId, "mutationCount"));
    keys[4] = keccak256(abi.encodePacked(_tokenId, "trophyCount"));
    keys[5] = keccak256(abi.encodePacked(_tokenId, "heartValue"));
    keys[6] = keccak256(abi.encodePacked(_tokenId, "growthValue"));

    values = cryptantCrabStorage.readUint256s(keys);

    // process heart value
    uint256 _processedHeartValue;
    for(uint256 i = 1 ; i <= 1000 ; i *= 10) {
      if(uint256(values[5]) / i % 10 > 0) {
        _processedHeartValue += i;
      }
    }

    _gene = values[0];
    _level = values[1];
    _exp = values[2];
    _mutationCount = values[3];
    _trophyCount = values[4];
    _heartValue = _processedHeartValue;
    _growthValue = values[6];
  }

  function _geneOfCrab(uint256 _tokenId) internal view returns (uint256 _gene) {
    require(cryptantCrabStorage != address(0));

    _gene = cryptantCrabStorage.readUint256(keccak256(abi.encodePacked(_tokenId, "gene")));
  }
}

contract CryptantCrabPurchasable is CryptantCrabInformant {
  using SafeMath for uint256;

  event CrabHatched(address indexed owner, uint256 tokenId, uint256 gene, uint256 specialSkin, uint256 crabPrice, uint256 growthValue);
  event CryptantFragmentsAdded(address indexed cryptantOwner, uint256 amount, uint256 newBalance);
  event CryptantFragmentsRemoved(address indexed cryptantOwner, uint256 amount, uint256 newBalance);
  event Refund(address indexed refundReceiver, uint256 reqAmt, uint256 paid, uint256 refundAmt);

  constructor
  (
    address _genesisCrabAddress, 
    address _cryptantCrabTokenAddress, 
    address _cryptantCrabStorageAddress
  ) 
  public 
  CryptantCrabInformant
  (
    _genesisCrabAddress, 
    _cryptantCrabTokenAddress, 
    _cryptantCrabStorageAddress
  ) {
    // constructor

  }

  function getCryptantFragments(address _sender) public view returns (uint256) {
    return cryptantCrabStorage.readUint256(keccak256(abi.encodePacked(_sender, "cryptant")));
  }

  function createCrab(uint256 _customTokenId, uint256 _crabPrice, uint256 _customGene, uint256 _customSkin, uint256 _customHeart, bool _hasLegendary) external onlyOwner {
    return _createCrab(false, _customTokenId, _crabPrice, _customGene, _customSkin, _customHeart, _hasLegendary);
  }

  function _addCryptantFragments(address _cryptantOwner, uint256 _amount) internal returns (uint256 _newBalance) {
    _newBalance = getCryptantFragments(_cryptantOwner).add(_amount);
    cryptantCrabStorage.updateUint256(keccak256(abi.encodePacked(_cryptantOwner, "cryptant")), _newBalance);
    emit CryptantFragmentsAdded(_cryptantOwner, _amount, _newBalance);
  }

  function _removeCryptantFragments(address _cryptantOwner, uint256 _amount) internal returns (uint256 _newBalance) {
    _newBalance = getCryptantFragments(_cryptantOwner).sub(_amount);
    cryptantCrabStorage.updateUint256(keccak256(abi.encodePacked(_cryptantOwner, "cryptant")), _newBalance);
    emit CryptantFragmentsRemoved(_cryptantOwner, _amount, _newBalance);
  }

  function _createCrab(bool _isPresale, uint256 _tokenId, uint256 _crabPrice, uint256 _customGene, uint256 _customSkin, uint256 _customHeart, bool _hasLegendary) internal {
    uint256[] memory _values = new uint256[](4);
    bytes32[] memory _keys = new bytes32[](4);

    uint256 _gene;
    uint256 _specialSkin;
    uint256 _heartValue;
    uint256 _growthValue;
    if(_customGene == 0) {
      (_gene, _specialSkin, _heartValue, _growthValue) = genesisCrab.generateCrabGene(_isPresale, _hasLegendary);
    } else {
      _gene = _customGene;
    }

    if(_customSkin != 0) {
      _specialSkin = _customSkin;
    }

    if(_customHeart != 0) {
      _heartValue = _customHeart;
    } else if (_heartValue == 0) {
      (_heartValue, _growthValue) = genesisCrab.generateCrabHeart();
    }
    
    cryptantCrabToken.mintToken(msg.sender, _tokenId, _specialSkin);

    // Gene pair
    _keys[0] = keccak256(abi.encodePacked(_tokenId, "gene"));
    _values[0] = _gene;

    // Level pair
    _keys[1] = keccak256(abi.encodePacked(_tokenId, "level"));
    _values[1] = 1;

    // Heart Value pair
    _keys[2] = keccak256(abi.encodePacked(_tokenId, "heartValue"));
    _values[2] = _heartValue;

    // Growth Value pair
    _keys[3] = keccak256(abi.encodePacked(_tokenId, "growthValue"));
    _values[3] = _growthValue;

    require(cryptantCrabStorage.createUint256s(_keys, _values));

    emit CrabHatched(msg.sender, _tokenId, _gene, _specialSkin, _crabPrice, _growthValue);
  }

  function _refundExceededValue(uint256 _senderValue, uint256 _requiredValue) internal {
    uint256 _exceededValue = _senderValue.sub(_requiredValue);

    if(_exceededValue > 0) {
      msg.sender.transfer(_exceededValue);

      emit Refund(msg.sender, _requiredValue, _senderValue, _exceededValue);
    } 
  }
}

contract Withdrawable is Ownable {
  address public withdrawer;

  /**
   * @dev Throws if called by any account other than the withdrawer.
   */
  modifier onlyWithdrawer() {
    require(msg.sender == withdrawer);
    _;
  }

  function setWithdrawer(address _newWithdrawer) external onlyOwner {
    withdrawer = _newWithdrawer;
  }

  /**
   * @dev withdraw the specified amount of ether from contract.
   * @param _amount the amount of ether to withdraw. Units in wei.
   */
  function withdraw(uint256 _amount) external onlyWithdrawer returns(bool) {
    require(_amount <= address(this).balance);
    withdrawer.transfer(_amount);
    return true;
  }
}

contract HasNoEther is Ownable {

  /**
  * @dev Constructor that rejects incoming Ether
  * The `payable` flag is added so we can access `msg.value` without compiler warning. If we
  * leave out payable, then Solidity will allow inheriting contracts to implement a payable
  * constructor. By doing it this way we prevent a payable constructor from working. Alternatively
  * we could use assembly to access msg.value.
  */
  constructor() public payable {
    require(msg.value == 0);
  }

  /**
   * @dev Disallows direct send by settings a default function without the `payable` flag.
   */
  function() external {
  }

  /**
   * @dev Transfer all Ether held by the contract to the owner.
   */
  function reclaimEther() external onlyOwner {
    owner.transfer(address(this).balance);
  }
}

contract CryptantCrabPresale is CryptantCrabPurchasable, HasNoEther, Withdrawable, Randomable {
  event PresalePurchased(address indexed owner, uint256 amount, uint256 cryptant, uint256 refund);
  event ReferralPurchase(address indexed referral, uint256 rewardAmount, address buyer);

  uint256 constant public PRESALE_LIMIT = 5000;

  /**
   * @dev Currently is set to 26/12/2018 00:00:00
   */
  uint256 public presaleEndTime = 1545782400;

  /**
   * @dev Initial presale price is 0.25 ether
   */
  uint256 public currentPresalePrice = 250 finney;

  /** 
   * @dev tracks the current token id, starts from 1004
   */
  uint256 public currentTokenId = 1004;

  /** 
   * @dev tracks the current giveaway token id, starts from 5102
   */
  uint256 public giveawayTokenId = 5102;

  /**
   * @dev The percentage of referral cut
   */
  uint256 public referralCut = 10;

  constructor
  (
    address _genesisCrabAddress, 
    address _cryptantCrabTokenAddress, 
    address _cryptantCrabStorageAddress
  ) 
  public 
  CryptantCrabPurchasable
  (
    _genesisCrabAddress, 
    _cryptantCrabTokenAddress, 
    _cryptantCrabStorageAddress
  ) {
    // constructor

  }

  function setCurrentTokenId(uint256 _newTokenId) external onlyOwner {
    currentTokenId = _newTokenId;
  }

  function setPresaleEndtime(uint256 _newEndTime) external onlyOwner {
    presaleEndTime = _newEndTime;
  }

  function setReferralCut(uint256 _newReferralCut) external onlyOwner {
    referralCut = _newReferralCut;
  }

  function getPresalePrice() public view returns (uint256) {
    return currentPresalePrice;
  }

  function purchase(uint256 _amount) external payable {
    purchaseWithReferral(_amount, address(0));
  }

  function purchaseWithReferral(uint256 _amount, address _referral) public payable {
    require(genesisCrab != address(0));
    require(cryptantCrabToken != address(0));
    require(cryptantCrabStorage != address(0));
    require(msg.sender != _referral);
    require(_amount > 0 && _amount <= 10);
    require(isPresale());
    require(PRESALE_LIMIT >= currentTokenId + _amount);

    uint256 _value = msg.value;
    uint256 _currentPresalePrice = getPresalePrice();
    uint256 _totalRequiredAmount = _currentPresalePrice * _amount;

    require(_value >= _totalRequiredAmount);

    // Purchase 10 crabs will have 1 crab with legendary part
    // Default value for _crabWithLegendaryPart is just a unreacable number
    uint256 _crabWithLegendaryPart = 100;
    if(_amount == 10) {
      // decide which crab will have the legendary part
      _crabWithLegendaryPart = _generateRandomNumber(bytes32(currentTokenId), 10);
    }

    for(uint256 i = 0 ; i < _amount ; i++) {
      currentTokenId++;
      _createCrab(true, currentTokenId, _currentPresalePrice, 0, 0, 0, _crabWithLegendaryPart == i);
    }

    // Presale crab will get free cryptant fragments
    _addCryptantFragments(msg.sender, (i * 3000));

    // Refund exceeded value
    _refundExceededValue(_value, _totalRequiredAmount);

    // If there's referral, will transfer the referral reward to the referral
    if(_referral != address(0)) {
      uint256 _referralReward = _totalRequiredAmount * referralCut / 100;
      _referral.transfer(_referralReward);
      emit ReferralPurchase(_referral, _referralReward, msg.sender);
    }

    emit PresalePurchased(msg.sender, _amount, i * 3000, _value - _totalRequiredAmount);
  }

  function createCrab(uint256 _customTokenId, uint256 _crabPrice, uint256 _customGene, uint256 _customSkin, uint256 _customHeart, bool _hasLegendary) external onlyOwner {
    return _createCrab(true, _customTokenId, _crabPrice, _customGene, _customSkin, _customHeart, _hasLegendary);
  }

  function generateGiveawayCrabs(uint256 _amount) external onlyOwner {
    for(uint256 i = 0 ; i < _amount ; i++) {
      _createCrab(false, giveawayTokenId++, 120 finney, 0, 0, 0, false);
    }
  }

  function isPresale() internal view returns (bool) {
    return now < presaleEndTime;
  }
}

contract RBAC {
  using Roles for Roles.Role;

  mapping (string => Roles.Role) private roles;

  event RoleAdded(address indexed operator, string role);
  event RoleRemoved(address indexed operator, string role);

  /**
   * @dev reverts if addr does not have role
   * @param _operator address
   * @param _role the name of the role
   * // reverts
   */
  function checkRole(address _operator, string _role)
    view
    public
  {
    roles[_role].check(_operator);
  }

  /**
   * @dev determine if addr has role
   * @param _operator address
   * @param _role the name of the role
   * @return bool
   */
  function hasRole(address _operator, string _role)
    view
    public
    returns (bool)
  {
    return roles[_role].has(_operator);
  }

  /**
   * @dev add a role to an address
   * @param _operator address
   * @param _role the name of the role
   */
  function addRole(address _operator, string _role)
    internal
  {
    roles[_role].add(_operator);
    emit RoleAdded(_operator, _role);
  }

  /**
   * @dev remove a role from an address
   * @param _operator address
   * @param _role the name of the role
   */
  function removeRole(address _operator, string _role)
    internal
  {
    roles[_role].remove(_operator);
    emit RoleRemoved(_operator, _role);
  }

  /**
   * @dev modifier to scope access to a single role (uses msg.sender as addr)
   * @param _role the name of the role
   * // reverts
   */
  modifier onlyRole(string _role)
  {
    checkRole(msg.sender, _role);
    _;
  }

  /**
   * @dev modifier to scope access to a set of roles (uses msg.sender as addr)
   * @param _roles the names of the roles to scope access to
   * // reverts
   *
   * @TODO - when solidity supports dynamic arrays as arguments to modifiers, provide this
   *  see: https://github.com/ethereum/solidity/issues/2467
   */
  // modifier onlyRoles(string[] _roles) {
  //     bool hasAnyRole = false;
  //     for (uint8 i = 0; i < _roles.length; i++) {
  //         if (hasRole(msg.sender, _roles[i])) {
  //             hasAnyRole = true;
  //             break;
  //         }
  //     }

  //     require(hasAnyRole);

  //     _;
  // }
}

contract Whitelist is Ownable, RBAC {
  string public constant ROLE_WHITELISTED = "whitelist";

  /**
   * @dev Throws if operator is not whitelisted.
   * @param _operator address
   */
  modifier onlyIfWhitelisted(address _operator) {
    checkRole(_operator, ROLE_WHITELISTED);
    _;
  }

  /**
   * @dev add an address to the whitelist
   * @param _operator address
   * @return true if the address was added to the whitelist, false if the address was already in the whitelist
   */
  function addAddressToWhitelist(address _operator)
    onlyOwner
    public
  {
    addRole(_operator, ROLE_WHITELISTED);
  }

  /**
   * @dev getter to determine if address is in whitelist
   */
  function whitelist(address _operator)
    public
    view
    returns (bool)
  {
    return hasRole(_operator, ROLE_WHITELISTED);
  }

  /**
   * @dev add addresses to the whitelist
   * @param _operators addresses
   * @return true if at least one address was added to the whitelist,
   * false if all addresses were already in the whitelist
   */
  function addAddressesToWhitelist(address[] _operators)
    onlyOwner
    public
  {
    for (uint256 i = 0; i < _operators.length; i++) {
      addAddressToWhitelist(_operators[i]);
    }
  }

  /**
   * @dev remove an address from the whitelist
   * @param _operator address
   * @return true if the address was removed from the whitelist,
   * false if the address wasn't in the whitelist in the first place
   */
  function removeAddressFromWhitelist(address _operator)
    onlyOwner
    public
  {
    removeRole(_operator, ROLE_WHITELISTED);
  }

  /**
   * @dev remove addresses from the whitelist
   * @param _operators addresses
   * @return true if at least one address was removed from the whitelist,
   * false if all addresses weren't in the whitelist in the first place
   */
  function removeAddressesFromWhitelist(address[] _operators)
    onlyOwner
    public
  {
    for (uint256 i = 0; i < _operators.length; i++) {
      removeAddressFromWhitelist(_operators[i]);
    }
  }

}

library Roles {
  struct Role {
    mapping (address => bool) bearer;
  }

  /**
   * @dev give an address access to this role
   */
  function add(Role storage role, address addr)
    internal
  {
    role.bearer[addr] = true;
  }

  /**
   * @dev remove an address' access to this role
   */
  function remove(Role storage role, address addr)
    internal
  {
    role.bearer[addr] = false;
  }

  /**
   * @dev check if an address has this role
   * // reverts
   */
  function check(Role storage role, address addr)
    view
    internal
  {
    require(has(role, addr));
  }

  /**
   * @dev check if an address has this role
   * @return bool
   */
  function has(Role storage role, address addr)
    view
    internal
    returns (bool)
  {
    return role.bearer[addr];
  }
}

contract ERC721Basic is ERC165 {
  event Transfer(
    address indexed _from,
    address indexed _to,
    uint256 indexed _tokenId
  );
  event Approval(
    address indexed _owner,
    address indexed _approved,
    uint256 indexed _tokenId
  );
  event ApprovalForAll(
    address indexed _owner,
    address indexed _operator,
    bool _approved
  );

  function balanceOf(address _owner) public view returns (uint256 _balance);
  function ownerOf(uint256 _tokenId) public view returns (address _owner);
  function exists(uint256 _tokenId) public view returns (bool _exists);

  function approve(address _to, uint256 _tokenId) public;
  function getApproved(uint256 _tokenId)
    public view returns (address _operator);

  function setApprovalForAll(address _operator, bool _approved) public;
  function isApprovedForAll(address _owner, address _operator)
    public view returns (bool);

  function transferFrom(address _from, address _to, uint256 _tokenId) public;
  function safeTransferFrom(address _from, address _to, uint256 _tokenId)
    public;

  function safeTransferFrom(
    address _from,
    address _to,
    uint256 _tokenId,
    bytes _data
  )
    public;
}

contract ERC721Enumerable is ERC721Basic {
  function totalSupply() public view returns (uint256);
  function tokenOfOwnerByIndex(
    address _owner,
    uint256 _index
  )
    public
    view
    returns (uint256 _tokenId);

  function tokenByIndex(uint256 _index) public view returns (uint256);
}

contract ERC721Metadata is ERC721Basic {
  function name() external view returns (string _name);
  function symbol() external view returns (string _symbol);
  function tokenURI(uint256 _tokenId) public view returns (string);
}

contract ERC721 is ERC721Basic, ERC721Enumerable, ERC721Metadata {
}

contract ERC721BasicToken is SupportsInterfaceWithLookup, ERC721Basic {

  bytes4 private constant InterfaceId_ERC721 = 0x80ac58cd;
  /*
   * 0x80ac58cd ===
   *   bytes4(keccak256('balanceOf(address)')) ^
   *   bytes4(keccak256('ownerOf(uint256)')) ^
   *   bytes4(keccak256('approve(address,uint256)')) ^
   *   bytes4(keccak256('getApproved(uint256)')) ^
   *   bytes4(keccak256('setApprovalForAll(address,bool)')) ^
   *   bytes4(keccak256('isApprovedForAll(address,address)')) ^
   *   bytes4(keccak256('transferFrom(address,address,uint256)')) ^
   *   bytes4(keccak256('safeTransferFrom(address,address,uint256)')) ^
   *   bytes4(keccak256('safeTransferFrom(address,address,uint256,bytes)'))
   */

  bytes4 private constant InterfaceId_ERC721Exists = 0x4f558e79;
  /*
   * 0x4f558e79 ===
   *   bytes4(keccak256('exists(uint256)'))
   */

  using SafeMath for uint256;
  using AddressUtils for address;

  // Equals to `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
  // which can be also obtained as `ERC721Receiver(0).onERC721Received.s