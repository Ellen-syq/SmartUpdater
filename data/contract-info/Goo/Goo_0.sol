pragma solidity ^0.4.0;

interface ERC20 {
    function totalSupply() public constant returns (uint);
    function balanceOf(address tokenOwner) public constant returns (uint balance);
    function allowance(address tokenOwner, address spender) public constant returns (uint remaining);
    function transfer(address to, uint tokens) public returns (bool success);
    function approve(address spender, uint tokens) public returns (bool success);
    function transferFrom(address from, address to, uint tokens) public returns (bool success);

    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}

// GOO - Crypto Idle Game
// https://ethergoo.io

contract Goo is ERC20 {
    
    string public constant name  = "IdleEth";
    string public constant symbol = "Goo";
    uint8 public constant decimals = 0;
    uint256 private roughSupply;
    uint256 public totalGooProduction;
    address public owner; // Minor management of game
    bool public gameStarted;
    
    uint256 public totalEtherGooResearchPool; // Eth dividends to be split between players' goo production
    uint256[] public totalGooProductionSnapshots; // The total goo production for each prior day past
    uint256[] public allocatedGooResearchSnapshots; // The research eth allocated to each prior day past
    uint256 public nextSnapshotTime;
    
    uint256 private MAX_PRODUCTION_UNITS = 999; // Per type (makes balancing slightly easier)
    uint256 private constant RAFFLE_TICKET_BASE_GOO_PRICE = 1000;
    
    // Balances for each player
    mapping(address => uint256) private ethBalance;
    mapping(address => uint256) private gooBalance;
    mapping(address => mapping(uint256 => uint256)) private gooProductionSnapshots; // Store player's goo production for given day (snapshot)
    mapping(address => mapping(uint256 => bool)) private gooProductionZeroedSnapshots; // This isn't great but we need know difference between 0 production and an unused/inactive day.
    
    mapping(address => uint256) private lastGooSaveTime; // Seconds (last time player claimed their produced goo)
    mapping(address => uint256) public lastGooProductionUpdate; // Days (last snapshot player updated their production)
    mapping(address => uint256) private lastGooResearchFundClaim; // Days (snapshot number)
    mapping(address => uint256) private battleCooldown; // If user attacks they cannot attack again for short time
    
    // Stuff owned by each player
    mapping(address => mapping(uint256 => uint256)) private unitsOwned;
    mapping(address => mapping(uint256 => bool)) private upgradesOwned;
    mapping(uint256 => address) private rareItemOwner;
    mapping(uint256 => uint256) private rareItemPrice;
    
    // Rares & Upgrades (Increase unit's production / attack etc.)
    mapping(address => mapping(uint256 => uint256)) private unitGooProductionIncreases; // Adds to the goo per second
    mapping(address => mapping(uint256 => uint256)) private unitGooProductionMultiplier; // Multiplies the goo per second
    mapping(address => mapping(uint256 => uint256)) private unitAttackIncreases;
    mapping(address => mapping(uint256 => uint256)) private unitAttackMultiplier;
    mapping(address => mapping(uint256 => uint256)) private unitDefenseIncreases;
    mapping(address => mapping(uint256 => uint256)) private unitDefenseMultiplier;
    mapping(address => mapping(uint256 => uint256)) private unitGooStealingIncreases;
    mapping(address => mapping(uint256 => uint256)) private unitGooStealingMultiplier;
    
    // Mapping of approved ERC20 transfers (by player)
    mapping(address => mapping(address => uint256)) private allowed;
    mapping(address => bool) private protectedAddresses; // For npc exchanges (requires 0 goo production)
    
    // Raffle structures
    struct TicketPurchases {
        TicketPurchase[] ticketsBought;
        uint256 numPurchases; // Allows us to reset without clearing TicketPurchase[] (avoids potential for gas limit)
        uint256 raffleRareId;
    }
    
    // Allows us to query winner without looping (avoiding potential for gas limit)
    struct TicketPurchase {
        uint256 startId;
        uint256 endId;
    }
    
    // Raffle tickets
    mapping(address => TicketPurchases) private ticketsBoughtByPlayer;
    mapping(uint256 => address[]) private rafflePlayers; // Keeping a seperate list for each raffle has it's benefits.

    // Current raffle info
    uint256 private raffleEndTime;
    uint256 private raffleRareId;
    uint256 private raffleTicketsBought;
    address private raffleWinner; // Address of winner
    bool private raffleWinningTicketSelected;
    uint256 private raffleTicketThatWon;
    
    // Minor game events
    event UnitBought(address player, uint256 unitId, uint256 amount);
    event UnitSold(address player, uint256 unitId, uint256 amount);
    event PlayerAttacked(address attacker, address target, bool success, uint256 gooStolen);
    
    GooGameConfig schema;
    
    // Constructor
    function Goo() public payable {
        owner = msg.sender;
        schema = GooGameConfig(0x21912e81d7eff8bff895302b45da76f7f070e3b9);
    }
    
    function() payable { }
    
    function beginGame(uint256 firstDivsTime) external payable {
        require(msg.sender == owner);
        require(!gameStarted);
        
        gameStarted = true; // GO-OOOO!
        nextSnapshotTime = firstDivsTime;
        totalEtherGooResearchPool = msg.value; // Seed pot
    }
    
    function totalSupply() public constant returns(uint256) {
        return roughSupply; // Stored goo (rough supply as it ignores earned/unclaimed goo)
    }
    
    function balanceOf(address player) public constant returns(uint256) {
        return gooBalance[player] + balanceOfUnclaimedGoo(player);
    }
    
    function balanceOfUnclaimedGoo(address player) internal constant returns (uint256) {
        if (lastGooSaveTime[player] > 0 && lastGooSaveTime[player] < block.timestamp) {
            return (getGooProduction(player) * (block.timestamp - lastGooSaveTime[player]));
        }
        return 0;
    }
    
    function etherBalanceOf(address player) public constant returns(uint256) {
        return ethBalance[player];
    }
    
    function transfer(address recipient, uint256 amount) public returns (bool) {
        updatePlayersGoo(msg.sender);
        require(amount <= gooBalance[msg.sender]);
        
        gooBalance[msg.sender] -= amount;
        gooBalance[recipient] += amount;
        
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }
    
    function transferFrom(address player, address recipient, uint256 amount) public returns (bool) {
        updatePlayersGoo(player);
        require(amount <= allowed[player][msg.sender] && amount <= gooBalance[msg.sender]);
        
        gooBalance[player] -= amount;
        gooBalance[recipient] += amount;
        allowed[player][msg.sender] -= amount;
        
        emit Transfer(player, recipient, amount);
        return true;
    }
    
    function approve(address approvee, uint256 amount) public returns (bool){
        allowed[msg.sender][approvee] = amount;
        emit Approval(msg.sender, approvee, amount);
        return true;
    }
    
    function allowance(address player, address approvee) public constant returns(uint256){
        return allowed[player][approvee];
    }
    
    function getGooProduction(address player) public constant returns (uint256){
        return gooProductionSnapshots[player][lastGooProductionUpdate[player]];
    }
    
    function updatePlayersGoo(address player) internal {
        uint256 gooGain = balanceOfUnclaimedGoo(player);
        lastGooSaveTime[player] = block.timestamp;
        roughSupply += gooGain;
        gooBalance[player] += gooGain;
    }
    
    function updatePlayersGooFromPurchase(address player, uint256 purchaseCost) internal {
        uint256 unclaimedGoo = balanceOfUnclaimedGoo(player);
        
        if (purchaseCost > unclaimedGoo) {
            uint256 gooDecrease = purchaseCost - unclaimedGoo;
            roughSupply -= gooDecrease;
            gooBalance[player] -= gooDecrease;
        } else {
            uint256 gooGain = unclaimedGoo - purchaseCost;
            roughSupply += gooGain;
            gooBalance[player] += gooGain;
        }
        
        lastGooSaveTime[player] = block.timestamp;
    }
    
    function increasePlayersGooProduction(uint256 increase) internal {
        gooProductionSnapshots[msg.sender][allocatedGooResearchSnapshots.length] = getGooProduction(msg.sender) + increase;
        lastGooProductionUpdate[msg.sender] = allocatedGooResearchSnapshots.length;
        totalGooProduction += increase;
    }
    
    function reducePlayersGooProduction(address player, uint256 decrease) internal {
        uint256 previousProduction = getGooProduction(player);
        uint256 newProduction = SafeMath.sub(previousProduction, decrease);
        
        if (newProduction == 0) { // Special case which tangles with "inactive day" snapshots (claiming divs)
            gooProductionZeroedSnapshots[player][allocatedGooResearchSnapshots.length] = true;
            delete gooProductionSnapshots[player][allocatedGooResearchSnapshots.length]; // 0
        } else {
            gooProductionSnapshots[player][allocatedGooResearchSnapshots.length] = newProduction;
        }
        
        lastGooProductionUpdate[player] = allocatedGooResearchSnapshots.length;
        totalGooProduction -= decrease;
    }
    
    function buyBasicUnit(uint256 unitId, uint256 amount) external {
        require(gameStarted);
        require(schema.validUnitId(unitId));
        require(unitsOwned[msg.sender][unitId] + amount <= MAX_PRODUCTION_UNITS);
        
        uint256 unitCost = schema.getGooCostForUnit(unitId, unitsOwned[msg.sender][unitId], amount);
        require(balanceOf(msg.sender) >= unitCost);
        require(schema.unitEthCost(unitId) == 0); // Free unit
        
        // Update players goo
        updatePlayersGooFromPurchase(msg.sender, unitCost);
        
        if (schema.unitGooProduction(unitId) > 0) {
            increasePlayersGooProduction(getUnitsProduction(msg.sender, unitId, amount));
        }
        
        unitsOwned[msg.sender][unitId] += amount;
        emit UnitBought(msg.sender, unitId, amount);
    }
    
    function buyEthUnit(uint256 unitId, uint256 amount) external payable {
        require(gameStarted);
        require(schema.validUnitId(unitId));
        require(unitsOwned[msg.sender][unitId] + amount <= MAX_PRODUCTION_UNITS);
        
        uint256 unitCost = schema.getGooCostForUnit(unitId, unitsOwned[msg.sender][unitId], amount);
        uint256 ethCost = SafeMath.mul(schema.unitEthCost(unitId), amount);
        
        require(balanceOf(msg.sender) >= unitCost);
        require(ethBalance[msg.sender] + msg.value >= ethCost);
        
        // Update players goo
        updatePlayersGooFromPurchase(msg.sender, unitCost);

        if (ethCost > msg.value) {
            ethBalance[msg.sender] -= (ethCost - msg.value);
        }
        
        uint256 devFund = ethCost / 50; // 2% fee on purchases (marketing, gameplay & maintenance)
        uint256 dividends = (ethCost - devFund) / 4; // 25% goes to pool (75% retained for sale value)
        totalEtherGooResearchPool += dividends;
        ethBalance[owner] += devFund;
        
        if (schema.unitGooProduction(unitId) > 0) {
            increasePlayersGooProduction(getUnitsProduction(msg.sender, unitId, amount));
        }
        
        unitsOwned[msg.sender][unitId] += amount;
        emit UnitBought(msg.sender, unitId, amount);
    }
    
    function sellUnit(uint256 unitId, uint256 amount) external {
        require(unitsOwned[msg.sender][unitId] >= amount);
        unitsOwned[msg.sender][unitId] -= amount;
        
        uint256 unitSalePrice = (schema.getGooCostForUnit(unitId, unitsOwned[msg.sender][unitId], amount) * 3) / 4; // 75%
        uint256 gooChange = balanceOfUnclaimedGoo(msg.sender) + unitSalePrice; // Claim unsaved goo whilst here
        lastGooSaveTime[msg.sender] = block.timestamp;
        roughSupply += gooChange;
        gooBalance[msg.sender] += gooChange;
        
        if (schema.unitGooProduction(unitId) > 0) {
            reducePlayersGooProduction(msg.sender, getUnitsProduction(msg.sender, unitId, amount));
        }
        
        if (schema.unitEthCost(unitId) > 0) { // Premium units sell for 75% of buy cost
            ethBalance[msg.sender] += ((schema.unitEthCost(unitId) * amount) * 3) / 4;
        }
        emit UnitSold(msg.sender, unitId, amount);
    }
    
    function buyUpgrade(uint256 upgradeId) external payable {
        require(gameStarted);
        require(schema.validUpgradeId(upgradeId)); // Valid upgrade
        require(!upgradesOwned[msg.sender][upgradeId]); // Haven't already purchased
        
        uint256 gooCost;
        uint256 ethCost;
        uint256 upgradeClass;
        uint256 unitId;
        uint256 upgradeValue;
        (gooCost, ethCost, upgradeClass, unitId, upgradeValue) = schema.getUpgradeInfo(upgradeId);
        
        require(balanceOf(msg.sender) >= gooCost);
        
        if (ethCost > 0) {
            require(ethBalance[msg.sender] + msg.value >= ethCost);
             if (ethCost > msg.value) { // They can use their balance instead
                ethBalance[msg.sender] -= (ethCost - msg.value);
            }
        
            uint256 devFund = ethCost / 50; // 2% fee on purchases (marketing, gameplay & maintenance)
            totalEtherGooResearchPool += (ethCost - devFund); // Rest goes to div pool (Can't sell upgrades)
            ethBalance[owner] += devFund;
        }
        
        // Update players goo
        updatePlayersGooFromPurchase(msg.sender, gooCost);

        upgradeUnitMultipliers(msg.sender, upgradeClass, unitId, upgradeValue);
        upgradesOwned[msg.sender][upgradeId] = true;
    }
    
    function upgradeUnitMultipliers(address player, uint256 upgradeClass, uint256 unitId, uint256 upgradeValue) internal {
        uint256 productionGain;
        if (upgradeClass == 0) {
            unitGooProductionIncreases[player][unitId] += upgradeValue;
            productionGain = (unitsOwned[player][unitId] * upgradeValue * (10 + unitGooProductionMultiplier[player][unitId])) / 10;
            increasePlayersGooProduction(productionGain);
        } else if (upgradeClass == 1) {
            unitGooProductionMultiplier[player][unitId] += upgradeValue;
            productionGain = (unitsOwned[player][unitId] * upgradeValue * (schema.unitGooProduction(unitId) + unitGooProductionIncreases[player][unitId])) / 10;
            increasePlayersGooProduction(productionGain);
        } else if (upgradeClass == 2) {
            unitAttackIncreases[player][unitId] += upgradeValue;
        } else if (upgradeClass == 3) {
            unitAttackMultiplier[player][unitId] += upgradeValue;
        } else if (upgradeClass == 4) {
            unitDefenseIncreases[player][unitId] += upgradeValue;
        } else if (upgradeClass == 5) {
            unitDefenseMultiplier[player][unitId] += upgradeValue;
        } else if (upgradeClass == 6) {
            unitGooStealingIncreases[player][unitId] += upgradeValue;
        } else if (upgradeClass == 7) {
            unitGooStealingMultiplier[player][unitId] += upgradeValue;
        }
    }
    
    function removeUnitMultipliers(address player, uint256 upgradeClass, uint256 unitId, uint256 upgradeValue) internal {
        uint256 productionLoss;
        if (upgradeClass == 0) {
            unitGooProductionIncreases[player][unitId] -= upgradeValue;
            productionLoss = (unitsOwned[player][unitId] * upgradeValue * (10 + unitGooProductionMultiplier[player][unitId])) / 10;
            reducePlayersGooProduction(player, productionLoss);
        } else if (upgradeClass == 1) {
            unitGooProductionMultiplier[player][unitId] -= upgradeValue;
            productionLoss = (unitsOwned[player][unitId] * upgradeValue * (schema.unitGooProduction(unitId) + unitGooProductionIncreases[player][unitId])) / 10;
            reducePlayersGooProduction(player, productionLoss);
        } else if (upgradeClass == 2) {
            unitAttackIncreases[player][unitId] -= upgradeValue;
        } else if (upgradeClass == 3) {
            unitAttackMultiplier[player][unitId] -= upgradeValue;
        } else if (upgradeClass == 4) {
            unitDefenseIncreases[player][unitId] -= upgradeValue;
        } else if (upgradeClass == 5) {
            unitDefenseMultiplier[player][unitId] -= upgradeValue;
        } else if (upgradeClass == 6) {
            unitGooStealingIncreases[player][unitId] -= upgradeValue;
        } else if (upgradeClass == 7) {
            unitGooStealingMultiplier[player][unitId] -= upgradeValue;
        }
    }
    
    function buyRareItem(uint256 rareId) external payable {
        require(schema.validRareId(rareId));
        
        address previousOwner = rareItemOwner[rareId];
        require(previousOwner != 0);

        uint256 ethCost = rareItemPrice[rareId];
        require(ethBalance[msg.sender] + msg.value >= ethCost);
        
        // We have to claim buyer's goo before updating their production values
        updatePlayersGoo(msg.sender);
        
        uint256 upgradeClass;
        uint256 unitId;
        uint256 upgradeValue;
        (upgradeClass, unitId, upgradeValue) = schema.getRareInfo(rareId);
        upgradeUnitMultipliers(msg.sender, upgradeClass, unitId, upgradeValue);
        
        // We have to claim seller's goo before reducing their production values
        updatePlayersGoo(previousOwner);
        removeUnitMultipliers(previousOwner, upgradeClass, unitId, upgradeValue);
        
        // Splitbid/Overbid
        if (ethCost > msg.value) {
            // Earlier require() said they can still afford it (so use their ingame balance)
            ethBalance[msg.sender] -= (ethCost - msg.value);
        } else if (msg.value > ethCost) {
            // Store overbid in their balance
            ethBalance[msg.sender] += msg.value - ethCost;
        }
        
        // Distribute ethCost
        uint256 devFund = ethCost / 50; // 2% fee on purchases (marketing, gameplay & maintenance)
        uint256 dividends = ethCost / 20; // 5% goes to pool (~93% goes to player)
        totalEtherGooResearchPool += dividends;
        ethBalance[owner] += devFund;
        
        // Transfer / update rare item
        rareItemOwner[rareId] = msg.sender;
        rareItemPrice[rareId] = (ethCost * 5) / 4; // 25% price flip increase
        ethBalance[previousOwner] += ethCost - (dividends + devFund);
    }
    
    function withdrawEther(uint256 amount) external {
        require(amount <= ethBalance[msg.sender]);
        ethBalance[msg.sender] -= amount;
        msg.sender.transfer(amount);
    }
    
    function claimResearchDividends(address referer, uint256 startSnapshot, uint256 endSnapShot) external {
        require(startSnapshot <= endSnapShot);
        require(startSnapshot >= lastGooResearchFundClaim[msg.sender]);
        require(endSnapShot < allocatedGooResearchSnapshots.length);
        
        uint256 researchShare;
        uint256 previousProduction = gooProductionSnapshots[msg.sender][lastGooResearchFundClaim[msg.sender] - 1]; // Underflow won't be a problem as gooProductionSnapshots[][0xffffffffff] = 0;
        for (uint256 i = startSnapshot; i <= endSnapShot; i++) {
            
            // Slightly complex things by accounting for days/snapshots when user made no tx's
            uint256 productionDuringSnapshot = gooProductionSnapshots[msg.sender][i];
            bool soldAllProduction = gooProductionZeroedSnapshots[msg.sender][i];
            if (productionDuringSnapshot == 0 && !soldAllProduction) {
                productionDuringSnapshot = previousProduction;
            } else {
               previousProduction = productionDuringSnapshot;
            }
            
            researchShare += (allocatedGooResearchSnapshots[i] * productionDuringSnapshot) / totalGooProductionSnapshots[i];
        }
        
        
        if (gooProductionSnapshots[msg.sender][endSnapShot] == 0 && !gooProductionZeroedSnapshots[msg.sender][i] && previousProduction > 0) {
            gooProductionSnapshots[msg.sender][endSnapShot] = previousProduction; // Checkpoint for next claim
        }
        
        lastGooResearchFundClaim[msg.sender] = endSnapShot + 1;
        
        uint256 referalDivs;
        if (referer != address(0) && referer != msg.sender) {
            referalDivs = researchShare / 100; // 1%
            ethBalance[referer] += referalDivs;
        }
        
        ethBalance[msg.sender] += researchShare - referalDivs;
    }
    
    // Allocate divs for the day (cron job)
    function snapshotDailyGooResearchFunding() external {
        require(msg.sender == owner);
        //require(block.timestamp >= (nextSnapshotTime - 30 minutes)); // Small bit of leeway for cron / network
        
        uint256 todaysEtherResearchFund = (totalEtherGooResearchPool / 10); // 10% of pool daily
        totalEtherGooResearchPool -= todaysEtherResearchFund;
        
        totalGooProductionSnapshots.push(totalGooProduction);
        allocatedGooResearchSnapshots.push(todaysEtherResearchFund);
        nextSnapshotTime = block.timestamp + 24 hours;
    }
    
    
    
    // Raffle for rare items
    function buyRaffleTicket(uint256 amount) external {
        require(raffleEndTime >= block.timestamp);
        require(amount > 0);
        
        uint256 ticketsCost = SafeMath.mul(RAFFLE_TICKET_BASE_GOO_PRICE, amount);
        require(balanceOf(msg.sender) >= ticketsCost);
        
        // Update players goo
        updatePlayersGooFromPurchase(msg.sender, ticketsCost);
        
        // Handle new tickets
        TicketPurchases storage purchases = ticketsBoughtByPlayer[msg.sender];
        
        // If we need to reset tickets from a previous raffle
        if (purchases.raffleRareId != raffleRareId) {
            purchases.numPurchases = 0;
            purchases.raffleRareId = raffleRareId;
            rafflePlayers[raffleRareId].push(msg.sender); // Add user to raffle
        }
        
        // Store new ticket purchase 
        if (purchases.numPurchases == purchases.ticketsBought.length) {
            purchases.ticketsBought.length += 1;
        }
        purchases.ticketsBought[purchases.numPurchases++] = TicketPurchase(raffleTicketsBought, raffleTicketsBought + (amount - 1)); // (eg: buy 10, get id's 0-9)
        
        // Finally update ticket total
        raffleTicketsBought += amount;
    }
    
    function startRareRaffle(uint256 endTime, uint256 rareId) external {
        require(msg.sender == owner);
        require(schema.validRareId(rareId));
        require(rareItemOwner[rareId] == 0);
        
        // Reset previous raffle info
        raffleWinningTicketSelected = false;
        raffleTicketThatWon = 0;
        raffleWinner = 0;
        raffleTicketsBought = 0;
        
        // Set current raffle info
        raffleEndTime = endTime;
        raffleRareId = rareId;
    }
    
    function awardRafflePrize(address checkWinner, uint256 checkIndex) external {
        require(raffleEndTime < block.timestamp);
        require(raffleWinner == 0);
        require(rareItemOwner[raffleRareId] == 0);
        
        if (!raffleWinningTicketSelected) {
            drawRandomWinner(); // Ideally do it in one call (gas limit cautious)
        }
        
        // Reduce gas by (optionally) offering an address to _check_ for winner
        if (checkWinner != 0) {
            TicketPurchases storage tickets = ticketsBoughtByPlayer[checkWinner];
            if (tickets.numPurchases > 0 && checkIndex < tickets.numPurchases && tickets.raffleRareId == raffleRareId) {
                TicketPurchase storage checkTicket = tickets.ticketsBought[checkIndex];
                if (raffleTicketThatWon >= checkTicket.startId && raffleTicketThatWon <= checkTicket.endId) {
                    assignRafflePrize(checkWinner); // WINNER!
                    return;
                }
            }
        }
        
        // Otherwise just naively try to find the winner (will work until mass amounts of players)
        for (uint256 i = 0; i < rafflePlayers[raffleRareId].length; i++) {
            address player = rafflePlayers[raffleRareId][i];
            TicketPurchases storage playersTickets = ticketsBoughtByPlayer[player];
            
            uint256 endIndex = playersTickets.numPurchases - 1;
            // Minor optimization to avoid checking every single player
            if (raffleTicketThatWon >= playersTickets.ticketsBought[0].startId && raffleTicketThatWon <= playersTickets.ticketsBought[endIndex].endId) {
                for (uint256 j = 0; j < playersTickets.numPurchases; j++) {
                    TicketPurchase storage playerTicket = playersTickets.ticketsBought[j];
                    if (raffleTicketThatWon >= playerTicket.startId && raffleTicketThatWon <= playerTicket.endId) {
                        assignRafflePrize(player); // WINNER!
                        return;
                    }
                }
            }
        }
    }
    
    function assignRafflePrize(address winner) internal {
        raffleWinner = winner;
        rareItemOwner[raffleRareId] = winner;
        rareItemPrice[raffleRareId] = (schema.rareStartPrice(raffleRareId) * 21) / 20; // Buy price slightly higher (Div pool cut)
        
        updatePlayersGoo(winner);
        uint256 upgradeClass;
        uint256 unitId;
        uint256 upgradeValue;
        (upgradeClass, unitId, upgradeValue) = schema.getRareInfo(raffleRareId);
        upgradeUnitMultipliers(winner, upgradeClass, unitId, upgradeValue);
    }
    
    // Random enough for small contests (Owner only to prevent trial & error execution)
    function drawRandomWinner() public {
        require(msg.sender == owner);
        require(raffleEndTime < block.timestamp);
        require(!raffleWinningTicketSelected);
        
        uint256 seed = raffleTicketsBought + block.timestamp;
        raffleTicketThatWon = addmod(uint256(block.blockhash(block.number-1)), seed, raffleTicketsBought);
        raffleWinningTicketSelected = true;
    }
    
    
    
    function protectAddress(address exchange, bool isProtected) external {
        require(msg.sender == owner);
        require(getGooProduction(exchange) == 0); // Can't protect actual players
        protectedAddresses[exchange] = isProtected;
    }
    
    function attackPlayer(address target) external {
        require(battleCooldown[msg.sender] < block.timestamp);
        require(target != msg.sender);
        require(!protectedAddresses[target]); //target not whitelisted (i.e. exchange wallets)
        
        uint256 attackingPower;
        uint256 defendingPower;
        uint256 stealingPower;
        (attackingPower, defendingPower, stealingPower) = getPlayersBattlePower(msg.sender, target);
        
        if (battleCooldown[target] > block.timestamp) { // When on battle cooldown you're vulnerable (starting value is 50% normal power)
            defendingPower = schema.getWeakenedDefensePower(defendingPower);
        }
        
        if (attackingPower > defendingPower) {
            battleCooldown[msg.sender] = block.timestamp + 30 minutes;
            if (balanceOf(target) > stealingPower) {
                // Save all their unclaimed goo, then steal attacker's max capacity (at same time)
                uint256 unclaimedGoo = balanceOfUnclaimedGoo(target);
                if (stealingPower > unclaimedGoo) {
                    uint256 gooDecrease = stealingPower - unclaimedGoo;
                    gooBalance[target] -= gooDecrease;
                } else {
                    uint256 gooGain = unclaimedGoo - stealingPower;
                    gooBalance[target] += gooGain;
                }
                gooBalance[msg.sender] += stealingPower;
                emit PlayerAttacked(msg.sender, target, true, stealingPower);
            } else {
                emit PlayerAttacked(msg.sender, target, true, balanceOf(target));
                gooBalance[msg.sender] += balanceOf(target);
                gooBalance[target] = 0;
            }
            
            lastGooSaveTime[target] = block.timestamp; 
            // We don't need to claim/save msg.sender's goo (as production delta is unchanged)
        } else {
            battleCooldown[msg.sender] = block.timestamp + 10 minutes;
            emit PlayerAttacked(msg.sender, target, false, 0);
        }
    }
    
    function getPlayersBattlePower(address attacker, address defender) internal constant returns (uint256, uint256, uint256) {
        uint256 startId;
        uint256 endId;
        (startId, endId) = schema.battleUnitIdRange();
        
        uint256 attackingPower;
        uint256 defendingPower;
        uint256 stealingPower;

        // Not ideal but will only be a small number of units (and saves gas when buying units)
        while (startId <= endId) {
            attackingPower += getUnitsAttack(attacker, startId, unitsOwned[attacker][startId]);
            stealingPower += getUnitsStealingCapacity(attacker, startId, unitsOwned[attacker][startId]);
            
            defendingPower += getUnitsDefense(defender, startId, unitsOwned[defender][startId]);
            startId++;
        }
        return (attackingPower, defendingPower, stealingPower);
    }
    
    function getPlayersBattleStats(address player) external constant returns (uint256, uint256, uint256) {
        uint256 startId;
        uint256 endId;
        (startId, endId) = schema.battleUnitIdRange();
        
        uint256 attackingPower;
        uint256 defendingPower;
        uint256 stealingPower;

        // Not ideal but will only be a small number of units (and saves gas when buying units)
        while (startId <= endId) {
            attackingPower += getUnitsAttack(player, startId, unitsOwned[player][startId]);
            stealingPower += getUnitsStealingCapacity(player, startId, unitsOwned[player][startId]);
            defendingPower += getUnitsDefense(player, startId, unitsOwned[player][startId]);
            startId++;
        }
        return (attackingPower, defendingPower, stealingPower);
    }
    
    function getUnitsProduction(address player, uint256 unitId, uint256 amount) internal constant returns (uint256) {
        return (amount * (schema.unitGooProduction(unitId) + unitGooProductionIncreases[player][unitId]) * (10 + unitGooProductionMultiplier[player][unitId])) / 10;
    }
    
    function getUnitsAttack(address player, uint256 unitId, uint256 amount) internal constant returns (uint256) {
        return (amount * (schema.unitAttack(unitId) + unitAttackIncreases[player][unitId]) * (10 + unitAttackMultiplier[player][unitId])) / 10;
    }
    
    function getUnitsDefense(address player, uint256 unitId, uint256 amount) internal constant returns (uint256) {
        return (amount * (schema.unitDefense(unitId) + unitDefenseIncreases[player][unitId]) * (10 + unitDefenseMultiplier[player][unitId])) / 10;
    }
    
    function getUnitsStealingCapacity(address player, uint256 unitId, uint256 amount) internal constant returns (uint256) {
        return (amount * (schema.unitStealingCapacity(unitId) + unitGooStealingIncreases[player][unitId]) * (10 + unitGooStealingMultiplier[player][unitId])) / 10;
    }
    
    
    // To display on website
    function getGameInfo() external constant returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256[], bool[]){
        uint256[] memory units = new uint256[](schema.currentNumberOfUnits());
        bool[] memory upgrades = new bool[](schema.currentNumberOfUpgrades());
        
        uint256 startId;
       