pragma solidity ^0.4.11;



contract Ownable {
  address public owner;


  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  function Ownable() public {
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
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address newOwner) public onlyOwner {
    if (newOwner != address(0)) {
      owner = newOwner;
    }
  }

}

/// @title Interface for contracts conforming to ERC-721: Non-Fungible Tokens
/// @author Dieter Shirley <dete@axiomzen.co> (https://github.com/dete)
contract ERC721 {
    // Required methods
    function totalSupply() public view returns (uint256 total);
    function balanceOf(address _owner) public view returns (uint256 balance);
    function ownerOf(uint256 _tokenId) external view returns (address owner);
    function approve(address _to, uint256 _tokenId) external;
    function transfer(address _to, uint256 _tokenId) external;
    function transferFrom(address _from, address _to, uint256 _tokenId) external;

    // Events
    event Transfer(address from, address to, uint256 tokenId);
    event Approval(address owner, address approved, uint256 tokenId);

    // Optional
    // function name() public view returns (string name);
    // function symbol() public view returns (string symbol);
    // function tokensOfOwner(address _owner) external view returns (uint256[] tokenIds);
    // function tokenMetadata(uint256 _tokenId, string _preferredTransport) public view returns (string infoUrl);

    // ERC-165 Compatibility (https://github.com/ethereum/EIPs/issues/165)
    function supportsInterface(bytes4 _interfaceID) external view returns (bool);
}











contract MonsterAccessControl {

    event ContractUpgrade(address newContract);

     // The addresses of the accounts (or contracts) that can execute actions within each roles.
    address public adminAddress;
    

  

    /// @dev Access modifier for CEO-only functionality
    modifier onlyAdmin() {
        require(msg.sender == adminAddress);
        _;
    }

  

    
}

// This contract stores all data on the blockchain
// only our other contracts can interact with this
// the data here will be valid for all eternity even if other contracts get updated
// this way we can make sure that our Monsters have a hard-coded value attached to them
// that no one including us can change(!)
contract MonstersData {

    address coreContract; // 
    


    struct Monster {
        // timestamp of block when this monster was spawned/created
        uint64 birthTime;

        // generation number
        // gen0 is the very first generation - the later monster spawn the less likely they are to have
        // special attributes and stats
       // uint16 generation;

        uint16 hp; // health points 
        uint16 attack; // attack points
        uint16 defense; // defense points
        uint16 spAttack; // special attack
        uint16 spDefense; // special defense
        uint16 speed; // speed responsible of who attacks first(!)
        

        uint16 typeOne;
        uint16 typeTwo;

        uint16 mID; // this id (from 1 to 151) is responsible for everything visually like showing the real deal!
        bool tradeable;
        //uint16 uID; // unique id
        
        // These attributes are handled by mappings since they would overflow the maximum stack
        //bool female
        // string nickname
        

    }

    // lv1 base stats
    struct MonsterBaseStats {
        uint16 hp;
        uint16 attack;
        uint16 defense;
        uint16 spAttack;
        uint16 spDefense;
        uint16 speed;
        
    }

    // lomonsterion struct used for travelling around the "world"
    // 
    struct Area {
        // areaID used in-engine to determine world position
       
             
        // minimum level to enter this area...
        uint16 minLevel;
    }

    struct Trainer {
        // timestamp of block when this player/trainer was created
        uint64 birthTime;
        
        // add username
        string username;
       
        
        // current area in the "world"
        uint16 currArea;
        
        address owner;
        
       
        
    }


   


    // take timestamp of block this game was created on the blockchain
    uint64 creationBlock = uint64(now);
   
   

   
  
    


    
  
        


}




contract MonstersBase is MonsterAccessControl, MonstersData {

    /// @dev Transfer event as defined in current draft of ERC721. Emitted every time a monster
    ///  ownership is assigned, including births.
    event Transfer(address from, address to, uint256 tokenId);

    bool lockedMonsterCreator = false;

    MonsterAuction public monsterAuction;

    MonsterCreatorInterface public monsterCreator;


    function setMonsterCreatorAddress(address _address) external onlyAdmin {
        // only set this once so we (the devs) can't cheat!
        require(!lockedMonsterCreator);
        MonsterCreatorInterface candidateContract = MonsterCreatorInterface(_address);

       

        monsterCreator = candidateContract;
        lockedMonsterCreator = true;

    }
    
    // An approximation of currently how many seconds are in between blocks.
    uint256 public secondsPerBlock = 15;
  

    // array containing all monsters in existence
    Monster[] monsters;

    uint8[] areas;

    uint8 areaIndex = 0;
    


      mapping(address => Trainer) public addressToTrainer;
    

    /// @dev A mapping from monster IDs to the address that owns them. All monster have
    ///  some valid owner address, even gen0 monster are created with a non-zero owner.
    mapping (uint256 => address) public monsterIndexToOwner;

    // @dev A mapping from owner address to count of tokens that address owns.
    //  Used internally inside balanceOf() to resolve ownership count.
    mapping (address => uint256) ownershipTokenCount;


    mapping (uint256 => address) public monsterIndexToApproved;
    
    mapping (uint256 => string) public monsterIdToNickname;
    
    mapping (uint256 => bool) public monsterIdToTradeable;
    
    mapping (uint256 => uint256) public monsterIdToGeneration;


     mapping (uint256 => MonsterBaseStats) public baseStats;

     mapping (uint256 => uint8[7]) public monsterIdToIVs;
    


    // adds new area to world 
    function _createArea() internal {
            
            areaIndex++;
            areas.push(areaIndex);
            
            
        }

    


    function _createMonster(
        uint256 _generation,
        uint256 _hp,
        uint256 _attack,
        uint256 _defense,
        uint256 _spAttack,
        uint256 _spDefense,
        uint256 _speed,
        uint256 _typeOne,
        uint256 _typeTwo,
        address _owner,
        uint256 _mID,
        bool tradeable
        
    )
        internal
        returns (uint)
        {
           

            Monster memory _monster = Monster({
                birthTime: uint64(now),
                hp: uint16(_hp),
                attack: uint16(_attack),
                defense: uint16(_defense),
                spAttack: uint16(_spAttack),
                spDefense: uint16(_spDefense),
                speed: uint16(_speed),
                typeOne: uint16(_typeOne),
                typeTwo: uint16(_typeTwo),
                mID: uint16(_mID),
                tradeable: tradeable
                


            });
            uint256 newMonsterId = monsters.push(_monster) - 1;
            monsterIdToTradeable[newMonsterId] = tradeable;
            monsterIdToGeneration[newMonsterId] = _generation;
           

            require(newMonsterId == uint256(uint32(newMonsterId)));
            
           
          
            
             monsterIdToNickname[newMonsterId] = "";

            _transfer(0, _owner, newMonsterId);

            return newMonsterId;


        }
    
    function _createTrainer(string _username, uint16 _starterId, address _owner)
        internal
        returns (uint mon)
        {
            
           
            Trainer memory _trainer = Trainer({
               
                birthTime: uint64(now),
                username: string(_username),
                currArea: uint16(1), // sets to first area!,
                owner: address(_owner)
                
            });
            addressToTrainer[_owner] = _trainer;
            
            // starter stats are hardcoded!
            if (_starterId == 1) {
                uint8[8] memory Stats = uint8[8](monsterCreator.getMonsterStats(1));
                mon = _createMonster(0, Stats[0], Stats[1], Stats[2], Stats[3], Stats[4], Stats[5], Stats[6], Stats[7], _owner, 1, false);
               
            } else if (_starterId == 2) {
                uint8[8] memory Stats2 = uint8[8](monsterCreator.getMonsterStats(4));
                mon = _createMonster(0, Stats2[0], Stats2[1], Stats2[2], Stats2[3], Stats2[4], Stats2[5], Stats2[6], Stats2[7], _owner, 4, false);
                
            } else if (_starterId == 3) {
                uint8[8] memory Stats3 = uint8[8](monsterCreator.getMonsterStats(7));
                mon = _createMonster(0, Stats3[0], Stats3[1], Stats3[2], Stats3[3], Stats3[4], Stats3[5], Stats3[6], Stats3[7], _owner, 7, false);
                
            }
            
        }


    function _moveToArea(uint16 _newArea, address player) internal {
            
            addressToTrainer[player].currArea = _newArea;
          
        }   
        
    
     

    
    // assigns ownership of monster to address
    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        ownershipTokenCount[_to]++;
        monsterIndexToOwner[_tokenId] = _to;

        if (_from != address(0)) {
            ownershipTokenCount[_from]--;

            // clear any previously approved ownership exchange
            delete monsterIndexToApproved[_tokenId];
        }

        // Emit Transfer event
        Transfer(_from, _to, _tokenId);
    }


    // Only admin can fix how many seconds per blocks are currently observed.
    function setSecondsPerBlock(uint256 secs) external onlyAdmin {
        //require(secs < cooldowns[0]);
        secondsPerBlock = secs;
    }


    


}

/// @title The external contract that is responsible for generating metadata for the monsters,
///  it has one function that will return the data as bytes.
contract ERC721Metadata {
    /// @dev Given a token Id, returns a byte array that is supposed to be converted into string.
    function getMetadata(uint256 _tokenId, string) public view returns (bytes32[4] buffer, uint256 count) {
        if (_tokenId == 1) {
            buffer[0] = "Hello World! :D";
            count = 15;
        } else if (_tokenId == 2) {
            buffer[0] = "I would definitely choose a medi";
            buffer[1] = "um length string.";
            count = 49;
        } else if (_tokenId == 3) {
            buffer[0] = "Lorem ipsum dolor sit amet, mi e";
            buffer[1] = "st accumsan dapibus augue lorem,";
            buffer[2] = " tristique vestibulum id, libero";
            buffer[3] = " suscipit varius sapien aliquam.";
            count = 128;
        }
    }
}


contract MonsterOwnership is MonstersBase, ERC721 {

    string public constant name = "ChainMonsters";
    string public constant symbol = "CHMO";


    // The contract that will return monster metadata
    ERC721Metadata public erc721Metadata;

    bytes4 constant InterfaceSignature_ERC165 =
        bytes4(keccak256('supportsInterface(bytes4)'));




    bytes4 constant InterfaceSignature_ERC721 =
        bytes4(keccak256('name()')) ^
        bytes4(keccak256('symbol()')) ^
        bytes4(keccak256('totalSupply()')) ^
        bytes4(keccak256('balanceOf(address)')) ^
        bytes4(keccak256('ownerOf(uint256)')) ^
        bytes4(keccak256('approve(address,uint256)')) ^
        bytes4(keccak256('transfer(address,uint256)')) ^
        bytes4(keccak256('transferFrom(address,address,uint256)')) ^
        bytes4(keccak256('tokensOfOwner(address)')) ^
        bytes4(keccak256('tokenMetadata(uint256,string)'));




    function supportsInterface(bytes4 _interfaceID) external view returns (bool) {
        // DEBUG ONLY
        //require((InterfaceSignature_ERC165 == 0x01ffc9a7) && (InterfaceSignature_ERC721 == 0x9a20483d));

        return ((_interfaceID == InterfaceSignature_ERC165) || (_interfaceID == InterfaceSignature_ERC721));
    }

    /// @dev Set the address of the sibling contract that tracks metadata.
    ///  CEO only.
    function setMetadataAddress(address _contractAddress) public onlyAdmin {
        erc721Metadata = ERC721Metadata(_contractAddress);
    }

    function _owns(address _claimant, uint256 _tokenId) internal view returns (bool) {
        return monsterIndexToOwner[_tokenId] == _claimant;
    }
    
    function _isTradeable(uint256 _tokenId) external view returns (bool) {
        return monsterIdToTradeable[_tokenId];
    }
    
    
    /// @dev Checks if a given address currently has transferApproval for a particular monster.
    /// @param _claimant the address we are confirming monster is approved for.
    /// @param _tokenId monster id, only valid when > 0
    function _approvedFor(address _claimant, uint256 _tokenId) internal view returns (bool) {
        return monsterIndexToApproved[_tokenId] == _claimant;
    }

    /// @dev Marks an address as being approved for transferFrom(), overwriting any previous
    ///  approval. Setting _approved to address(0) clears all transfer approval.
    ///  NOTE: _approve() does NOT send the Approval event. This is intentional because
    ///  _approve() and transferFrom() are used together for putting monsters on auction, and
    ///  there is no value in spamming the log with Approval events in that case.
    function _approve(uint256 _tokenId, address _approved) internal {
        monsterIndexToApproved[_tokenId] = _approved;
    }
    
    
    function balanceOf(address _owner) public view returns (uint256 count) {
        return ownershipTokenCount[_owner];
    }


    function transfer (address _to, uint256 _tokenId) external {
        // Safety check to prevent against an unexpected 0x0 default.
        require(_to != address(0));
        // Disallow transfers to this contract to prevent accidental misuse.
        // The contract should never own any monsters (except very briefly
        // after a gen0 monster is created and before it goes on auction).
        require(_to != address(this));
        

        // You can only send your own monster.
        require(_owns(msg.sender, _tokenId));

        // Reassign ownership, clear pending approvals, emit Transfer event.
        _transfer(msg.sender, _to, _tokenId);
    }

    
    

/// @notice Grant another address the right to transfer a specific monster via
    ///  transferFrom(). This is the preferred flow for transfering NFTs to contracts.
    /// @param _to The address to be granted transfer approval. Pass address(0) to
    ///  clear all approvals.
    /// @param _tokenId The ID of the monster that can be transferred if this call succeeds.
    /// @dev Required for ERC-721 compliance.
    function approve(address _to, uint256 _tokenId ) external {
        // Only an owner can grant transfer approval.
        require(_owns(msg.sender, _tokenId));

        // Register the approval (replacing any previous approval).
        _approve(_tokenId, _to);

        // Emit approval event.
        Approval(msg.sender, _to, _tokenId);
    }

    /// @notice Transfer a monster owned by another address, for which the calling address
    ///  has previously been granted transfer approval by the owner.
    /// @param _from The address that owns the monster to be transfered.
    /// @param _to The address that should take ownership of the monster. Can be any address,
    ///  including the caller.
    /// @param _tokenId The ID of the monster to be transferred.
    /// @dev Required for ERC-721 compliance.
    function transferFrom (address _from, address _to, uint256 _tokenId ) external {
        // Safety check to prevent against an unexpected 0x0 default.
        require(_to != address(0));
        // Disallow transfers to this contract to prevent accidental misuse.
        // The contract should never own any monsters (except very briefly
        // after a gen0 monster is created and before it goes on auction).
        require(_to != address(this));
        // Check for approval and valid ownership
        //require(_approvedFor(msg.sender, _tokenId));
        require(_owns(_from, _tokenId));

        // Reassign ownership (also clears pending approvals and emits Transfer event).
        _transfer(_from, _to, _tokenId);
    }

    function totalSupply() public view returns (uint) {
        return monsters.length;
    }


    function ownerOf(uint256 _tokenId)
            external
            view
            returns (address owner)
        {
            owner = monsterIndexToOwner[_tokenId];

            require(owner != address(0));
        }

     function tokensOfOwner(address _owner) external view returns(uint256[] ownerTokens) {
        uint256 tokenCount = balanceOf(_owner);

        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 totalMonsters = totalSupply();
            uint256 resultIndex = 0;

            
            uint256 monsterId;

            for (monsterId = 0; monsterId <= totalMonsters; monsterId++) {
                if (monsterIndexToOwner[monsterId] == _owner) {
                    result[resultIndex] = monsterId;
                    resultIndex++;
                }
            }

            return result;
        }
    }


   

    /// @dev Adapted from memcpy() by @arachnid (Nick Johnson <arachnid@notdot.net>)
    ///  This method is licenced under the Apache License.
    ///  Ref: https://github.com/Arachnid/solidity-stringutils/blob/2f6ca9accb48ae14c66f1437ec50ed19a0616f78/strings.sol
    function _memcpy(uint _dest, uint _src, uint _len) private view {
        // Copy word-length chunks while possible
        for(; _len >= 32; _len -= 32) {
            assembly {
                mstore(_dest, mload(_src))
            }
            _dest += 32;
            _src += 32;
        }

        // Copy remaining bytes
        uint256 mask = 256 ** (32 - _len) - 1;
        assembly {
            let srcpart := and(mload(_src), not(mask))
            let destpart := and(mload(_dest), mask)
            mstore(_dest, or(destpart, srcpart))
        }
    }

    /// @dev Adapted from toString(slice) by @arachnid (Nick Johnson <arachnid@notdot.net>)
    ///  This method is licenced under the Apache License.
    ///  Ref: https://github.com/Arachnid/solidity-stringutils/blob/2f6ca9accb48ae14c66f1437ec50ed19a0616f78/strings.sol
    function _toString(bytes32[4] _rawBytes, uint256 _stringLength) private view returns (string) {
        var outputString = new string(_stringLength);
        uint256 outputPtr;
        uint256 bytesPtr;

        assembly {
            outputPtr := add(outputString, 32)
            bytesPtr := _rawBytes
        }

        _memcpy(outputPtr, bytesPtr, _stringLength);

        return outputString;
    }

    /// @notice Returns a URI pointing to a metadata package for this token conforming to
    ///  ERC-721 (https://github.com/ethereum/EIPs/issues/721)
    /// @param _tokenId The ID number of the monster whose metadata should be returned.
    function tokenMetadata(uint256 _tokenId, string _preferredTransport) external view returns (string infoUrl) {
        require(erc721Metadata != address(0));
        bytes32[4] memory buffer;
        uint256 count;
        (buffer, count) = erc721Metadata.getMetadata(_tokenId, _preferredTransport);

        return _toString(buffer, count);
    }

}

contract MonsterAuctionBase {
    
    
    // Reference to contract tracking NFT ownership
    ERC721 public nonFungibleContract;
    ChainMonstersCore public core;
    
    struct Auction {

        // current owner
        address seller;

        // price in wei
        uint256 price;

        // time when auction started
        uint64 startedAt;

        uint256 id;
    }

  

    // Cut owner takes on each auction, measured in basis points (1/100 of a percent).
    // Values 0-10,000 map to 0%-100%
    uint256 public ownerCut;

    // Map from token ID to their corresponding auction.
    mapping(uint256 => Auction) tokenIdToAuction;

    mapping(uint256 => address) public auctionIdToSeller;
    
    mapping (address => uint256) public ownershipAuctionCount;


    event AuctionCreated(uint256 tokenId, uint256 price, uint256 uID, address seller);
    event AuctionSuccessful(uint256 tokenId, uint256 price, address newOwner, uint256 uID);
    event AuctionCancelled(uint256 tokenId, uint256 uID);


    function _transfer(address _receiver, uint256 _tokenId) internal {
        // it will throw if transfer fails
        nonFungibleContract.transfer(_receiver, _tokenId);
    }


    function _addAuction(uint256 _tokenId, Auction _auction) internal {
        
        tokenIdToAuction[_tokenId] = _auction;

        AuctionCreated(
            uint256(_tokenId),
            uint256(_auction.price),
            uint256(_auction.id),
            address(_auction.seller)
        );
       
    }


    function _cancelAuction(uint256 _tokenId, address _seller) internal {
        
        Auction storage _auction = tokenIdToAuction[_tokenId];

        uint256 uID = _auction.id;
        
        _removeAuction(_tokenId);
        ownershipAuctionCount[_seller]--;
        _transfer(_seller, _tokenId);
        
        AuctionCancelled(_tokenId, uID);
    }


    function _buy(uint256 _tokenId, uint256 _bidAmount)
        internal
        returns (uint256)
        {
            Auction storage auction = tokenIdToAuction[_tokenId];
        

        require(_isOnAuction(auction));

        uint256 price = auction.price;
        require(_bidAmount >= price);

        address seller = auction.seller;

        uint256 uID = auction.id;
        // Auction Bid looks fine! so remove
        _removeAuction(_tokenId);
        ownershipAuctionCount[seller]--;

        if (price > 0) {

            uint256 auctioneerCut = _computeCut(price);
            uint256 sellerProceeds = price - auctioneerCut;

            // NOTE: Doing a transfer() in the middle of a complex
            // method like this is generally discouraged because of
            // reentrancy attacks and DoS attacks if the seller is
            // a contract with an invalid fallback function. We explicitly
            // guard against reentrancy attacks by removing the auction
            // before calling transfer(), and the only thing the seller
            // can DoS is the sale of their own asset! (And if it's an
            // accident, they can call cancelAuction(). )
            if(seller != address(core)) {
                seller.transfer(sellerProceeds);
            }
        }

        // Calculate any excess funds included with the bid. If the excess
        // is anything worth worrying about, transfer it back to bidder.
        // NOTE: We checked above that the bid amount is greater than or
        // equal to the price so this cannot underflow.
        uint256 bidExcess = _bidAmount - price;

        // Return the funds. Similar to the previous transfer, this is
        // not susceptible to a re-entry attack because the auction is
        // removed before any transfers occur.
        msg.sender.transfer(bidExcess);

        // Tell the world!
        AuctionSuccessful(_tokenId, price, msg.sender, uID);

        return price;


    }

    function _removeAuction(uint256 _tokenId) internal {
        delete tokenIdToAuction[_tokenId];
    }

    function _isOnAuction(Auction storage _auction) internal view returns (bool) {
        return (_auction.startedAt > 0);
    }

     function _computeCut(uint256 _price) internal view returns (uint256) {
        // NOTE: We don't use SafeMath (or similar) in this function because
        //  all of our entry functions carefully cap the maximum values for
        //  currency (at 128-bits), and ownerCut <= 10000 (see the require()
        //  statement in the ClockAuction constructor). The result of this
        //  function is always guaranteed to be <= _price.
        return _price * ownerCut / 10000;
    }

    

}


contract MonsterAuction is  MonsterAuctionBase, Ownable {


    bool public isMonsterAuction = true;
     uint256 public auctionIndex = 0;

    /// @dev The ERC-165 interface signature for ERC-721.
    ///  Ref: https://github.com/ethereum/EIPs/issues/165
    ///  Ref: https://github.com/ethereum/EIPs/issues/721
    bytes4 constant InterfaceSignature_ERC721 = bytes4(0x9a20483d);

    function MonsterAuction(address _nftAddress, uint256 _cut) public {
        require(_cut <= 10000);
        ownerCut = _cut;

        ERC721 candidateContract = ERC721(_nftAddress);
        
        nonFungibleContract = candidateContract;
        ChainMonstersCore candidateCoreContract = ChainMonstersCore(_nftAddress);
        core = candidateCoreContract;

        
    }
    
    // only possible to decrease ownerCut!
    function setOwnerCut(uint256 _cut) external onlyOwner {
        require(_cut <= ownerCut);
        ownerCut = _cut;
    }
    
    
    function _owns(address _claimant, uint256 _tokenId) internal view returns (bool) {
        return (nonFungibleContract.ownerOf(_tokenId) == _claimant);
    }
    
    function _escrow(address _owner, uint256 _tokenId) internal {
        // it will throw if transfer fails
        nonFungibleContract.transferFrom(_owner, this, _tokenId);
    }

    function withdrawBalance() external onlyOwner {
       
       
       uint256 balance = this.balance;
       
       
        owner.transfer(balance);

        
       
    }

    
    function tokensInAuctionsOfOwner(address _owner) external view returns(uint256[] auctionTokens) {
        
           uint256 numAuctions = ownershipAuctionCount[_owner];

            
        
            uint256[] memory result = new uint256[](numAuctions);
            uint256 totalAuctions = core.totalSupply();
            uint256 resultIndex = 0;

            
            uint256 auctionId;

            for (auctionId = 0; auctionId <= totalAuctions; auctionId++) {
                
                Auction storage auction = tokenIdToAuction[auctionId];
                if (auction.seller == _owner) {
                    
                    result[resultIndex] = auctionId;
                    resultIndex++;
                }
            }

            return result;
        
        
    }




    function createAuction(uint256 _tokenId, uint256 _price, address _seller) external {
             require(_price == uint256(_price));
            require(core._isTradeable(_tokenId));
             require(_owns(msg.sender, _tokenId));
             _escrow(msg.sender, _tokenId);

            

            
             Auction memory auction = Auction(
                 _seller,
                 uint256(_price),
                 uint64(now),
                 uint256(auctionIndex)
             );

            auctionIdToSeller[auctionIndex] = _seller;
            ownershipAuctionCount[_seller]++;
            
             auctionIndex++;
             _addAuction(_tokenId, auction);
        }

    function buy(uint256 _tokenId) external payable {
            //delete auctionIdToSeller[_tokenId];
            // buy will throw if the bid or funds transfer fails
            _buy (_tokenId, msg.value);
            _transfer(msg.sender, _tokenId);
            
            
        }

    
    function cancelAuction(uint256 _tokenId) external {
            Auction storage auction = tokenIdToAuction[_tokenId];
            require(_isOnAuction(auction));

            address seller = auction.seller;
            require(msg.sender == seller);
            
            
            _cancelAuction(_tokenId, seller);
        }

    
    function getAuction(uint256 _tokenId)
        external
        view
        returns
        (
            address seller,
            uint256 price,
            uint256 startedAt
        ) {
            Auction storage auction = tokenIdToAuction[_tokenId];
            require(_isOnAuction(auction));

            return (
                auction.seller,
                auction.price,
                auction.startedAt
            );
        }


    function getPrice(uint256 _tokenId)
        external
        view
        returns (uint256)
        {
            Auction storage auction = tokenIdToAuction[_tokenId];
            require(_isOnAuction(auction));
            return auction.price;
        }
}


contract ChainMonstersAuction is MonsterOwnership {

  


    function setMonsterAuctionAddress(address _address) external onlyAdmin {
        MonsterAuction candidateContract = MonsterAuction(_address);

        require(candidateContract.isMonsterAuction());

        monsterAuction = candidateContract;
    }



    uint256 public constant PROMO_CREATION_LIMIT = 5000;

    uint256 public constant GEN0_CREATION_LIMIT = 5000;

    // Counts the number of monster the contract owner has created.
    uint256 public promoCreatedCount;
    uint256 public gen0CreatedCount;


    
    // its stats are completely dependent on the spawn alghorithm
    function createPromoMonster(uint256 _mId, address _owner) external onlyAdmin {
       

       // during generation we have to keep in mind that we have only 10,000 tokens available
       // which have to be divided by 151 monsters, some rarer than others
       // see WhitePaper for gen0/promo monster plan
        
        require(promoCreatedCount < PROMO_CREATION_LIMIT);

        promoCreatedCount++;
        uint8[8] memory Stats = uint8[8](monsterCreator.getMonsterStats(uint256(_mId)));
        uint8[7] memory IVs = uint8[7](monsterCreator.getGen0IVs());
        
        uint256 monsterId = _createMonster(0, Stats[0], Stats[1], Stats[2], Stats[3], Stats[4], Stats[5], Stats[6], Stats[7], _owner, _mId, true);
        monsterIdToTradeable[monsterId] = true;

        monsterIdToIVs[monsterId] = IVs;
        
       
    }

   


    function createGen0Auction(uint256 _mId, uint256 price) external onlyAdmin {
        require(gen0CreatedCount < GEN0_CREATION_LIMIT);

        uint8[8] memory Stats = uint8[8](monsterCreator.getMonsterStats(uint256(_mId)));
        uint8[7] memory IVs = uint8[7](monsterCreator.getGen0IVs());
        uint256 monsterId = _createMonster(0, Stats[0], Stats[1], Stats[2], Stats[3], Stats[4], Stats[5], Stats[6], Stats[7], this, _mId, true);
        monsterIdToTradeable[monsterId] = true;

        monsterIdToIVs[monsterId] = IVs;

        monsterAuction.createAuction(monsterId, price, address(this));


        gen0CreatedCount++;
        
    }

    
}


// used during launch for world championship
// can and will be upgraded during development with new battle system!
// this is just to give players something to do and test their monsters
// also demonstrates how we can build up more mechanics on top of our locked core contract!
contract MonsterChampionship is Ownable {

    bool public is