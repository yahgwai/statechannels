pragma solidity ^0.4.24;

contract StateChannel {
    address[] public plist;
    mapping (address => bool) pmap; // List of players in this channel!

    enum Status { ON, DISPUTE, OFF }

    // Configuration for state channel
    uint256 public disputePeriod;  // Minimum time for dispute process (time all parties have to submit a command)

    // Current status for channel
    Status public status;
    // YAH: why initialise bestRound to 0, and not any other vars?
    uint256 public bestRound = 0;
    uint256 public t_start;
    uint256 public deadline;
    bytes32 public hstate;

    // List of disputes (i.e. successful state transitions on-chain)
    struct Dispute {
        uint256 round;
        uint256 t_start;
        uint256 t_settle;
    }

    Dispute dispute;

    event EventDispute (uint256 indexed deadline);
    event EventResolve (uint256 indexed bestround);
    event EventEvidence (uint256 indexed bestround, bytes32 hstate);

    modifier onlyplayers { if (pmap[msg.sender]) _; else revert(); }


    // The application creates this state channel and updates it with the list of players.
    // Also sets a fixed dispute period.
    constructor(address[] _plist, uint _disputePeriod) public {

        for (uint i = 0; i < _plist.length; i++) {
            plist.push(_plist[i]);
            pmap[_plist[i]] = true;
        }

        disputePeriod = _disputePeriod;
    }

    // Trigger the dispute
    function triggerDispute() onlyplayers public {

        // Only accept a single command during a dispute
        require( status == Status.ON );
        status = Status.DISPUTE;
        // YAH: bug? should be setting deadline?
        t_start = block.timestamp + t_start;

    }

    // Store a state hash that was authorised by all parties in the state channel
    // This cancels any disputes in progress if it is associated with the largest nonce seen so far.
    // ANYONE can relay a message! Important for PISA.
    // YAH: prefer camel case
    function setstate(uint256[] sigs, uint256 _i, bytes32 _hstate) public {
        require(_i > bestRound);
        require( status == Status.DISPUTE);

        // Commitment to signed message for new state hash.
        bytes32 h = keccak256(_hstate, _i, address(this));
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        h = keccak256(prefix, h);

        // Check all parties in channel have signed it.
        for (uint i = 0; i < plist.length; i++) {
            uint8 V = uint8(sigs[i*3+0])+27;
            bytes32 R = bytes32(sigs[i*3+1]);
            bytes32 S = bytes32(sigs[i*3+2]);
            verifySignature(plist[i], h, V, R, S);
        }

        // Store new state!
        bestRound = _i;
        hstate = _hstate;

        // Tell the world about the new state!
        emit EventEvidence(bestRound, hstate);
    }

    function resolve() onlyplayers public {
        require(block.number > deadline); // Dispute process should be finished?
        require(status == Status.DISPUTE);

        // Return to normal operations and update bestRound
        // YAH: return to normal operations? off? a dispute cannot be triggered in off, and there's no way of setting back to ON
        // YAH: if that's the case, what's the point in setting bestRound = bestRound + 1?
        status = Status.OFF;
        bestRound = bestRound + 1;

        // Store dispute... due to successful on-chain transition
        dispute = Dispute(bestRound, t_start, deadline);

        emit EventResolve(bestRound);
    }


    // Fetch a dispute.
    // YAH: whats the purpose of this when dispute is actually public?
    function getDispute() public view returns (uint256, uint256, uint256) {
        require(status == Status.OFF);

        return (dispute.round, dispute.t_start, dispute.t_settle);
    }

    // Helper function to verify signatures
    function verifySignature(address pub, bytes32 h, uint8 v, bytes32 r, bytes32 s) public pure {
        address _signer = ecrecover(h,v,r,s);
        if (pub != _signer) revert();
    }

    // Fetch latest state hash, only fetchable once dispute process has concluded.
    // YAH: whats the purpose of this when hstate is actually public?
    function getStateHash() public view returns (bytes32) {
        require(status == Status.OFF);

        return hstate;
    }

    // Latest round in contract
    // YAH: whats the purpose of this when bestRound is actually public?
    function latestClaim() public view returns(uint) {
        return bestRound;
    }
}
