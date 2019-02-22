pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./RewardPool.sol";
import "./IAsset.sol";

contract Curator is IAsset, Ownable {

  RewardPool public _rewardPool;

  function init(address rewardPool) external
    onlyOwner()
  {
    require(address(rewardPool) != address(0));
    require(address(_rewardPool) == address(0));
    _rewardPool = RewardPool(rewardPool);
  }

  function addVote(bytes32 docId, uint256 deposit) external {
    _rewardPool._ballot().create(_rewardPool._ballot().next(), msg.sender, docId, deposit);
  }

  function getVote(uint256 i) external view returns (address, bytes32, uint256, uint256, uint256) {
    return _rewardPool._ballot().getVote(i);
  }

  function getDocuments(address owner) external view returns (bytes32[]) {
    return _rewardPool._ballot().getUserDocuments(owner);
  }

  function count() external view returns (uint256) {
    return _rewardPool._ballot().count();
  }

  function getActiveVotes(bytes32 docId) external view returns (uint256) {
    return _rewardPool._ballot().getActiveVotes(docId, uint(block.timestamp/86400) * 86400000, _rewardPool.getVestingMillis());
  }

  function getUserActiveVotes(address addr, bytes32 docId) external view returns (uint256) {
    return _rewardPool._ballot().getUserActiveVotes(addr, docId, uint(block.timestamp/86400) * 86400000, _rewardPool.getVestingMillis());
  }

  function getUserDocuments(address addr) external view returns (bytes32[]) {
    return _rewardPool._ballot().getUserDocuments(addr);
  }

  function determine(bytes32 docId) external view returns (uint256, uint256) {
    require(docId != 0);
    require(address(_rewardPool) != address(0));
    require(_rewardPool._registry().contains(docId));
    return totalReward(msg.sender, docId, uint(block.timestamp/86400) * 86400000);
  }

  function totalReward(address addr, bytes32 docId, uint256 claimMillis) private view returns (uint256, uint256) {
    uint256 sum = 0;
    uint256 refund = 0;
    uint256 next = 0;
    uint256 listed = 0;
    uint256 last = 0;
    (,listed,last,) = _rewardPool._registry().getDocument(docId);
    while (last <= claimMillis) {
      if (last == 0) {
        last = listed;
      }
      uint deposit = _rewardPool._ballot().getUserClaimableVotes(addr, docId, last, claimMillis, _rewardPool.getVestingMillis());
      sum += dailyReward(docId, last, deposit);
      refund += dailyRefund(addr, docId, last, claimMillis);
      next = last + 86400000;
      assert(last < next);
      last = next;
    }
    return (sum, refund);
  }

  function dailyReward(bytes32 docId, uint dateMillis, uint deposit) private view returns (uint) {
    uint pool = _rewardPool.getDailyRewardPool(uint(30), dateMillis);
    uint tvd = _rewardPool._ballot().getActiveVotes(docId, dateMillis, _rewardPool.getVestingMillis());
    uint pv = _rewardPool._registry().getPageView(docId, dateMillis);
    uint tpvs = _rewardPool._registry().getTotalPageViewSquare(dateMillis);
    return calculate(pool, deposit, tvd, pv, tpvs);
  }

  function dailyRefund(address addr, bytes32 docId, uint dateMillis, uint claimMillis) private view returns (uint) {
    return _rewardPool._ballot().getUserRefundableDeposit(addr, docId, dateMillis, claimMillis, _rewardPool.getVestingMillis());
  }

  function calculate(uint pool, uint v, uint tv, uint pv, uint tpvs) public pure returns (uint) {
    if (tpvs == 0 || pv == 0 || tv == 0) {
      return uint(0);
    }
    assert(tv >= v);
    assert(tpvs >= (pv ** 2));
    uint reward = uint(uint((pool * (pv ** 2)) / tpvs) * v / tv);
    assert(pool >= reward);
    return reward;
  }

  function determineAt(address addr, bytes32 docId, uint256 dateMillis) external view returns (uint256, uint256) {
    require(msg.sender == address(_rewardPool));
    require(address(_rewardPool) != address(0));
    return totalReward(addr, docId, dateMillis);
  }

  function recentEarnings(address addr, bytes32 docId, uint256 day) external view returns (uint256) {
    uint256 sum = 0;
    uint256 next = 0;
    uint256 todayMillis = uint(block.timestamp/86400) * 86400000;
    uint256 listed;
    (,listed,,) = _rewardPool._registry().getDocument(docId);
    next = (todayMillis - (day * 86400000)) < listed ? listed : (todayMillis - (day * 86400000));
    while (next < todayMillis) {
      uint deposit = _rewardPool._ballot().getUserActiveVotes(addr, docId, next, _rewardPool.getVestingMillis());
      sum += dailyReward(docId, next, deposit);
      next += 86400000;
    }
    return sum;
  }
}
