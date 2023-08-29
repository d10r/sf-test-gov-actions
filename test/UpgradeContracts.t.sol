// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import { 
    ISuperfluid,
    ISuperfluidGovernance,
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IMultiSigWallet } from "./helpers/IMultiSigWallet.sol";
import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";
import { CFAv1Forwarder } from "@superfluid-finance/ethereum-contracts/contracts/utils/CFAv1Forwarder.sol";
import { UUPSProxiable } from "@superfluid-finance/ethereum-contracts/contracts/upgradability/UUPSProxiable.sol";
import { ConstantOutflowNFT } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/ConstantOutflowNFT.sol";
import { ConstantInflowNFT } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/ConstantInflowNFT.sol";
import { SuperTokenFactory } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperTokenFactory.sol";

contract UpgradeContracts is Test {
    
    address HOST_ADDR;
    ISuperfluid host;
    ISuperfluidGovernance gov;
    address govOwner;
    SuperTokenFactory factory;
    IMultiSigWallet multisig;
    address HOST_NEW_LOGIC;
    address CFA_NEW_LOGIC;
    address IDA_NEW_LOGIC;
    address FACTORY_NEW_LOGIC;
    
    CFAv1Forwarder cfaFwd = CFAv1Forwarder(0xcfA132E353cB4E398080B9700609bb008eceB125);

    address constant alice = address(0x420);

    constructor() {
        string memory rpc = vm.envString("RPC");
        vm.createSelectFork(rpc);
        HOST_ADDR = vm.envAddress("HOST_ADDR");
        HOST_NEW_LOGIC = vm.envAddress("HOST_NEW_LOGIC");
        CFA_NEW_LOGIC = vm.envAddress("CFA_NEW_LOGIC");
        IDA_NEW_LOGIC = vm.envAddress("IDA_NEW_LOGIC");
        FACTORY_NEW_LOGIC = vm.envAddress("FACTORY_NEW_LOGIC");

        host = ISuperfluid(HOST_ADDR);
        gov = ISuperfluidGovernance(host.getGovernance());
        console.log("gov: %s", address(gov));

        govOwner = Ownable(address(gov)).owner();
        multisig = IMultiSigWallet(govOwner);
    }

    function testUpgrade() public {
        address[] memory agreementNewLogics = new address[](2);
        agreementNewLogics[0] = CFA_NEW_LOGIC;
        agreementNewLogics[1] = IDA_NEW_LOGIC;

        vm.startPrank(govOwner);
        gov.updateContracts(
            ISuperfluid(HOST_ADDR),
            HOST_NEW_LOGIC,
            agreementNewLogics,
            FACTORY_NEW_LOGIC
        );
        vm.stopPrank();
    }
}