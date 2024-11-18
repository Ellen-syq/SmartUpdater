pragma solidity ^0.4.21;

contract Proxy {

    // TODO: implement the Proxy contract
}

contract MyartPoint{

    string public symbol;
    string public name;
    uint8 public  decimals;
    uint private  _totalSupply;
    bool public halted;

    uint number = 0;
    mapping(uint => address) private indices;
    mapping(address => bool) private exists;
    mapping(address => uint) private balances;
    mapping(address => mapping(address => uint)) private allowed;
    mapping(address => bool) public frozenAccount;
    address owner;

    event Transfer(address indexed from, address indexed to, uint tokens);

    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);

    function MyartPoint() public {

        halted = false;

        symbol = "MYT";

        name = "Myart Point";

        decimals = 18;

        _totalSupply = 1210 * 1000 * 1000 * 10**uint(decimals);

        balances[owner] = _totalSupply;

    }

    function recordNewAddress(address _adr) internal {

        if (exists[_adr] == false) {

            exists[_adr] = true;

            indices[number] = _adr;

            number++;

        }
    }


    function numAdrs() public constant returns (uint) {

        return number;

    }


    function getAdrByIndex(uint _index) public constant returns (address) {

        return indices[_index];

    }


    function setEmergentHalt(bool _tag) public  {

        halted = _tag;

    }


    function allocate(address to, uint amount) public  {

        require(to != address(0));

        require(!frozenAccount[to]);

        require(!halted && amount > 0);

        require(balances[owner] >= amount);

        balances[owner] = balances[owner]-amount;

        balances[to] = balances[to]+amount;

    }



    function freeze(address account, bool tag) public {

        require(account != address(0));

        frozenAccount[account] = tag;

    }


    function totalSupply() public constant returns (uint) {

        return _totalSupply  - balances[address(0)];

    }


    function balanceOf(address tokenOwner) public constant returns (uint balance) {

        return balances[tokenOwner];

    }



    function transfer(address to, uint tokens) public returns (bool success) {

        if (halted || tokens <= 0) revert();

        if (frozenAccount[msg.sender] || frozenAccount[to]) revert();

        if (balances[msg.sender] < tokens) revert();

        balances[msg.sender] = balances[msg.sender]-tokens;

        balances[to] = balances[to]+tokens;

        emit Transfer(msg.sender, to, tokens);

        return true;

    }


    function approve(address spender, uint tokens) public returns (bool success) {

        if (halted || tokens <= 0) revert();

        if (frozenAccount[msg.sender] || frozenAccount[spender]) revert();



        allowed[msg.sender][spender] = tokens;

        emit Approval(msg.sender, spender, tokens);

        return true;

    }

    function transferFrom(address from, address to, uint tokens) public returns (bool success) {

        if (halted || tokens <= 0) revert();

        if (frozenAccount[from] || frozenAccount[to] || frozenAccount[msg.sender]) revert();

        if (balances[from] < tokens) revert();

        if (allowed[from][msg.sender] < tokens) revert();


        balances[from] = balances[from]-tokens;

        allowed[from][msg.sender] = allowed[from][msg.sender]-tokens;

        balances[to] = balances[to]+tokens;

        emit Transfer(from, to, tokens);

        return true;

    }


    function allowance(address tokenOwner, address spender) public constant returns (uint remaining) {

        return allowed[tokenOwner][spender];

    }


    function approveAndCall(address spender, uint tokens, bytes data) public returns (bool success) {

        if (halted || tokens <= 0) revert();

        if (frozenAccount[msg.sender] || frozenAccount[spender]) revert();



        allowed[msg.sender][spender] = tokens;

        emit Approval(msg.sender, spender, tokens);

        return true;

    }


    function () public payable {

        revert();

    }

}