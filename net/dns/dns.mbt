/// DNS Protocol — RFC 1035 Message Parsing and Construction
///
/// Implements DNS message format for encoding/decoding DNS queries and
/// responses, including name encoding (with label compression), RR types,
/// and the basic query/response structure.
///
/// `proof-enabled` is `false`.

///|
/// DNS record types.
pub enum DnsRecordType {
  A // 1
  NS // 2
  CNAME // 5
  MX // 15
  TXT // 16
  AAAA // 28
  SRV // 33
  PTR // 12
}

///|
/// DNS resource record.
pub struct DnsRR {
  name : String
  rtype : Int
  rclass : Int
  ttl : Int
  rdata : Bytes
}

///|
/// DNS query.
pub struct DnsQuery {
  name : String
  qtype : Int
  qclass : Int
}

///|
/// DNS message header.
pub struct DnsHeader {
  id : Int // 16-bit transaction ID
  flags : Int // 16-bit flags
  qdcount : Int // number of questions
  ancount : Int // number of answers
  nscount : Int // number of NS records
  arcount : Int // number of additional records
}

///|
/// Build a DNS query message as raw bytes.
///
/// ## Parameters
/// - `id`: transaction ID
/// - `domain`: domain name to query (e.g., "example.com")
/// - `qtype`: query type (1=A, 28=AAAA, 15=MX)
/// - `qclass`: query class (1=IN)
pub fn build_dns_query(
  id : Int,
  domain : String,
  qtype : Int,
  qclass : Int,
) -> Bytes {
  // Buffer
  let msg : Array[Byte] = []
  // ID
  msg.push(((id >> 8) & 0xFF).to_byte())
  msg.push((id & 0xFF).to_byte())
  // Flags: standard query, recursion desired
  msg.push(b'\x01')
  msg.push(b'\x00')
  // QDCOUNT = 1
  msg.push(b'\x00')
  msg.push(b'\x01')
  // ANCOUNT = 0
  msg.push(b'\x00')
  msg.push(b'\x00')
  // NSCOUNT = 0
  msg.push(b'\x00')
  msg.push(b'\x00')
  // ARCOUNT = 0
  msg.push(b'\x00')
  msg.push(b'\x00')
  // Question section: encode domain name
  let msg_int : Array[Int] = []
  let pos = encode_name(msg_int, 0, domain)
  for i = 0; i < pos; i = i + 1 {
    msg.push(msg_int[i].to_byte())
  }
  // QTYPE
  msg.push(((qtype >> 8) & 0xFF).to_byte())
  msg.push((qtype & 0xFF).to_byte())
  // QCLASS
  msg.push(((qclass >> 8) & 0xFF).to_byte())
  msg.push((qclass & 0xFF).to_byte())
  Bytes::from_array(msg)
}

///|
/// Encode a domain name as DNS labels.
fn encode_name(buf : Array[Int], offset : Int, name : String) -> Int {
  let mut pos = offset
  let mut label_start = 0
  for i = 0; i <= name.length(); i = i + 1 {
    if i == name.length() || name[i] == '.' {
      let label_len = i - label_start
      if label_len > 0 && label_len < 64 {
        buf[pos] = label_len
        pos = pos + 1
        for j = label_start; j < i; j = j + 1 {
          buf[pos] = name[j].to_int()
          pos = pos + 1
        }
      }
      label_start = i + 1
    }
  }
  // Null terminator
  buf[pos] = 0
  pos = pos + 1
  pos
}

///|
/// Parse DNS header from raw bytes.
pub fn parse_dns_header(data : Bytes) -> DnsHeader? {
  if data.length() < 12 {
    return None
  }
  let id = ((data[0].to_int() & 0xFF) << 8) | (data[1].to_int() & 0xFF)
  let flags = ((data[2].to_int() & 0xFF) << 8) | (data[3].to_int() & 0xFF)
  let qdcount = ((data[4].to_int() & 0xFF) << 8) | (data[5].to_int() & 0xFF)
  let ancount = ((data[6].to_int() & 0xFF) << 8) | (data[7].to_int() & 0xFF)
  let nscount = ((data[8].to_int() & 0xFF) << 8) | (data[9].to_int() & 0xFF)
  let arcount = ((data[10].to_int() & 0xFF) << 8) | (data[11].to_int() & 0xFF)
  Some({ id, flags, qdcount, ancount, nscount, arcount })
}

///|
/// Parse a DNS domain name (with label compression) starting at offset.
/// Returns (name, new_offset).
pub fn parse_name(data : Bytes, offset : Int) -> (String, Int) {
  let mut pos = offset
  let labels : Array[String] = []
  let mut jumped = false
  let mut final_pos = pos
  let mut safety = 0
  while pos < data.length() && safety < 128 {
    safety = safety + 1
    let len = data[pos].to_int() & 0xFF
    if len == 0 {
      pos = pos + 1
      if !jumped {
        final_pos = pos
      }
      break
    }
    if (len & 0xC0) == 0xC0 {
      // Compression pointer
      let ptr = ((len & 0x3F) << 8) | (data[pos + 1].to_int() & 0xFF)
      if !jumped {
        final_pos = pos + 2
      }
      jumped = true
      pos = ptr
    } else {
      // Regular label
      pos = pos + 1
      let label = StringBuilder::new()
      for i = 0; i < len && pos < data.length(); i = i + 1 {
        label.write_char((data[pos].to_int() & 0xFF).unsafe_to_char())
        pos = pos + 1
      }
      labels.push(label.to_string())
    }
  }
  // Join labels with "."
  let sb = StringBuilder::new()
  for i in 0..<labels.length() {
    if i > 0 {
      sb.write_char('.')
    }
    sb.write(labels[i])
  }
  (sb.to_string(), final_pos)
}
