/// Gossip Protocol — Epidemic Broadcast for Cluster Dissemination
///
/// Gossip (a.k.a. epidemic protocol) disseminates information through
/// a network by having each node periodically share data with a random
/// subset of peers. It provides probabilistic eventual consistency with
/// O(log n) rounds.
///
/// ## Variants
/// - **Push**: Nodes send their data to random peers
/// - **Pull**: Nodes request data from random peers
/// - **Push-Pull**: Both (fastest convergence)
///
/// `proof-enabled` is `false`.

///|
/// Gossip message.
pub struct GossipMessage {
  /// Node ID of sender
  sender_id : Int
  /// Data being gossiped (key)
  key : String
  /// Data value
  value : String
  /// Message version/timestamp
  version : Int
}

///|
/// Create a new gossip message.
pub fn GossipMessage::new(
  sender_id : Int,
  key : String,
  value : String,
  version : Int,
) -> GossipMessage {
  { sender_id, key, value, version, }
}

///|
/// Gossip node state.
pub struct GossipNode {
  id : Int
  /// Known peers
  peers : Array[Int]
  /// Local data store: key -> (value, version)
  data : Array[(String, String, Int)]
  /// Nodes that have seen the latest data
  seen : Array[(String, Int)] // (key, node_id)
  /// Infection state per key: Infected | Susceptible
  infected : Array[(String, Bool)]
}

///|
/// Create a new gossip node.
pub fn GossipNode::new(id : Int, peers : Array[Int]) -> GossipNode {
  { id, peers, data: [], seen: [], infected: [], }
}

///|
/// Update local data (infect).
pub fn GossipNode::infect(
  self : GossipNode,
  key : String,
  value : String,
  version : Int,
) -> Unit {
  // Check if we have a newer version
  let mut found = false
  for i in 0..<self.data.length() {
    if self.data[i].0 == key {
      if version > self.data[i].2 {
        self.data[i] = (key, value, version)
      }
      found = true
      break
    }
  }
  if !found {
    self.data.push((key, value, version))
  }
  // Mark as infected
  let mut ifound = false
  for i in 0..<self.infected.length() {
    if self.infected[i].0 == key {
      self.infected[i] = (key, true)
      ifound = true
      break
    }
  }
  if !ifound {
    self.infected.push((key, true))
  }
}

///|
/// Select random peers to gossip with.
pub fn GossipNode::select_peers(
  self : GossipNode,
  fanout : Int,
  rng_seed : Int,
) -> Array[Int] {
  let mut rng = rng_seed + self.id
  let selected : Array[Int] = []
  let available = self.peers.length()
  if available == 0 {
    return selected
  }
  let count = if fanout < available { fanout } else { available }
  // Simple random selection (with replacement)
  for i = 0; i < count; i = i + 1 {
    rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
    let idx = rng % available
    selected.push(self.peers[idx])
  }
  selected
}

///|
/// Generate gossip messages to send to peers (push).
pub fn GossipNode::push_messages(
  self : GossipNode,
  peers : Array[Int],
) -> Array[(Int, GossipMessage)] {
  let result : Array[(Int, GossipMessage)] = []
  // Only push infected keys
  for entry in self.data {
    let key = entry.0
    let value = entry.1
    let version = entry.2
    // Check if infected
    let mut is_infected = false
    for inf in self.infected {
      if inf.0 == key && inf.1 {
        is_infected = true
        break
      }
    }
    if is_infected {
      for peer in peers {
        result.push((peer, { sender_id: self.id, key, value, version, }))
      }
    }
  }
  result
}

///|
/// Receive a gossip message and update local state.
///
/// Returns true if the message caused a state update.
pub fn GossipNode::receive(self : GossipNode, msg : GossipMessage) -> Bool {
  // Check if we already have this version or newer
  for i in 0..<self.data.length() {
    if self.data[i].0 == msg.key {
      if msg.version > self.data[i].2 {
        // Update
        self.data[i] = (msg.key, msg.value, msg.version)
        // Mark as infected (continue spreading)
        self.infect(msg.key, msg.value, msg.version)
        return true
      }
      return false
    }
  }
  // New key
  self.data.push((msg.key, msg.value, msg.version))
  self.infect(msg.key, msg.value, msg.version)
  true
}

///|
/// Run one round of push-pull gossip.
pub fn gossip_round(
  nodes : Array[GossipNode],
  fanout : Int,
  rng_seed : Int,
) -> Array[GossipNode] {
  // For each node, generate push messages and deliver
  let all_messages : Array[(Int, Int, GossipMessage)] = [] // (target, sender, msg)
  for node in nodes {
    let peers = node.select_peers(fanout, rng_seed)
    let msgs = node.push_messages(peers)
    for m in msgs {
      all_messages.push((m.0, node.id, m.1))
    }
  }
  // Deliver messages
  for msg in all_messages {
    for node in nodes {
      if node.id == msg.0 {
        ignore(node.receive(msg.2))
        break
      }
    }
  }
  nodes
}

///|
/// Check if all nodes have converged (all have the same data).
pub fn gossip_converged(nodes : Array[GossipNode]) -> Bool {
  if nodes.length() == 0 {
    return true
  }
  let first = nodes[0]
  for i = 1; i < nodes.length(); i = i + 1 {
    if nodes[i].data.length() != first.data.length() {
      return false
    }
    for entry in first.data {
      let mut found = false
      for entry2 in nodes[i].data {
        if entry.0 == entry2.0 && entry.1 == entry2.1 && entry.2 == entry2.2 {
          found = true
          break
        }
      }
      if !found {
        return false
      }
    }
  }
  true
}
