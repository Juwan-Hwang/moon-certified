/// Raft — Invariant-preserving consensus for replicated state machines.
///
/// This module implements the Raft consensus algorithm as described in
/// Ongaro & Ousterhout (2014), "In Search of an Understandable Consensus
/// Algorithm." Raft decomposes consensus into three sub-problems:
///
/// 1. **Leader Election** — A randomized timeout mechanism ensures that
///    exactly one leader is elected per term with high probability.
/// 2. **Log Replication** — The leader accepts commands, appends them to
///    its log, and replicates them to followers. An entry is committed
///    once a majority of followers acknowledge it.
/// 3. **Safety** — Election restrictions guarantee that only a candidate
///    whose log is at least as up-to-date as a majority can become leader,
///    and a leader only commits entries from its own term.
///
/// ## Design
///
/// The implementation is a **single-node state machine** that processes
/// incoming RPC messages and produces outgoing RPC messages. A real
/// deployment wires these to a network transport; the test suite uses an
/// in-memory message bus. The node itself is deterministic given its
/// inputs — all non-determinism (election timeout jitter) is injected
/// through an explicit `tick` counter.
///
/// ## RPC Protocol
///
/// Two RPC types are defined:
///
/// - **RequestVote** — Candidate solicits votes. The recipient grants a
///   vote only if the candidate's term ≥ voter's term, the voter has not
///   already voted in this term, and the candidate's log is at least as
///   up-to-date.
/// - **AppendEntries** — Leader replicates log entries and sends heartbeats.
///   The recipient appends entries only if the leader's term is current
///   and the prev-log-index/term match.
///
/// ## Complexity
///
/// | Operation | Time |
/// |-----------|------|
/// | `handle_request_vote` | O(1) |
/// | `handle_append_entries` | O(n) where n = entries in the RPC |
/// | `tick` | O(1) |
/// | `become_leader` | O(n) where n = cluster size |
///
/// ## References
///
/// - Ongaro, D. & Ousterhout, J. (2014). "In Search of an Understandable
///   Consensus Algorithm." *USENIX ATC*.
/// - Ongaro, D. (2014). "Consensus: Bridging Theory and Practice." PhD
///   thesis, Stanford University.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Default heartbeat interval (in ticks). The leader sends AppendEntries
/// at this cadence to prevent followers from timing out.
let default_heartbeat_interval : Int = 1

///|
/// Default election timeout minimum (in ticks). A follower becomes a
/// candidate after a random timeout in [min, min + range).
let default_election_timeout_min : Int = 5

///|
/// Default election timeout range (in ticks).
let default_election_timeout_range : Int = 5

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

///|
/// Role of a Raft node.
pub enum RaftRole {
  Follower
  Candidate
  Leader
}

///|
/// A single log entry. Each entry contains a term and a command.
/// The index is implicit (0-based position in the log array).
pub struct LogEntry {
  /// Term in which the entry was created.
  term : Int
  /// Opaque command data (application-specific).
  command : Int
}

///|
/// Persistent state on all servers (survives restarts).
/// In a real implementation, this would be persisted to disk.
pub struct PersistentState {
  /// Latest term the node has seen.
  mut current_term : Int
  /// Candidate ID that received this node's vote in the current term
  /// (or -1 if none).
  mut voted_for : Int
  /// Log entries; index 0 is a sentinel with term 0 (bootstrap).
  log : Array[LogEntry]
}

///|
/// Volatile state on all servers (re-initialized on restart).
pub struct VolatileState {
  /// Index of the highest log entry known to be committed.
  mut commit_index : Int
  /// Index of the highest log entry applied to the state machine.
  mut last_applied : Int
}

///|
/// Volatile state on leaders only (re-initialized after election).
pub struct LeaderState {
  /// For each follower, index of the next log entry to send.
  mut next_index : Array[Int]
  /// For each follower, index of highest log entry known to be replicated.
  mut match_index : Array[Int]
}

///|
/// A complete Raft node with all state.
///
/// The node processes RPCs via `handle_request_vote` and
/// `handle_append_entries`, and produces outgoing RPCs that the caller
/// is responsible for delivering over the network.
pub struct RaftNode {
  /// This node's ID (0-based).
  node_id : Int
  /// Total number of nodes in the cluster.
  cluster_size : Int
  /// Current role.
  mut role : RaftRole
  /// Persistent state.
  persistent : PersistentState
  /// Volatile state.
  vol_state : VolatileState
  /// Leader state (only meaningful when role == Leader).
  leader_state : LeaderState
  /// Current leader ID (-1 if unknown).
  mut leader_id : Int
  /// Ticks since last AppendEntries received or vote granted.
  mut election_elapsed : Int
  /// Randomized election timeout for this election period.
  mut election_timeout : Int
  /// Ticks since last heartbeat sent (leader only).
  mut heartbeat_elapsed : Int
  /// Heartbeat interval (in ticks).
  heartbeat_interval : Int
  /// PRNG state for election timeout randomization.
  mut rng_state : Int
}

// ---------------------------------------------------------------------------
// PRNG (xorshift32)
// ---------------------------------------------------------------------------

///|
/// Advance the xorshift32 PRNG and return the next 32-bit value.
fn rng_next(state : Int) -> Int {
  let mut x = state
  x = x ^ (x << 13)
  x = x ^ (x.reinterpret_as_uint() >> 17).reinterpret_as_int()
  x = x ^ (x << 5)
  x
}

///|
/// Generate a random integer in [lo, lo + range).
fn rng_range(state : Int, lo : Int, range : Int) -> (Int, Int) {
  let s = rng_next(state)
  if range <= 0 {
    return (s, lo)
  }
  let v = lo + (s.reinterpret_as_uint() >> 1).reinterpret_as_int() % range
  (s, v)
}

// ---------------------------------------------------------------------------
// Log helpers
// ---------------------------------------------------------------------------

///|
/// Get the index of the last log entry (0-based, matching array indices).
/// The log always has at least the sentinel entry at index 0.
fn last_log_index(node : RaftNode) -> Int {
  node.persistent.log.length() - 1
}

///|
/// Get the term of the last log entry.
fn last_log_term(node : RaftNode) -> Int {
  let idx = last_log_index(node)
  if idx < 0 {
    return 0
  }
  node.persistent.log[idx].term
}

///|
/// Get the term of the log entry at `index` (0-based).
/// Returns 0 if the index is out of bounds (including the sentinel).
fn log_term_at(node : RaftNode, index : Int) -> Int {
  if index < 0 || index >= node.persistent.log.length() {
    return 0
  }
  node.persistent.log[index].term
}

///|
/// Check whether `candidate_last_index` / `candidate_last_term` is at
/// least as up-to-date as this node's log.
///
/// Per §5.4.1: the candidate's log is at least as up-to-date if:
/// - its last term is greater, OR
/// - its last term is equal and its last index is ≥ ours.
fn is_log_up_to_date(
  node : RaftNode,
  candidate_last_term : Int,
  candidate_last_index : Int,
) -> Bool {
  let my_last_term = last_log_term(node)
  let my_last_index = last_log_index(node)
  if candidate_last_term != my_last_term {
    candidate_last_term > my_last_term
  } else {
    candidate_last_index >= my_last_index
  }
}

// ---------------------------------------------------------------------------
// Node creation
// ---------------------------------------------------------------------------

///|
/// Create a new Raft node.
///
/// The node starts as a Follower with term 0, an empty log (just the
/// sentinel), and a randomized election timeout.
pub fn raft_node_create(
  node_id : Int,
  cluster_size : Int,
  seed : Int,
) -> RaftNode {
  let (rng, timeout) = rng_range(
    if seed == 0 {
      1
    } else {
      seed
    },
    default_election_timeout_min,
    default_election_timeout_range,
  )
  {
    node_id,
    cluster_size,
    role: Follower,
    persistent: {
      current_term: 0,
      voted_for: -1,
      log: [{ term: 0, command: 0 }], // sentinel entry at index 0
    },
    vol_state: { commit_index: 0, last_applied: 0 },
    leader_state: { next_index: [], match_index: [] },
    leader_id: -1,
    election_elapsed: 0,
    election_timeout: timeout,
    heartbeat_elapsed: 0,
    heartbeat_interval: default_heartbeat_interval,
    rng_state: rng,
  }
}

// ---------------------------------------------------------------------------
// Role transitions
// ---------------------------------------------------------------------------

///|
/// Convert to Follower with the given term (if term > current term).
/// Resets voted_for and leader_id.
fn become_follower(node : RaftNode, term : Int) -> Unit {
  if term > node.persistent.current_term {
    node.persistent.current_term = term
    node.persistent.voted_for = -1
  }
  node.role = Follower
  node.leader_id = -1
  node.heartbeat_elapsed = 0
  // Randomize next election timeout
  let (rng, timeout) = rng_range(
    node.rng_state,
    default_election_timeout_min,
    default_election_timeout_range,
  )
  node.rng_state = rng
  node.election_timeout = timeout
  node.election_elapsed = 0
}

///|
/// Convert to Candidate and start a new election.
fn become_candidate(node : RaftNode) -> Unit {
  node.role = Candidate
  node.persistent.current_term = node.persistent.current_term + 1
  node.persistent.voted_for = node.node_id
  node.leader_id = -1
  node.election_elapsed = 0
  // Randomize next election timeout
  let (rng, timeout) = rng_range(
    node.rng_state,
    default_election_timeout_min,
    default_election_timeout_range,
  )
  node.rng_state = rng
  node.election_timeout = timeout
}

///|
/// Convert to Leader. Initialize leader state (next_index, match_index).
fn become_leader(node : RaftNode) -> Unit {
  node.role = Leader
  node.leader_id = node.node_id
  let last = last_log_index(node)
  // next_index for each follower starts at last_log_index + 1
  // match_index for each follower starts at 0
  node.leader_state.next_index = Array::make(node.cluster_size, last + 1)
  node.leader_state.match_index = Array::make(node.cluster_size, 0)
  node.leader_state.match_index[node.node_id] = last
  node.heartbeat_elapsed = node.heartbeat_interval // send heartbeat immediately
}

// ---------------------------------------------------------------------------
// Tick — time progression
// ---------------------------------------------------------------------------

///|
/// Message produced by a Raft node that must be sent to other nodes.
pub enum RaftMessage {
  /// RequestVote RPC: (candidate_id, term, last_log_index, last_log_term)
  RequestVote(Int, Int, Int, Int)
  /// RequestVote response: (voter_id, term, vote_granted)
  RequestVoteResp(Int, Int, Bool)
  /// AppendEntries RPC: (leader_id, term, prev_log_index, prev_log_term,
  ///   entries, leader_commit)
  AppendEntries(Int, Int, Int, Int, Array[LogEntry], Int)
  /// AppendEntries response: (follower_id, term, success, match_index)
  AppendEntriesResp(Int, Int, Bool, Int)
}

///|
/// Advance the node by one tick. Returns a list of outgoing messages.
///
/// - **Followers/Candidates**: If the election timeout elapses, the node
///   starts a new election (becomes Candidate and sends RequestVote to
///   all peers).
/// - **Leaders**: If the heartbeat interval elapses, the node sends
///   AppendEntries (heartbeats or log entries) to all followers.
pub fn raft_tick(node : RaftNode) -> Array[RaftMessage] {
  match node.role {
    Leader => {
      node.heartbeat_elapsed = node.heartbeat_elapsed + 1
      if node.heartbeat_elapsed >= node.heartbeat_interval {
        node.heartbeat_elapsed = 0
        send_append_entries_to_all(node)
      } else {
        []
      }
    }
    Follower => {
      node.election_elapsed = node.election_elapsed + 1
      if node.election_elapsed >= node.election_timeout {
        become_candidate(node)
        start_election(node)
      } else {
        []
      }
    }
    Candidate => {
      node.election_elapsed = node.election_elapsed + 1
      if node.election_elapsed >= node.election_timeout {
        become_candidate(node)
        start_election(node)
      } else {
        []
      }
    }
  }
}

///|
/// Start a new election as a Candidate. Sends RequestVote to all peers.
fn start_election(node : RaftNode) -> Array[RaftMessage] {
  let msgs : Array[RaftMessage] = []
  let last_idx = last_log_index(node)
  let last_term = last_log_term(node)
  for i = 0; i < node.cluster_size; i = i + 1 {
    if i != node.node_id {
      msgs.push(
        RequestVote(
          node.node_id,
          node.persistent.current_term,
          last_idx,
          last_term,
        ),
      )
    }
  }
  msgs
}

///|
/// Send AppendEntries to all followers. The leader sends entries from
/// `next_index[follower]` onwards.
fn send_append_entries_to_all(node : RaftNode) -> Array[RaftMessage] {
  let msgs : Array[RaftMessage] = []
  for i = 0; i < node.cluster_size; i = i + 1 {
    if i != node.node_id {
      msgs.push(create_append_entries(node, i))
    }
  }
  msgs
}

///|
/// Create an AppendEntries RPC for a specific follower.
fn create_append_entries(node : RaftNode, follower : Int) -> RaftMessage {
  let next_idx = node.leader_state.next_index[follower]
  let prev_idx = next_idx - 1
  let prev_term = log_term_at(node, prev_idx)
  // Collect entries from next_idx onwards
  let entries : Array[LogEntry] = []
  let last = last_log_index(node)
  for j = next_idx; j <= last; j = j + 1 {
    entries.push({
      term: node.persistent.log[j].term,
      command: node.persistent.log[j].command,
    })
  }
  AppendEntries(
    node.node_id,
    node.persistent.current_term,
    prev_idx,
    prev_term,
    entries,
    node.vol_state.commit_index,
  )
}

// ---------------------------------------------------------------------------
// RequestVote RPC handling
// ---------------------------------------------------------------------------

///|
/// Handle a RequestVote RPC from a candidate.
///
/// Returns a `RequestVoteResp` message if a response should be sent.
///
/// **Rules:**
/// 1. If the candidate's term < current term, reject.
/// 2. If the candidate's term > current term, update term and become follower.
/// 3. Grant vote if: (a) voted_for is -1 or candidate_id, AND
///    (b) candidate's log is at least as up-to-date.
pub fn handle_request_vote(
  node : RaftNode,
  candidate_id : Int,
  candidate_term : Int,
  candidate_last_index : Int,
  candidate_last_term : Int,
) -> RaftMessage {
  // Reply false if term < current term (§5.1)
  if candidate_term < node.persistent.current_term {
    return RequestVoteResp(node.node_id, node.persistent.current_term, false)
  }
  // If candidate's term > current term, update and become follower
  if candidate_term > node.persistent.current_term {
    become_follower(node, candidate_term)
  }
  // Check if we can vote for this candidate
  let can_vote = node.persistent.voted_for == -1 ||
    node.persistent.voted_for == candidate_id
  let log_ok = is_log_up_to_date(
    node, candidate_last_term, candidate_last_index,
  )
  if can_vote && log_ok {
    node.persistent.voted_for = candidate_id
    node.election_elapsed = 0 // reset timer on granting vote
    RequestVoteResp(node.node_id, node.persistent.current_term, true)
  } else {
    RequestVoteResp(node.node_id, node.persistent.current_term, false)
  }
}

// ---------------------------------------------------------------------------
// RequestVote response handling
// ---------------------------------------------------------------------------

///|
/// Handle a RequestVote response from a voter.
///
/// Returns `true` if this node became leader, `false` otherwise.
/// The caller should check `node.role` after calling.
pub fn handle_request_vote_resp(
  node : RaftNode,
  voter_id : Int,
  term : Int,
  vote_granted : Bool,
) -> Bool {
  // If the response term > current term, step down
  if term > node.persistent.current_term {
    become_follower(node, term)
    return false
  }
  // Ignore if we're no longer a candidate
  match node.role {
    Candidate => ()
    _ => return false
  }
  // Ignore stale responses
  if term != node.persistent.current_term {
    return false
  }
  if vote_granted {
    node.leader_state.match_index = Array::make(node.cluster_size, 0)
    // Count votes (including self-vote)
    let mut votes = 1 // self
    // We need to track votes; use match_index as a proxy
    // Since we can't add a separate field, we'll use a different approach:
    // Store vote count in match_index[0] as a hack... No, let's just check
    // if we have enough votes by counting from the messages.
    // Actually, the caller should track votes. Let's return true if
    // votes >= majority. But we don't have a vote counter field.
    //
    // Better approach: the caller of handle_request_vote_resp should
    // track the total votes and call become_leader when majority is reached.
    // This function just records the vote.
    //
    // For simplicity, we'll use a simple approach: store the vote count
    // in a separate mechanism. Since RaftNode is mutable, we can track
    // votes using the leader_state.next_index array (repurposed during
    // election). Set next_index[voter_id] = 1 to indicate a vote.
    if node.leader_state.next_index.length() == 0 {
      node.leader_state.next_index = Array::make(node.cluster_size, 0)
    }
    node.leader_state.next_index[voter_id] = 1
    // Count total votes
    for i = 0; i < node.cluster_size; i = i + 1 {
      if node.leader_state.next_index[i] == 1 {
        votes = votes + 1
      }
    }
    // Check majority
    if votes * 2 > node.cluster_size {
      become_leader(node)
      return true
    }
  }
  false
}

// ---------------------------------------------------------------------------
// AppendEntries RPC handling
// ---------------------------------------------------------------------------

///|
/// Handle an AppendEntries RPC from a leader.
///
/// Returns an `AppendEntriesResp` message.
///
/// **Rules:**
/// 1. If term < current term, reject.
/// 2. If term ≥ current term, become follower (if not already), reset timer.
/// 3. If log doesn't contain entry at prev_log_index with matching term, reject.
/// 4. Delete conflicting entries and append new ones.
/// 5. Advance commit_index if leader_commit > current commit_index.
pub fn handle_append_entries(
  node : RaftNode,
  leader_id : Int,
  term : Int,
  prev_log_index : Int,
  prev_log_term : Int,
  entries : Array[LogEntry],
  leader_commit : Int,
) -> RaftMessage {
  // Reply false if term < current term (§5.1)
  if term < node.persistent.current_term {
    return AppendEntriesResp(
      node.node_id,
      node.persistent.current_term,
      false,
      0,
    )
  }
  // Update term and become follower if needed
  if term > node.persistent.current_term {
    become_follower(node, term)
  } else {
    // Same term: if we're a candidate, step down
    match node.role {
      Candidate => node.role = Follower
      _ => ()
    }
  }
  // Recognize the leader
  node.leader_id = leader_id
  node.election_elapsed = 0
  // Consistency check: verify prev_log_index/term match
  // prev_log_index is 0-based; index 0 is the sentinel
  if prev_log_index >= node.persistent.log.length() {
    // Our log is too short
    return AppendEntriesResp(
      node.node_id,
      node.persistent.current_term,
      false,
      last_log_index(node),
    )
  }
  if prev_log_index > 0 &&
    node.persistent.log[prev_log_index].term != prev_log_term {
    // Term mismatch at prev_log_index
    return AppendEntriesResp(
      node.node_id,
      node.persistent.current_term,
      false,
      prev_log_index - 1,
    )
  }
  // Append entries, deleting any conflicting ones
  let mut entries_idx = 0
  let mut log_idx = prev_log_index + 1
  while entries_idx < entries.length() {
    if log_idx < node.persistent.log.length() {
      // Check for conflict
      if node.persistent.log[log_idx].term != entries[entries_idx].term {
        // Delete this and all following entries
        while node.persistent.log.length() > log_idx {
          ignore(node.persistent.log.pop())
        }
        // Append the new entry
        node.persistent.log.push({
          term: entries[entries_idx].term,
          command: entries[entries_idx].command,
        })
      }
      // else: same term, entry already exists, skip
    } else {
      // Append new entry
      node.persistent.log.push({
        term: entries[entries_idx].term,
        command: entries[entries_idx].command,
      })
    }
    entries_idx = entries_idx + 1
    log_idx = log_idx + 1
  }
  // Advance commit index
  let new_commit = if leader_commit > node.vol_state.commit_index {
    // Don't commit beyond the last log entry
    let last = last_log_index(node)
    if leader_commit < last {
      leader_commit
    } else {
      last
    }
  } else {
    node.vol_state.commit_index
  }
  node.vol_state.commit_index = new_commit
  // Apply newly committed entries
  apply_committed(node)
  AppendEntriesResp(
    node.node_id,
    node.persistent.current_term,
    true,
    log_idx - 1,
  )
}

// ---------------------------------------------------------------------------
// AppendEntries response handling
// ---------------------------------------------------------------------------

///|
/// Handle an AppendEntries response from a follower.
///
/// Returns a list of new messages to send (e.g., retry with earlier index
/// or send new entries).
pub fn handle_append_entries_resp(
  node : RaftNode,
  follower_id : Int,
  term : Int,
  success : Bool,
  match_index : Int,
) -> Array[RaftMessage] {
  // If response term > current term, step down
  if term > node.persistent.current_term {
    become_follower(node, term)
    return []
  }
  // Ignore if not leader
  match node.role {
    Leader => ()
    _ => return []
  }
  if success {
    // Update match_index and next_index
    node.leader_state.match_index[follower_id] = match_index
    node.leader_state.next_index[follower_id] = match_index + 1
    // Try to advance commit index
    advance_commit_index(node)
    []
  } else {
    // Decrement next_index and retry
    // match_index from failed response is a hint for faster decrement
    let new_next = if match_index > 0 &&
      match_index < node.leader_state.next_index[follower_id] {
      match_index + 1
    } else {
      node.leader_state.next_index[follower_id] - 1
    }
    if new_next < 1 {
      node.leader_state.next_index[follower_id] = 1
    } else {
      node.leader_state.next_index[follower_id] = new_next
    }
    // Retry immediately
    [create_append_entries(node, follower_id)]
  }
}

// ---------------------------------------------------------------------------
// Commit and apply
// ---------------------------------------------------------------------------

///|
/// Advance the commit index on the leader.
///
/// Per §5.4.2: Find the largest N such that:
/// 1. N > commit_index,
/// 2. A majority of match_index[i] ≥ N, AND
/// 3. log[N].term == current_term.
///
/// Condition (3) ensures the leader only commits entries from its own
/// term, which is critical for safety.
fn advance_commit_index(node : RaftNode) -> Unit {
  let last = last_log_index(node)
  let mut n = last
  while n > node.vol_state.commit_index {
    // Check that log[n] is from the current term
    if log_term_at(node, n) != node.persistent.current_term {
      n = n - 1
      continue
    }
    // Count how many followers have replicated this entry
    let mut count = 1 // self
    for i = 0; i < node.cluster_size; i = i + 1 {
      if i != node.node_id && node.leader_state.match_index[i] >= n {
        count = count + 1
      }
    }
    if count * 2 > node.cluster_size {
      node.vol_state.commit_index = n
      apply_committed(node)
      return
    }
    n = n - 1
  }
}

///|
/// Apply all committed but not-yet-applied entries to the state machine.
/// In this implementation, applying is a no-op (the state machine is
/// abstract). In a real system, this would execute the commands.
fn apply_committed(node : RaftNode) -> Unit {
  while node.vol_state.last_applied < node.vol_state.commit_index {
    node.vol_state.last_applied = node.vol_state.last_applied + 1
    // In a real implementation: apply log[last_applied].command to SM
  }
}

// ---------------------------------------------------------------------------
// Client interface
// ---------------------------------------------------------------------------

///|
/// Submit a command to the leader.
///
/// Returns `true` if the command was accepted (node is leader), `false`
/// otherwise. The command is appended to the leader's log and will be
/// replicated on the next heartbeat.
pub fn raft_submit(node : RaftNode, command : Int) -> Bool {
  match node.role {
    Leader => {
      node.persistent.log.push({ term: node.persistent.current_term, command })
      true
    }
    _ => false
  }
}

// ---------------------------------------------------------------------------
// Accessors (for testing and introspection)
// ---------------------------------------------------------------------------

///|
/// Get the node's current role.
pub fn raft_role(node : RaftNode) -> RaftRole {
  node.role
}

///|
/// Get the node's current term.
pub fn raft_term(node : RaftNode) -> Int {
  node.persistent.current_term
}

///|
/// Get the node's leader ID (-1 if unknown).
pub fn raft_leader_id(node : RaftNode) -> Int {
  node.leader_id
}

///|
/// Get the commit index.
pub fn raft_commit_index(node : RaftNode) -> Int {
  node.vol_state.commit_index
}

///|
/// Get the last applied index.
pub fn raft_last_applied(node : RaftNode) -> Int {
  node.vol_state.last_applied
}

///|
/// Get the log length (including sentinel).
pub fn raft_log_length(node : RaftNode) -> Int {
  node.persistent.log.length()
}

///|
/// Get the term of a log entry at the given 1-based index.
/// Returns 0 if the index is out of bounds.
pub fn raft_log_term(node : RaftNode, index : Int) -> Int {
  if index < 1 || index >= node.persistent.log.length() {
    return 0
  }
  node.persistent.log[index].term
}

///|
/// Get the command of a log entry at the given 1-based index.
/// Returns 0 if the index is out of bounds.
pub fn raft_log_command(node : RaftNode, index : Int) -> Int {
  if index < 1 || index >= node.persistent.log.length() {
    return 0
  }
  node.persistent.log[index].command
}

///|
/// Get the match_index for a follower (leader only).
pub fn raft_match_index(node : RaftNode, follower : Int) -> Int {
  if follower < 0 || follower >= node.leader_state.match_index.length() {
    return 0
  }
  node.leader_state.match_index[follower]
}

///|
/// Get the next_index for a follower (leader only).
pub fn raft_next_index(node : RaftNode, follower : Int) -> Int {
  if follower < 0 || follower >= node.leader_state.next_index.length() {
    return 0
  }
  node.leader_state.next_index[follower]
}

///|
/// Get the node's voted_for in the current term.
pub fn raft_voted_for(node : RaftNode) -> Int {
  node.persistent.voted_for
}

///|
/// Get election elapsed (for debugging/testing).
pub fn raft_test_election_elapsed(node : RaftNode) -> Int {
  node.election_elapsed
}

///|
/// Get election timeout (for debugging/testing).
pub fn raft_test_election_timeout(node : RaftNode) -> Int {
  node.election_timeout
}

// ---------------------------------------------------------------------------
// Test helpers (for test setup only)
// ---------------------------------------------------------------------------

///|
/// Force a node into the Leader role with the given term.
/// Initializes leader state (next_index, match_index).
/// This bypasses the normal election process — for testing only.
pub fn raft_test_force_leader(node : RaftNode, term : Int) -> Unit {
  node.role = Leader
  node.leader_id = node.node_id
  node.persistent.current_term = term
  node.leader_state.next_index = Array::make(node.cluster_size, 1)
  node.leader_state.match_index = Array::make(node.cluster_size, 0)
  node.heartbeat_elapsed = 0
}

///|
/// Set the node's current term (for testing).
pub fn raft_test_set_term(node : RaftNode, term : Int) -> Unit {
  node.persistent.current_term = term
}

///|
/// Append a log entry to the node's log (for testing).
pub fn raft_test_add_log_entry(
  node : RaftNode,
  term : Int,
  command : Int,
) -> Unit {
  node.persistent.log.push({ term, command })
}

///|
/// Set the match_index for a specific follower (for testing).
pub fn raft_test_set_match_index(
  node : RaftNode,
  follower : Int,
  index : Int,
) -> Unit {
  if follower >= 0 && follower < node.leader_state.match_index.length() {
    node.leader_state.match_index[follower] = index
  }
}

///|
/// Set the next_index for a specific follower (for testing).
pub fn raft_test_set_next_index(
  node : RaftNode,
  follower : Int,
  index : Int,
) -> Unit {
  if follower >= 0 && follower < node.leader_state.next_index.length() {
    node.leader_state.next_index[follower] = index
  }
}

///|
/// Create a LogEntry value (for testing).
pub fn raft_test_make_log_entry(term : Int, command : Int) -> LogEntry {
  { term, command }
}
