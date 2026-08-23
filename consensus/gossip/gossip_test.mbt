// White-box tests for consensus/gossip.
// Covers node construction, infect/update, message receive (idempotency),
// peer selection, convergence helper, and full-mesh epidemic propagation.

///|
test "gossip_new_node" {
  let n = GossipNode::new(1, [2, 3])
  assert_eq(n.id, 1)
  assert_eq(n.peers.length(), 2)
  assert_eq(n.data.length(), 0)
  assert_eq(n.infected.length(), 0)
}

///|
test "gossip_infect_and_update" {
  let n = GossipNode::new(0, [])
  n.infect("k", "v", 1)
  assert_eq(n.data.length(), 1)
  assert_eq(n.data[0], ("k", "v", 1))
  // newer version overwrites
  n.infect("k", "v2", 2)
  assert_eq(n.data[0], ("k", "v2", 2))
  // older version ignored
  n.infect("k", "v0", 0)
  assert_eq(n.data[0], ("k", "v2", 2))
  // mark infected
  assert_eq(n.infected[0], ("k", true))
}

///|
test "gossip_receive_idempotent" {
  let n = GossipNode::new(2, [])
  let msg = GossipMessage::new(0, "k", "v", 1)
  assert_true(n.receive(msg))
  assert_eq(n.data[0], ("k", "v", 1))
  // duplicate -> no update
  assert_false(n.receive(msg))
  // newer version -> update
  let msg2 = GossipMessage::new(0, "k", "v3", 3)
  assert_true(n.receive(msg2))
  assert_eq(n.data[0], ("k", "v3", 3))
  // older version -> ignored
  let msg0 = GossipMessage::new(0, "k", "old", 1)
  assert_false(n.receive(msg0))
}

///|
test "gossip_select_peers" {
  let n = GossipNode::new(0, [1, 2])
  let p1 = n.select_peers(1, 0)
  assert_eq(p1.length(), 1)
  assert_true(p1[0] == 1 || p1[0] == 2)
  // fanout capped at available peer count
  let p2 = n.select_peers(5, 0)
  assert_eq(p2.length(), 2)
  // no peers -> empty
  let ne = GossipNode::new(7, [])
  assert_eq(ne.select_peers(3, 0).length(), 0)
}

///|
test "gossip_push_messages_only_infected" {
  let n = GossipNode::new(0, [1, 2])
  // nothing infected -> no messages
  assert_eq(n.push_messages([1, 2]).length(), 0)
  n.infect("k", "v", 1)
  let msgs = n.push_messages([1, 2])
  // one infected key -> one message per peer
  assert_eq(msgs.length(), 2)
  for m in msgs {
    assert_eq(m.1.key, "k")
    assert_eq(m.1.value, "v")
    assert_eq(m.1.version, 1)
  }
}

///|
test "gossip_converged_helper" {
  let a = GossipNode::new(0, [])
  a.infect("k", "v", 1)
  let b = GossipNode::new(1, [])
  b.infect("k", "v", 1)
  assert_true(gossip_converged([a, b]))
  let c = GossipNode::new(2, [])
  c.infect("k", "w", 1)
  assert_false(gossip_converged([a, c]))
  // empty / single node
  assert_true(gossip_converged([]))
  assert_true(gossip_converged([a]))
}

///|
test "gossip_round_converges_full_mesh" {
  let n0 = GossipNode::new(0, [1, 2])
  let n1 = GossipNode::new(1, [0, 2])
  let n2 = GossipNode::new(2, [0, 1])
  n0.infect("secret", "42", 1)
  let mut nodes = [n0, n1, n2]
  let mut converged = false
  for round = 0; round < 20; round = round + 1 {
    nodes = gossip_round(nodes, 2, 0)
    if gossip_converged(nodes) {
      converged = true
      break
    }
  }
  assert_true(converged)
  for node in nodes {
    assert_eq(node.data.length(), 1)
    assert_eq(node.data[0], ("secret", "42", 1))
  }
}

///|
test "gossip_round_idempotent_after_convergence" {
  let n0 = GossipNode::new(0, [1, 2])
  let n1 = GossipNode::new(1, [0, 2])
  let n2 = GossipNode::new(2, [0, 1])
  n0.infect("secret", "42", 1)
  let mut nodes = [n0, n1, n2]
  for round = 0; round < 20; round = round + 1 {
    nodes = gossip_round(nodes, 2, 0)
    if gossip_converged(nodes) {
      break
    }
  }
  assert_true(gossip_converged(nodes))
  let before = nodes[0].data[0]
  // extra rounds must not change converged state / values
  for round = 0; round < 5; round = round + 1 {
    nodes = gossip_round(nodes, 2, 0)
  }
  assert_true(gossip_converged(nodes))
  assert_eq(nodes[0].data[0], before)
}
