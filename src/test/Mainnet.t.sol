// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.16;

import "ds-test/test.sol";
import {Vm} from "forge-std/Vm.sol";
import {EIP20Interface} from "../interfaces/EIP20Interface.sol";
import {InterestRateModel} from "../interfaces/InterestRateModel.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IERC20} from "../interfaces/IERC20.sol";

import {ComptrollerInterface} from "../interfaces/ComptrollerInterface.sol";
import {CErc20ImmutableCVX} from "../cTokens/CErc20ImmutableCVX.sol";
import {CToken} from "../cTokens/CToken.sol";
import {CrvDolaFeed} from "../cTokens/CrvDolaFeed.sol";

contract MainnetTest is DSTest {
    Vm internal constant vm = Vm(HEVM_ADDRESS);

    // Anchor
    ComptrollerInterface comptroller = ComptrollerInterface(0x4dCf7407AE5C07f8681e1659f626E114A7667339);
    address interestRateModelAddy = 0x8f0439382359c05ED287Acd5170757B76402D93F;
    address anchorOracle = 0xE8929AFd47064EfD36A7fB51dA3F8C5eb40c4cb4;
    address payable governance = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    CErc20ImmutableCVX cvxCToken;
    CrvDolaFeed crvDolaFeed;

    // CRV
    EIP20Interface crvLpToken = EIP20Interface(0xAA5A67c256e27A5d80712c51971408db3370927D);
    address public constant crv =
        address(0xD533a949740bb3306d119CC777fa900bA034cd52);

    // CVX
    address cvxRewardsPool = 0x835f69e58087E5B6bffEf182fe2bf959Fe253c3c;
    address cvxToken = 0xb3E8f3D7Ec208a032178880955f6c877479d1FDd;
    uint256 cvxPoolID = 62;
    address public constant cvx =
        address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    
    // Numbas
    uint256 crvDolaAmount = 1_000_000 * 10**18;
    uint256 NUM_DAYS = 2 days;

    // EOAs
    address user = address(0x69);
    address user2 = address(0x0101);

    function setUp() public {
        //Send tokens to test EOAs
        distributeCrvDola(user);
        distributeCrvDola(user2);

        //Deploy new contracts
        crvDolaFeed = new CrvDolaFeed();
        cvxCToken = new CErc20ImmutableCVX(address(crvLpToken), comptroller, InterestRateModel(interestRateModelAddy), 2e26, "anCvx", "anCvx", 8, governance, cvxRewardsPool, cvxToken, cvxPoolID);

        //Set new price feed and add new cToken market to comptroller
        vm.startPrank(governance);
        IOracle(anchorOracle).setFeed(address(cvxCToken), address(crvDolaFeed), 18);
        comptroller._supportMarket(CToken(address(cvxCToken)));
        comptroller._setCollateralFactor(CToken(address(cvxCToken)), 0.8e18);

        //Enter new cToken market on test EOAs
        vm.startPrank(user2);
        address[] memory addrs = new address[](1);
        addrs[0] = address(cvxCToken);
        comptroller.enterMarkets(addrs);

        vm.startPrank(user);
        comptroller.enterMarkets(addrs);
    }

    function testMintRedeemGivesCorrectAmount() public {
        vm.startPrank(user);
        crvLpToken.approve(address(cvxCToken), crvDolaAmount);
        uint256 startBal = crvLpToken.balanceOf(user);
        cvxCToken.mint(crvDolaAmount);

        (,uint256 liquidity,) = comptroller.getAccountLiquidity(user);
        emit log_named_uint("liquidity", liquidity);
        emit log_named_uint("liquidity $", liquidity / 1e18);

        vm.startPrank(user);
        cvxCToken.redeem(cvxCToken.balanceOf(user));

        assert(crvLpToken.balanceOf(user) == startBal);
    }

    function testClaimCVXRewards() public {
        vm.startPrank(user);
        crvLpToken.approve(address(cvxCToken), crvDolaAmount);
        cvxCToken.mint(crvDolaAmount);

        vm.warp(block.timestamp + NUM_DAYS);
        
        uint256 crvBalUser = IERC20(crv).balanceOf(user);
        uint256 cvxBalUser = IERC20(cvx).balanceOf(user);

        cvxCToken.getReward(user);

        assert(crvBalUser < IERC20(crv).balanceOf(user));
        assert(cvxBalUser < IERC20(cvx).balanceOf(user));
    }

    function testFailClaimAnotherUsersReward() public {
        vm.startPrank(user);
        crvLpToken.approve(address(cvxCToken), crvDolaAmount);
        cvxCToken.mint(crvDolaAmount);

        vm.warp(block.timestamp + NUM_DAYS);

        vm.startPrank(user2);
        cvxCToken.getReward(user, user2);
    }

    function testUserCheckpointDoesNotClaimRewards() public {
        vm.startPrank(user);
        crvLpToken.approve(address(cvxCToken), crvDolaAmount);
        cvxCToken.mint(crvDolaAmount);

        vm.warp(block.timestamp + NUM_DAYS);
        
        uint256 crvBalUser = IERC20(crv).balanceOf(user);
        uint256 cvxBalUser = IERC20(cvx).balanceOf(user);

        cvxCToken.user_checkpoint([user, user]);

        assert(crvBalUser == IERC20(crv).balanceOf(user));
        assert(cvxBalUser == IERC20(cvx).balanceOf(user));
    }

    function testClaimCVXRewardsAfterRedeemingCTokens() public {
        vm.startPrank(user);
        crvLpToken.approve(address(cvxCToken), crvDolaAmount);
        cvxCToken.mint(crvDolaAmount);

        vm.warp(block.timestamp + NUM_DAYS);

        cvxCToken.redeem(cvxCToken.balanceOf(user));
        cvxCToken.getReward(user);        

        uint256 crvBalUser = IERC20(crv).balanceOf(user);
        uint256 cvxBalUser = IERC20(cvx).balanceOf(user);

        emit log_named_uint("user crv bal", crvBalUser);
        emit log_named_uint("user cvx bal", cvxBalUser);
    }

    function testClaimCVXRewardsUsingMultipleAccountsAfterTransfer() public {
        vm.startPrank(user);
        crvLpToken.approve(address(cvxCToken), crvDolaAmount);
        cvxCToken.mint(crvDolaAmount);

        vm.warp(block.timestamp + NUM_DAYS);

        cvxCToken.transfer(user2, cvxCToken.balanceOf(user));

        cvxCToken.getReward(user);
        cvxCToken.getReward(user2);
        vm.warp(block.timestamp + NUM_DAYS);
        cvxCToken.getReward(user);
        cvxCToken.getReward(user2);

        uint256 userCrvBal = IERC20(crv).balanceOf(user);
        uint256 userCvxBal = IERC20(cvx).balanceOf(user);
        uint256 user2CrvBal = IERC20(crv).balanceOf(user2);
        uint256 user2CvxBal = IERC20(cvx).balanceOf(user2);

        emit log_named_uint("user crv bal", userCrvBal);
        emit log_named_uint("user cvx bal", userCvxBal);
        emit log_named_uint("user2 crv bal", user2CrvBal);
        emit log_named_uint("user2 cvx bal", user2CvxBal);
        assert(userCvxBal == user2CvxBal);
        assert(userCrvBal == user2CrvBal);
    }

    function testDoubleClaimDoesNotGiveDoubleRewards() public {
        vm.startPrank(user2);
        crvLpToken.approve(address(cvxCToken), crvDolaAmount * 2);
        cvxCToken.mint(crvDolaAmount * 2);

        vm.startPrank(user);
        crvLpToken.approve(address(cvxCToken), crvDolaAmount);
        cvxCToken.mint(crvDolaAmount);

        vm.warp(block.timestamp + NUM_DAYS);
        cvxCToken.getReward(user);
        
        uint256 crvBalUser = IERC20(crv).balanceOf(user);
        uint256 cvxBalUser = IERC20(cvx).balanceOf(user);

        cvxCToken.getReward(user);

        assert(crvBalUser == IERC20(crv).balanceOf(user));
        assert(cvxBalUser == IERC20(cvx).balanceOf(user));
    }

    function testTransfer() public {
        vm.startPrank(user);
        crvLpToken.approve(address(cvxCToken), crvDolaAmount);
        cvxCToken.mint(crvDolaAmount);

        uint256 prevBal = cvxCToken.balanceOf(user);

        cvxCToken.transfer(user2, cvxCToken.balanceOf(user));

        assert(prevBal == cvxCToken.balanceOf(user2));
        assert(cvxCToken.balanceOf(user) == 0);
    }

    function testTransferFrom() public {
        vm.startPrank(user);
        crvLpToken.approve(address(cvxCToken), crvDolaAmount);
        cvxCToken.mint(crvDolaAmount);

        uint256 prevBal = cvxCToken.balanceOf(user);

        cvxCToken.approve(user2, uint256(-1));

        vm.startPrank(user2);
        cvxCToken.transferFrom(user, user2, cvxCToken.balanceOf(user));

        assert(prevBal == cvxCToken.balanceOf(user2));
        assert(cvxCToken.balanceOf(user) == 0);
    }

    function distributeCrvDola(address _user) public {
        bytes32 slot;

        assembly {
            mstore(0, 0x18)
            mstore(0x20, _user)
            slot := keccak256(0, 0x40)
        }

        vm.store(address(crvLpToken), slot, bytes32(crvDolaAmount * 2));
    }
}
