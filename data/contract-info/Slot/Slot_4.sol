pragma solidity ^0.4.16;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {
  function mul(uint256 a, uint256 b) internal constant returns (uint256) {
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal constant returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  function sub(uint256 a, uint256 b) internal constant returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal constant returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}

/**
 * @title ERC20Basic
 * @dev Simpler version of ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/179
 */
contract ERC20Basic {
  uint256 public totalSupply;
  function balanceOf(address who) constant returns (uint256);
  function transfer(address to, uint256 value) returns (bool);
  event Transfer(address indexed from, address indexed to, uint256 value);
}


/**
 * @title Basic token
 * @dev Basic version of StandardToken, with no allowances. 
 */
contract BasicToken is ERC20Basic {
  using SafeMath for uint256;

  mapping(address => uint256) balances;

  /**
  * @dev transfer token for a specified address
  * @param _to The address to transfer to.
  * @param _value The amount to be transferred.
  */
  function transfer(address _to, uint256 _value) returns (bool) {
    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
    Transfer(msg.sender, _to, _value);
    return true;
  }

  /**
  * @dev Gets the balance of the specified address.
  * @param _owner The address to query the the balance of. 
  * @return An uint256 representing the amount owned by the passed address.
  */
  function balanceOf(address _owner) constant returns (uint256 balance) {
    return balances[_owner];
  }

}

/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 is ERC20Basic {
  function allowance(address owner, address spender) constant returns (uint256);
  function transferFrom(address from, address to, uint256 value) returns (bool);
  function approve(address spender, uint256 value) returns (bool);
  event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @title Standard ERC20 token
 *
 * @dev Implementation of the basic standard token.
 * @dev https://github.com/ethereum/EIPs/issues/20
 * @dev Based on code by FirstBlood: https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
 */
contract StandardToken is ERC20, BasicToken {

  mapping (address => mapping (address => uint256)) allowed;

  /**
   * @dev Transfer tokens from one address to another
   * @param _from address The address which you want to send tokens from
   * @param _to address The address which you want to transfer to
   * @param _value uint256 the amout of tokens to be transfered
   */
  function transferFrom(address _from, address _to, uint256 _value) returns (bool) {
    var _allowance = allowed[_from][msg.sender];

    // Check is not needed because sub(_allowance, _value) will already throw if this condition is not met
    // require (_value <= _allowance);

    balances[_to] = balances[_to].add(_value);
    balances[_from] = balances[_from].sub(_value);
    allowed[_from][msg.sender] = _allowance.sub(_value);
    Transfer(_from, _to, _value);
    return true;
  }

  /**
   * @dev Aprove the passed address to spend the specified amount of tokens on behalf of msg.sender.
   * @param _spender The address which will spend the funds.
   * @param _value The amount of tokens to be spent.
   */
  function approve(address _spender, uint256 _value) returns (bool) {

    // To change the approve amount you first have to reduce the addresses`
    //  allowance to zero by calling `approve(_spender, 0)` if it is not
    //  already 0 to mitigate the race condition described here:
    //  https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    require((_value == 0) || (allowed[msg.sender][_spender] == 0));

    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
    return true;
  }

  /**
   * @dev Function to check the amount of tokens that an owner allowed to a spender.
   * @param _owner address The address which owns the funds.
   * @param _spender address The address which will spend the funds.
   * @return A uint256 specifing the amount of tokens still avaible for the spender.
   */
  function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
    return allowed[_owner][_spender];
  }

}

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
  address public owner;

  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  function Ownable() {
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
  function transferOwnership(address newOwner) onlyOwner {
    if (newOwner != address(0)) {
      owner = newOwner;
    }
  }

}

/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 */
contract Pausable is Ownable {
  event Pause();
  event Unpause();

  bool public paused = false;

  /**
   * @dev modifier to allow actions only when the contract IS paused
   */
  modifier whenNotPaused() {
    require(!paused);
    _;
  }

  /**
   * @dev modifier to allow actions only when the contract IS NOT paused
   */
  modifier whenPaused {
    require(paused);
    _;
  }

  /**
   * @dev called by the owner to pause, triggers stopped state
   */
  function pause() onlyOwner whenNotPaused returns (bool) {
    paused = true;
    Pause();
    return true;
  }

  /**
   * @dev called by the owner to unpause, returns to normal state
   */
  function unpause() onlyOwner whenPaused returns (bool) {
    paused = false;
    Unpause();
    return true;
  }
}

/**
 * @title Slot Ticket token
 * @dev Simple ERC20 Token example, with mintable token creation
 * @dev Issue: * https://github.com/OpenZeppelin/zeppelin-solidity/issues/120
 * Based on code by TokenMarketNet: https://github.com/TokenMarketNet/ico/blob/master/contracts/MintableToken.sol
 */
 
contract SlotTicket is StandardToken, Ownable {

  string public name = "Slot Ticket";
  uint8 public decimals = 0;
  string public symbol = "SLOT";
  string public version = "0.1";

  event Mint(address indexed to, uint256 amount);

  function mint(address _to, uint256 _amount) onlyOwner returns (bool) {
    totalSupply = totalSupply.add(_amount);
    balances[_to] = balances[_to].add(_amount);
    Mint(_to, _amount);
    Transfer(0x0, _to, _amount); // so it is displayed properly on EtherScan
    return true;
  }

function destroy() onlyOwner {
    // Transfer Eth to owner and terminate contract
    selfdestruct(owner);
  }

}

contract Slot is Ownable, Pausable { // TODO: for production disable tokenDestructible
    using SafeMath for uint256;

    // this token is just a gimmick to receive when buying a ticket, it wont affect the prize
    SlotTicket public token;

    // every participant has an account index, the winners are picked from here
    // all winners are picked in order from the single random int 
    // needs to be cleared after every game
    mapping (uint => mapping (uint => address)) participants; // game number => counter => address
    uint256[] prizes = [0.04 ether, 
                        0.02 ether,
                        0.01 ether, 
                        5 finney, 
                        5 finney, 
                        5 finney, 
                        5 finney, 
                        5 finney];
    

    uint8   constant public SIZE = 10; // size of the lottery
    uint32  constant public JACKPOT_SIZE = 1000000; // one in a million
    uint256 constant public PRICE = 10 finney;
    
    uint256 public jackpot;
    uint256 public gameNumber;
    address wallet;
    uint256 counter;

    event AnotherParticipant(address indexed _participant, uint256 indexed _game, uint256 indexed _number);
    event PrizeAwarded(uint256 indexed _game , address indexed _winner, uint256 indexed _amount);
    event JackpotAwarded(uint256 indexed _game, address indexed _winner, uint256 indexed _amount);
    event Refunded(address indexed _participant, uint256 _amount);

    function Slot(address _wallet) payable {
        token = new SlotTicket();
        wallet = _wallet;

        jackpot = 0;
        gameNumber = 0;
        counter = 0;
    }

    function() payable {
        // fallback function to buy tickets from
        buyTicketsFor(msg.sender);
    }

    function buyTicketsFor(address beneficiary) whenNotPaused() payable {
        require(beneficiary != 0x0);
        require(msg.value >= PRICE);

        // calculate number of tickets, issue tokens and add participants
        // every 100 finney buys a ticket, the rest is returned
        uint256 change = msg.value%PRICE;
        uint256 numberOfTickets = msg.value.sub(change).div(PRICE);
        token.mint(beneficiary, numberOfTickets);
        addParticipant(beneficiary, numberOfTickets);

        // Return change to msg.sender
        // TODO: check if change amount correct
        msg.sender.transfer(change);
    }

    function addParticipant(address _participant, uint256 _numberOfTickets) private {
        // if number of tickets exceeds the size of the game, tickets are added to next game

        for (uint256 i = 0; i < _numberOfTickets; i++) {
            participants[counter/SIZE][counter%SIZE] = _participant;
            AnotherParticipant(_participant, counter/SIZE, counter%SIZE);

            // msg.sender triggers the drawing of lots
            if (++counter%SIZE == 0) 
                awardPrizes();
        
            // loop continues if there are more tickets
        }
        
    }
    
    function rand(uint32 _size) constant private returns (uint256 randomNumber) {
      // Providing random numbers within a deterministic system is, naturally, an impossible task.
      // However, we can approximate with pseudo-random numbers by utilising data which is generally unknowable
      // at the time of transacting. Such data might include the blockâ€™s hash.

        return uint256(keccak256(block.blockhash(block.number-1), block.blockhash(block.number-10)))%_size;
    }

    function awardPrizes() private {
        uint256 winnerIndex = rand(SIZE);
        // hash result of two digit number (index) with 4 leading zeroes will win
        bool jackpotWon = winnerIndex == rand(JACKPOT_SIZE); 

        // loop throught the prizes, incrementing the winner index to receive the next prize
        for (uint8 i = 0; i < prizes.length; i++) {
            
            if (jackpotWon && i==0) 
                distributeJackpot(winnerIndex);

            participants[gameNumber][winnerIndex%SIZE].transfer(prizes[i]); // msg.sender pays the gas, he's refunded later, % to wrap around
            PrizeAwarded(gameNumber, participants[gameNumber][winnerIndex%SIZE], prizes[i]);

            winnerIndex++;
        }
        
        // Split the rest
        jackpot = jackpot.add(2.5 finney);  // add to jackpot
        wallet.transfer(2.49 finney);        // *cash register sound*
        // gas for Tx is around 100000, times 10 transactions, of around 5 Gwei is around 1 finney
        msg.sender.transfer(0.01 finney);     // repay gas to msg.sender

        gameNumber++;
    }

    function distributeJackpot(uint256 _winnerIndex) private {
        participants[gameNumber][_winnerIndex].transfer(jackpot);
        JackpotAwarded(gameNumber,  participants[gameNumber][_winnerIndex], jackpot);
        jackpot = 0; // later on in the code sequence funds will be added
    }

    function refundAll() onlyOwner {
        // We send refunds after the game has gone 1 month without conclusion

        for (uint8 i = 0; i < counter%SIZE; i++) { // not counter.size, but modulus of SIZE
            participants[gameNumber][i].transfer(PRICE);
            Refunded(msg.sender, PRICE);
        }

        // reduce the counter
        counter -= counter%SIZE;
    }

    function destroy() onlyOwner {
        // Transfer Eth to owner and terminate contract
        token.destroy();
        selfdestruct(owner);
    }

    function changeWallet(address _newWallet) onlyOwner {
        require(_newWallet != 0x0);
        wallet = _newWallet;
    }

}