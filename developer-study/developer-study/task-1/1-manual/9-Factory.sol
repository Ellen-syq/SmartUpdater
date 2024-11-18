pragma solidity ^0.6.4;

contract Proxy {

    // TODO: implement the Proxy contract
}

contract Factory{

    //Adress of creator

    address private creator;


    // Addresses of owners

    address private owner1 = 0x6CAa636cFFbCbb2043A3322c04dE3f26b1fa6555;

    address private owner2 = 0xbc2d90C2D3A87ba3fC8B23aA951A9936A6D68121;

    address private owner3 = 0x680d821fFE703762E7755c52C2a5E8556519EEDc;

  
    //List of deployed Forwarders

    address[] public deployed_forwarders;

    

    //Get number of forwarders created

    uint public forwarders_count = 0;

    

    //Last forwarder create

    address public last_forwarder_created;

  

    //Only owners can generate a forwarder

    modifier onlyOwnerOrCreator {

      require(msg.sender == owner1 || msg.sender == owner2 || msg.sender == owner3 || msg.sender == creator);

      _;

    }

  

    //Constructor

    constructor() public {

        creator = msg.sender;

    }

  

    //Create new Forwarder

    function create_forwarder() public onlyOwnerOrCreator {

        address new_forwarder = new Forwarder();

        deployed_forwarders.push(new_forwarder);

        last_forwarder_created = new_forwarder;

        forwarders_count += 1;

    }

    

    //Get deployed forwarders

    function get_deployed_forwarders() public view returns (address[]) {

        return deployed_forwarders;

    }


}
