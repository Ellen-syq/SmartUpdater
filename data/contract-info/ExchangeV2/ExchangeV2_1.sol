pragma solidity ^0.4.24;

/**
 * @title Log Various Error Types
 * @author Adam Lemmon <adam@oraclize.it>
 * @dev Inherit this contract and your may now log errors easily
 * To support various error types, params, etc.
 */
contract LoggingErrors {
  /**
  * Events
  */
  event LogErrorString(string errorString);

  /**
  * Error cases
  */

  /**
   * @dev Default error to simply log the error message and return
   * @param _errorMessage The error message to log
   * @return ALWAYS false
   */
  function error(string _errorMessage) internal returns(bool) {
    LogErrorString(_errorMessage);
    return false;
  }
}

/**
 * @title Wallet Connector
 * @dev Connect the wallet contract to the correct Wallet Logic version
 */
contract WalletConnector is LoggingErrors {
  /**
   * Storage
   */
  address public owner_;
  address public latestLogic_;
  uint256 public latestVersion_;
  mapping(uint256 => address) public logicVersions_;
  uint256 public birthBlock_;

  /**
   * Events
   */
  event LogLogicVersionAdded(uint256 version);
  event LogLogicVersionRemoved(uint256 version);

  /**
   * @dev Constructor to set the latest logic address
   * @param _latestVersion Latest version of the wallet logic
   * @param _latestLogic Latest address of the wallet logic contract
   */
  function WalletConnector (
    uint256 _latestVersion,
    address _latestLogic
  ) public {
    owner_ = msg.sender;
    latestLogic_ = _latestLogic;
    latestVersion_ = _latestVersion;
    logicVersions_[_latestVersion] = _latestLogic;
    birthBlock_ = block.number;
  }

  /**
   * Add a new version of the logic contract
   * @param _version The version to be associated with the new contract.
   * @param _logic New logic contract.
   * @return Success of the transaction.
   */
  function addLogicVersion (
    uint256 _version,
    address _logic
  ) external
    returns(bool)
  {
    if (msg.sender != owner_)
      return error('msg.sender != owner, WalletConnector.addLogicVersion()');

    if (logicVersions_[_version] != 0)
      return error('Version already exists, WalletConnector.addLogicVersion()');

    // Update latest if this is the latest version
    if (_version > latestVersion_) {
      latestLogic_ = _logic;
      latestVersion_ = _version;
    }

    logicVersions_[_version] = _logic;
    LogLogicVersionAdded(_version);

    return true;
  }

  /**
   * @dev Remove a version. Cannot remove the latest version.
   * @param  _version The version to remove.
   */
  function removeLogicVersion(uint256 _version) external {
    require(msg.sender == owner_);
    require(_version != latestVersion_);
    delete logicVersions_[_version];
    LogLogicVersionRemoved(_version);
  }

  /**
   * Constants
   */

  /**
   * Called from user wallets in order to upgrade their logic.
   * @param _version The version to upgrade to. NOTE pass in 0 to upgrade to latest.
   * @return The address of the logic contract to upgrade to.
   */
  function getLogic(uint256 _version)
    external
    constant
    returns(address)
  {
    if (_version == 0)
      return latestLogic_;
    else
      return logicVersions_[_version];
  }
}

/**
 * @title Wallet to hold and trade ERC20 tokens and ether
 * @author Adam Lemmon <adam@oraclize.it>
 * @dev User wallet to interact with the exchange.
 * all tokens and ether held in this wallet, 1 to 1 mapping to user EOAs.
 */
contract WalletV2 is LoggingErrors {
  /**
   * Storage
   */
  // Vars included in wallet logic "lib", the order must match between Wallet and Logic
  address public owner_;
  address public exchange_;
  mapping(address => uint256) public tokenBalances_;

  address public logic_; // storage location 0x3 loaded for delegatecalls so this var must remain at index 3
  uint256 public birthBlock_;

  WalletConnector private connector_;

  /**
   * Events
   */
  event LogDeposit(address token, uint256 amount, uint256 balance);
  event LogWithdrawal(address token, uint256 amount, uint256 balance);

  /**
   * @dev Contract constructor. Set user as owner and connector address.
   * @param _owner The address of the user's EOA, wallets created from the exchange
   * so must past in the owner address, msg.sender == exchange.
   * @param _connector The wallet connector to be used to retrieve the wallet logic
   */
  function WalletV2(address _owner, address _connector) public {
    owner_ = _owner;
    connector_ = WalletConnector(_connector);
    exchange_ = msg.sender;
    logic_ = connector_.latestLogic_();
    birthBlock_ = block.number;
  }

  /**
   * @dev Fallback - Only enable funds to be sent from the exchange.
   * Ensures balances will be consistent.
   */
  function () external payable {
    require(msg.sender == exchange_);
  }

  /**
  * External
  */

  /**
   * @dev Deposit ether into this wallet, default to address 0 for consistent token lookup.
   */
  function depositEther()
    external
    payable
  {
    require(logic_.delegatecall(bytes4(sha3('deposit(address,uint256)')), 0, msg.value));
  }

  /**
   * @dev Deposit any ERC20 token into this wallet.
   * @param _token The address of the existing token contract.
   * @param _amount The amount of tokens to deposit.
   * @return Bool if the deposit was successful.
   */
  function depositERC20Token (
    address _token,
    uint256 _amount
  ) external
    returns(bool)
  {
    // ether
    if (_token == 0)
      return error('Cannot deposit ether via depositERC20, Wallet.depositERC20Token()');

    require(logic_.delegatecall(bytes4(sha3('deposit(address,uint256)')), _token, _amount));
    return true;
  }

  /**
   * @dev The result of an order, update the balance of this wallet.
   * @param _token The address of the token balance to update.
   * @param _amount The amount to update the balance by.
   * @param _subtractionFlag If true then subtract the token amount else add.
   * @return Bool if the update was successful.
   */
  function updateBalance (
    address _token,
    uint256 _amount,
    bool _subtractionFlag
  ) external
    returns(bool)
  {
    assembly {
      calldatacopy(0x40, 0, calldatasize)
      delegatecall(gas, sload(0x3), 0x40, calldatasize, 0, 32)
      return(0, 32)
      pop
    }
  }

  /**
   * User may update to the latest version of the exchange contract.
   * Note that multiple versions are NOT supported at this time and therefore if a
   * user does not wish to update they will no longer be able to use the exchange.
   * @param _exchange The new exchange.
   * @return Success of this transaction.
   */
  function updateExchange(address _exchange)
    external
    returns(bool)
  {
    if (msg.sender != owner_)
      return error('msg.sender != owner_, Wallet.updateExchange()');

    // If subsequent messages are not sent from this address all orders will fail
    exchange_ = _exchange;

    return true;
  }

  /**
   * User may update to a new or older version of the logic contract.
   * @param _version The versin to update to.
   * @return Success of this transaction.
   */
  function updateLogic(uint256 _version)
    external
    returns(bool)
  {
    if (msg.sender != owner_)
      return error('msg.sender != owner_, Wallet.updateLogic()');

    address newVersion = connector_.getLogic(_version);

    // Invalid version as defined by connector
    if (newVersion == 0)
      return error('Invalid version, Wallet.updateLogic()');

    logic_ = newVersion;
    return true;
  }

  /**
   * @dev Verify an order that the Exchange has received involving this wallet.
   * Internal checks and then authorize the exchange to move the tokens.
   * If sending ether will transfer to the exchange to broker the trade.
   * @param _token The address of the token contract being sold.
   * @param _amount The amount of tokens the order is for.
   * @param _fee The fee for the current trade.
   * @param _feeToken The token of which the fee is to be paid in.
   * @return If the order was verified or not.
   */
  function verifyOrder (
    address _token,
    uint256 _amount,
    uint256 _fee,
    address _feeToken
  ) external
    returns(bool)
  {
    assembly {
      calldatacopy(0x40, 0, calldatasize)
      delegatecall(gas, sload(0x3), 0x40, calldatasize, 0, 32)
      return(0, 32)
      pop
    }
  }

  /**
   * @dev Withdraw any token, including ether from this wallet to an EOA.
   * @param _token The address of the token to withdraw.
   * @param _amount The amount to withdraw.
   * @return Success of the withdrawal.
   */
  function withdraw(address _token, uint256 _amount)
    external
    returns(bool)
  {
    if(msg.sender != owner_)
      return error('msg.sender != owner, Wallet.withdraw()');

    assembly {
      calldatacopy(0x40, 0, calldatasize)
      delegatecall(gas, sload(0x3), 0x40, calldatasize, 0, 32)
      return(0, 32)
      pop
    }
  }

  /**
   * Constants
   */

  /**
   * @dev Get the balance for a specific token.
   * @param _token The address of the token contract to retrieve the balance of.
   * @return The current balance within this contract.
   */
  function balanceOf(address _token)
    public
    view
    returns(uint)
  {
    return tokenBalances_[_token];
  }
}

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

contract Token {
  /// @return total amount of tokens
  function totalSupply() constant returns (uint256 supply) {}

  /// @param _owner The address from which the balance will be retrieved
  /// @return The balance
  function balanceOf(address _owner) constant returns (uint256 balance) {}

  /// @notice send `_value` token to `_to` from `msg.sender`
  /// @param _to The address of the recipient
  /// @param _value The amount of token to be transferred
  /// @return Whether the transfer was successful or not
  function transfer(address _to, uint256 _value) returns (bool success) {}

  /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
  /// @param _from The address of the sender
  /// @param _to The address of the recipient
  /// @param _value The amount of token to be transferred
  /// @return Whether the transfer was successful or not
  function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {}

  /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
  /// @param _spender The address of the account able to transfer the tokens
  /// @param _value The amount of wei to be approved for transfer
  /// @return Whether the approval was successful or not
  function approve(address _spender, uint256 _value) returns (bool success) {}

  /// @param _owner The address of the account owning tokens
  /// @param _spender The address of the account able to transfer the tokens
  /// @return Amount of remaining tokens allowed to spent
  function allowance(address _owner, address _spender) constant returns (uint256 remaining) {}

  event Transfer(address indexed _from, address indexed _to, uint256 _value);
  event Approval(address indexed _owner, address indexed _spender, uint256 _value);

  uint public decimals;
  string public name;
}

interface ExchangeV1 {
  function userAccountToWallet_(address) external returns(address);
}

interface BadERC20 {
  function transfer(address to, uint value) external;
  function transferFrom(address from, address to, uint256 value) external;
}

/**
 * @title Decentralized exchange for ether and ERC20 tokens.
 * @author Eidoo SAGL.
 * @dev All trades brokered by this contract.
 * Orders submitted by off chain order book and this contract handles
 * verification and execution of orders.
 * All value between parties is transferred via this exchange.
 * Methods arranged by visibility; external, public, internal, private and alphabatized within.
 *
 * New Exchange SC with eventually no fee and ERC20 tokens as quote
 */
contract ExchangeV2 is LoggingErrors {

  using SafeMath for uint256;

  /**
   * Data Structures
   */
  struct Order {
    address offerToken_;
    uint256 offerTokenTotal_;
    uint256 offerTokenRemaining_;  // Amount left to give
    address wantToken_;
    uint256 wantTokenTotal_;
    uint256 wantTokenReceived_;  // Amount received, note this may exceed want total
  }

  struct OrderStatus {
    uint256 expirationBlock_;
    uint256 wantTokenReceived_;    // Amount received, note this may exceed want total
    uint256 offerTokenRemaining_;  // Amount left to give
  }

  /**
   * Storage
   */
  address public previousExchangeAddress_;
  address private orderBookAccount_;
  address public owner_;
  uint256 public birthBlock_;
  address public edoToken_;
  address public walletConnector;

  mapping (address => uint256) public feeEdoPerQuote;
  mapping (address => uint256) public feeEdoPerQuoteDecimals;

  address public eidooWallet_;

  // Define if fee calculation must be skipped for a given trade. By default (false) fee must not be skipped.
  mapping(address => mapping(address => bool)) public mustSkipFee;

  /**
   * @dev Define in a trade who is the quote using a priority system:
   * values example
   *   0: not used as quote
   *  >0: used as quote
   *  if wanted and offered tokens have value > 0 the quote is the token with the bigger value
   */
  mapping(address => uint256) public quotePriority;

  mapping(bytes32 => OrderStatus) public orders_; // Map order hashes to order data struct
  mapping(address => address) public userAccountToWallet_; // User EOA to wallet addresses

  /**
   * Events
   */
  event LogFeeRateSet(address indexed token, uint256 rate, uint256 decimals);
  event LogQuotePrioritySet(address indexed quoteToken, uint256 priority);
  event LogMustSkipFeeSet(address indexed base, address indexed quote, bool mustSkipFee);
  event LogUserAdded(address indexed user, address walletAddress);
  event LogWalletDeposit(address indexed walletAddress, address token, uint256 amount, uint256 balance);
  event LogWalletWithdrawal(address indexed walletAddress, address token, uint256 amount, uint256 balance);

  event LogOrderExecutionSuccess(
    bytes32 indexed makerOrderId,
    bytes32 indexed takerOrderId,
    uint256 toMaker,
    uint256 toTaker
  );
  event LogOrderFilled(bytes32 indexed orderId, uint256 totalOfferRemaining, uint256 totalWantReceived);

  /**
   * @dev Contract constructor - CONFIRM matches contract name.  Set owner and addr of order book.
   * @param _bookAccount The EOA address for the order book, will submit ALL orders.
   * @param _edoToken Deployed edo token.
   * @param _edoPerWei Rate of edo tokens per wei.
   * @param _edoPerWeiDecimals Decimlas carried in edo rate.
   * @param _eidooWallet Wallet to pay fees to.
   * @param _previousExchangeAddress Previous exchange smart contract address.
   */
  constructor (
    address _bookAccount,
    address _edoToken,
    uint256 _edoPerWei,
    uint256 _edoPerWeiDecimals,
    address _eidooWallet,
    address _previousExchangeAddress,
    address _walletConnector
  ) public {
    orderBookAccount_ = _bookAccount;
    owner_ = msg.sender;
    birthBlock_ = block.number;
    edoToken_ = _edoToken;
    feeEdoPerQuote[address(0)] = _edoPerWei;
    feeEdoPerQuoteDecimals[address(0)] = _edoPerWeiDecimals;
    eidooWallet_ = _eidooWallet;
    quotePriority[address(0)] = 10;
    previousExchangeAddress_ = _previousExchangeAddress;
    require(_walletConnector != address (0), "WalletConnector address == 0");
    walletConnector = _walletConnector;
  }

  /**
   * @dev Fallback. wallets utilize to send ether in order to broker trade.
   */
  function () external payable { }

  /**
   * External
   */

  /**
   * @dev Returns the Wallet contract address associated to a user account. If the user account is not known, try to
   * migrate the wallet address from the old exchange instance. This function is equivalent to getWallet(), in addition
   * it stores the wallet address fetched from old the exchange instance.
   * @param userAccount The user account address
   * @return The address of the Wallet instance associated to the user account
   */
  function retrieveWallet(address userAccount)
    public
    returns(address walletAddress)
  {
    walletAddress = userAccountToWallet_[userAccount];
    if (walletAddress == address(0) && previousExchangeAddress_ != 0) {
      // Retrieve the wallet address from the old exchange.
      walletAddress = ExchangeV1(previousExchangeAddress_).userAccountToWallet_(userAccount);
      // TODO: in the future versions of the exchange the above line must be replaced with the following one
      //walletAddress = ExchangeV2(previousExchangeAddress_).retrieveWallet(userAccount);

      if (walletAddress != address(0)) {
        userAccountToWallet_[userAccount] = walletAddress;
      }
    }
  }

  /**
   * @dev Add a new user to the exchange, create a wallet for them.
   * Map their account address to the wallet contract for lookup.
   * @param userExternalOwnedAccount The address of the user"s EOA.
   * @return Success of the transaction, false if error condition met.
   */
  function addNewUser(address userExternalOwnedAccount)
    public
    returns (bool)
  {
    if (retrieveWallet(userExternalOwnedAccount) != address(0)) {
      return error("User already exists, Exchange.addNewUser()");
    }

    // Pass the userAccount address to wallet constructor so owner is not the exchange contract
    address userTradingWallet = new WalletV2(userExternalOwnedAccount, walletConnector);
    userAccountToWallet_[userExternalOwnedAccount] = userTradingWallet;
    emit LogUserAdded(userExternalOwnedAccount, userTradingWallet);
    return true;
  }

  /**
   * Execute orders in batches.
   * @param ownedExternalAddressesAndTokenAddresses Tokan and user addresses.
   * @param amountsExpirationsAndSalts Offer and want token amount and expiration and salt values.
   * @param vSignatures All order signature v values.
   * @param rAndSsignatures All order signature r and r values.
   * @return The success of this transaction.
   */
  function batchExecuteOrder(
    address[4][] ownedExternalAddressesAndTokenAddresses,
    uint256[8][] amountsExpirationsAndSalts, // Packing to save stack size
    uint8[2][] vSignatures,
    bytes32[4][] rAndSsignatures
  ) external
    returns(bool)
  {
    for (uint256 i = 0; i < amountsExpirationsAndSalts.length; i++) {
      require(
        executeOrder(
          ownedExternalAddressesAndTokenAddresses[i],
          amountsExpirationsAndSalts[i],
          vSignatures[i],
          rAndSsignatures[i]
        ),
        "Cannot execute order, Exchange.batchExecuteOrder()"
      );
    }

    return true;
  }

  /**
   * @dev Execute an order that was submitted by the external order book server.
   * The order book server believes it to be a match.
   * There are components for both orders, maker and taker, 2 signatures as well.
   * @param ownedExternalAddressesAndTokenAddresses The maker and taker external owned accounts addresses and offered tokens contracts.
   * [
   *   makerEOA
   *   makerOfferToken
   *   takerEOA
   *   takerOfferToken
   * ]
   * @param amountsExpirationsAndSalts The amount of tokens and the block number at which this order expires and a random number to mitigate replay.
   * [
   *   makerOffer
   *   makerWant
   *   takerOffer
   *   takerWant
   *   makerExpiry
   *   makerSalt
   *   takerExpiry
   *   takerSalt
   * ]
   * @param vSignatures ECDSA signature parameter.
   * [
   *   maker V
   *   taker V
   * ]
   * @param rAndSsignatures ECDSA signature parameters r ans s, maker 0, 1 and taker 2, 3.
   * [
   *   maker R
   *   maker S
   *   taker R
   *   taker S
   * ]
   * @return Success of the transaction, false if error condition met.
   * Like types grouped to eliminate stack depth error.
   */
  function executeOrder (
    address[4] ownedExternalAddressesAndTokenAddresses,
    uint256[8] amountsExpirationsAndSalts, // Packing to save stack size
    uint8[2] vSignatures,
    bytes32[4] rAndSsignatures
  ) public
    returns(bool)
  {
    // Only read wallet addresses from storage once
    // Need one more stack slot so squashing into array
    WalletV2[2] memory makerAndTakerTradingWallets = [
      WalletV2(retrieveWallet(ownedExternalAddressesAndTokenAddresses[0])), // maker
      WalletV2(retrieveWallet(ownedExternalAddressesAndTokenAddresses[2])) // taker
    ];

    // Basic pre-conditions, return if any input data is invalid
    if(!__executeOrderInputIsValid__(
      ownedExternalAddressesAndTokenAddresses,
      amountsExpirationsAndSalts,
      makerAndTakerTradingWallets[0], // maker
      makerAndTakerTradingWallets[1] // taker
    )) {
      return error("Input is invalid, Exchange.executeOrder()");
    }

    // Verify Maker and Taker signatures
    bytes32[2] memory makerAndTakerOrderHash = generateOrderHashes(
      ownedExternalAddressesAndTokenAddresses,
      amountsExpirationsAndSalts
    );

    // Check maker order signature
    if (!__signatureIsValid__(
      ownedExternalAddressesAndTokenAddresses[0],
      makerAndTakerOrderHash[0],
      vSignatures[0],
      rAndSsignatures[0],
      rAndSsignatures[1]
    )) {
      return error("Maker signature is invalid, Exchange.executeOrder()");
    }

    // Check taker order signature
    if (!__signatureIsValid__(
      ownedExternalAddressesAndTokenAddresses[2],
      makerAndTakerOrderHash[1],
      vSignatures[1],
      rAndSsignatures[2],
      rAndSsignatures[3]
    )) {
      return error("Taker signature is invalid, Exchange.executeOrder()");
    }

    // Exchange Order Verification and matching
    OrderStatus memory makerOrderStatus = orders_[makerAndTakerOrderHash[0]];
    OrderStatus memory takerOrderStatus = orders_[makerAndTakerOrderHash[1]];
    Order memory makerOrder;
    Order memory takerOrder;

    makerOrder.offerToken_ = ownedExternalAddressesAndTokenAddresses[1];
    makerOrder.offerTokenTotal_ = amountsExpirationsAndSalts[0];
    makerOrder.wantToken_ = ownedExternalAddressesAndTokenAddresses[3];
    makerOrder.wantTokenTotal_ = amountsExpirationsAndSalts[1];

    if (makerOrderStatus.expirationBlock_ > 0) {  // Check for existence
      // Orders still active
      if (makerOrderStatus.offerTokenRemaining_ == 0) {
        return error("Maker order is inactive, Exchange.executeOrder()");
      }
      makerOrder.offerTokenRemaining_ = makerOrderStatus.offerTokenRemaining_; // Amount to give
      makerOrder.wantTokenReceived_ = makerOrderStatus.wantTokenReceived_; // Amount received
    } else {
      makerOrder.offerTokenRemaining_ = amountsExpirationsAndSalts[0]; // Amount to give
      makerOrder.wantTokenReceived_ = 0; // Amount received
      makerOrderStatus.expirationBlock_ = amountsExpirationsAndSalts[4]; // maker order expiration block
    }

    takerOrder.offerToken_ = ownedExternalAddressesAndTokenAddresses[3];
    takerOrder.offerTokenTotal_ = amountsExpirationsAndSalts[2];
    takerOrder.wantToken_ = ownedExternalAddressesAndTokenAddresses[1];
    takerOrder.wantTokenTotal_ = amountsExpirationsAndSalts[3];

    if (takerOrderStatus.expirationBlock_ > 0) {  // Check for existence
      if (takerOrderStatus.offerTokenRemaining_ == 0) {
        return error("Taker order is inactive, Exchange.executeOrder()");
      }
      takerOrder.offerTokenRemaining_ = takerOrderStatus.offerTokenRemaining_;  // Amount to give
      takerOrder.wantTokenReceived_ = takerOrderStatus.wantTokenReceived_; // Amount received

    } else {
      takerOrder.offerTokenRemaining_ = amountsExpirationsAndSalts[2];  // Amount to give
      takerOrder.wantTokenReceived_ = 0; // Amount received
      takerOrderStatus.expirationBlock_ = amountsExpirationsAndSalts[6]; // taker order expiration block
    }

    // Check if orders are matching and are valid
    if (!__ordersMatch_and_AreVaild__(makerOrder, takerOrder)) {
      return error("Orders do not match, Exchange.executeOrder()");
    }

    // Trade amounts
    // [0] => toTakerAmount
    // [1] => toMakerAmount
    uint[2] memory toTakerAndToMakerAmount;
    toTakerAndToMakerAmount = __getTradeAmounts__(makerOrder, takerOrder);

    // TODO consider removing. Can this condition be met?
    if (toTakerAndToMakerAmount[0] < 1 || toTakerAndToMakerAmount[1] < 1) {
      return error("Token amount < 1, price ratio is invalid! Token value < 1, Exchange.executeOrder()");
    }

    uint calculatedFee = __calculateFee__(makerOrder, toTakerAndToMakerAmount[0], toTakerAndToMakerAmount[1]);

    // Check taker has sufficent EDO token balance to pay the fee
    if (
      takerOrder.offerToken_ == edoToken_ &&
      Token(edoToken_).balanceOf(makerAndTakerTradingWallets[1]) < calculatedFee.add(toTakerAndToMakerAmount[1])
    ) {
      return error("Taker has an insufficient EDO token balance to cover the fee AND the offer, Exchange.executeOrder()");
    } else if (Token(edoToken_).balanceOf(makerAndTakerTradingWallets[1]) < calculatedFee) {
      return error("Taker has an insufficient EDO token balance to cover the fee, Exchange.executeOrder()");
    }

    // Wallet Order Verification, reach out to the maker and taker wallets.
    if (
      !__ordersVerifiedByWallets__(
        ownedExternalAddressesAndTokenAddresses,
        toTakerAndToMakerAmount[1],
        toTakerAndToMakerAmount[0],
        makerAndTakerTradingWallets[0],
        makerAndTakerTradingWallets[1],
        calculatedFee
    )) {
      return error("Order could not be verified by wallets, Exchange.executeOrder()");
    }

    // Write to storage then external calls
    makerOrderStatus.offerTokenRemaining_ = makerOrder.offerTokenRemaining_.sub(toTakerAndToMakerAmount[0]);
    makerOrderStatus.wantTokenReceived_ = makerOrder.wantTokenReceived_.add(toTakerAndToMakerAmount[1]);

    takerOrderStatus.offerTokenRemaining_ = takerOrder.offerTokenRemaining_.sub(toTakerAndToMakerAmount[1]);
    takerOrderStatus.wantTokenReceived_ = takerOrder.wantTokenReceived_.add(toTakerAndToMakerAmount[0]);

    // Finally write orders to storage
    orders_[makerAndTakerOrderHash[0]] = makerOrderStatus;
    orders_[makerAndTakerOrderHash[1]] = takerOrderStatus;

    // Transfer the external value, ether <> tokens
    require(
      __executeTokenTransfer__(
        ownedExternalAddressesAndTokenAddresses,
        toTakerAndToMakerAmount[0],
        toTakerAndToMakerAmount[1],
        calculatedFee,
        makerAndTakerTradingWallets[0],
        makerAndTakerTradingWallets[1]
      ),
      "Cannot execute token transfer, Exchange.__executeTokenTransfer__()"
    );

    // Log the order id(hash), amount of offer given, amount of offer remaining
    emit LogOrderFilled(makerAndTakerOrderHash[0], makerOrderStatus.offerTokenRemaining_, makerOrderStatus.wantTokenReceived_);
    emit LogOrderFilled(makerAndTakerOrderHash[1], takerOrderStatus.offerTokenRemaining_, takerOrderStatus.wantTokenReceived_);
    emit LogOrderExecutionSuccess(makerAndTakerOrderHash[0], makerAndTakerOrderHash[1], toTakerAndToMakerAmount[1], toTakerAndToMakerAmount[0]);

    return true;
  }

  /**
   * @dev Set the fee rate for a specific quote
   * @param _quoteToken Quote token.
   * @param _edoPerQuote EdoPerQuote.
   * @param _edoPerQuoteDecimals EdoPerQuoteDecimals.
   * @return Success of the transaction.
   */
  function setFeeRate(
    address _quoteToken,
    uint256 _edoPerQuote,
    uint256 _edoPerQuoteDecimals
  ) external
    returns(bool)
  {
    if (msg.sender != owner_) {
      return error("msg.sender != owner, Exchange.setFeeRate()");
    }

    if (quotePriority[_quoteToken] == 0) {
      return error("quotePriority[_quoteToken] == 0, Exchange.setFeeRate()");
    }

    feeEdoPerQuote[_quoteToken] = _edoPerQuote;
    feeEdoPerQuoteDecimals[_quoteToken] = _edoPerQuoteDecimals;

    emit LogFeeRateSet(_quoteToken, _edoPerQuote, _edoPerQuoteDecimals);

    return true;
  }

  /**
   * @dev Set the wallet for fees to be paid to.
   * @param eidooWallet Wallet to pay fees to.
   * @return Success of the transaction.
   */
  function setEidooWallet(
    address eidooWallet
  ) external
    returns(bool)
  {
    if (msg.sender != owner_) {
      return error("msg.sender != owner, Exchange.setEidooWallet()");
    }
    eidooWallet_ = eidooWallet;
    return true;
  }

  /**
   * @dev Set a new order book account.
   * @param account The new order book account.
   */
  function setOrderBookAcount (
    address account
  ) external
    returns(bool)
  {
    if (msg.sender != owner_) {
      return error("msg.sender != owner, Exchange.setOrderBookAcount()");
    }
    orderBookAccount_ = account;
    return true;
  }

  /**
   * @dev Set if a base must skip fee calculation.
   * @param _baseTokenAddress The trade base token address that must skip fee calculation.
   * @param _quoteTokenAddress The trade quote token address that must skip fee calculation.
   * @param _mustSkipFee The trade base token address that must skip fee calculation.
   */
  function setMustSkipFee (
    address _baseTokenAddress,
    address _quoteTokenAddress,
    bool _mustSkipFee
  ) external
    returns(bool)
  {
    // Preserving same owner check style
    if (msg.sender != owner_) {
      return error("msg.sender != owner, Exchange.setMustSkipFee()");
    }
    mustSkipFee[_baseTokenAddress][_quoteTokenAddress] = _mustSkipFee;
    emit LogMustSkipFeeSet(_baseTokenAddress, _quoteTokenAddress, _mustSkipFee);
    return true;
  }

  /**
   * @dev Set quote priority token.
   * Set the sorting of token quote based on a priority.
   * @param _token The address of the token that was deposited.
   * @param _priority The amount of the token that was deposited.
   * @return Operation success.
   */

  function setQuotePriority(address _token, uint256 _priority)
    external
    returns(bool)
  {
    if (msg.sender != owner_) {
      return error("msg.sender != owner, Exchange.setQuotePriority()");
    }
    quotePriority[_token] = _priority;
    emit LogQuotePrioritySet(_token, _priority);
    return true;
  }

  /*
   Methods to catch events from external contracts, user wallets primarily
   */

  /**
   * @dev Simply log the event to track wallet interaction off-chain.
   * @param tokenAddress The address of the token that was deposited.
   * @param amount The amount of the token that was deposited.
   * @param tradingWalletBalance The updated balance of the wallet after deposit.
   */
  function walletDeposit(
    address tokenAddress,
    uint256 amount,
    uint256 tradingWalletBalance
  ) external
  {
    emit LogWalletDeposit(msg.sender, tokenAddress, amount, tradingWalletBalance);
  }

  /**
   * @dev Simply log the event to track wallet interaction off-chain.
   * @param tokenAddress The address of the token that was deposited.
   * @param amount The amount of the token that was deposited.
   * @param tradingWalletBalance The updated balance of the wallet after deposit.
   */
  function walletWithdrawal(
    address tokenAddress,
    uint256 amount,
    uint256 tradingWalletBalance
  ) external
  {
    emit LogWalletWithdrawal(msg.sender, tokenAddress, amount, tradingWalletBalance);
  }

  /**
   * Private
   */
