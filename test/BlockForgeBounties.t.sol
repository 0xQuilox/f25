// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/BlockForgeBounties.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockBOBA is ERC20 {
    constructor() ERC20("BOBA Token", "BOBA") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract BlockForgeBountiesTest is Test {
    BlockForgeBounties public bounties;
    MockBOBA public bobaToken;
    address public bountyOwner;
    address public user1;
    address public user2;

    uint256 constant INITIAL_BALANCE = 100 ether;
    uint256 constant INITIAL_BOBA_BALANCE = 1000 * 10**18;
    uint256 constant ONE_DAY = 1 days;

    event BountyCreated(uint indexed bountyId, address indexed owner, uint amount);
    event BountyCompleted(uint indexed bountyId, address indexed winner, uint amount);
    event BountyRefunded(uint indexed bountyId, address indexed owner, uint amount);

    function setUp() public {
        bountyOwner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy mock BOBA token
        bobaToken = new MockBOBA();
        
        // Deploy BlockForgeBounties with mock BOBA token
        bounties = new BlockForgeBounties(address(bobaToken));

        // Setup initial balances
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);
        bobaToken.transfer(user1, INITIAL_BOBA_BALANCE);
        bobaToken.transfer(user2, INITIAL_BOBA_BALANCE);
    }

    // --- Bounty Creation Tests ---
    function testCreateETHBounty() public {
        vm.startPrank(user1);
        uint bountyAmount = 1 ether;

        vm.expectEmit(true, true, false, true);
        emit BountyCreated(0, user1, bountyAmount);

        uint bountyId = bounties.createBounty{value: bountyAmount}(
            bountyAmount,
            address(0),
            ONE_DAY,
            "QmHash123"
        );
        vm.stopPrank();

        (
            address bountyCreator,
            address winner,
            uint amount,
            address tokenAddress,
            uint deadline,
            string memory descriptionHash,
            bool isCompleted,
            bool isRefunded
        ) = bounties.getBounty(bountyId);

        assertEq(bountyCreator, user1);
        assertEq(winner, address(0));
        assertEq(amount, bountyAmount);
        assertEq(tokenAddress, address(0));
        assertEq(deadline, block.timestamp + ONE_DAY);
        assertEq(descriptionHash, "QmHash123");
        assertFalse(isCompleted);
        assertFalse(isRefunded);
    }

    function testCreateBOBABounty() public {
        vm.startPrank(user1);
        uint bountyAmount = 100 * 10**18;
        
        bobaToken.approve(address(bounties), bountyAmount);
        
        uint bountyId = bounties.createBounty(
            bountyAmount,
            bounties.BOBA_TOKEN_SENTINEL(),
            ONE_DAY,
            "QmHash123"
        );
        vm.stopPrank();

        (
            address bountyCreator,
            ,
            uint amount,
            address tokenAddress,
            ,
            ,
            bool isCompleted,
            bool isRefunded
        ) = bounties.getBounty(bountyId);

        assertEq(bountyCreator, user1);
        assertEq(amount, bountyAmount);
        assertEq(tokenAddress, address(bobaToken));
        assertFalse(isCompleted);
        assertFalse(isRefunded);
    }

    // --- Bounty Completion Tests ---
    function testCompleteBountyETH() public {
        // Create bounty
        vm.startPrank(user1);
        uint bountyAmount = 1 ether;
        uint bountyId = bounties.createBounty{value: bountyAmount}(
            bountyAmount,
            address(0),
            ONE_DAY,
            "QmHash123"
        );

        // Complete bounty
        uint user2BalanceBefore = address(user2).balance;
        
        vm.expectEmit(true, true, false, true);
        emit BountyCompleted(bountyId, user2, bountyAmount);
        
        bounties.completeBounty(bountyId, user2);
        vm.stopPrank();

        uint user2BalanceAfter = address(user2).balance;
        assertEq(user2BalanceAfter - user2BalanceBefore, bountyAmount);

        (
            ,
            address winner,
            ,
            ,
            ,
            ,
            bool isCompleted,
            bool isRefunded
        ) = bounties.getBounty(bountyId);

        assertEq(winner, user2);
        assertTrue(isCompleted);
        assertFalse(isRefunded);
    }

    // --- Refund Tests ---
    function testRequestRefundAfterDeadline() public {
        // Create bounty
        vm.startPrank(user1);
        uint bountyAmount = 1 ether;
        uint deadline = block.timestamp + ONE_DAY;
        uint bountyId = bounties.createBounty{value: bountyAmount}(
            bountyAmount,
            address(0),
            ONE_DAY,
            "QmHash123"
        );

        // Fast forward beyond deadline
        vm.warp(deadline + 1);

        uint user1BalanceBefore = address(user1).balance;
        
        vm.expectEmit(true, true, false, true);
        emit BountyRefunded(bountyId, user1, bountyAmount);
        
        bounties.requestRefund(bountyId);
        vm.stopPrank();

        uint user1BalanceAfter = address(user1).balance;
        assertEq(user1BalanceAfter - user1BalanceBefore, bountyAmount);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            bool isCompleted,
            bool isRefunded
        ) = bounties.getBounty(bountyId);

        assertFalse(isCompleted);
        assertTrue(isRefunded);
    }

    // --- Error Cases ---
    function testCannotCompleteRefundedBounty() public {
        // Create and cancel bounty
        vm.startPrank(user1);
        uint bountyAmount = 1 ether;
        uint bountyId = bounties.createBounty{value: bountyAmount}(
            bountyAmount,
            address(0),
            ONE_DAY,
            "QmHash123"
        );
        bounties.cancelBounty(bountyId);

        vm.expectRevert("BlockForgeBounties: This bounty has been refunded and cannot be completed.");
        bounties.completeBounty(bountyId, user2);
        vm.stopPrank();
    }

    function testCannotRefundBeforeDeadline() public {
        vm.startPrank(user1);
        uint bountyAmount = 1 ether;
        uint bountyId = bounties.createBounty{value: bountyAmount}(
            bountyAmount,
            address(0),
            ONE_DAY,
            "QmHash123"
        );

        vm.expectRevert("BlockForgeBounties: Bounty deadline has not yet passed. Use `cancelBounty` for early cancellation.");
        bounties.requestRefund(bountyId);
        vm.stopPrank();
    }

    function testCannotCompleteCompletedBounty() public {
        vm.startPrank(user1);
        uint bountyAmount = 1 ether;
        uint bountyId = bounties.createBounty{value: bountyAmount}(
            bountyAmount,
            address(0),
            ONE_DAY,
            "QmHash123"
        );

        bounties.completeBounty(bountyId, user2);

        vm.expectRevert("BlockForgeBounties: Bounty has already been completed.");
        bounties.completeBounty(bountyId, user2);
        vm.stopPrank();
    }
}